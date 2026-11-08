import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import {machineCid} from './actql-spec-family.mjs';
import {checkLocalTableInputContract} from './local-table-input-contract.mjs';
import {checkLocalModelObservationContract} from './local-model-observation-contract.mjs';

const registryPath = 'spec/contracts/actql-protocol-schemas.json';
const cliPath = 'spec/contracts/actql-cli-run-response.schema.json';
const cliReceiptPath = 'spec/contracts/actql-cli-result-delivery-receipts.schema.json';
const cliVerificationPath = 'spec/contracts/actql-cli-output-verification.schema.json';
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
const stageRegistry = JSON.parse(readFileSync(
  'spec/contracts/actql-stage-contracts.json', 'utf8'));
const stageSchemas = stageRegistry.schemas;
const referenceSchemas = JSON.parse(readFileSync(registryPath, 'utf8')).schemas;
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
      definition: {oneOf: [
        clone(stageSchemas.local_result_definition),
        clone(stageSchemas.local_table_input_definition),
      ]},
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
  artifact.required.push('store_authority_cid');
  artifact.required = artifact.required.filter(field =>
    field !== 'ordering_evidence_cid');
  artifact.properties.version = {const: 'actql-effect-source-artifact/0.1'};
  delete artifact.properties.result_definition_cid;
  delete artifact.properties.ordering_evidence_cid;
  artifact.properties.source_binding_cid = clone(cid);
  artifact.properties.source_result = {type: 'string', minLength: 1};
  artifact.properties.source_table_input = {type: 'string', minLength: 1};
  artifact.oneOf = [
    {required: ['source_result'], not: {required: ['source_table_input']}},
    {required: ['source_table_input'], not: {required: ['source_result']}},
  ];
  artifact.properties.store_authority_cid = clone(cid);
  return artifact;
}

// Preserve the ordinary member schema and its contract-selection obligations.
// The private input is a distinct closed source namespace, never a Result alias.
function withResourceTarget(existing, resourceRef) {
  const target = clone(existing);
  target.oneOf = target.oneOf.filter(branch =>
    branch.properties?.$actql_ref?.const !== 'resource');
  target.oneOf.push(clone(resourceRef));
  return target;
}

export function effectPreviewSchema(existing, resourceRef = referenceSchemas.resource_ref) {
  const preview = clone(existing);
  const member = preview.properties.effects.items;
  // Command technical contracts carry no approval minimum. Absence is DATA,
  // not Account allow; the original authorization gate still decides dispatch.
  member.required = member.required.filter(field => field !== 'approval');
  const selection = member.allOf.find(rule => rule.oneOf?.some(branch =>
    branch.properties?.effect_kind?.const === 'command'));
  for (const branch of selection.oneOf) {
    if (branch.properties?.effect_kind?.const === 'command') {
      branch.not = {required: ['approval']};
    } else if (!branch.required.includes('approval')) {
      branch.required.push('approval');
    }
  }
  // A concrete original ResourceRef and an authored field selector are
  // different scope alternatives. Never substitute a representative row.
  member.properties.target = withResourceTarget(member.properties.target, resourceRef);
  // A Command keeps the checked ResourceRef, not a row scalar or a hash-only
  // approximation. Shape admission does not issue it or authorize its use.
  member.properties.changes.items.properties.target_row_identity = withResourceTarget(
    member.properties.changes.items.properties.target_row_identity, resourceRef);
  member.properties.source_table_input = {type: 'string', minLength: 1};
  const sources = ['source_result', 'source_table_input', 'result_artifact_cid'];
  const sourceBinding = {oneOf: [
    {not: {anyOf: sources.map(field => ({required: [field]}))}},
    {required: ['source_result', 'result_artifact_cid'],
      not: {required: ['source_table_input']}},
    {required: ['source_table_input', 'result_artifact_cid'],
      properties: {effect_kind: {const: 'store'}},
      not: {required: ['source_result']}},
  ]};
  // Idempotently own only this source-binding obligation. Other member
  // constraints, including command/Mapping selection, remain untouched.
  member.allOf = (member.allOf ?? []).filter(rule =>
    !isDeepStrictEqual(rule, sourceBinding));
  member.allOf.push(sourceBinding);
  return preview;
}

