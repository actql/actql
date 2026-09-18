import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const registryPath = 'spec/contracts/actql-protocol-schemas.json';
const cliPath = 'spec/contracts/actql-cli-run-response.schema.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const timestamp = {
  type: 'string',
  pattern: '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$',
};
const resultNames = {
  type: 'array',
  minItems: 1,
  uniqueItems: true,
  items: {type: 'string', minLength: 1},
};

const clone = value => structuredClone(value);

export function resultArtifactSchema() {
  return {
    type: 'object',
    additionalProperties: false,
    required: [
      'version',
      'result_definition_cid',
      'invocation_cid',
      'logical_result_cid',
      'result_schema_cid',
      'ordering_evidence_cid',
      'actual_row_count',
      'actual_completeness',
      'effective_data_policy_cid',
      'effective_retention_policy_cid',
      'provenance_evidence_cids',
      'result_artifact_cid',
    ],
    properties: {
      version: {const: 'actql-result-artifact/0.1'},
      result_definition_cid: clone(cid),
      invocation_cid: clone(cid),
      logical_result_cid: clone(cid),
      result_schema_cid: clone(cid),
      ordering_evidence_cid: clone(cid),
      actual_row_count: {
        type: 'integer',
        minimum: 0,
        maximum: 9007199254740991,
      },
      actual_completeness: {enum: ['complete', 'partial']},
      effective_data_policy_cid: clone(cid),
      effective_retention_policy_cid: clone(cid),
      provenance_evidence_cids: {
        type: 'array',
        uniqueItems: true,
        items: clone(cid),
      },
      result_artifact_cid: clone(cid),
    },
  };
}

export function runStateSchema(previous) {
  const availability = {
    type: 'object',
    minProperties: 1,
    propertyNames: {minLength: 1},
    additionalProperties: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'observed_at', 'reason'],
      properties: {
        state: {enum: ['available', 'unavailable', 'unknown']},
        observed_at: clone(timestamp),
        reason: {
          enum: [
            'confirmed_present',
            'retention_expired',
            'deleted',
            'policy_unavailable',
            'integrity_failed',
            'not_published',
            'store_query_failed',
            'clock_uncertain',
            'verification_pending',
          ],
        },
        cause_cid: clone(cid),
      },
      allOf: [
        {
          if: {properties: {state: {const: 'available'}}, required: ['state']},
          then: {properties: {reason: {const: 'confirmed_present'}}},
        },
        {
          if: {properties: {state: {const: 'unavailable'}}, required: ['state']},
          then: {
            properties: {
              reason: {
                enum: [
                  'retention_expired',
                  'deleted',
                  'policy_unavailable',
                  'integrity_failed',
                  'not_published',
                ],
              },
            },
          },
        },
        {
          if: {properties: {state: {const: 'unknown'}}, required: ['state']},
          then: {
            properties: {
              reason: {
                enum: [
                  'store_query_failed',
                  'clock_uncertain',
                  'verification_pending',
                ],
              },
            },
          },
        },
      ],
    },
  };
  const nextAction = {
    oneOf: [
      previous.properties.next_action.oneOf[0],
      previous.properties.next_action.oneOf[1],
      {
        type: 'object',
        additionalProperties: false,
        required: ['kind', 'results'],
        properties: {kind: {const: 'read_result'}, results: clone(resultNames)},
      },
      {
        type: 'object',
        additionalProperties: false,
        required: ['kind', 'results'],
        properties: {
          kind: {const: 'refresh_availability'},
          results: clone(resultNames),
        },
      },
      previous.properties.next_action.oneOf.at(-1),
    ],
  };
  const state = clone(previous);
  state.required = [
    'version',
    'run_id',
    'status',
    'updated_at',
    'next_action',
    'result_available',
    'result_availability',
  ];
  state.properties.next_action = nextAction;
  state.properties.result_available = {type: 'boolean'};
  state.properties.result_availability = availability;
  state.allOf = previous.allOf.map(rule => clone(rule));
  const succeeded = state.allOf.find(
    rule => rule.if?.properties?.status?.const === 'succeeded',
  );
  succeeded.then = {
    not: {required: ['checkpoint']},
    properties: {
      next_action: {
        type: 'object',
        required: ['kind'],
        properties: {
          kind: {
            enum: ['read_result', 'refresh_availability', 'none'],
          },
        },
      },
    },
  };
  return state;
}

