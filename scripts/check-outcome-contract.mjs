import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

// The public `check` outcome. A distinct contract from actql-diagnostics/0.1
// and actql-plan-result/0.1, which keep their own schemas and identities.
const path = 'spec/contracts/actql-protocol-schemas.json';
const code = {type: 'string', pattern: '^[a-z][a-z0-9_]{0,63}$'};
const opaqueRef = {type: 'string', minLength: 1, maxLength: 128,
  pattern: '^[A-Za-z0-9:_-]+$'};

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
// This registered facts schema is separate from outcome and presentation identity.
// Known facts are closed; future codes have only a safe code-only representation.
const parameterName = {type: 'string', minLength: 1, maxLength: 256};
const typeName = {enum: ['null', 'boolean', 'number', 'string', 'array', 'object',
  'date', 'timestamp', 'decimal', 'json', 'vector', 'resource_ref', 'artifact_ref']};
const lexicalIssues = ['unexpected_end', 'unexpected_token', 'invalid_escape',
  'invalid_scalar', 'empty_identifier', 'unterminated_comment', 'invalid_number', 'invalid_parameter'];
const expressionIssues = ['unknown_reference', 'invalid_arguments', 'invalid_number'];
export const checkReasonSchema = {
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: 'https://smooth.dev/schemas/actql-check-reason-0.1.json',
  title: 'actql-check-reason-0.1',
  type: 'object', additionalProperties: false,
  required: ['code'], properties: {code, location,
    facts: {oneOf: [
      {type: 'object', additionalProperties: false, required: ['parameter'], properties: {parameter: parameterName}},
      {type: 'object', additionalProperties: false,
        required: ['parameter', 'expected_type', 'actual_type'],
        properties: {parameter: parameterName, expected_type: typeName, actual_type: typeName}},
      {type: 'object', additionalProperties: false,
        required: ['parameter', 'expected_type'],
        properties: {parameter: parameterName, expected_type: typeName}},
      {type: 'object', additionalProperties: false,
        required: ['parameter', 'constraint'],
        properties: {parameter: parameterName,
          constraint: {enum: ['numeric', 'duration', 'array_length', 'array_size']}}},
      {type: 'object', additionalProperties: false, required: ['issue'],
        properties: {issue: {enum: [...new Set([...lexicalIssues, ...expressionIssues])]}}},
    ]}},
  allOf: [
    {if: {properties: {code: {const: 'supplied_value_type_mismatch'}}},
      then: {required: ['facts'], properties: {facts: {required: ['actual_type']}}}},
    {if: {properties: {code: {const: 'parameter_undeclared'}}},
      then: {required: ['facts'], properties: {facts: {required: ['parameter'], allOf: [
        {not: {required: ['expected_type']}}, {not: {required: ['constraint']}}]}}}},
    {if: {properties: {code: {const: 'parameter_value_required'}}},
      then: {required: ['facts'], properties: {facts: {required: ['expected_type'], not: {required: ['actual_type']}}}}},
    {if: {properties: {code: {const: 'supplied_value_constraint_violation'}}},
      then: {required: ['facts'], properties: {facts: {required: ['constraint']}}}},
    {if: {properties: {code: {const: 'query_lexical_invalid'}}},
      then: {required: ['facts'], properties: {facts: {required: ['issue'], properties: {issue: {enum: lexicalIssues}}},
        location: {properties: {kind: {const: 'text'}}}}}},
    {if: {properties: {code: {const: 'query_expression_invalid'}}},
      then: {required: ['facts'], properties: {facts: {required: ['issue'],
        properties: {issue: {enum: expressionIssues}}},
        location: {properties: {kind: {const: 'text'}}}}}},
    {if: {properties: {code: {not: {enum: ['supplied_value_type_mismatch', 'parameter_value_required', 'parameter_undeclared', 'supplied_value_constraint_violation', 'query_lexical_invalid', 'query_expression_invalid']}}}},
      then: {not: {required: ['facts']}}},
  ],
};
export const checkReasonSchemaCid = machineCid(checkReasonSchema);

