import {finiteWireNumberSource, wireNonControlIdPattern} from './client-wire-scalar-rules.mjs';
import {execFileSync} from 'node:child_process';
import {closeSync, mkdirSync, mkdtempSync, openSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeCheckReportRules} from './client-check-report-rules.mjs';

// Compile the selected wire schemas to ordinary MoonBit predicates. This is a
// build-time projection, not a schema interpreter in the Native executable.
export function nativeClientWire(schemas, rules, requestRules, checkPins, reportRules) {
  const functions = [];
  const checkOutcomePredicates = new Set();
  let serial = 0;
  let checkDepth = 0;
  const emitted = new Map();
  const quote = JSON.stringify;
  function emit(schema, name = `wire_rule_${serial++}`) {
    const key = (checkDepth > 0 ? 'check:' : 'wire:') + JSON.stringify(schema);
    if (emitted.has(key)) {
      const existing = emitted.get(key);
      if (arguments.length > 1 && name !== existing) {
        functions.push(`///|\nfn ${name}(value : Json) -> Bool {\n  ${existing}(value)\n}\n`);
        return name;
      }
      return existing;
    }
    emitted.set(key, name);
    const lines = [];
    if (schema.$ref !== undefined) {
      if (!['check_outcome', 'value_contract', 'run_state'].includes(schema.$ref) || Object.keys(schema).length !== 1 ||
          schemas[schema.$ref] === undefined) throw new Error('UnsupportedNativeWireReference');
      let referred;
      checkDepth++;
      try { referred = emit(schemas[schema.$ref]); } finally { checkDepth--; }
      lines.push(`if !${referred}(value) { return false }`);
      if (schema.$ref === 'check_outcome') {
        checkOutcomePredicates.add(name);
        if (!checkPins?.reason || !checkPins?.outcome) throw new Error('MissingNativeCheckPins');
        lines.push('guard value is Object(fields) else { return false }',
          `if fields.get("reason_schema_cid") != Some(Json::string(${quote(checkPins.reason)})) { return false }`,
          `if fields.get("outcome_schema_cid") != Some(Json::string(${quote(checkPins.outcome)})) { return false }`,
          'if !wire_check_report_contract(value) { return false }');
      }
      functions.push(`///|\nfn ${name}(${lines.length ? 'value' : '_value'} : Json) -> Bool {\n  ${lines.join('\n  ')}\n  true\n}\n`);
      return name;
    }
    for (const key of Object.keys(schema)) if (!['type','required','properties',
      'additionalProperties','items','uniqueItems','const','enum','pattern',
      'minLength','maxLength','minimum','maximum','minItems','maxItems',
      'allOf','oneOf','not','if','then','propertyNames','minProperties','maxProperties'].includes(key)) throw new Error(`UnsupportedNativeWireRule:${key}`);
    if (Object.hasOwn(schema, 'const') && Object.hasOwn(schema, 'enum')) {
      throw new Error('UnsupportedNativeWireConstAndEnum');
    }
    if (schema.additionalProperties === false && !schema.properties) {
      throw new Error('UnsupportedNativeWireClosedObjectWithoutProperties');
    }
    // Conditional diagnostic constraints apply only to their JSON type.
    // Keep the existing strict rejection for unrelated untyped wire rules.
    if (checkDepth > 0 && schema.type === undefined) {
      const constrained = [['number', ['minimum', 'maximum'], 'Number(_, ..)'],
        ['string', ['minLength', 'maxLength', 'pattern'], 'String(_)'],
        ['array', ['items', 'minItems', 'maxItems'], 'Array(_)']]
        .filter(([, keys]) => keys.some(key => Object.hasOwn(schema, key)));
      if (constrained.length > 1) throw new Error('UnsupportedNativeWireMixedConstraint');
      if (constrained.length === 1) {
        const [type, , pattern] = constrained[0];
        const typed = emit({...schema, type});
        functions.push(`///|\nfn ${name}(value : Json) -> Bool {\n  if value is ${pattern} { return ${typed}(value) }\n  true\n}\n`);
        return name;
      }
    }
    // Refuse combinations this bounded compiler does not implement. The JS
    // projection can express untyped conditional constraints; silently dropping
    // them here would recreate the original cross-consumer rule divergence.
    for (const [type, keys] of [
      ['string', ['minLength', 'maxLength', 'pattern']],
      ['integer', ['minimum', 'maximum']],
      ['array', ['items', 'uniqueItems', 'minItems', 'maxItems']],
    ]) if (keys.some(key => Object.hasOwn(schema, key)) && schema.type !== type && !(checkDepth > 0 && type === 'integer' && schema.type === 'number')) {
      throw new Error(`UnsupportedNativeWireConstraintType:${type}`);
    }
    if (schema.allOf) for (const rule of schema.allOf) lines.push(`if !${emit(rule)}(value) { return false }`);
    if (schema.oneOf) lines.push(`if [${schema.oneOf.map(rule => `${emit(rule)}(value)`).join(', ')}].filter(fn(ok) { ok }).length() != 1 { return false }`);
    if (schema.if) {
      if (!schema.then) throw new Error('UnsupportedNativeWireConditional');
      lines.push(`if ${emit(schema.if)}(value) && !${emit(schema.then)}(value) { return false }`);
    } else if (schema.then) throw new Error('UnsupportedNativeWireConditional');
    if (schema.not) lines.push(`if ${emit(schema.not)}(value) { return false }`);
    if (schema.const !== undefined || schema.enum) {
      const values = schema.enum ?? [schema.const];
      if (values.every(value => typeof value === 'boolean')) {
        lines.push('if !(value is True || value is False) { return false }',
          `if !(${values.map(value => `(value is ${value ? 'True' : 'False'})`).join(' || ')}) { return false }`);
      } else if (values.every(value => typeof value === 'number' && Number.isFinite(value))) {
        const number = value => String(value).match(/[.e]/iu) ? String(value) : String(value) + '.0';
        lines.push('guard value is Number(number, ..) else { return false }',
          'if !wire_finite_number(number) { return false }',
          `if !(${values.map(value => `number == ${number(value)}`).join(' || ')}) { return false }`);
      } else if (values.every(value => value === null)) {
        lines.push('guard value is Null else { return false }');
      } else {
        if (values.some(value => typeof value !== 'string')) throw new Error('UnsupportedNativeWireLiteral');
        lines.push('guard value is String(text) else { return false }',
          `if !(${values.map(value => `text == ${quote(value)}`).join(' || ')}) { return false }`);
      }
    }
    if (schema.type === 'string') {
      const needsText = ['minLength', 'maxLength', 'pattern'].some(key =>
        schema[key] !== undefined);
      lines.push(`guard value is String(${needsText ? 'text' : '_'}) else { return false }`);
      if (schema.minLength !== undefined) lines.push(`if text.iter().count() < ${schema.minLength} { return false }`);
      if (schema.maxLength !== undefined) lines.push(`if text.length() > ${schema.maxLength} { return false }`);
      if (schema.pattern === wireNonControlIdPattern) lines.push('if text.is_empty() { return false }', 'for character in text { if character.to_int() < 32 || character.to_int() == 127 { return false } }');
      else if (schema.pattern === '^sha256:[0-9a-f]{64}$') lines.push('if text.length() != 71 || !text.has_prefix("sha256:") { return false }', 'for character in text[7:] { if !((character >= \'0\' && character <= \'9\') || (character >= \'a\' && character <= \'f\')) { return false } }');
      else if (schema.pattern === '^[0-9a-f]{64}$') lines.push('if text.length() != 64 { return false }', 'for character in text { if !((character >= \'0\' && character <= \'9\') || (character >= \'a\' && character <= \'f\')) { return false } }');
      else if (schema.pattern === '^rev:[0-9a-f]{64}$') lines.push('if text.length() != 68 || !text.has_prefix("rev:") { return false }',
        `for character in text[4:] { if !((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')) { return false } }`);
      else if (schema.pattern === '^[A-Za-z0-9:_-]+$') lines.push('if text.is_empty() { return false }',
        `for character in text { if !((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == ':' || character == '_' || character == '-') { return false } }`);
      else if (schema.pattern === '^[a-z][a-z0-9_]{0,63}$') lines.push('if text.is_empty() || text.length() > 64 { return false }',
        `if text[0] < 'a' || text[0] > 'z' { return false }`,
        `for character in text { if !((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '_') { return false } }`);
      else if (schema.pattern === '^(?:/(?:[^~]|~[01])*)*$') lines.push('if !text.is_empty() && !text.has_prefix("/") { return false }',
        'let mut escape = false', `for character in text { if escape { if character != '0' && character != '1' { return false }; escape = false } else if character == '~' { escape = true } }`,
        'if escape { return false }');
      else if (schema.pattern === '^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$') lines.push(
        'if text.is_empty() || text == "__cid" || text.has_prefix("__actql_") || text.contains(".") { return false }',
        'let mut nonblank = false',
        'for character in text { let code = character.to_int(); if !(code == 9 || code == 10 || code == 11 || code == 12 || code == 13 || code == 32 || code == 160 || code == 5760 || (code >= 8192 && code <= 8202) || code == 8232 || code == 8233 || code == 8239 || code == 8287 || code == 12288 || code == 65279) { nonblank = true } }',
        'if !nonblank { return false }');
      else if (schema.pattern === '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$') lines.push(
        'if text.length() != 24 { return false }',
        'let mut index = 0',
        'for character in text {',
        '  let separator = match index { 4 | 7 => Some(\'-\'); 10 => Some(\'T\'); 13 | 16 => Some(\':\'); 19 => Some(\'.\'); 23 => Some(\'Z\'); _ => None }',
        '  match separator { Some(expected) => if character != expected { return false }; None => if character < \'0\' || character > \'9\' { return false } }',
        '  index = index + 1',
        '}');
      else if (schema.pattern === '^ACTQL_E_[A-Z0-9_]+$') lines.push(
        'if text.length() < 9 || !text.has_prefix("ACTQL_E_") { return false }',
        'for character in text[8:] { if !((character >= \'A\' && character <= \'Z\') || (character >= \'0\' && character <= \'9\') || character == \'_\') { return false } }');
      else if (schema.pattern === '^(0|[1-9][0-9]*)$(?![\\s\\S])') lines.push(
        'if text.is_empty() || (text.length() > 1 && text[0] == \'0\') { return false }',
        'for character in text { if character < \'0\' || character > \'9\' { return false } }');
      else if (schema.pattern !== undefined) throw new Error(`UnsupportedNativeWirePattern:${schema.pattern}`);
    } else if (schema.type === 'boolean') {
      lines.push('if !(value is True || value is False) { return false }');
    } else if (schema.type === 'number') {
      lines.push('guard value is Number(number, ..) else { return false }', 'if !wire_finite_number(number) { return false }');
      if (schema.minimum !== undefined) lines.push(`if number < ${schema.minimum}.0 { return false }`);
      if (schema.maximum !== undefined) lines.push(`if number > ${schema.maximum}.0 { return false }`);
    } else if (schema.type === 'integer') {
      lines.push('guard value is Number(number, ..) else { return false }', 'if !wire_finite_number(number) || number != number.floor() || number < -9007199254740991.0 || number > 9007199254740991.0 { return false }');
      if (schema.minimum !== undefined) lines.push(`if number < ${schema.minimum}.0 { return false }`);
      if (schema.maximum !== undefined) lines.push(`if number > ${schema.maximum}.0 { return false }`);
    } else if (schema.type === 'array') {
      lines.push('guard value is Array(items) else { return false }');
      if (schema.minItems !== undefined) lines.push(`if items.length() < ${schema.minItems} { return false }`);
      if (schema.maxItems !== undefined) lines.push(`if items.length() > ${schema.maxItems} { return false }`);
      if (schema.items) lines.push(`for item in items { if !${emit(schema.items)}(item) { return false } }`);
      if (schema.uniqueItems) lines.push('let seen : Map[String, Bool] = Map([])', 'for item in items { guard item is String(text) else { return false }; if seen.contains(text) { return false }; seen[text] = true }');
    } else if (schema.type === 'object' || schema.properties || schema.required || schema.additionalProperties !== undefined) {
      lines.push('guard value is Object(fields) else { return false }');
      if (schema.additionalProperties === false) lines.push(`for key, _ in fields { if !(${Object.keys(schema.properties ?? {}).map(key => `key == ${quote(key)}`).join(' || ') || 'false'}) { return false } }`);
      else if (checkDepth > 0 && schema.additionalProperties === true) { /* JSON Schema permits these fields. */ }
      else if (checkDepth > 0 && schema.additionalProperties && typeof schema.additionalProperties === 'object') {
        const unknown = emit(schema.additionalProperties);
        const known = Object.keys(schema.properties ?? {}).map(key => `key == ${quote(key)}`).join(' || ') || 'false';
        lines.push(`for ${known === 'false' ? '_key' : 'key'}, item in fields { if !(${known}) && !${unknown}(item) { return false } }`);
      }
      else if (schema.additionalProperties !== undefined) throw new Error('UnsupportedNativeWireAdditionalProperties');
      if (schema.minProperties !== undefined) lines.push(`if fields.size() < ${schema.minProperties} { return false }`);
      if (schema.maxProperties !== undefined) lines.push(`if fields.size() > ${schema.maxProperties} { return false }`);
      if (schema.propertyNames) lines.push(`for key, _ in fields { if !${emit(schema.propertyNames)}(Json::string(key)) { return false } }`);
      for (const key of schema.required ?? []) lines.push(`if !fields.contains(${quote(key)}) { return false }`);
      for (const [key, rule] of Object.entries(schema.properties ?? {})) lines.push(`if fields.get(${quote(key)}) is Some(item) { if !${emit(rule)}(item) { return false } }`);
    } else if (schema.type !== undefined) throw new Error(`UnsupportedNativeWireType:${schema.type}`);
    functions.push(`///|\nfn ${name}(${lines.length ? 'value' : '_value'} : Json) -> Bool {\n  ${lines.join('\n  ')}\n  true\n}\n`);
    return name;
  }
  for (const name of ['submission_epoch','submission_ref','submission_outcome','submission_lookup','submission_restart','submission_attempt',
    'connection','profile','admission','run_ref',
    'lookup_found','lookup_not_found','lookup_unknown','held',
    'cancellation_ref','cancellation','cancellation_lookup','operation_attempt_ref','cancellation_attempt']) emit(schemas[name], `wire_${name}_shape`);
  emit({$ref: 'check_outcome'}, 'wire_check_outcome_shape');
  const observationStart = functions.length;
  for (const name of ['owner_ref', 'owner_cursor', 'owner_observations', 'run_plan_view']) {
    emit(schemas[name], `wire_${name}_shape`);
  }
  const observationFunctions = functions.slice(observationStart);
  functions.push('///|\nenum WireResponseIssue {\n  InvalidShape\n  ConnectionMismatch\n  RequestedValueUnavailable\n}\n');
  for (const [name, rule] of Object.entries(rules)) {
    const lines = [`if !wire_connection_shape(selected) || !wire_${name}_shape(value) { return Some(InvalidShape) }`,
      'guard value is Object(fields) else { return Some(InvalidShape) }',
      'guard selected is Object(connection) else { return Some(InvalidShape) }'];
    for (const field of rule.matchConnection) lines.push(`if fields.get(${quote(field)}) != connection.get(${quote(field)}) { return Some(ConnectionMismatch) }`);
    for (const [field, requested] of Object.entries(rule.requireRequested)) lines.push(`if connection.get(${quote(field)}) == Some(Json::string(${quote(requested)})) && fields.get(${quote(field)}) != Some(Json::string(${quote(requested)})) { return Some(RequestedValueUnavailable) }`);
    functions.push(`///|\nfn wire_${name}_issue(value : Json, selected : Json) -> WireResponseIssue? {\n  ${lines.join('\n  ')}\n  None\n}\n`);
    if (name === 'admission') functions.push(`///|\nfn wire_${name}(value : Json, selected : Json) -> Bool {\n  wire_${name}_issue(value, selected) is None\n}\n`);
  }
  for (const [name, rule] of Object.entries(requestRules)) {
    if (name === 'run_wait') continue;
    const expected = emit(schemas[rule.expectedSchema].properties[rule.matchRequest]);
    const alternatives = rule.schemas.map(schema => {
      const shape = `wire_${schema}_shape(value)`;
      return Object.hasOwn(schemas[schema].properties, rule.matchRequest)
        ? `(${shape} && fields.get(${quote(rule.matchRequest)}) == Some(Json::string(expected)))`
        : shape;
    });
    functions.push(`///|\nfn wire_${name}(value : Json, expected : String) -> Bool {\n` +
      `  if !${expected}(Json::string(expected)) { return false }\n` +
      '  guard value is Object(fields) else { return false }\n' +
      `  ${alternatives.join(' ||\n  ')}\n}\n`);
  }
  // Owner observations are tested against the Native wire contract, but are
  // not a CLI operation yet. Keep their exclusive helpers in white-box test
  // output. Any helper also reached by a production validator stays there.
  const observationSet = new Set(observationFunctions);
  const candidates = new Map(observationFunctions.map(source =>
    [/\bfn (wire_[a-z0-9_]+)\(/u.exec(source)[1], source]));
  const production = functions.filter(source => !observationSet.has(source));
  const report = nativeCheckReportRules(reportRules);
  const reached = new Set();
  const pending = [production.join('\n') + report];
  while (pending.length) {
    for (const [, name] of pending.pop().matchAll(/\b(wire_[a-z0-9_]+)\(/gu)) {
      if (candidates.has(name) && !reached.has(name)) {
        reached.add(name);
        pending.push(candidates.get(name));
      }
    }
  }
  const testOnly = new Set([...candidates].filter(([name]) => !reached.has(name))
    .map(([, source]) => source));
  const header = '// Generated from spec/contracts/actql-client-host.json.\n// Run: node scripts/generate-client-host-wire.mjs --write\n\n';
  const source = header + finiteWireNumberSource('native') + functions.filter(source => !testOnly.has(source)).join('\n') + '\n' + report;
  // Use the repository's pinned formatter, also required by the CI formatting gate.
  const formatter = process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin', 'moonfmt') : 'moonfmt';
  const format = input => {
    // The generated body exceeds ordinary pipe capacity. Supply a finite file
    // as stdin so synchronous formatting needs no concurrent input-pipe writer.
    // Keep the same formatter mode, output checks and execution deadline.
    // Installed consumers may configure their temp root before creating their
    // owned scratch. Freshness checks run first and use that same root.
    const parent = tmpdir();
    mkdirSync(parent, {recursive: true});
    const directory = mkdtempSync(join(parent, 'actql-native-wire-'));
    let fd;
    try {
      const path = join(directory, 'stdin.mbt');
      writeFileSync(path, input, {encoding: 'utf8', mode: 0o600, flag: 'wx'});
      fd = openSync(path, 'r');
      return execFileSync(formatter, ['-'], {
        stdio: [fd, 'pipe', 'pipe'], encoding: 'utf8', timeout: 10000,
      });
    } finally {
      try { if (fd !== undefined) closeSync(fd); }
      finally { rmSync(directory, {recursive: true, force: true}); }
    }
  };
  if (checkOutcomePredicates.size !== 1) throw Error('AmbiguousNativeCheckOutcomePredicate');
  return {nativeCheckOutcome: [...checkOutcomePredicates][0], native: format(source), nativeTests: format(header + observationFunctions
    .filter(source => testOnly.has(source)).join('\n') + '\n')};
}

export function responseRules(registry) {
  const rules = registry.response_rules;
  if (!rules || Object.keys(rules).sort().join() !== 'admission,profile') throw new Error('InvalidClientHostResponseRules');
  for (const [name, rule] of Object.entries(rules)) {
    if (Object.keys(rule).sort().join() !== 'matchConnection,requireRequested' ||
        !Array.isArray(rule.matchConnection) || new Set(rule.matchConnection).size !== rule.matchConnection.length ||
        rule.matchConnection.some(field => !registry.schemas[name].properties[field] || !registry.schemas.connection.properties[field]) ||
        Object.entries(rule.requireRequested).some(([field,value]) => !registry.schemas[name].properties[field]?.enum?.includes(value) || !registry.schemas.connection.properties[field]?.enum?.includes(value))) throw new Error('InvalidClientHostResponseRule');
  }
  return rules;
}

export function jsResponseRules(rules) {
  return Object.entries(rules).map(([name,rule]) => `export const valid${name === 'profile' ? 'Profile' : 'Admission'}Contract = (value, selected) =>\n  validConnectionShape(selected) && valid${name === 'profile' ? 'Profile' : 'Admission'}Shape(value)${rule.matchConnection.map(field => ` &&\n  value.${field} === selected.${field}`).join('')}${Object.entries(rule.requireRequested).map(([field,value]) => ` &&\n  !(selected.${field} === ${JSON.stringify(value)} && value.${field} !== ${JSON.stringify(value)})`).join('')};\n`).join('');
}

// The requested identity uses the same field contract as the reply. Every
// correlated variant must require that field with an identical definition;
// uncorrelated closed variants still validate the caller's expected identity.
export function requestResponseRules(registry, schemas) {
  const rules = registry.request_response_rules;
  const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  const canonical = value => Array.isArray(value) ? value.map(canonical) :
    record(value) ? Object.fromEntries(Object.keys(value).sort().map(key =>
      [key, canonical(value[key])])) : value;
  const invalid = () => { throw new Error('InvalidClientHostRequestResponseRule'); };
  if (!record(rules) || Object.keys(rules).sort().join() !== 'held,request_lookup,run_wait') invalid();
  return Object.fromEntries(Object.entries(rules).map(([name, rule]) => {
    if (name === 'run_wait') {
      if (!record(rule) || Object.keys(rule).sort().join() !== 'revisionField,schema,stableStatuses' ||
          rule.schema !== 'run_state' || rule.revisionField !== 'revision' ||
          !Array.isArray(rule.stableStatuses) || rule.stableStatuses.length === 0 ||
          new Set(rule.stableStatuses).size !== rule.stableStatuses.length ||
          rule.stableStatuses.some(status => !schemas.run_state.properties.status.enum.includes(status)) ||
          JSON.stringify(canonical(schemas.run_state.properties.revision)) !==
            JSON.stringify(canonical({type:'integer',minimum:0,maximum:9007199254740991}))) invalid();
      return [name, rule];
    }
    if (!record(rule) || Object.keys(rule).sort().join() !== 'matchRequest,schemas' ||
        typeof rule.matchRequest !== 'string' || !/^[a-zA-Z][a-zA-Z0-9]*$/u.test(rule.matchRequest) ||
        !Array.isArray(rule.schemas) || rule.schemas.length === 0 ||
        new Set(rule.schemas).size !== rule.schemas.length ||
        rule.schemas.some(schema => !['lookup_found', 'lookup_not_found', 'lookup_unknown', 'held'].includes(schema) ||
          schemas[schema]?.type !== 'object' || !record(schemas[schema].properties) ||
          schemas[schema].additionalProperties !== false)) invalid();
    const correlated = rule.schemas.filter(schema =>
      Object.hasOwn(schemas[schema].properties, rule.matchRequest));
    if (correlated.length === 0) invalid();
    const field = schemas[correlated[0]].properties[rule.matchRequest];
    if (field.type !== 'string' || correlated.some(schema =>
      !schemas[schema].required?.includes(rule.matchRequest) ||
      JSON.stringify(canonical(schemas[schema].properties[rule.matchRequest])) !==
        JSON.stringify(canonical(field)))) invalid();
    return [name, {...rule, expectedSchema: correlated[0]}];
  }));
}

export function jsRequestResponseRules(schemas, rules) {
  return Object.entries(rules).map(([name, rule]) => {
    if (name === 'run_wait') {
      return `export const validRunWaitContract = (value, since) =>\n` +
        `  valid(value, schemas.${rule.schema}) &&\n` +
        `  (since === null || valid(since, schemas.${rule.schema}.properties.${rule.revisionField})) &&\n` +
        `  ${JSON.stringify(rule.stableStatuses)}.includes(value.status) &&\n` +
        `  (since === null || value.${rule.revisionField} > since);\n`;
    }
    const exportName = name === 'held' ? 'Held' : 'RequestLookup';
    const alternatives = rule.schemas.map(schema => {
      const shape = `valid(value, schemas.${schema})`;
      return Object.hasOwn(schemas[schema].properties, rule.matchRequest)
        ? `(${shape} && value.${rule.matchRequest} === expected)` : shape;
    });
    return `export const valid${exportName}Contract = (value, expected) =>\n` +
      `  valid(expected, schemas.${rule.expectedSchema}.properties.${rule.matchRequest}) &&\n` +
      `  (${alternatives.join(' ||\n   ')});\n`;
  }).join('');
}
