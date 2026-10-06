import {execFileSync} from 'node:child_process';
import {join} from 'node:path';

// Compile the selected wire schemas to ordinary MoonBit predicates. This is a
// build-time projection, not a schema interpreter in the Native executable.
export function nativeClientWire(schemas, rules, requestRules) {
  const functions = [];
  let serial = 0;
  const quote = JSON.stringify;
  function emit(schema, name = `wire_rule_${serial++}`) {
    const lines = [];
    for (const key of Object.keys(schema)) if (!['type','required','properties',
      'additionalProperties','items','uniqueItems','const','enum','pattern',
      'minLength','maxLength','minimum','maximum','minItems','maxItems',
      'allOf','oneOf','not'].includes(key)) throw new Error(`UnsupportedNativeWireRule:${key}`);
    if (Object.hasOwn(schema, 'const') && Object.hasOwn(schema, 'enum')) {
      throw new Error('UnsupportedNativeWireConstAndEnum');
    }
    if (schema.additionalProperties === false && !schema.properties) {
      throw new Error('UnsupportedNativeWireClosedObjectWithoutProperties');
    }
    // Refuse combinations this bounded compiler does not implement. The JS
    // projection can express untyped conditional constraints; silently dropping
    // them here would recreate the original cross-consumer rule divergence.
    for (const [type, keys] of [
      ['string', ['minLength', 'maxLength', 'pattern']],
      ['integer', ['minimum', 'maximum']],
      ['array', ['items', 'uniqueItems', 'minItems', 'maxItems']],
    ]) if (keys.some(key => Object.hasOwn(schema, key)) && schema.type !== type) {
      throw new Error(`UnsupportedNativeWireConstraintType:${type}`);
    }
    if (schema.allOf) for (const rule of schema.allOf) lines.push(`if !${emit(rule)}(value) { return false }`);
    if (schema.oneOf) lines.push(`if [${schema.oneOf.map(rule => `${emit(rule)}(value)`).join(', ')}].filter(fn(ok) { ok }).length() != 1 { return false }`);
    if (schema.not) lines.push(`if ${emit(schema.not)}(value) { return false }`);
    if (schema.const !== undefined || schema.enum) {
      const values = schema.enum ?? [schema.const];
      if (values.some(value => typeof value !== 'string')) throw new Error('UnsupportedNativeWireLiteral');
      lines.push(`guard value is String(text) else { return false }`,
        `if !(${values.map(value => `text == ${quote(value)}`).join(' || ')}) { return false }`);
    }
    if (schema.type === 'string') {
      lines.push('guard value is String(text) else { return false }');
      if (schema.minLength !== undefined) lines.push(`if text.iter().count() < ${schema.minLength} { return false }`);
      if (schema.maxLength !== undefined) lines.push(`if text.length() > ${schema.maxLength} { return false }`);
      if (schema.pattern === '^[^\\u0000-\\u001f\\u007f]+$') lines.push('if text.is_empty() { return false }', 'for character in text { if character.to_int() < 32 || character.to_int() == 127 { return false } }');
      else if (schema.pattern === '^sha256:[0-9a-f]{64}$') lines.push('if text.length() != 71 || !text.has_prefix("sha256:") { return false }', 'for character in text[7:] { if !((character >= \'0\' && character <= \'9\') || (character >= \'a\' && character <= \'f\')) { return false } }');
      else if (schema.pattern !== undefined) throw new Error(`UnsupportedNativeWirePattern:${schema.pattern}`);
    } else if (schema.type === 'integer') {
      lines.push('guard value is Number(number, ..) else { return false }', 'if number != number.floor() || number < -9007199254740991.0 || number > 9007199254740991.0 { return false }');
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
      else if (schema.additionalProperties !== undefined) throw new Error('UnsupportedNativeWireAdditionalProperties');
      for (const key of schema.required ?? []) lines.push(`if !fields.contains(${quote(key)}) { return false }`);
      for (const [key, rule] of Object.entries(schema.properties ?? {})) lines.push(`if fields.get(${quote(key)}) is Some(item) { if !${emit(rule)}(item) { return false } }`);
    } else if (schema.type !== undefined) throw new Error(`UnsupportedNativeWireType:${schema.type}`);
    functions.push(`///|\nfn ${name}(value : Json) -> Bool {\n  ${lines.join('\n  ')}\n  true\n}\n`);
    return name;
  }
  for (const name of ['connection','profile','admission','run_ref',
    'lookup_found','lookup_not_found','lookup_unknown','held']) emit(schemas[name], `wire_${name}_shape`);
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
  const source = '// Generated from spec/contracts/actql-client-host.json.\n// Run: node scripts/generate-client-host-wire.mjs --write\n\n' + functions.join('\n');
  // Use the repository's pinned formatter, also required by the CI formatting gate.
  const formatter = process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin', 'moonfmt') : 'moonfmt';
  return execFileSync(formatter, ['-'], {input: source, encoding: 'utf8', timeout: 10000});
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
  if (!record(rules) || Object.keys(rules).sort().join() !== 'held,request_lookup') invalid();
  return Object.fromEntries(Object.entries(rules).map(([name, rule]) => {
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
