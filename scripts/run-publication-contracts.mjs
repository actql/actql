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
const stageSchemas = JSON.parse(readFileSync(
  'spec/contracts/actql-stage-contracts.json', 'utf8')).schemas;
const publicationSchemas = JSON.parse(readFileSync(
  'spec/contracts/actql-run-publication.json', 'utf8')).schemas;

function capturedLocalEffectSourceSchema() {
  return {
    type: 'object', additionalProperties: false,
    required: [
      'artifact', 'definition', 'derivation', 'invocation', 'manifest',
      'ordering', 'retention',
    ],
    properties: {
      artifact: clone(stageSchemas.local_result_artifact),
      definition: clone(stageSchemas.local_result_definition),
      derivation: {type: 'object'},
      invocation: clone(stageSchemas.local_computation),
      manifest: clone(stageSchemas.local_manifest),
      ordering: {type: 'object'},
      retention: clone(publicationSchemas.result_retention_policy),
    },
  };
}

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

export function effectSourceArtifactSchema() {
  const artifact = resultArtifactSchema();
  artifact.required = artifact.required.map(field =>
    field === 'result_definition_cid' ? 'source_binding_cid' : field);
  artifact.required.splice(2, 0, 'source_result');
  artifact.required.push('store_authority_cid');
  artifact.required = artifact.required.filter(field =>
    field !== 'ordering_evidence_cid');
  artifact.properties.version = {const: 'actql-effect-source-artifact/0.1'};
  delete artifact.properties.result_definition_cid;
  delete artifact.properties.ordering_evidence_cid;
  artifact.properties.source_binding_cid = clone(cid);
  artifact.properties.source_result = {type: 'string', minLength: 1};
  artifact.properties.store_authority_cid = clone(cid);
  return artifact;
}

export function effectRowOutcomeReceiptSchema(outcome) {
  return {
    type: 'object',
    additionalProperties: false,
    required: [
      'version', 'effect_preview_cid', 'effect_member_preview_cid',
      'row_preview_cid', 'dispatch_entry_cid', 'credential_use_cid',
      'response_physical_sha256', 'response_byte_count', 'http_status_code',
      'typed_outcome', 'typed_outcome_cid', 'receipt_cid',
    ],
    properties: {
      version: {const: 'actql-effect-row-outcome-receipt/0.1'},
      effect_preview_cid: clone(cid),
      effect_member_preview_cid: clone(cid),
      row_preview_cid: clone(cid),
      dispatch_entry_cid: clone(cid),
      credential_use_cid: clone(cid),
      response_physical_sha256: {type: 'string', pattern: '^[0-9a-f]{64}$'},
      response_byte_count: {type: 'integer', minimum: 0, maximum: 9007199254740991},
      http_status_code: {type: 'integer', minimum: 100, maximum: 599},
      typed_outcome: {
        oneOf: outcome.oneOf.filter(branch =>
          branch.properties?.state?.const !== 'unknown').map(clone),
      },
      typed_outcome_cid: clone(cid),
      receipt_cid: clone(cid),
    },
  };
}

export function effectApplyReceiptSchema() {
  const rowIdentity = {
    row_index: {type: 'integer', minimum: 0, maximum: 9007199254740991},
    row_preview_cid: clone(cid),
  };
  const dispatched = {
    ...rowIdentity,
    dispatch_entry_cid: clone(cid),
    attempt_sequence: {type: 'integer', minimum: 1, maximum: 9007199254740991},
  };
  const row = (state, extra, required) => ({
    type: 'object', additionalProperties: false,
    required: ['row_index', 'row_preview_cid', 'state', ...required],
    properties: {state: {const: state}, ...extra},
  });
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-effect-apply-receipt-0.1.json',
    title: 'actql-effect-apply-receipt-0.1',
    type: 'object', additionalProperties: false,
    required: ['version', 'run_identity_cid', 'effect_preview_cid',
      'effect_member_preview_cid', 'rows', 'status', 'receipt_cid'],
    properties: {
      version: {const: 'actql-effect-apply-receipt/0.1'},
      run_identity_cid: clone(cid),
      effect_preview_cid: clone(cid),
      effect_member_preview_cid: clone(cid),
      approval_attestation_cid: clone(cid),
      stale_error_cid: clone(cid),
      rows: {type: 'array', items: {oneOf: [
        row('unattempted', rowIdentity, []),
        row('unknown', {...dispatched, ledger_head_cid: clone(cid)},
          ['dispatch_entry_cid', 'attempt_sequence', 'ledger_head_cid']),
        ...['applied', 'accepted', 'failed'].map(state =>
          row(state, {...dispatched, outcome_receipt_cid: clone(cid),
            batch_result_cid: clone(cid)},
            ['dispatch_entry_cid', 'attempt_sequence', 'outcome_receipt_cid'])),
        row('rolled_back', {...dispatched, outcome_receipt_cid: clone(cid),
          batch_result_cid: clone(cid)},
        ['dispatch_entry_cid', 'attempt_sequence', 'outcome_receipt_cid',
          'batch_result_cid']),
      ]}},
      status: {enum: ['applied', 'accepted', 'unknown_outcome',
        'partial_failure', 'failed', 'stale_preview']},
      receipt_cid: clone(cid),
    },
  };
}