export function effectReviewProjectionSchema(existing, preview, resourceRef) {
  const review = clone(existing);
  const row = review.properties.displayed_rows.items;
  const member = preview.properties.effects.items;
  row.properties.target_row_identity = withResourceTarget(
    row.properties.target_row_identity, resourceRef);
  for (const name of ['preview_strength', 'target_guard', 'intended_changes']) {
    row.properties[name] = clone(name === 'preview_strength'
      ? member.properties[name] : member.properties.changes.items.properties[name]);
  }
  review.properties.displayed_scope.properties.effects.items.properties.target =
    withResourceTarget(review.properties.displayed_scope.properties.effects.items
      .properties.target, resourceRef);
  return review;
}

// Select only this existing Owner's changed boundary. The full historical
// publication generator also owns unrelated Run/CLI/outcome transformations;
// a review-only refresh must not replay those over later adopted contracts.
export function correctedEffectReviewContracts(registry) {
  const next = clone(registry);
  const preview = effectPreviewSchema(next.artifact_schemas.effect_preview,
    next.schemas.resource_ref);
  next.artifact_schemas.effect_preview = preview;
  next.artifact_schemas.review_projection = effectReviewProjectionSchema(
    next.artifact_schemas.review_projection, preview, next.schemas.resource_ref);
  for (const name of ['effect_preview', 'review_projection']) {
    next.artifact_schema_cids[name] = machineCid(next.artifact_schemas[name]);
  }
  next.artifact_registry_cid = machineCid(next.artifact_schemas);
  return next;
}

export function httpEffectRowOutcomeReceiptSchema(outcome) {
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
          branch.properties?.state?.const !== 'unknown').map(branch => {
          const typed = clone(branch);
          if (typed.properties?.state?.const === 'applied') {
            typed.$comment = 'action is required exactly for an applied upsert; admission checks the original dispatch operation. It is included in the typed outcome and receipt identities.';
          }
          return typed;
        }),
      },
      typed_outcome_cid: clone(cid),
      receipt_cid: clone(cid),
    },
  };
}

function localUpdateOutcomes(outcome) {
  const applied = clone(outcome.oneOf.find(branch => branch.properties?.state?.const === 'applied'));
  delete applied.properties.action;
  const conflict = clone(outcome.oneOf.find(branch => branch.properties?.state?.const === 'failed'));
  conflict.properties.error.properties.code = {const: 'conflict'};
  return {applied, conflict};
}

export function effectLocalOperationReceiptSchema(outcome) {
  const {applied, conflict} = localUpdateOutcomes(outcome);
  const identities = ['effect_preview_cid', 'effect_member_preview_cid', 'row_preview_cid',
    'installation_cid', 'target_cid', 'canonical_request_cid', 'dispatch_entry_cid',
    'authorization_use_cid', 'approval_use_cid', 'target_version_cid', 'typed_outcome_cid', 'receipt_cid'];
  return {type: 'object', additionalProperties: false,
    required: ['version', ...identities, 'backend_kind', 'operation_kind',
      'commit_status', 'observed_version_cid', 'typed_outcome'],
    properties: {version: {const: 'actql-local-effect-operation-receipt/0.1'},
      ...Object.fromEntries(identities.map(name => [name, clone(cid)])),
      backend_kind: {const: 'sqlite'}, operation_kind: {const: 'update'},
      commit_status: {enum: ['committed', 'conflict']},
      observed_version_cid: {oneOf: [clone(cid), {type: 'null'}]},
      typed_outcome: {oneOf: [applied, conflict]}},
    oneOf: [
      {properties: {commit_status: {const: 'committed'}, observed_version_cid: clone(cid), typed_outcome: applied}},
      {properties: {commit_status: {const: 'conflict'}, typed_outcome: conflict}},
    ]};
}

export function effectRowOutcomeReceiptSchema(outcome) {
  const http = httpEffectRowOutcomeReceiptSchema(outcome);
  const local = clone(http);
  local.required = local.required.filter(name => !['credential_use_cid', 'http_status_code'].includes(name));
  delete local.properties.credential_use_cid;
  delete local.properties.http_status_code;
  local.required.push('response_kind', 'local_operation_receipt_cid');
  local.properties.response_kind = {const: 'local_operation'};
  local.properties.local_operation_receipt_cid = clone(cid);
  const {applied, conflict} = localUpdateOutcomes(outcome);
  local.properties.typed_outcome = {oneOf: [applied, conflict]};
  return {oneOf: [http, local]};
}

