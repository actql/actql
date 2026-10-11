import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const controlRegistryPath =
  'spec/contracts/actql-interactive-run-control.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const integer = {type: 'integer', minimum: 0, maximum: 2147483647};
const positive = {...integer, minimum: 1};
const decimal = {type: 'string', pattern: '^(0|[1-9][0-9]*)$(?![\\s\\S])'};
// The negotiated amount domain uses the existing checked Int64 ledger range.
// Wire amounts remain decimal strings, including above MAX_SAFE_INTEGER.
export const maxAmountMicro = '9223372036854775807';
export const amountMicroPattern = '^(' + [
  '0', '[1-9][0-9]{0,17}',
  ...[...maxAmountMicro].flatMap((digit, index) => {
    const lower = index === 0 ? 1 : 0;
    const upper = Number(digit) - 1;
    if (upper < lower) return [];
    const range = lower === upper ? String(lower) : `[${lower}-${upper}]`;
    const suffix = maxAmountMicro.length - index - 1;
    return [maxAmountMicro.slice(0, index) + range +
      (suffix ? `[0-9]{${suffix}}` : '')];
  }), maxAmountMicro,
].join('|') + ')$(?![\\s\\S])';
const timestamp = {type: 'string', format: 'date-time'};
const bool = {type: 'boolean'};
const nullable = schema => ({oneOf: [{type: 'null'}, schema]});
const list = (items, minItems = 0) => ({type: 'array', items, minItems});
const choice = (...values) => ({type: 'string', enum: values});
const ref = name => ({$ref: `#/schemas/${name}`});
const object = (properties, optional = [], allOf) => ({
  type: 'object', additionalProperties: false,
  required: Object.keys(properties).filter(name => !optional.includes(name)),
  properties, ...(allOf ? {allOf} : {}),
});
const envelope = (name, fields, optional = [], allOf) => ({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: `https://smooth.dev/schemas/actql-${name.replaceAll('_', '-')}-0.1.json`,
  ...object({version: {const: `actql-${name.replaceAll('_', '-')}/0.1`},
    ...fields}, optional, allOf),
});
const when = (field, value, then, otherwise) => ({
  if: {properties: {[field]: {const: value}}, required: [field]}, then,
  ...(otherwise ? {else: otherwise} : {}),
});
const kind = choice('relation', 'graph', 'vectors', 'events');
// Checked logical operation tags, not backend/AoA opcodes or an execution
// support claim. Keep this finite vocabulary aligned with the common checker.
export const logicalOperators = Object.freeze([
  'analytic', 'append', 'apply_graph_delta', 'asof_join', 'assert_rows',
  'calendar_bucket', 'calendar_series', 'components', 'cross_join',
  'dedupe_events', 'dedupe_rows', 'degree', 'derive', 'distinct', 'drop',
  'edge_rows', 'events', 'except', 'filter', 'graft_graph', 'graph',
  'graph_bounds', 'graph_diff', 'graphs_equal', 'group', 'infer', 'intersect',
  'interval_join', 'join', 'json_pick', 'lag', 'match_edges', 'match_nodes',
  'mean_graphs', 'merge_rankings', 'nearest', 'nest', 'node_rows',
  'normalize_graph', 'normalize_vectors', 'pivot', 'pool_vectors', 'reach',
  'rename', 'row_window', 'score_vectors', 'select', 'sequence', 'session',
  'shortest_path', 'sort', 'subgraph', 'subtract_graphs', 'take', 'text_rank',
  'time_series', 'to_events', 'to_vectors', 'top_k', 'top_k_by', 'traverse',
  'union_graphs', 'unnest', 'unpivot', 'values', 'vectors', 'watermark_events',
  'watermark_rows', 'window_events', 'window_group',
]);
const selector = {oneOf: [
  object({by: {const: 'name'}, name: text}),
  object({by: {const: 'operator'}, operator: choice(...logicalOperators)}),
  object({by: {const: 'id'}, step_id: cid}),
]};
const breakpoint = {oneOf: [
  object({kind: {const: 'logical_step'}, select: selector,
    position: choice('before', 'after')}),
  object({kind: {const: 'gate'}, gate_kind: {const: 'effect_set'},
    position: {const: 'before'}}),
]};

