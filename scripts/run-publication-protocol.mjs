import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(root, 'spec/contracts/actql-protocol-schemas.json');
const output = join(
  root, 'src/run_publication/protocol_schema.generated.mbt',
);
const document = JSON.parse(readFileSync(source, 'utf8'));
const selected = Object.freeze({
  result_plan: Object.freeze({
    schema: 'result_plan',
    identity: 'result_plan_logical_cid',
  }),
  bound_invocation_template: Object.freeze({
    schema: 'bound_invocation_template',
    identity: 'bound_invocation_template_cid',
  }),
  prepared_invocation: Object.freeze({
    schema: 'prepared_invocation',
    identity: 'prepared_invocation_cid',
  }),
  run_authorization: Object.freeze({
    schema: 'run_authorization',
    identity: 'run_authorization_cid',
  }),
  observation_set: Object.freeze({
    schema: 'observation_set',
    identity: 'observation_set_cid',
  }),
  normalization_journal: Object.freeze({
    schema: 'normalization_journal',
    identity: 'journal_cid',
  }),
  source_evidence: Object.freeze({
    schema: 'source_evidence',
    identity: 'source_evidence_cid',
  }),
  source_input_logical: Object.freeze({
    schema: 'source_input_logical',
    identity: 'input_logical_cid',
  }),
  authoring_context: Object.freeze({
    schema: 'authoring_context',
    identity: 'authoring_context_cid',
  }),
  model_invocation_evidence: Object.freeze({
    schema: 'model_invocation_evidence',
    identity: 'model_invocation_evidence_cid',
  }),
  run_receipt: Object.freeze({
    schema: 'run_receipt',
    identity: 'receipt_identity_cid',
  }),
  captured_run: Object.freeze({
    schema: 'captured_run',
    identity: 'captured_run_cid',
  }),
  result_delivery_receipt: Object.freeze({
    schema: 'result_delivery_receipt',
    identity: 'result_delivery_receipt_cid',
  }),
  effect_preview: Object.freeze({
    schema: 'effect_preview',
    identity: 'effect_preview_cid',
  }),
  effect_source_artifact: Object.freeze({
    schema: 'effect_source_artifact',
    identity: 'result_artifact_cid',
  }),
  effect_row_outcome_receipt: Object.freeze({
    schema: 'effect_row_outcome_receipt',
    identity: 'receipt_cid',
  }),
  effect_apply_receipt: Object.freeze({
    schema: 'effect_apply_receipt',
    identity: 'receipt_cid',
  }),
  effect_set_apply_receipt: Object.freeze({
    schema: 'effect_set_apply_receipt',
    identity: 'receipt_cid',
  }),
  effect_reconciliation_receipt: Object.freeze({
    schema: 'effect_reconciliation_receipt',
    identity: 'reconciliation_receipt_cid',
  }),
  invocation_bindings: Object.freeze({
    schema: 'invocation_bindings',
    identity: 'invocation_bindings_cid',
  }),
});

const moonString = value => JSON.stringify(value);
const optionString = value => value === undefined
  ? 'None'
  : `Some(${moonString(value)})`;
const optionBool = value => value === undefined
  ? 'None'
  : `Some(${String(value)})`;
const optionInt64 = value => value === undefined
  ? 'None'
  : `Some(${String(value)}L)`;
const stringArray = values =>
  `[${values.map(moonString).join(', ')}]`;

function patternTag(schema) {
  if (schema.format === 'date-time') return 2;
  switch (schema.pattern) {
    case undefined: return 0;
    case '^sha256:[0-9a-f]{64}$':
    case '^sha256:[a-f0-9]{64}$': return 1;
    case '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$':
      return 2;
    case '^[A-Za-z0-9][A-Za-z0-9._+:-]{0,127}$': return 3;
    case '^[0-9a-f]{64}$': return 4;
    case '^\\$': return 5;
    case '^command:': return 6;
    case '^[A-Za-z_][A-Za-z0-9_]*$': return 7;
    default:
      throw new Error(`Unsupported publication schema pattern: ${schema.pattern}`);
  }
}

const nodes = [];
const supportedKeywords = new Set([
  '$schema', '$id', 'title', 'description', '$comment', 'examples',
  'default', 'deprecated', 'readOnly', 'writeOnly', 'type', 'const',
  'enum', 'oneOf', 'allOf', 'pattern', 'format', 'minLength', 'minimum',
  'anyOf', 'not', 'if', 'then', 'else',
  'maximum', 'properties', 'required', 'additionalProperties',
  'minProperties', 'propertyNames', 'items', 'minItems', 'maxItems', 'uniqueItems',
]);
const annotationKeywords = new Set([
  '$schema', '$id', 'title', 'description', '$comment', 'examples',
  'default', 'deprecated', 'readOnly', 'writeOnly',
]);