export function effectSetApplyReceiptSchema(previous) {
  const schema = clone(previous);
  const entry = schema.properties.effects.items;
  delete entry.properties.outcome;
  entry.properties.state.enum = [
    'applied', 'accepted', 'failed', 'unknown', 'unattempted', 'rolled_back',
  ];
  return schema;
}

export function effectReconciliationReceiptSchema(previous) {
  const schema = clone(previous);
  for (const field of ['run_identity_cid', 'effect_preview_cid',
    'effect_member_preview_cid', 'row_preview_cid',
    'dispatch_entry_cid', 'dispatch_attempt_sequence',
    'prior_ledger_head_cid']) {
    if (!schema.required.includes(field)) schema.required.push(field);
  }
  for (const field of ['run_identity_cid', 'effect_preview_cid',
    'effect_member_preview_cid', 'row_preview_cid',
    'dispatch_entry_cid', 'prior_ledger_head_cid',
    'outcome_receipt_cid']) {
    schema.properties[field] = clone(cid);
  }
  schema.properties.dispatch_attempt_sequence = {
    type: 'integer', minimum: 1, maximum: 9007199254740991,
  };
  schema.allOf[1].then.not = {required: ['outcome_receipt_cid']};
  schema.allOf[1].else.required = ['outcome_receipt_cid'];
  return schema;
}

export function runStateSchema(previous) {
  const runReconciliation = {
    type: 'object', additionalProperties: false,
    required: ['kind', 'reason'],
    properties: {kind: {const: 'reconcile_run'},
      reason: {const: 'execution_unknown'}},
  };
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
      {type: 'object', additionalProperties: false,
        required: ['kind'], properties: {kind: {const: 'none'}}},
      runReconciliation,
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
  state.properties.control = {
    type: 'object', additionalProperties: false,
    required: ['revision', 'cancellation_requested', 'physical_stop'],
    properties: {
      revision: {type: 'integer', minimum: 0, maximum: 2147483647},
      cancellation_requested: {type: 'boolean'},
      physical_stop: {enum: ['unknown', 'confirmed']},
    },
  };
  state.properties.next_action = nextAction;
  state.properties.result_available = {type: 'boolean'};
  state.properties.result_availability = availability;
  state.allOf = previous.allOf.map(rule => clone(rule));
  const reconciliation = state.allOf.find(
    rule => rule.if?.properties?.status?.const === 'needs_reconciliation');
  reconciliation.then.properties.next_action = {oneOf: [
    clone(nextAction.oneOf[1]), clone(runReconciliation),
  ]};
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
  const effectSourceArtifact = effectSourceArtifactSchema();
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
    effect_preview_cid: clone(cid),
    effect_set_apply_receipt_cid: clone(cid),
    captured_run_cid: clone(cid),
  };
  const finalReferences = [
    'effect_preview_cid',
    'effect_set_apply_receipt_cid',
    'captured_run_cid',
  ];
  receipt.oneOf = [
    {required: finalReferences},
    {not: {anyOf: finalReferences.map(field => ({required: [field]}))}},
  ];
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
  next.artifact_schemas.effect_row_outcome_receipt =
    effectRowOutcomeReceiptSchema(next.schemas.effect_outcome);
  next.artifact_schemas.effect_apply_receipt = effectApplyReceiptSchema();
  next.artifact_schemas.effect_set_apply_receipt =
    effectSetApplyReceiptSchema(next.artifact_schemas.effect_set_apply_receipt);
  next.artifact_schemas.effect_reconciliation_receipt =
    effectReconciliationReceiptSchema(
      next.artifact_schemas.effect_reconciliation_receipt);
  next.artifact_schemas.effect_source_artifact = effectSourceArtifact;
  const effectContext = next.artifact_schemas.captured_run
    .properties.effect_context;
  for (const field of ['effect_source_artifacts',
    'effect_source_holding_cids', 'effect_source_local_inventory']) {
    if (!effectContext.required.includes(field)) effectContext.required.push(field);
  }
  effectContext.properties.effect_source_artifacts = {
    type: 'object', additionalProperties: clone(effectSourceArtifact),
  };
  effectContext.properties.effect_source_holding_cids = {
    type: 'object', additionalProperties: clone(cid),
  };
  for (const [name, schema] of Object.entries(next.artifact_schemas)) {
    next.artifact_schemas[name] = replaceNested(schema, replacements);
  }
  next.artifact_schemas.captured_run.properties.effect_context.properties
    .effect_source_local_inventory = {
      type: 'object',
      additionalProperties: capturedLocalEffectSourceSchema(),
    };
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
  assert.deepEqual(registry.artifact_schemas.effect_source_artifact,
    effectSourceArtifactSchema());
  assert.ok(registry.artifact_schemas.run_receipt.required.includes('compiler_version'));
  assert.ok(registry.artifact_schemas.run_receipt.required.includes('aoa_ir_version'));
  assert.deepEqual(registry.artifact_schemas.run_receipt.oneOf, [
    {
      required: [
        'effect_preview_cid',
        'effect_set_apply_receipt_cid',
        'captured_run_cid',
      ],
    },
    {
      not: {
        anyOf: [
          {required: ['effect_preview_cid']},
          {required: ['effect_set_apply_receipt_cid']},
          {required: ['captured_run_cid']},
        ],
      },
    },
  ]);
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