// Schemas describe wire admission, not installed execution capabilities.
// Shared identity, authorization and material Owners validate referenced facts.
export function interactiveRunControlSchemas() {
  const schemas = {};
  schemas.control_quantity = {oneOf: [
    object({kind: choice('exact', 'bound', 'estimate'), value: decimal,
      unit: text, scope_cid: cid, basis_cid: cid}),
    object({kind: {const: 'unknown'}, unit: text, reason: text}),
  ]};
  schemas.control_money = object({currency: {type: 'string', pattern: '^[A-Z]{3}$(?![\\s\\S])'},
    amount_micro: {type: 'string', pattern: amountMicroPattern},
    scope_cids: {...list(cid, 1), uniqueItems: true}, tariff_revision_cid: cid,
    valid_until: timestamp});
  schemas.control_guards = object({estimated_cost_ceiling:
    ref('control_money')});
  schemas.control_interval = object({until: choice('step', 'batch', 'gate',
    'boundary', 'breakpoint', 'terminal'), guards: nullable(ref('control_guards'))});
  schemas.control_profile = envelope('control_profile', {
    execution: object({stop_on_entry: bool,
      default_until: choice('terminal', 'breakpoint', 'step'),
      breakpoints: list(breakpoint), guards: nullable(ref('control_guards'))}),
    retain: object({
      samples: object({strategy: {const: 'execution_prefix'},
        capture_scope: choice('all_outputs', 'selected_outputs'),
        targets: list(selector), max_items: positive, max_bytes: decimal,
        max_artifacts: positive, ttl_seconds: positive, required: bool,
        graph: object({max_nodes: integer, max_edges: integer}),
        vectors: object({max_components_per_item: positive})}, [], [
        when('capture_scope', 'selected_outputs',
          {properties: {targets: {type: 'array', minItems: 1}}},
          {properties: {targets: {type: 'array', maxItems: 0}}}),
      ]),
      intermediate: object({max_bytes: decimal, max_artifacts: positive,
        ttl_seconds: positive}),
    }, ['samples', 'intermediate']), self_cid: cid,
  });
  schemas.control_request_intent = envelope('control_request_intent', {
    submission_ref: {$ref: 'actql-client-host.json#/schemas/submission_ref'},
    legacy_request_fingerprint_cid: cid, requested_profile_cid: cid,
    expected_plan_cid: nullable(cid), self_cid: cid,
  });
  schemas.control_admission = envelope('control_admission', {
    request_intent_cid: cid,
    run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
    compiled_plan_cid: cid, logical_map_cid: cid,
    resolved_profile_cid: cid, policy_revision_cid: cid, self_cid: cid,
  });
  schemas.resolved_control_profile = envelope('resolved_control_profile', {
    requested_profile_cid: cid, compiled_plan_cid: cid, logical_map_cid: cid,
    effective_profile_cid: cid,
    breakpoints: list({oneOf: [
      object({kind: {const: 'logical_step'}, step_id: cid,
        position: choice('before', 'after')}),
      object({kind: {const: 'gate'}, gate_kind: {const: 'effect_set'},
        position: {const: 'before'}}),
    ]}),
    sample_output_port_ids: {...list(cid), uniqueItems: true}, self_cid: cid,
  });
  schemas.logical_step_key = envelope('logical_step_key', {
    compiled_plan_cid: cid, stage_ordinal: integer,
    occurrence: {oneOf: [
      object({kind: {const: 'operation'}, operation_ordinal: integer}),
      object({kind: {const: 'input_output'}, input_port_ordinal: integer}),
    ]}, self_cid: cid,
  });
  schemas.logical_port_key = envelope('logical_port_key', {
    compiled_plan_cid: cid, step_id: cid, role: choice('input', 'output'),
    port_ordinal: integer, self_cid: cid,
  });
  schemas.logical_source_locator = {oneOf: [
    object({kind: {const: 'stage_input'}, stage_ordinal: integer,
      input_port_ordinal: integer}),
    object({kind: {const: 'logical_output'}, step_id: cid, output_port_id: cid}),
  ]};
  schemas.logical_port = object({port_id: cid, role: choice('input', 'output'),
    port_ordinal: integer, carrier: kind, carrier_contract_cid: cid,
    source: ref('logical_source_locator'), can_sample: bool,
    sample_reason: nullable(text)});
  schemas.logical_step = object({step_id: cid,
    key: ref('logical_step_key'), names: {...list(text), uniqueItems: true},
    operator: nullable(choice(...logicalOperators)), ports: list(ref('logical_port'), 1),
    can_stop_before: bool, can_stop_after: bool, stop_reason: nullable(text)});
  schemas.logical_map = envelope('logical_map', {
    compiled_plan_cid: cid, program_definition_cid: cid,
    steps: list(ref('logical_step')), self_cid: cid,
  });
  schemas.run_control_capabilities = object({
    static_plan: bool, inspect: bool, durable_control: bool,
    sample_capture: {...list(kind), uniqueItems: true},
    full_intermediate_retention: {...list(kind), uniqueItems: true},
    cost_guard: bool, execution_batch: bool, policy_revision_cid: cid,
  });
  schemas.plan_view = envelope('plan_view', {
    compiled_plan_cid: cid, logical_map: ref('logical_map'),
    observation: {const: 'static'}, provider_io: {const: 0},
    quantities: list(ref('control_quantity')),
    capabilities: ref('run_control_capabilities'),
  });
  schemas.control_resume_origin = {oneOf: [
    object({kind: {const: 'manual'}, command_cid: cid,
      continuation_generation_cid: cid, fence_cid: cid}),
    object({kind: {const: 'checkpoint_resolution'}, checkpoint_cid: cid,
      resolution_cid: cid, continuation_generation_cid: cid, fence_cid: cid}),
  ]};
  // Embed the original closed old schema by reference. The new envelope does
  // not relax it, replace its discriminator or synthesize approval fields.
  schemas.controlled_run_state = envelope('controlled_run_state', {
    run_id: text, status: choice('preparing', 'running', 'waiting_checkpoint',
      'resuming', 'needs_reconciliation', 'succeeded', 'failed', 'cancelled',
      'paused'), updated_at: timestamp, control_revision: integer,
    legacy_state: {$ref: 'actql-protocol-schemas.json#/artifact_schemas/run_state'},
    resume_origin: ref('control_resume_origin'),
    stop_reason: choice('entry', 'step', 'batch', 'boundary', 'gate',
      'breakpoint', 'pause', 'guard_exceeded', 'guard_unavailable'),
    boundary: object({step_id: nullable(cid), position: choice('before', 'after'),
      kind: choice('entry', 'logical_step', 'batch', 'gate', 'boundary'),
      consumed_boundary_cid: cid}),
    matched_breakpoints: list(cid), paused_at: timestamp, expires_at: timestamp,
    ttl_policy_cid: cid, pause_pending: bool, expiry_pending: bool,
    cleanup_pending: bool,
  }, ['legacy_state', 'resume_origin', 'stop_reason', 'boundary',
    'matched_breakpoints', 'paused_at', 'expires_at', 'ttl_policy_cid',
    'pause_pending', 'expiry_pending', 'cleanup_pending'], [
    when('status', 'paused', {
      required: ['stop_reason', 'boundary', 'matched_breakpoints', 'paused_at',
        'expires_at', 'ttl_policy_cid'], not: {required: ['legacy_state']},
    }, {not: {anyOf: ['stop_reason', 'boundary', 'matched_breakpoints',
      'paused_at', 'expires_at', 'ttl_policy_cid'].map(name => ({required: [name]}))}}),
    when('status', 'resuming', {required: ['resume_origin']},
      {not: {required: ['resume_origin']}}),
    {if: {properties: {resume_origin: {properties: {kind: {const: 'manual'}},
      required: ['kind']}}, required: ['resume_origin']},
    then: {not: {required: ['legacy_state']}}},
    when('stop_reason', 'breakpoint',
      {properties: {matched_breakpoints: {type: 'array', minItems: 1}}}),
  ]);
  schemas.control_command = envelope('control_command', {
    operation: choice('pause', 'resume'),
    run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
    expected_control_revision: integer, operation_id: text,
    interval: ref('control_interval'), self_cid: cid,
  }, ['interval'], [when('operation', 'resume', {required: ['interval']},
    {not: {required: ['interval']}})]);
  schemas.control_operation_ref = object({
    run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
    operation_id: text, command_cid: cid, accepted_from_revision: integer,
  });
  schemas.control_operation_receipt = envelope('control_operation_receipt', {
    operation_ref: ref('control_operation_ref'),
    outcome: choice('accepted', 'completed', 'unknown'),
    observed_state: ref('controlled_run_state'), self_cid: cid,
  });
  schemas.control_operation_observation = object({
    original_receipt_cid: cid, operation_ref: ref('control_operation_ref'),
    outcome: choice('accepted', 'completed', 'unknown',
      'suppressed_by_checkpoint', 'completed_without_pause'),
    checkpoint_cid: cid, observed_at: timestamp,
  }, ['checkpoint_cid'], [when('outcome', 'suppressed_by_checkpoint',
    {required: ['checkpoint_cid']}, {not: {required: ['checkpoint_cid']}})]);
  schemas.control_operation_lookup = {oneOf: [
    object({state: {const: 'found'}, receipt: ref('control_operation_receipt'),
      observation: ref('control_operation_observation')}),
    object({state: choice('unknown', 'history_unavailable', 'not_found'),
      reason: text}),
  ]};
  schemas.control_operation_query = {oneOf: [
    object({by: {const: 'operation'}, operation_ref: ref('control_operation_ref')}),
    object({by: {const: 'revision'},
      run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
      expected_control_revision: integer}),
  ]};
  schemas.sample_selector = object({step: selector, role: choice('input', 'output'),
    input_port_id: cid}, ['input_port_id'], [
    when('role', 'output', {not: {required: ['input_port_id']}}),
  ]);
  schemas.sample_source = object({
    run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
    compiled_plan_cid: cid, logical_map_cid: cid, step_id: cid,
    role: choice('input', 'output'), port_id: cid, carrier: kind,
    carrier_contract_cid: cid, source_generation_cid: cid,
    original_capture_cid: cid, producer: ref('logical_source_locator'),
  });
  schemas.sample_capture = object({strategy: {const: 'execution_prefix'},
    sampled_items: decimal, total: ref('control_quantity'),
    completeness: choice('complete', 'partial', 'unknown'),
    truncation: choice('confirmed', 'not_truncated', 'unknown'),
    sample_ref_cid: cid, receipt_cid: cid, emission_provenance_cid: cid});
  // A value is bound to its original admitted value contract. Presence is
  // separate from NULL. Reading this envelope alone establishes no type proof.
  schemas.sample_cell = {oneOf: [
    object({presence: {const: 'absent'}}),
    object({presence: {const: 'present'}, value_contract_cid: cid, value: {}}),
  ]};
  schemas.sample_relation = envelope('sample_relation', {
    kind: {const: 'relation'}, schema_cid: cid,
    columns: list(object({position: integer, name: nullable(text),
      value_contract_cid: cid, required: bool})),
    rows: list(list(ref('sample_cell'))), ordering_evidence_cid: nullable(cid),
  });
  const key = list(object({value_contract_cid: cid, value: {}}), 1);
  const properties = list(object({name: text, cell: ref('sample_cell')}));
  schemas.sample_graph = envelope('sample_graph', {
    kind: {const: 'graph'}, graph_contract_cid: cid, topology_complete: bool,
    nodes: list(object({definition_cid: cid, domain_cid: cid, identity_cid: cid,
      key, properties})),
    edges: list(object({definition_cid: cid, domain_cid: cid, identity_cid: cid,
      key, src_identity_cid: cid, dst_identity_cid: cid,
      label: ref('sample_cell'), properties})),
  });
  schemas.sample_vectors = envelope('sample_vectors', {
    kind: {const: 'vectors'}, vectors_contract_cid: cid,
    items: list(object({key, dimension: positive, precision: text,
      components_complete: bool,
      components: list(object({index: integer, value: {type: 'number'}}))})),
  });
  schemas.sample_events = envelope('sample_events', {
    kind: {const: 'events'}, events_contract_cid: cid,
    identity_role: text, time_role: text, clock_evidence_cid: nullable(cid),
    window_evidence_cid: nullable(cid), watermark_evidence_cid: nullable(cid),
    late_evidence_cid: nullable(cid), order_proven: bool,
    ordering_evidence_cid: nullable(cid),
    occurrences: list(object({occurrence_cid: cid, key,
      timestamp: ref('sample_cell'), payload: ref('sample_cell')})),
  }, [], [when('order_proven', true, {properties: {ordering_evidence_cid: cid}})]);
  schemas.run_sample = {oneOf: [
    ...['relation', 'graph', 'vectors', 'events'].map(carrier => object({
      state: {const: 'available'},
      source: {...ref('sample_source'), allOf: [{properties: {
        carrier: {const: carrier}}}]},
      capture: ref('sample_capture'), data: ref(`sample_${carrier}`),
    })),
    object({state: {const: 'unavailable'}, reason: choice('selection_required',
      'not_retained', 'not_supported', 'not_sealed', 'evicted', 'capacity')}),
    object({state: {const: 'unknown'}, reason: text}),
    object({state: {const: 'expired'}}),
    object({state: {const: 'forbidden'}}),
  ]};
  schemas.run_view = envelope('run_view', {
    run_ref: {$ref: 'actql-client-host.json#/schemas/run_ref'},
    run_state: ref('controlled_run_state'),
    compiled_plan_cid: nullable(cid), logical_map_cid: nullable(cid),
    consistency: {const: 'non_atomic'}, observation_scope: {const: 'owner_local'},
    components: list(object({owner: text, revision: nullable(text),
      state: choice('observed', 'unknown', 'unavailable', 'forbidden'),
      provenance_cid: nullable(cid)})),
    quantities: list(ref('control_quantity')), sample: ref('run_sample'),
    available_operations: {...list(choice('inspect', 'wait_view', 'pause',
      'resume', 'cancel', 'resolve', 'lookup_control_operation')),
    uniqueItems: true}, capabilities: ref('run_control_capabilities'),
  });
  return schemas;
}