function requireKeywords(schema, type, allowed) {
  for (const key of Object.keys(schema)) {
    if (!annotationKeywords.has(key) && !allowed.includes(key)) {
      throw new Error(`Unsupported ${type} publication schema keyword: ${key}`);
    }
  }
}

function matchesType(value, type) {
  if (type === 'number') return typeof value === 'number' && Number.isFinite(value);
  return inferredType(value) === type;
}

function inferredType(value) {
  if (value === null) return 'null';
  if (typeof value === 'string') return 'string';
  if (typeof value === 'boolean') return 'boolean';
  if (Number.isSafeInteger(value)) return 'integer';
  if (typeof value === 'number') return 'number';
  throw new Error('Unsupported publication schema literal');
}

function emitSchema(schema, assumedType) {
  for (const key of Object.keys(schema)) {
    if (!supportedKeywords.has(key)) {
      throw new Error(`Unsupported publication schema keyword: ${key}`);
    }
  }
  if (schema.oneOf !== undefined) {
    const alternatives = schema.oneOf.map(branch =>
      emitSchema(branch, schema.type ?? assumedType));
    nodes.push(`protocol_one_of_rule([${alternatives.join(', ')}])`);
    const alternativeIndex = nodes.length - 1;
    const siblings = {...schema};
    delete siblings.oneOf;
    if (Object.keys(siblings).some(key => !annotationKeywords.has(key))) {
      const siblingIndex = emitSchema(siblings, assumedType);
      nodes.push(`AllOfRule([${alternativeIndex}, ${siblingIndex}])`);
      return nodes.length - 1;
    }
    return alternativeIndex;
  }
  if (schema.allOf !== undefined) {
    if (!Array.isArray(schema.allOf) || schema.allOf.length === 0) {
      throw new Error('Empty publication schema allOf is unsupported');
    }
    const conditions = schema.allOf.map(branch =>
      emitSchema(branch, schema.type ?? assumedType));
    const siblings = {...schema};
    delete siblings.allOf;
    if (Object.keys(siblings).some(key => !annotationKeywords.has(key))) {
      conditions.push(emitSchema(siblings, assumedType));
    }
    nodes.push(`AllOfRule([${conditions.join(', ')}])`);
    return nodes.length - 1;
  }
  if (schema.anyOf !== undefined) {
    if (!Array.isArray(schema.anyOf) || schema.anyOf.length === 0) {
      throw new Error('Empty publication schema anyOf is unsupported');
    }
    const alternatives = schema.anyOf.map(branch =>
      emitSchema(branch, schema.type ?? assumedType));
    nodes.push(`AnyOfRule([${alternatives.join(', ')}])`);
    const alternativeIndex = nodes.length - 1;
    const siblings = {...schema};
    delete siblings.anyOf;
    if (Object.keys(siblings).some(key => !annotationKeywords.has(key))) {
      const siblingIndex = emitSchema(siblings, assumedType);
      nodes.push(`AllOfRule([${alternativeIndex}, ${siblingIndex}])`);
      return nodes.length - 1;
    }
    return alternativeIndex;
  }
  if (schema.not !== undefined) {
    const excluded = emitSchema(schema.not, schema.type ?? assumedType);
    nodes.push(`NotRule(${excluded})`);
    const excludedIndex = nodes.length - 1;
    const siblings = {...schema};
    delete siblings.not;
    if (Object.keys(siblings).some(key => !annotationKeywords.has(key))) {
      const siblingIndex = emitSchema(siblings, assumedType);
      nodes.push(`AllOfRule([${excludedIndex}, ${siblingIndex}])`);
      return nodes.length - 1;
    }
    return excludedIndex;
  }
  if (schema.if !== undefined) {
    if (schema.then === undefined && schema.else === undefined) {
      throw new Error('Unconstrained publication schema if is unsupported');
    }
    const condition = emitSchema(schema.if, schema.type ?? assumedType);
    const whenTrue = emitSchema(schema.then ?? {}, schema.type ?? assumedType);
    const whenFalse = emitSchema(schema.else ?? {}, schema.type ?? assumedType);
    nodes.push(`ConditionalRule(${condition}, ${whenTrue}, ${whenFalse})`);
    const conditionalIndex = nodes.length - 1;
    const siblings = {...schema};
    delete siblings.if;
    delete siblings.then;
    delete siblings.else;
    if (Object.keys(siblings).some(key => !annotationKeywords.has(key))) {
      const siblingIndex = emitSchema(siblings, assumedType);
      nodes.push(`AllOfRule([${conditionalIndex}, ${siblingIndex}])`);
      return nodes.length - 1;
    }
    return conditionalIndex;
  }
  if (schema.then !== undefined || schema.else !== undefined) {
    throw new Error('Publication schema then/else requires if');
  }
  if (Array.isArray(schema.type)) {
    const alternatives = schema.type.map(type => emitSchema({...schema, type}));
    nodes.push(`protocol_one_of_rule([${alternatives.join(', ')}])`);
    return nodes.length - 1;
  }
  if (schema.type === undefined) {
    if (assumedType === 'object' &&
        (schema.properties !== undefined || schema.required !== undefined ||
         schema.additionalProperties !== undefined)) {
      return emitSchema({...schema, type: 'object'});
    }
    if (schema.const !== undefined) {
      return emitSchema({...schema, type: inferredType(schema.const)});
    }
    if (schema.enum !== undefined) {
      const types = new Set(schema.enum.map(inferredType));
      if (types.size !== 1) {
        throw new Error('Mixed-type publication schema enum is unsupported');
      }
      return emitSchema({...schema, type: [...types][0]});
    }
    if (Object.keys(schema).some(key => !annotationKeywords.has(key))) {
      throw new Error('Unsupported typeless publication schema constraint');
    }
    nodes.push('protocol_any_rule()');
    return nodes.length - 1;
  }
  if (schema.const !== undefined && !matchesType(schema.const, schema.type)) {
    throw new Error('Conflicting publication schema literal and type');
  }
  if (schema.enum !== undefined &&
      (!Array.isArray(schema.enum) || schema.enum.length === 0 ||
       schema.enum.some(value => !matchesType(value, schema.type)))) {
    throw new Error('Conflicting publication schema enum and type');
  }
  if (schema.type === 'null') {
    requireKeywords(schema, 'null', ['type']);
    nodes.push('protocol_null_rule()');
    return nodes.length - 1;
  }
  if (schema.type === 'boolean') {
    requireKeywords(schema, 'boolean', ['type', 'const', 'enum']);
    if (schema.enum !== undefined) {
      throw new Error('Boolean publication schema enum is unsupported');
    }
    nodes.push(`protocol_bool_rule(${optionBool(schema.const)})`);
    return nodes.length - 1;
  }
  if (schema.type === 'string') {
    requireKeywords(schema, 'string', [
      'type', 'const', 'enum', 'pattern', 'format', 'minLength',
    ]);
    const choices = schema.enum ?? [];
    nodes.push(
      `protocol_string_rule(${optionString(schema.const)}, ` +
      `${stringArray(choices)}, ${patternTag(schema)}, ` +
      `${schema.minLength ?? 0})`,
    );
    return nodes.length - 1;
  }
  if (schema.type === 'integer') {
    requireKeywords(schema, 'integer', [
      'type', 'const', 'enum', 'minimum', 'maximum',
    ]);
    if (schema.enum !== undefined) {
      throw new Error('Integer publication schema enum is unsupported');
    }
    if (schema.const !== undefined &&
        (schema.minimum !== undefined && schema.const < schema.minimum ||
         schema.maximum !== undefined && schema.const > schema.maximum)) {
      throw new Error('Conflicting integer publication schema constraints');
    }
    nodes.push(
      `protocol_integer_rule(${optionInt64(schema.const ?? schema.minimum)}, ` +
      `${optionInt64(schema.const ?? schema.maximum)})`,
    );
    return nodes.length - 1;
  }
  if (schema.type === 'number') {
    requireKeywords(schema, 'number', ['type']);
    nodes.push('protocol_number_rule()');
    return nodes.length - 1;
  }
  if (schema.type === 'array') {
    requireKeywords(schema, 'array', [
      'type', 'items', 'minItems', 'maxItems', 'uniqueItems',
    ]);
    const items = emitSchema(schema.items ?? {});
    nodes.push(
      `protocol_array_rule(${items}, ${schema.minItems ?? 0}, ` +
      `${String(schema.uniqueItems === true)}, ${schema.maxItems ?? -1})`,
    );
    return nodes.length - 1;
  }
  if (schema.type === 'object') {
    requireKeywords(schema, 'object', [
      'type', 'properties', 'required', 'additionalProperties',
      'minProperties', 'propertyNames',
    ]);
    const properties = Object.entries(schema.properties ?? {})
      .map(([name, child]) => [name, emitSchema(
        child,
        child.type ?? (child.properties !== undefined ||
          child.required !== undefined ? 'object' : undefined),
      )]);
    let additional = -2;
    if (schema.additionalProperties === false) additional = -1;
    else if (schema.additionalProperties !== undefined &&
        typeof schema.additionalProperties === 'object') {
      additional = emitSchema(schema.additionalProperties);
    }
    const names = schema.propertyNames;
    const forbidden = names !== undefined &&
      Object.keys(names).length === 1 &&
      Object.keys(names.not ?? {}).length === 1 &&
      names.not?.pattern === '^actql_'
      ? 'Some("actql_")'
      : 'None';
    const namePattern = names?.pattern === '^[A-Za-z_][A-Za-z0-9_]*$'
      ? 7 : 0;
    if (schema.propertyNames !== undefined && forbidden === 'None' &&
        namePattern === 0) {
      throw new Error('Unsupported publication propertyNames rule');
    }
    const propertyText = properties
      .map(([name, index]) => `(${moonString(name)}, ${index})`)
      .join(', ');
    const constructor = namePattern === 0
      ? 'protocol_object_rule' : 'protocol_named_object_rule';
    const extra = namePattern === 0 ? '' : `, ${namePattern}`;
    nodes.push(
      `${constructor}([${propertyText}], ` +
      `${stringArray(schema.required ?? [])}, ${additional}, ` +
      `${schema.minProperties ?? 0}, ${forbidden}${extra})`,
    );
    return nodes.length - 1;
  }
  throw new Error(`Unsupported publication schema type: ${schema.type}`);
}