export function correctedLocalEffectOutcomeContracts(registry) {
  const next = clone(registry);
  next.artifact_schemas.effect_row_outcome_receipt = effectRowOutcomeReceiptSchema(next.schemas.effect_outcome);
  next.artifact_schemas.effect_local_operation_receipt = effectLocalOperationReceiptSchema(next.schemas.effect_outcome);
  for (const name of ['effect_row_outcome_receipt', 'effect_local_operation_receipt']) {
    next.artifact_schema_cids[name] = machineCid(next.artifact_schemas[name]);
  }
  next.artifact_registry_cid = machineCid(next.artifact_schemas);
  return next;
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
    'revision',
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
  state.properties.revision = {type: 'integer', minimum: 0, maximum: 9007199254740991};
  state.properties.next_action = nextAction;
  state.properties.result_available = {type: 'boolean'};
  state.properties.result_availability = availability;
  state.allOf = previous.allOf.map(rule => clone(rule));
  const emptyInventory = {
    if: {required: ['result_availability'],
      properties: {result_availability: {maxProperties: 0}}},
    then: {properties: {result_available: {const: false},
      next_action: {properties: {kind: {enum: [
        'none', 'resolve_checkpoint', 'reconcile', 'reconcile_run',
      ]}}}}},
  };
  if (!state.allOf.some(rule => isDeepStrictEqual(rule, emptyInventory))) {
    state.allOf.push(emptyInventory);
  }
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
  // The admitted Run copies this optional projection from its Compiled Plan.
  // It never accepts an independent caller declaration of selection custody.
  next.artifact_schemas.run_definition.properties.effect_target_selections_cid =
    clone(cid);
  const artifact = resultArtifactSchema();
  const effectSourceArtifact = effectSourceArtifactSchema();
  const preview = effectPreviewSchema(next.artifact_schemas.effect_preview,
    next.schemas.resource_ref);
  const manifest = clone(next.artifact_schemas.result_manifest);
  delete manifest.properties.results.minProperties;
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
    ['actql-effect-preview/0.1', preview],
  ]);
  next.artifact_schemas.effect_preview = preview;
  next.artifact_schemas.review_projection = effectReviewProjectionSchema(
    next.artifact_schemas.review_projection, preview, next.schemas.resource_ref);
  next.artifact_schemas.result_manifest = manifest;
  next.artifact_schemas.run_receipt = receipt;
  next.artifact_schemas.run_state = state;
  next.artifact_schemas.effect_row_outcome_receipt =
    effectRowOutcomeReceiptSchema(next.schemas.effect_outcome);
  next.artifact_schemas.effect_local_operation_receipt =
    effectLocalOperationReceiptSchema(next.schemas.effect_outcome);
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
    'effect_source_holding_cids', 'effect_source_local_inventory',
    'effect_dependency_inventory']) {
    if (!effectContext.required.includes(field)) effectContext.required.push(field);
  }
  effectContext.properties.effect_source_artifacts = {
    type: 'object', additionalProperties: clone(effectSourceArtifact),
  };
  effectContext.properties.effect_source_holding_cids = {
    type: 'object', additionalProperties: clone(cid),
  };
  effectContext.properties.effect_dependency_inventory = {
    type: 'array', maxItems: 4096,
    items: {type: 'object', additionalProperties: false,
      required: ['kind', 'cid', 'body'],
      properties: {kind: {type: 'string', enum: [
        'result_artifact', 'derivation_evidence', 'ordering_evidence',
        'table_input_artifact', 'table_input_derivation', 'table_input_ordering',
        'acquisition_relation', 'acquisition_scope', 'result_retention_policy',
        'local_result_definition', 'local_table_input_definition', 'local_computation', 'local_manifest',
        'result_import_observation', 'local_model_observation', 'local_dependencies',
        'result_import_interface', 'gate_requirement', 'source_input_logical',
        'source_evidence', 'local_body', 'parameter_declarations',
        'used_values', 'local_contracts', 'local_policy', 'result_import_type',
        'request_values', 'schema_evidence', 'capability_evidence',
        'relation_schema', 'relation_value',
        'source_contract', 'source_view_contract', 'data_policy',
        'retention_contract', 'metadata_retention_policy', 'clock_contract',
      ]}, cid: clone(cid), body: {type: 'object'}}},
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

// CLI containers reuse the existing closed receipt object. The array has no
// protocol version, kind, CID or aggregate authority of its own.
export function cliResultDeliveryReceiptFileSchema(registry) {
  const receipt = clone(registry.artifact_schemas.result_delivery_receipt);
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    title: 'CLI Result delivery receipt file',
    oneOf: [receipt, {type: 'array', maxItems: 16, items: clone(receipt)}],
  };
}