function schemaVersion(schema) {
  return schema?.properties?.version?.const;
}

function replaceNested(schema, replacements, root = true) {
  if (!schema || typeof schema !== 'object') return schema;
  if (!root && replacements.has(schemaVersion(schema))) {
    return clone(replacements.get(schemaVersion(schema)));
  }
  if (Array.isArray(schema)) {
    return schema.map(item => replaceNested(item, replacements, false));
  }
  return Object.fromEntries(
    Object.entries(schema).map(([key, value]) => [
      key,
      replaceNested(value, replacements, false),
    ]),
  );
}

export function correctedContracts(registry, cli) {
  const next = clone(registry);
  const artifact = resultArtifactSchema();
  const manifest = clone(next.artifact_schemas.result_manifest);
  manifest.properties.results.additionalProperties = clone(artifact);
  const receipt = clone(next.artifact_schemas.run_receipt);
  receipt.required = [
    'version',
    'compiler_version',
    'aoa_ir_version',
    ...receipt.required.filter(
      field => !['version', 'compiler_version', 'aoa_ir_version'].includes(field),
    ),
  ];
  receipt.properties = {
    version: receipt.properties.version,
    compiler_version: {
      type: 'string',
      pattern: '^[A-Za-z0-9][A-Za-z0-9._+:-]{0,127}$',
    },
    aoa_ir_version: {
      type: 'string',
      pattern: '^[A-Za-z0-9][A-Za-z0-9._+:-]{0,127}$',
    },
    ...Object.fromEntries(
      Object.entries(receipt.properties).filter(([key]) => key !== 'version'),
    ),
  };
  receipt.properties.result_manifest = clone(manifest);
  receipt.properties.result_artifacts.additionalProperties = clone(artifact);
  const state = runStateSchema(next.artifact_schemas.run_state);
  const replacements = new Map([
    ['actql-result-artifact/0.1', artifact],
    ['actql-result-manifest/0.1', manifest],
    ['actql-run-receipt/0.1', receipt],
  ]);
  next.artifact_schemas.result_manifest = manifest;
  next.artifact_schemas.run_receipt = receipt;
  next.artifact_schemas.run_state = state;
  for (const [name, schema] of Object.entries(next.artifact_schemas)) {
    next.artifact_schemas[name] = replaceNested(schema, replacements);
  }
  for (const [name, schema] of Object.entries(next.artifact_schemas)) {
    next.artifact_schema_cids[name] = machineCid(schema);
  }
  next.artifact_registry_cid = machineCid(next.artifact_schemas);
  const nextCli = clone(cli);
  nextCli.properties.run = clone(state);
  return {registry: next, cli: nextCli};
}

export function checkContracts(registry, cli) {
  const expected = correctedContracts(registry, cli);
  assert.deepEqual(registry, expected.registry, 'Run publication schemas are stale');
  assert.deepEqual(cli, expected.cli, 'CLI Run state embedding is stale');
  const artifact = resultArtifactSchema();
  assert.deepEqual(
    registry.artifact_schemas.result_manifest.properties.results.additionalProperties,
    artifact,
  );
  assert.ok(registry.artifact_schemas.run_receipt.required.includes('compiler_version'));
  assert.ok(registry.artifact_schemas.run_receipt.required.includes('aoa_ir_version'));
  assert.ok(registry.artifact_schemas.run_state.required.includes('result_availability'));
  for (const [name, schema] of Object.entries(registry.artifact_schemas)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(schema), name);
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const read = path => JSON.parse(readFileSync(path, 'utf8'));
  const registry = read(registryPath);
  const cli = read(cliPath);
  if (process.argv.includes('--write')) {
    const next = correctedContracts(registry, cli);
    writeFileSync(registryPath, JSON.stringify(next.registry, null, 2) + '\n');
    writeFileSync(cliPath, JSON.stringify(next.cli, null, 2) + '\n');
    checkContracts(next.registry, next.cli);
  } else {
    checkContracts(registry, cli);
  }
  console.log('Run publication 0.1 schemas and embeddings verified.');
}
