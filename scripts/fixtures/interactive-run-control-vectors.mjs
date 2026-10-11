// Independently authored semantic cases, not compiler/Host output.
// Fixed identities are checked against an independent canonical JSON oracle.
import {createHash} from 'node:crypto';
import {canonicalText} from '../check-canonical-json.mjs';
export const cid = digit => `sha256:${digit.repeat(64)}`;
export const ref = {namespaceId: 'workspace:test', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
export const time = '2026-10-11T00:00:00.000Z';
export const legacyState = {version: 'actql-run-state/0.1', run_id: 'original',
  status: 'running', updated_at: time, next_action: {kind: 'none'},
  result_available: false, result_availability: {},
  control: {revision: 17, cancellation_requested: false, physical_stop: 'unknown'}};
export const running = {version: 'actql-controlled-run-state/0.1',
  run_id: 'original', status: 'running', updated_at: time, control_revision: 17,
  legacy_state: legacyState, pause_pending: false, expiry_pending: false,
  cleanup_pending: false};
export const paused = {version: 'actql-controlled-run-state/0.1',
  run_id: 'original', status: 'paused', updated_at: time, control_revision: 18,
  stop_reason: 'pause', boundary: {step_id: cid('1'), position: 'after',
    kind: 'logical_step', consumed_boundary_cid: cid('2')},
  matched_breakpoints: [], paused_at: time, expires_at: '2026-10-11T00:10:00.000Z',
  ttl_policy_cid: cid('3'), pause_pending: false, expiry_pending: false,
  cleanup_pending: false};
export const manual = {version: 'actql-controlled-run-state/0.1',
  run_id: 'original', status: 'resuming', updated_at: time, control_revision: 19,
  resume_origin: {kind: 'manual', command_cid: cid('4'),
    continuation_generation_cid: cid('5'), fence_cid: cid('6')},
  pause_pending: false, expiry_pending: false, cleanup_pending: false};
export const profile = {version: 'actql-control-profile/0.1', execution: {
  stop_on_entry: false, default_until: 'terminal', breakpoints: [], guards: null},
retain: {}};
export const command = {version: 'actql-control-command/0.1', operation: 'resume',
  run_ref: ref, expected_control_revision: 18, operation_id: 'original-command',
  interval: {until: 'terminal', guards: null}};
export const inputKey = {version: 'actql-logical-step-key/0.1',
  compiled_plan_cid: cid('1'), stage_ordinal: 1,
  occurrence: {kind: 'input_output', input_port_ordinal: 0}};
export const operationKey = {version: 'actql-logical-step-key/0.1',
  compiled_plan_cid: cid('1'), stage_ordinal: 1,
  occurrence: {kind: 'operation', operation_ordinal: 0}};
// This oracle never calls a product sealer/compiler or observes a Host result.
const digest = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;
const sealed = body => ({...body, self_cid: digest(body)});
export const planBody = {version: 'actql-compiled-plan/0.1', compiler_version: '0.1',
  aoa_ir_version: '0.1', executable_plan_cid: cid('2'),
  program_definition_cid: cid('3'), program_semantics_cid: cid('4'),
  aoa_contract_cid: cid('5'), aoa_logical_cid: cid('6')};
export const planCid = digest(planBody);
export const boundInputKey = sealed({...inputKey, compiled_plan_cid: planCid});
export const portKey = role => sealed({version: 'actql-logical-port-key/0.1',
  compiled_plan_cid: planCid, step_id: boundInputKey.self_cid, role, port_ordinal: 0});
export const mapBody = {version: 'actql-logical-map/0.1', compiled_plan_cid: planCid,
  program_definition_cid: planBody.program_definition_cid, steps: [{
    step_id: boundInputKey.self_cid, key: boundInputKey, names: ['answer'],
    operator: null, ports: ['input', 'output'].map(role => ({
      port_id: portKey(role).self_cid, role, port_ordinal: 0, carrier: 'relation',
      carrier_contract_cid: cid('7'), source: {kind: 'stage_input', stage_ordinal: 1,
        input_port_ordinal: 0}, can_sample: false, sample_reason: 'not_installed'})),
    can_stop_before: false, can_stop_after: false, stop_reason: 'not_installed',
  }]};
export const intentBody = {version: 'actql-control-request-intent/0.1',
  submission_ref: {epoch: {version: 'actql-submission-epoch/0.1',
    authorityScopeCid: ref.authorityScopeCid, epochNonce: '1'.repeat(64),
    notBefore: 1, expiresAt: 2, authenticator: '2'.repeat(64)}, nonce: 'original-request'},
  legacy_request_fingerprint_cid: cid('8'),
  requested_profile_cid: digest(profile), expected_plan_cid: planCid};
export const resolvedBody = {version: 'actql-resolved-control-profile/0.1',
  requested_profile_cid: digest(profile), compiled_plan_cid: planCid,
  logical_map_cid: digest(mapBody), effective_profile_cid: digest(profile),
  breakpoints: [], sample_output_port_ids: []};
export const admissionBody = {version: 'actql-control-admission/0.1',
  request_intent_cid: digest(intentBody), run_ref: ref, compiled_plan_cid: planCid,
  logical_map_cid: digest(mapBody), resolved_profile_cid: digest(resolvedBody),
  policy_revision_cid: cid('9')};
export const bindingVectors = [
  ['control_request_intent', intentBody], ['resolved_control_profile', resolvedBody],
  ['logical_map', mapBody], ['control_admission', admissionBody],
].map(([name, body]) => ({name, body, cid: digest(body)}));
export const bindingMutations = [
  ['logical_map', {...mapBody, compiled_plan_cid: cid('0')}],
  ['logical_map', {...mapBody, program_definition_cid: cid('0')}],
  ['logical_map', {...mapBody, steps: [{...mapBody.steps[0], operator: 'select'}]}],
  ['logical_map', {...mapBody, steps: [{...mapBody.steps[0],
    ports: mapBody.steps[0].ports.map(p => ({...p, port_id: cid('0')}))}]}],
  ['logical_map', {...mapBody, steps: [mapBody.steps[0], mapBody.steps[0]]}],
  ['control_request_intent', {...intentBody, expected_plan_cid: cid('0')}],
  ['control_request_intent', {...intentBody, requested_profile_cid: cid('0')}],
  ['resolved_control_profile', {...resolvedBody, logical_map_cid: cid('0')}],
  ['resolved_control_profile', {...resolvedBody, effective_profile_cid: cid('0')}],
  ['resolved_control_profile', {...resolvedBody, breakpoints: [{kind: 'logical_step',
    step_id: cid('0'), position: 'before'}]}],
  ['resolved_control_profile', {...resolvedBody, sample_output_port_ids: [portKey('input').self_cid]}],
  ['control_admission', {...admissionBody, request_intent_cid: cid('0')}],
  ['control_admission', {...admissionBody, run_ref: {...ref, runDefinitionCid: cid('0')}}],
  ['control_admission', {...admissionBody, run_ref: {...ref, authorityScopeCid: cid('0')}}],
].map(([name, body]) => ({name, body, cid: digest(body)}));
export const sampleRelation = {version: 'actql-sample-relation/0.1',
  kind: 'relation', schema_cid: cid('7'), columns: [
    {position: 0, name: 'p', value_contract_cid: cid('8'), required: false}],
  rows: [[{presence: 'present', value_contract_cid: cid('8'), value: null}],
    [{presence: 'absent'}], [{presence: 'present', value_contract_cid: cid('8'),
      value: 'e\u0301\r\né'}]], ordering_evidence_cid: null};
export const sampleGraph = {version: 'actql-sample-graph/0.1', kind: 'graph',
  graph_contract_cid: cid('7'), topology_complete: false, nodes: [], edges: [
    {definition_cid: cid('1'), domain_cid: cid('2'), identity_cid: cid('3'),
      key: [{value_contract_cid: cid('8'), value: 1}],
      src_identity_cid: cid('4'), dst_identity_cid: cid('5'),
      label: {presence: 'absent'}, properties: []},
    {definition_cid: cid('1'), domain_cid: cid('2'), identity_cid: cid('6'),
      key: [{value_contract_cid: cid('8'), value: 2}],
      src_identity_cid: cid('4'), dst_identity_cid: cid('5'),
      label: {presence: 'present', value_contract_cid: cid('8'), value: null},
      properties: []},
  ]};
export const sampleVectors = {version: 'actql-sample-vectors/0.1',
  kind: 'vectors', vectors_contract_cid: cid('7'), items: [
    {key: [{value_contract_cid: cid('8'), value: 'q'},
      {value_contract_cid: cid('9'), value: 1}], dimension: 1536,
    precision: 'float64', components_complete: false,
    components: [{index: 0, value: 0.5}, {index: 1, value: 0}]},
  ]};
export const sampleEvents = {version: 'actql-sample-events/0.1', kind: 'events',
  events_contract_cid: cid('7'), identity_role: 'event_id', time_role: 'event_time',
  clock_evidence_cid: null, window_evidence_cid: null, watermark_evidence_cid: null,
  late_evidence_cid: null, order_proven: false, ordering_evidence_cid: null,
  occurrences: ['1', '2'].map(id => ({occurrence_cid: cid(id),
    key: [{value_contract_cid: cid('8'), value: 'same-id'}],
    timestamp: {presence: 'present', value_contract_cid: cid('8'), value: time},
    payload: {presence: 'present', value_contract_cid: cid('9'), value: {v: 1}}})),
};
export const identityVectors = [
  {name: 'control_profile', body: profile,
    cid: 'sha256:bfaf0bf9b06cb598cdc3f7d56d23745e7bc6b5277bd9320e632c51a4f1cf8b50'},
  {name: 'control_command', body: command,
    cid: 'sha256:7f7e365b0dad169d951aa7fa88311bc12f8fb0caa13551dea104c4bf18084cce'},
  {name: 'logical_step_key', body: inputKey,
    cid: 'sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9'},
  {name: 'logical_step_key', body: operationKey,
    cid: 'sha256:2ad8ff68dc3e793e262cc6efcb41ffb3d254795cd6780457fd04600cc09d8fbd'},
];
export const shapeVectors = [
  {name: 'controlled_run_state', value: running},
  {name: 'controlled_run_state', value: paused},
  {name: 'controlled_run_state', value: manual},
  {name: 'sample_relation', value: sampleRelation},
  {name: 'sample_graph', value: sampleGraph},
  {name: 'sample_vectors', value: sampleVectors},
  {name: 'sample_events', value: sampleEvents},
  {name: 'run_sample', value: {state: 'forbidden'}},
  {name: 'run_sample', value: {state: 'expired'}},
  {name: 'run_sample', value: {state: 'unavailable', reason: 'selection_required'}},
  {name: 'run_sample', value: {state: 'unavailable', reason: 'evicted'}},
  {name: 'control_operation_lookup', value: {state: 'history_unavailable', reason: 'bounded_history_expired'}},
  ...['0', '9007199254740993', '9223372036854775806', '9223372036854775807']
    .map(amount_micro => ({name: 'control_money', value: {currency: 'USD',
      amount_micro, scope_cids: [cid('1')], tariff_revision_cid: cid('2'), valid_until: time}})),
];
export const negativeVectors = [
  ...['effect', 'unregistered_operator'].map(operator => ({name: 'control_profile',
    value: sealed({...profile, execution: {...profile.execution, breakpoints: [
      {kind: 'logical_step', select: {by: 'operator', operator}, position: 'after'},
    ]}})})),
  {name: 'controlled_run_state', value: {...running, control_revision: '17'}},
  {name: 'controlled_run_state', value: {...running, control_revision: 2147483648}},
  {name: 'controlled_run_state', value: {...paused, legacy_state: legacyState}},
  {name: 'controlled_run_state', value: {...manual, legacy_state: {...legacyState, status: 'resuming'}}},
  {name: 'controlled_run_state', value: {...running, stop_reason: 'pause'}},
  {name: 'controlled_run_state', value: {...paused, previous_stop_reason: 'entry'}},
  {name: 'controlled_run_state', value: {...paused, stop_reason: 'breakpoint'}},
  {name: 'run_sample', value: {state: 'forbidden', kind: 'graph', count: 1}},
  {name: 'run_sample', value: {state: 'expired', source: {}}},
  {name: 'control_quantity', value: {kind: 'unknown', unit: 'rows', reason: 'unobserved', value: '0'}},
  {name: 'control_quantity', value: {kind: 'bound', unit: 'bytes', scope_cid: cid('1'), basis_cid: cid('2'), value: '01'}},
  {name: 'control_quantity', value: {kind: 'bound', unit: 'bytes', scope_cid: cid('1'), basis_cid: cid('2'), value: '1\n'}},
  {name: 'sample_relation', value: {...sampleRelation, kind: 'graph'}},
  {name: 'sample_relation', value: {...sampleRelation, rows: [[{presence: 'absent', value: null}]]}},
  {name: 'sample_events', value: {...sampleEvents, order_proven: true}},
  {name: 'control_interval', value: {until: 'automatically_retry', guards: null}},
  ...['9223372036854775808', '00', '+1', '-1', '1e3', ' 1', '1.0', '1\n', 1]
    .map(amount_micro => ({name: 'control_money', value: {currency: 'USD',
      amount_micro, scope_cids: [cid('1')], tariff_revision_cid: cid('2'), valid_until: time}})),
  ...['usd', 'US', 'USDA', 'USD\n'].map(currency => ({name: 'control_money',
    value: {currency, amount_micro: '1', scope_cids: [cid('1')],
      tariff_revision_cid: cid('2'), valid_until: time}})),
];