function report(verdicts) {
  const empty = {type: 'array', items: {}, maxItems: 0};
  const emptyCoverage = {properties: {limits: empty, unresolved: empty}};
  return {
    allOf: [
      {if: {properties: {verdict: {const: 'verified'}}},
        then: {properties: {reasons: empty, requirements: empty, coverage: emptyCoverage}}},
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
      inputs: {type: 'array', minItems: 1, maxItems: 3, items: {
        type: 'object', additionalProperties: false,
        required: ['document_id', 'revision', 'kind', 'byte_length'],
        properties: {document_id: documentId, revision, kind: {enum: ['text', 'structured']}, byte_length: submittedBytes}}},
      coverage: {
        type: 'object', additionalProperties: false,
        required: ['limits', 'unresolved'],
        properties: {
          limits: {type: 'array', items: {
            type: 'object', additionalProperties: false,
            required: ['code'], properties: {code}}},
          unresolved: {type: 'array', items: {
            type: 'object', additionalProperties: false,
            required: ['boundary', 'reason'],
            properties: {boundary: code,
              reason: {const: 'unresolved_protected'}}}},
        },
      },
      reasons: {type: 'array', maxItems: 1024, items: checkReasonSchema},
      requirements: {type: 'array', maxItems: 1024, items: {...checkReasonSchema,
        properties: {...checkReasonSchema.properties, code: {const: 'parameter_value_required'}},
        required: ['code', 'facts']}},
      scope: {type: 'object', additionalProperties: false,
        required: ['kind'], properties: {kind: {const: 'bound_input'}}},
      verdict: {enum: verdicts},
    },
  };
}

const problem = {type: 'object', additionalProperties: false,
  required: ['code'], properties: {code}};

export function checkOutcomeSchema() {
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-check-outcome-0.1.json',
    title: 'actql-check-outcome-0.1',
    oneOf: [
      {type: 'object', additionalProperties: false,
        required: ['outcome', 'report', 'version', 'reason_schema_cid'],
        properties: {
          outcome: {const: 'completed'},
          report: report(['invalid', 'undetermined', 'verified']),
          reason_schema_cid: {const: checkReasonSchemaCid},
          version: {const: 'actql-check-outcome/0.1'}}},
      // A partial report can never verify.
      {type: 'object', additionalProperties: false,
        required: ['outcome', 'problem', 'version', 'reason_schema_cid'],
        properties: {
          outcome: {const: 'failed'},
          partial_report: report(['invalid', 'undetermined']),
          problem,
          reason_schema_cid: {const: checkReasonSchemaCid},
          version: {const: 'actql-check-outcome/0.1'}}},
      // No verdict, report, scope or context field.
      {type: 'object', additionalProperties: false,
        required: ['correlation_ref', 'outcome', 'problem', 'version', 'reason_schema_cid'],
        properties: {
          correlation_ref: opaqueRef,
          outcome: {const: 'unavailable'},
          problem,
          reason_schema_cid: {const: checkReasonSchemaCid},
          version: {const: 'actql-check-outcome/0.1'}}},
    ],
  };
}

export function applyCheckOutcomeSchema(registry) {
  const schema = checkOutcomeSchema();
  registry.artifact_schemas.check_reason = checkReasonSchema;
  registry.artifact_schema_cids.check_reason = checkReasonSchemaCid;
  registry.artifact_schemas.check_outcome = schema;
  registry.artifact_schema_cids.check_outcome = machineCid(schema);
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkCheckOutcomeSchema(registry) {
  assert.deepEqual(registry.artifact_schemas.check_reason, checkReasonSchema);
  assert.equal(registry.artifact_schema_cids.check_reason, checkReasonSchemaCid);
  assert.deepEqual(registry.artifact_schemas.check_outcome,
    checkOutcomeSchema());
  assert.equal(registry.artifact_schema_cids.check_outcome,
    machineCid(checkOutcomeSchema()));
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyCheckOutcomeSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync('src/connectors_builtin_node/check_reason_schema.generated.mbt',
      '// Generated by scripts/check-outcome-contract.mjs --write.\n\n///|\n' +
      'let check_reason_schema_cid = ' + JSON.stringify(checkReasonSchemaCid) + '\n');
  }
  checkCheckOutcomeSchema(registry);
  assert.equal(readFileSync(
    'src/connectors_builtin_node/check_reason_schema.generated.mbt', 'utf8'),
  '// Generated by scripts/check-outcome-contract.mjs --write.\n\n///|\n' +
    'let check_reason_schema_cid = ' + JSON.stringify(checkReasonSchemaCid) + '\n');
}