export const controlErrors = Object.freeze([
  'RunControlCapabilityRequired', 'RunStateVersionUnsupported', 'RunNotPaused',
  'CheckpointPending', 'ControlRevisionConflict', 'ControlOperationConflict',
  'ControlRevisionExhausted', 'BreakpointUnresolved', 'BreakpointAmbiguous',
  'BreakpointPlanMismatch', 'BreakpointUnsupported', 'BoundaryUnsupported',
  'InitialPauseUnsupported', 'InspectionRetentionUnsupported',
  'SampleCaptureRequiredFailed', 'GuardExceeded', 'GuardUnavailable',
  'InvalidCostAmount', 'ExecutionProfileConflict', 'CLIOptionConflict',
  'InteractiveTTYRequired',
]);

export function buildControlRegistry() {
  const schemas = interactiveRunControlSchemas();
  const body = {
    version: 'actql-interactive-run-control-registry/0.1',
    schemas, schema_cids: Object.fromEntries(Object.entries(schemas)
      .map(([name, schema]) => [name, machineCid(schema)])),
    identity_domains: Object.fromEntries(Object.entries(schemas)
      .filter(([, schema]) => schema.properties?.self_cid)
      .map(([name, schema]) => [name, {
        version: schema.properties.version.const, identity_field: 'self_cid',
        preimage: 'complete_body_except_self_cid', algorithm: 'sha256',
      }])),
    errors: [...controlErrors],
    compatibility: {
      legacy_run_state: 'unchanged_closed_schema',
      legacy_start: 'unchanged_preimage', run_definition: 'unchanged_preimage',
      legacy_status_wait: 'exact_projection_or_RunStateVersionUnsupported',
      paused: 'RunStateVersionUnsupported',
      manual_resuming: 'RunStateVersionUnsupported',
      checkpoint_resuming: 'requires_original_checkpoint_resolution',
      observation: 'non_atomic_owner_local',
      schema_registration: 'does_not_advertise_runtime_capabilities',
    },
  };
  return {...body, registry_cid: machineCid(body)};
}