export {emitSchema};

const roots = new Map();
function omitRequiredProperty(schema, field) {
  if (!schema.required?.includes(field) || schema.properties?.[field] === undefined) {
    throw new Error(`Missing Effect Preview identity exclusion: ${field}`);
  }
  schema.required = schema.required.filter(name => name !== field);
  delete schema.properties[field];
}

for (const [name, selection] of Object.entries(selected)) {
  const complete = structuredClone(
    document.artifact_schemas[selection.schema],
  );
  if (complete === undefined) {
    throw new Error(`Missing publication schema: ${selection.schema}`);
  }
  const body = structuredClone(complete);
  omitRequiredProperty(body, selection.identity);
  if (name === 'effect_preview') {
    // The generated body descriptor is the semantic CID preimage, not the
    // transported Preview minus only its self field.
    omitRequiredProperty(body, 'run_identity_cid');
    omitRequiredProperty(body, 'authoring_context');
    const row = body.properties.effects?.items?.properties?.changes?.items;
    if (row === undefined) throw new Error('Missing Effect Preview row schema');
    omitRequiredProperty(row, 'row_idempotency_key');
  }
  roots.set(`${name}:false`, emitSchema(body));
  roots.set(`${name}:true`, emitSchema(complete));
}

// EffectOutcome is a value contract, not a self-addressed artifact. Reuse
// its pinned protocol schema without inventing an identity-excluded body.
roots.set('effect_outcome:true', emitSchema(document.schemas.effect_outcome));

