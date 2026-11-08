import {nativeFileLookupTransportSchema} from './native-file-lookup-contract.mjs';
import {verifyNativeFileReadProfile} from './native-file-read-profile-contract.mjs';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';
import {resolveControlSchema} from './interactive-run-control-schema.mjs';
import {amountMicroPattern} from './interactive-run-control-contract.mjs';
import {generateEffectLocalOperationVectors} from './effect-local-operation-vectors.mjs';
import {generateEffectReviewVectors} from './effect-review-projection-vectors.mjs';
import {checkInstallationPublicationStorageSchema} from './installation-publication-storage-contract.mjs';

verifyNativeFileReadProfile();

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(root, 'spec/contracts/actql-protocol-schemas.json');
const output = join(
  root, 'src/run_publication/protocol_schema.generated.mbt',
);
const document = JSON.parse(readFileSync(source, 'utf8'));
checkInstallationPublicationStorageSchema(document);
const stage = JSON.parse(readFileSync(join(root,
  'spec/contracts/actql-stage-contracts.json'), 'utf8'));
const profiles = JSON.parse(readFileSync(join(root,
  'spec/contracts/actql-production-profile-schemas.json'), 'utf8'));
const lookup = JSON.parse(readFileSync(join(root,
  'spec/contracts/actql-lookup-identities.json'), 'utf8'));
const control = JSON.parse(readFileSync(join(root,
  'spec/contracts/actql-interactive-run-control.json'), 'utf8'));