export function cliOutputVerificationSchema() {
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    title: 'CLI output verification report',
    type: 'object', additionalProperties: false,
    required: ['verified', 'byte_count', 'sha256', 'supplied_receipt_count',
      'matching_receipt_count', 'receipt_cids'],
    properties: {
      verified: {const: true},
      byte_count: {type: 'integer', minimum: 0, maximum: 536870912},
      sha256: {type: 'string', pattern: '^[0-9a-f]{64}$'},
      supplied_receipt_count: {type: 'integer', minimum: 1, maximum: 16},
      matching_receipt_count: {type: 'integer', minimum: 1, maximum: 16},
      receipt_cids: {type: 'array', minItems: 1, maxItems: 16,
        uniqueItems: true, items: clone(cid)},
    },
    $comment: 'receipt_cids contains every distinct matching admitted identity; '
      + 'matching_receipt_count equals its length and is at most supplied_receipt_count. '
      + 'Other valid receipts make no claim about unprovided output files.',
  };
}

export function checkContracts(registry, cli) {
  checkLocalTableInputContract(stageRegistry);
  checkLocalModelObservationContract(stageRegistry);
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
  assert.ok(!registry.artifact_schemas.run_definition.required.includes(
    'effect_target_selections_cid'));
  for (const [name, schema] of Object.entries(registry.artifact_schemas)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(schema), name);
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const read = path => JSON.parse(readFileSync(path, 'utf8'));
  const registry = read(registryPath);
  const cli = read(cliPath);
  if (process.argv.includes('--local-effect-only')) {
    const next = correctedLocalEffectOutcomeContracts(registry);
    if (process.argv.includes('--write')) writeFileSync(registryPath, JSON.stringify(next, null, 2) + '\n');
    else assert.deepEqual(registry, next, 'Local Effect outcome schemas are stale');
  } else if (process.argv.includes('--review-only')) {
    const next = correctedEffectReviewContracts(registry);
    if (process.argv.includes('--write')) {
      writeFileSync(registryPath, JSON.stringify(next, null, 2) + '\n');
    } else {
      assert.deepEqual(registry, next, 'Effect review schemas are stale');
    }
  } else if (process.argv.includes('--write')) {
    const next = correctedContracts(registry, cli);
    writeFileSync(registryPath, JSON.stringify(next.registry, null, 2) + '\n');
    writeFileSync(cliPath, JSON.stringify(next.cli, null, 2) + '\n');
    checkContracts(next.registry, next.cli);
  } else {
    checkContracts(registry, cli);
  }
  if (!process.argv.includes('--review-only') && !process.argv.includes('--local-effect-only')) {
    for (const [path, expected] of [
      [cliReceiptPath, cliResultDeliveryReceiptFileSchema(read(registryPath))],
      [cliVerificationPath, cliOutputVerificationSchema()],
    ]) {
      if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(expected, null, 2) + '\n');
      else assert.deepEqual(read(path), expected, `CLI receipt container/report is stale: ${path}`);
    }
  }
  console.log(process.argv.includes('--local-effect-only')
    ? 'Local Effect outcome evidence 0.1 schemas verified; unrelated publication/CLI contracts not checked.'
    : process.argv.includes('--review-only')
    ? 'Effect Preview/review 0.1 schemas verified; unrelated publication/CLI contracts not checked.'
    : 'Run publication 0.1 schemas and embeddings verified.');
}
