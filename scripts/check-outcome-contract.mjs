import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {readCheckReasonCatalog, checkReasonSchemaFromCatalog} from './check-reason-catalog.mjs';

// The public `check` outcome. A distinct contract from actql-diagnostics/0.1
// and actql-plan-result/0.1, which keep their own schemas and identities.
const path = 'spec/contracts/actql-protocol-schemas.json';
const parameterContractSchemaCid = machineCid(JSON.parse(readFileSync(path, 'utf8')).schemas.canonical_value_contract);
const code = {type: 'string', pattern: '^[a-z][a-z0-9_]{0,63}$'};
const opaqueRef = {type: 'string', minLength: 1, maxLength: 128,
  pattern: '^[A-Za-z0-9:_-]+$'};
// The body's ordinary CID is checked by the generated consumer boundary.
// A constant equal to this schema's own CID would create a cyclic preimage.
const schemaCid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};

const documentId = {enum: ['source', 'parameter_declarations', 'parameters']};
const revision = {type: 'string', pattern: '^rev:[0-9a-f]{64}$'};
const integer = {type: 'integer', minimum: 0, maximum: 1048576};
// This is the submitted size, including inputs rejected by admission budgets.
const submittedBytes = {type: 'integer', minimum: 0, maximum: Number.MAX_SAFE_INTEGER};
const location = {oneOf: [
  {type: 'object', additionalProperties: false,
    required: ['kind', 'document_id', 'revision', 'start_byte', 'end_byte', 'precision'],
    properties: {kind: {const: 'text'}, document_id: {const: 'source'}, revision,
      start_byte: integer, end_byte: integer, precision: {enum: ['exact', 'approximate']}}},
  {type: 'object', additionalProperties: false,
    required: ['kind', 'document_id', 'revision', 'pointer'],
    properties: {kind: {const: 'structured'},
      document_id: {enum: ['parameter_declarations', 'parameters']}, revision,
      pointer: {type: 'string', maxLength: 4096, pattern: '^(?:/(?:[^~]|~[01])*)*$'}}},
]};
// The catalog owns the existing closed schema; no semantic checker is added.
export const checkReasonSchema = checkReasonSchemaFromCatalog(readCheckReasonCatalog(), parameterContractSchemaCid);
export const checkReasonSchemaCid = machineCid(checkReasonSchema);

function report(verdicts, reasonSchema = checkReasonSchema) {
  const empty = {type: 'array', items: {}, maxItems: 0};
  const emptyCoverage = {properties: {limits: empty, unresolved: empty}};
  return {
    allOf: [
      {if: {properties: {verdict: {const: 'verified'}}},
        then: {not: {required: ['omissions']}, properties: {reasons: empty, requirements: empty, coverage: emptyCoverage}}},
      {if: {properties: {verdict: {const: 'invalid'}}},
        then: {properties: {reasons: {type: 'array', items: {}, minItems: 1}}}},
      {if: {properties: {verdict: {const: 'undetermined'}}},
        then: {properties: {reasons: empty,
          coverage: {not: emptyCoverage}}}},
    ],
    type: 'object', additionalProperties: false,
    required: ['context_ref', 'coverage', 'inputs', 'reasons', 'requirements', 'scope', 'verdict'],
    properties: {
      context_ref: opaqueRef,
      omissions: {type: 'object', additionalProperties: false, required: ['requirements'],
        properties: {requirements: {const: true}}},
      inputs: {type: 'array', minItems: 1, maxItems: 3, items: {
        type: 'object', additionalProperties: false,
        required: ['document_id', 'revision', 'kind', 'byte_length'],
        properties: {document_id: documentId, revision, kind: {enum: ['text', 'structured']}, byte_length: submittedBytes}}},
      coverage: {
        type: 'object', additionalProperties: false,
        required: ['limits', 'unresolved'],
        properties: {
          limits: {type: 'array', items: {oneOf: [
            {type: 'object', additionalProperties: false, required: ['code'], properties: {code}},
            {type: 'object', additionalProperties: false, required: ['code', 'facts'],
              properties: {code: {const: 'implementation_limit'},
                facts: {type: 'object', additionalProperties: false, required: ['issue'],
                  properties: {issue: {const: 'function_lowering_unresolved'}}},
                location: location.oneOf[0]}},
          ]}},
          unresolved: {type: 'array', items: {
            type: 'object', additionalProperties: false,
            required: ['boundary', 'reason'],
            properties: {boundary: code,
              reason: {const: 'unresolved_protected'}}}},
        },
      },
      reasons: {type: 'array', maxItems: 1024, items: {...reasonSchema,
        allOf: [...reasonSchema.allOf, {not: {properties: {code: {enum: ['parameter_value_required', 'host_capacity_policy_required']}}}}]}},
      requirements: {type: 'array', maxItems: 1024, items: {...reasonSchema,
        properties: {...reasonSchema.properties, code: {enum: ['parameter_value_required', 'host_capacity_policy_required']}},
        required: ['code', 'facts']}},
      scope: {type: 'object', additionalProperties: false,
        required: ['kind'], properties: {kind: {const: 'bound_input'}}},
      verdict: {enum: verdicts},
    },
  };
}