// Registration is generated from this reviewed shape source. Independent
// semantic vectors have a separate authored source and are never overwritten.
function install(registry) {
  writeFileSync(controlRegistryPath, JSON.stringify(registry, null, 2) + '\n');
  const manifestPath = 'spec/spec-family.json';
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const owner = manifest.documents.find(entry => entry.document_id === 'run');
  assert.ok(owner);
  let source = readFileSync(owner.path, 'utf8');
  for (const [name, schema] of [...Object.entries(registry.schemas), ['', registry]]) {
    const pointer = name ? `/schemas/${name}` : '';
    const pin = machineCid(schema);
    const reference = owner.machine_contracts.find(entry =>
      entry.path === controlRegistryPath && entry.pointer === pointer);
    const prefix = `../../../${controlRegistryPath}#${pointer} `;
    if (reference) {
      source = source.replace(prefix + reference.cid, prefix + pin);
      reference.cid = pin;
    } else {
      owner.machine_contracts.push({path: controlRegistryPath,
        pointer, cid: pin, version: registry.version});
      const anchor = '<!-- page-contents:start -->';
      source = source.replace(anchor,
        `<!-- machine-import: ${prefix}${pin} -->\n${anchor}`);
    }
  }
  writeFileSync(owner.path, source);
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const expected = buildControlRegistry();
  if (process.argv.includes('--write')) install(expected);
  assert.deepEqual(JSON.parse(readFileSync(controlRegistryPath, 'utf8')), expected);
  console.log(`${Object.keys(expected.schemas).length} interactive contracts verified; runtime capabilities not enabled.`);
}