const publication = JSON.parse(readFileSync(join(root,
  'spec/contracts/actql-run-publication.json'), 'utf8'));
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
  content_generation: Object.freeze({
    schema: 'content_generation',
    identity: 'generation_cid',
  }),
  content_input_artifact: Object.freeze({
    schema: 'content_input_artifact', identity: 'input_artifact_cid',
  }),
  content_evidence: Object.freeze({
    schema: 'content_evidence', identity: 'evidence_cid', registry: 'profiles',
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
    schema: 'model_invocation_evidence_compatible',
    identity: 'model_invocation_evidence_cid',
  }),
  model_capture_bundle: Object.freeze({
    schema: 'model_capture_bundle_compatible',
    identity: 'bundle_cid',
  }),
  model_slot_capture: Object.freeze({
    schema: 'model_slot_capture', identity: 'self_cid', registry: 'stage',
  }),
  ...Object.fromEntries(['model_dispatch_authority', 'model_call_attempt',
    'model_attempt_accounting', 'model_attempt_outcome', 'model_attachment_admission', 'model_prompt',
    'model_retry_policy', 'model_backoff', 'model_media_input'].map(schema =>
    [schema, Object.freeze({schema, identity: 'self_cid'})])),
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
  effect_local_operation_receipt: Object.freeze({
    schema: 'effect_local_operation_receipt', identity: 'receipt_cid',
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
  model_effective_inputs: Object.freeze({
    schema: 'model_effective_inputs', identity: 'effective_inputs_cid',
  }),
  model_input_artifact: Object.freeze({
    schema: 'model_input_artifact', identity: 'input_artifact_cid',
  }),
  model_input_key: Object.freeze({
    schema: 'model_input_key', identity: 'input_key_cid',
  }),
  model_call_slot: Object.freeze({
    schema: 'model_call_slot', identity: 'model_call_slot_cid',
  }),
  ...Object.fromEntries(['model_invocation_scope', 'model_provider_binding']
    .map(schema => [schema, Object.freeze({schema, identity: 'self_cid'})])),
  run_review_projection: Object.freeze({
    schema: 'run_review_projection', identity: 'review_projection_cid',
  }),
  request_key_set: Object.freeze({
    schema: 'key_set', identity: 'self_cid', registry: 'lookup',
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
  if (schema.pattern === amountMicroPattern) return 12;
  switch (schema.pattern) {
    case undefined: return 0;
    case '^sha256:[0-9a-f]{64}$':
    case '^sha256:[a-f0-9]{64}$': return 1;
    case '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$':
    case '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$':
      return 2;
    case '^[A-Za-z0-9][A-Za-z0-9._+:-]{0,127}$': return 3;
    case '^[0-9a-f]{64}$': return 4;
    case '^\\$': return 5;
    case '^command:': return 6;
    case '^[A-Za-z_][A-Za-z0-9_]*$': return 7;
    case '^(0|[1-9][0-9]*)$':
    case '^(0|[1-9][0-9]*)$(?![\\s\\S])': return 8;
    case '^[^\\u0000-\\u001f\\u007f]+$':
    case '^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])': return 9;
    case '^ACTQL_E_[A-Z0-9_]+$': return 10;
    case '^[A-Z]{3}$(?![\\s\\S])': return 13;
    case '^(0|-?[1-9][0-9]*)$(?![\\s\\S])': return 14;
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
  'minProperties', 'maxProperties', 'maxLength', 'propertyNames', 'items',
  'minItems', 'maxItems', 'uniqueItems', 'prefixItems',
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
  if (schema.maxLength !== undefined || schema.maxProperties !== undefined) {
    const rest = {...schema};
    const bounds = [];
    if (schema.maxLength !== undefined) {
      if (schema.type !== 'string' || !Number.isSafeInteger(schema.maxLength) ||
          schema.maxLength < 0) throw new Error('Invalid string ceiling');
      nodes.push(`StringCeilingRule(${schema.maxLength})`);
      bounds.push(nodes.length - 1);
      delete rest.maxLength;
    }
    if (schema.maxProperties !== undefined) {
      if (schema.type !== undefined && schema.type !== 'object' ||
          !Number.isSafeInteger(schema.maxProperties) || schema.maxProperties < 0)
        throw new Error('Invalid object ceiling');
      nodes.push(`ObjectCeilingRule(${schema.maxProperties})`);
      bounds.push(nodes.length - 1);
      delete rest.maxProperties;
    }
    bounds.push(emitSchema(rest, assumedType));
    nodes.push(`AllOfRule([${bounds.join(', ')}])`);
    return nodes.length - 1;
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
  if (Array.isArray(schema.const)) {
    // The Run review's one fixed approval claim has an exact equivalent in
    // the existing homogeneous-array rule. Do not weaken arbitrary tuples.
    requireKeywords(schema, 'singleton array literal', ['type', 'const']);
    if (schema.type !== undefined && schema.type !== 'array' ||
        schema.const.length !== 1 || typeof schema.const[0] !== 'string') {
      throw new Error('Unsupported publication schema array literal');
    }
    return emitSchema({type: 'array', minItems: 1, maxItems: 1,
      items: {type: 'string', const: schema.const[0]}});
  }
  if (Array.isArray(schema.type)) {
    const alternatives = schema.type.map(type => emitSchema({...schema, type}));
    nodes.push(`protocol_one_of_rule([${alternatives.join(', ')}])`);
    return nodes.length - 1;
  }
  if (schema.type === undefined) {
    if (schema.propertyNames !== undefined) {
      return emitSchema({...schema, type: 'object'});
    }
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
    if (schema.prefixItems !== undefined) {
      requireKeywords(schema, 'tuple', [
        'type', 'prefixItems', 'items', 'minItems', 'maxItems',
      ]);
      if (!Array.isArray(schema.prefixItems) || schema.items !== false ||
          schema.minItems !== schema.prefixItems.length ||
          schema.maxItems !== schema.prefixItems.length) {
        throw new Error('Unsupported tuple schema: exact closed positional shape required');
      }
      const items = schema.prefixItems.map(item => emitSchema(item));
      nodes.push(`protocol_tuple_rule([${items.join(', ')}])`);
      return nodes.length - 1;
    }
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
      ? 7 : names?.minLength === 1 && Object.keys(names).length === 1 ? 11 : 0;
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

function registerArtifactSchema(name, selection) {
  let complete = structuredClone(
    selection.registry === 'publication' ? publication.schemas[selection.schema]
      : selection.registry === 'lookup' ? lookup.schemas[selection.schema]
      : selection.registry === 'stage' ? stage.schemas[selection.schema]
        : selection.registry === 'profiles' ? profiles.schemas[selection.schema]
      : document.artifact_schemas[selection.schema],
  );
  if (complete === undefined) {
    throw new Error(`Missing publication schema: ${selection.schema}`);
  }
  if (name === 'native_file_lookup_transport' &&
      selection.registry === 'lookup' && selection.schema === 'transport_plan') {
    complete = nativeFileLookupTransportSchema(lookup);
  }
  if (selection.registry === 'lookup' && selection.schema === 'key_set') {
    // Preserve the pinned scalar/reference contract branches verbatim. The
    // recursive object/array branches cannot be KeyComparable and are rejected
    // by the shared typed reader/order admission as well. Do not introduce a
    // second recursive value-contract compiler for this scalar key boundary.
    const hasReference = value => value && typeof value === 'object' &&
      (Object.hasOwn(value, '$ref') || Object.values(value).some(hasReference));
    const contracts = structuredClone(complete.$defs.value_contract);
    contracts.oneOf = contracts.oneOf.filter(branch => !hasReference(branch));
    // Decimal scale conditions inherit the already-required integer property.
    // Copy only that declared type into the descriptor fragment; retain every
    // original precision/scale condition and bound from the registry.
    for (const branch of contracts.oneOf) {
      for (const condition of branch.allOf ?? []) {
        for (const arm of ['then', 'else']) {
          for (const [name, fragment] of Object.entries(condition[arm]?.properties ?? {})) {
            if (fragment.type === undefined) {
              const type = branch.properties?.[name]?.type;
              if (type === undefined) throw new Error('UnknownLookupConditionalProperty');
              fragment.type = type;
            }
          }
        }
      }
    }
    complete.properties.key_roles.items.properties.value_contract = contracts;
    delete complete.$defs;
  }
  const body = structuredClone(complete);
  if (['model_invocation_evidence', 'model_capture_bundle', 'effect_row_outcome_receipt', 'lookup_barrier'].includes(name)) {
    // Each closed registered alternative excludes only its own identity field.
    // Unknown versions and mixed proof/runtime forms match no branch.
    for (const version of body.oneOf) {
      omitRequiredProperty(version, selection.identity);
    }
  } else {
    omitRequiredProperty(body, selection.identity);
  }
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

for (const [name, selection] of Object.entries(selected)) {
  if (name !== "request_key_set") registerArtifactSchema(name, selection);
}

// EffectOutcome is a value contract, not a self-addressed artifact. Reuse
// its pinned protocol schema without inventing an identity-excluded body.
roots.set('effect_outcome:true', emitSchema(document.schemas.effect_outcome));

for (const [name, schema] of Object.entries(control.schemas)) {
  const complete = resolveControlSchema(schema, control);
  roots.set(`${name}:true`, emitSchema(complete));
  if (schema.properties?.self_cid) {
    const body = structuredClone(complete);
    omitRequiredProperty(body, 'self_cid');
    roots.set(`${name}:false`, emitSchema(body));
  }
}

// Append the new descriptor without renumbering historical artifact/control
// rules. This is the same generator/validator, not another registry or Owner.
registerArtifactSchema('model_response_profile', {
  schema: 'model_response_profile', identity: 'self_cid',
});
for (const name of ['model_raw_capture_policy', 'model_raw_response',
  'model_original_storage_binding']) {
  registerArtifactSchema(name, {
    schema: name, identity: 'self_cid', registry: 'publication',
  });
}

// Append without renumbering historical descriptors. Byte-addressed original
// resource evidence has no self field or configuration-CID exclusion path.
if (document.artifact_schemas.model_original_resource_state !== undefined) {
  roots.set('model_original_resource_state:true',
    emitSchema(document.artifact_schemas.model_original_resource_state));
}

for (const name of ['model_journal_entry', 'model_journal_settlement']) {
  registerArtifactSchema(name, {schema: name, identity: 'self_cid'});
}

// The original value-only RunState has no CID/control envelope. Reuse its
// closed pinned schema for persisted metadata without changing any wire/pin.
roots.set('run_state:true', emitSchema(document.artifact_schemas.run_state));

// The Effect review is the existing self-addressed artifact, not its private
// Preview or the full-byte digest used by the physical evidence Store.
registerArtifactSchema('review_projection', {
  schema: 'review_projection', identity: 'review_projection_cid',
});

// Installation storage association is private DATA, not Run evidence. Append
// its owned descriptor without renumbering any existing contract rules.
if (document.artifact_schemas.installation_publication_storage_binding !== undefined) {
  roots.set('installation_publication_storage_binding:true',
    emitSchema(document.artifact_schemas.installation_publication_storage_binding));
}

// The existing lookup envelope appends to the same descriptor owner; preserve
// every prior rule/root index rather than renumbering unrelated contracts.
registerArtifactSchema('request_key_set', selected.request_key_set);

// Rule descriptors are private immutable DATA. Share only exactly identical
// constructor expressions during generation; every original table slot and
// child/root index remains present. No runtime map, schema omission or lazy
// first-use construction is introduced.
export function shareProtocolRuleConstructors(constructors) {
  const first = new Map();
  return constructors.map((node, index) => {
    const previous = first.get(node);
    if (previous !== undefined) return `nodes[${previous}]`;
    first.set(node, index);
    return node;
  });
}

// Keep compiler text segments finite without concatenating temporary rule
// arrays. Each helper borrows the same destination. Capacity uses the pinned
// target's existing constructor semantics (a hint only on JS), not a new
// physical memory guarantee or a numerical Model profile.
registerArtifactSchema('native_file_content_read', {
  schema: 'native_file_content_read', identity: 'transport_cid', registry: 'profiles',
});
registerArtifactSchema('native_file_lookup_transport', {
  schema: 'transport_plan', identity: 'self_cid', registry: 'lookup',
});
registerArtifactSchema('lookup_barrier', {
  schema: 'lookup_barrier', identity: 'barrier_cid', registry: 'profiles',
});
registerArtifactSchema('native_file_lookup_batch_plan', {
  schema: 'batch_plan', identity: 'self_cid', registry: 'lookup',
});
for (const [name, schema] of [
  ['native_file_lookup_request', 'request'],
  ['native_file_lookup_call_slot', 'call_slot'],
  ['native_file_lookup_activation', 'activation'],
  ['native_file_lookup_raw_response', 'raw_response'],
]) {
  registerArtifactSchema(name, {schema, identity: 'self_cid', registry: 'lookup'});
}
const sharedNodes = shareProtocolRuleConstructors(nodes);

const nodeChunks = [];
for (let offset = 0; offset < sharedNodes.length; offset += 1000) {
  nodeChunks.push(sharedNodes.slice(offset, offset + 1000));
}
let generated = `// Generated by scripts/run-publication-protocol.mjs.\n` +
  `// Product validation is implemented by protocol_schema.mbt.\n\n` +
  `///|\nfn generated_protocol_schema_nodes() -> ` +
  `Array[ProtocolSchemaRule] {\n` +
  `  let nodes : Array[ProtocolSchemaRule] = Array(capacity=${nodes.length})\n` +
  nodeChunks.map((_, i) => `  generated_protocol_schema_nodes_${i}(nodes)\n`).join('') +
  `  nodes\n}\n\n` +
  nodeChunks.map((chunk, i) => `///|\nfn generated_protocol_schema_nodes_${i}(` +
    `nodes : Array[ProtocolSchemaRule]) -> Unit {\n` +
    chunk.map(node => `  nodes.push(${node})\n`).join('') + `}\n\n`).join('') +
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

generated += `\n///|\nfn generated_interactive_protocol_schema(name : String) -> Bool {\n` +
  `  match name {\n` + Object.keys(control.schemas)
    .map(name => `    ${moonString(name)} => true\n`).join('') +
  `    _ => false\n  }\n}\n` +
  `\n///|\nfn generated_interactive_identity_field(name : String) -> String? {\n` +
  `  match name {\n` + Object.keys(control.identity_domains)
    .map(name => `    ${moonString(name)} => Some("self_cid")\n`).join('') +
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
// Existing protocol freshness also checks the independent review preimages.
// This never rewrites an expected CID from a product runtime observation.
const reviewVectors = join(root,
  'src/run_publication/effect_review_projection.generated_wbtest.mbt');
if (readFileSync(reviewVectors, 'utf8') !== generateEffectReviewVectors()) {
  throw new Error(`Independent Effect review vectors are stale: ${reviewVectors}`);
}
const localVectors = join(root,
  'src/run_publication/effect_local_operation.generated_wbtest.mbt');
if (readFileSync(localVectors, 'utf8') !== generateEffectLocalOperationVectors()) {
  throw new Error(`Independent local-operation vectors are stale: ${localVectors}`);
}
// Count actual registered names, including value-only and appended private
// descriptors. A second handwritten offset drifts when a consumer is added.
const registeredNames = new Set([...roots.keys()].map(key => key.slice(0, key.lastIndexOf(':'))));
const artifactSchemaCount = [...registeredNames].filter(name => !Object.hasOwn(control.schemas, name)).length;
console.log(`${artifactSchemaCount} Run and Effect schemas and ` +
  `${Object.keys(control.schemas).length} interactive schemas verified.`);