const problem = {type: 'object', additionalProperties: false,
  required: ['code'], properties: {code}};

export function checkOutcomeSchema(reasonSchema = checkReasonSchema) {
  const reasonCid = machineCid(reasonSchema);
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-check-outcome-0.1.json',
    title: 'actql-check-outcome-0.1',
    oneOf: [
      {type: 'object', additionalProperties: false,
        required: ['outcome', 'report', 'version', 'reason_schema_cid', 'outcome_schema_cid'],
        properties: {
          outcome: {const: 'completed'},
          report: report(['invalid', 'undetermined', 'verified'], reasonSchema),
          outcome_schema_cid: schemaCid,
          reason_schema_cid: {const: reasonCid},
          version: {const: 'actql-check-outcome/0.1'}}},
      // A partial report can never verify.
      {type: 'object', additionalProperties: false,
        required: ['outcome', 'problem', 'version', 'reason_schema_cid', 'outcome_schema_cid', 'correlation_ref'],
        properties: {
          outcome: {const: 'failed'},
          partial_report: report(['invalid', 'undetermined'], reasonSchema),
          problem,
          correlation_ref: opaqueRef,
          outcome_schema_cid: schemaCid,
          reason_schema_cid: {const: reasonCid},
          version: {const: 'actql-check-outcome/0.1'}}},
      // No verdict, report, scope or context field.
      {type: 'object', additionalProperties: false,
        required: ['correlation_ref', 'outcome', 'problem', 'version', 'reason_schema_cid', 'outcome_schema_cid'],
        properties: {
          correlation_ref: opaqueRef,
          outcome: {const: 'unavailable'},
          problem,
          outcome_schema_cid: schemaCid,
          reason_schema_cid: {const: reasonCid},
          version: {const: 'actql-check-outcome/0.1'}}},
    ],
  };
}

export function checkReasonSchemaFor(registry) {
  const reason = structuredClone(checkReasonSchema);
  const pin = machineCid(registry.schemas.canonical_value_contract);
  for (const facts of reason.properties.facts.oneOf) {
    if (facts.properties.admission) facts.properties.admission.properties.contract_schema_cid.const = pin;
  }
  const capacity = JSON.parse(readFileSync('spec/contracts/actql-capacity-host-policy.json', 'utf8'));
  const facts = reason.properties.facts.oneOf.find(value => value.properties.schema_pointer);
  assert.equal(facts.properties.contract_cid.const, machineCid(capacity));
  assert.equal(facts.properties.schema_cid.const, machineCid(capacity.schema));
  return reason;
}

export function applyCheckOutcomeSchema(registry) {
  const reason = checkReasonSchemaFor(registry);
  const schema = checkOutcomeSchema(reason);
  registry.artifact_schemas.check_reason = reason;
  registry.artifact_schema_cids.check_reason = machineCid(reason);
  registry.artifact_schemas.check_outcome = schema;
  registry.artifact_schema_cids.check_outcome = machineCid(schema);
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkCheckOutcomeSchema(registry) {
  const reason = checkReasonSchemaFor(registry);
  assert.deepEqual(registry.artifact_schemas.check_reason, reason);
  assert.equal(registry.artifact_schema_cids.check_reason, machineCid(reason));
  assert.deepEqual(registry.artifact_schemas.check_outcome,
    checkOutcomeSchema(reason));
  assert.equal(registry.artifact_schema_cids.check_outcome,
    machineCid(checkOutcomeSchema(reason)));
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

const generatedPins = registry =>
  '// Generated by scripts/check-outcome-contract.mjs --write.\n\n///|\n' +
  'let check_reason_schema_cid = ' + JSON.stringify(machineCid(checkReasonSchemaFor(registry))) + '\n\n///|\n' +
  'let check_outcome_schema_cid = ' + JSON.stringify(machineCid(checkOutcomeSchema(checkReasonSchemaFor(registry)))) + '\n\n///|\nlet check_parameter_contract_schema_cid = ' +
  JSON.stringify(machineCid(registry.schemas.canonical_value_contract)) + '\n\n///|\nlet check_capacity_contract_cid = ' +
  JSON.stringify(machineCid(JSON.parse(readFileSync('spec/contracts/actql-capacity-host-policy.json', 'utf8')))) + '\n\n///|\nlet check_capacity_schema_cid = ' +
  JSON.stringify(machineCid(JSON.parse(readFileSync('spec/contracts/actql-capacity-host-policy.json', 'utf8')).schema)) + '\n';

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyCheckOutcomeSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync('src/connectors_builtin_node/check_reason_schema.generated.mbt',
      generatedPins(registry));
  }
  checkCheckOutcomeSchema(registry);
  assert.equal(readFileSync(
    'src/connectors_builtin_node/check_reason_schema.generated.mbt', 'utf8'),
  generatedPins(registry));
}
