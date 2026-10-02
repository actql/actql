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

function report(verdicts) {
  const empty = {type: 'array', items: {}, maxItems: 0};
  const emptyCoverage = {properties: {limits: empty, unresolved: empty}};
  return {
    allOf: [
      {if: {properties: {verdict: {const: 'verified'}}},
        then: {properties: {reasons: empty, coverage: emptyCoverage}}},
      {if: {properties: {verdict: {const: 'invalid'}}},
        then: {properties: {reasons: {type: 'array', items: {}, minItems: 1}}}},
      {if: {properties: {verdict: {const: 'undetermined'}}},
        then: {properties: {reasons: empty,
          coverage: {not: emptyCoverage}}}},
    ],
    type: 'object', additionalProperties: false,
    required: ['context_ref', 'coverage', 'reasons', 'scope', 'verdict'],
    properties: {
      context_ref: opaqueRef,
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
      reasons: {type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['code'], properties: {code}}},
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
        required: ['outcome', 'report', 'version'],
        properties: {
          outcome: {const: 'completed'},
          report: report(['invalid', 'undetermined', 'verified']),
          version: {const: 'actql-check-outcome/0.1'}}},
      // A partial report can never verify.
      {type: 'object', additionalProperties: false,
        required: ['outcome', 'problem', 'version'],
        properties: {
          outcome: {const: 'failed'},
          partial_report: report(['invalid', 'undetermined']),
          problem,
          version: {const: 'actql-check-outcome/0.1'}}},
      // No verdict, report, scope or context field.
      {type: 'object', additionalProperties: false,
        required: ['correlation_ref', 'outcome', 'problem', 'version'],
        properties: {
          correlation_ref: opaqueRef,
          outcome: {const: 'unavailable'},
          problem,
          version: {const: 'actql-check-outcome/0.1'}}},
    ],
  };
}

export function applyCheckOutcomeSchema(registry) {
  const schema = checkOutcomeSchema();
  registry.artifact_schemas.check_outcome = schema;
  registry.artifact_schema_cids.check_outcome = machineCid(schema);
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkCheckOutcomeSchema(registry) {
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
  }
  checkCheckOutcomeSchema(registry);
}