let generated = `// Generated by scripts/run-publication-protocol.mjs.\n` +
  `// Product validation is implemented by protocol_schema.mbt.\n\n` +
  `///|\nfn generated_protocol_schema_nodes() -> ` +
  `Array[ProtocolSchemaRule] {\n  [\n` +
  nodes.map(node => `    ${node},\n`).join('') +
  `  ]\n}\n\n` +
  `///|\nfn generated_protocol_schema_root(` +
  `name : String, complete : Bool) -> Int? {\n` +
  `  match (name, complete) {\n` +
  [...roots.entries()].map(([key, index]) => {
    const separator = key.lastIndexOf(':');
    const name = key.slice(0, separator);
    const complete = key.slice(separator + 1);
    return `    (${moonString(name)}, ${complete}) => Some(${index})\n`;
  }).join('') +
  `    _ => None\n  }\n}\n`;

const formatter = process.env.MOON_HOME
  ? join(process.env.MOON_HOME, 'bin/moonfmt')
  : 'moonfmt';
generated = execFileSync(formatter, ['-'], {
  input: generated,
  encoding: 'utf8',
});

if (process.argv.includes('--write')) writeFileSync(output, generated);
else if (readFileSync(output, 'utf8') !== generated) {
  throw new Error(`Run publication protocol descriptors are stale: ${output}`);
}
console.log(`${Object.keys(selected).length + 1} Run and Effect protocol schemas verified.`);
