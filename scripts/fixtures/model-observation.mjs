// Independent authored observations. Symbolic identity roots isolate exact
// shape/version/provenance; they are not execution or provider authority.
const cid = digit => `sha256:${digit.repeat(64)}`;
export const historicalModelObservation = {
  version: 'actql-model-invocation-evidence/0.1',
  model_task_contract_cid: cid('1'), semantic_request_cid: cid('2'),
  model_call_slot_cid: cid('3'), input_result_artifact_cid: cid('4'),
  input_row_identity_cid: cid('5'), input_row_identity: ['key', 7],
  authored_model_selector: 'configured-selector',
  provider_reported_model_id: 'historical-model',
  provider_request_id: 'historical-request', attempt: 1,
  structured_response_artifact_cid: cid('6'),
  validated_structured_output_cid: cid('7'),
  input_tokens: 0, output_tokens: 11, finish_reason: 'stop',
  observed_at: '2026-10-11T00:00:00.000Z',
};
export const nullableModelObservation = {
  ...historicalModelObservation,
  version: 'actql-model-invocation-evidence/0.2',
  provider_reported_model_id: null, provider_reported_revision: null,
  provider_request_id: null, gateway_request_id: null,
  input_tokens: null, output_tokens: 0, finish_reason: null,
  raw_response_artifact_cid: null, response_profile_cid: cid('8'),
  response_complete: true, provider_metadata: null,
};
export const reportedModelObservation = {
  ...nullableModelObservation, provider_reported_model_id: 'raw-e\u0301\r\nmodel',
  provider_reported_revision: 'revision-1', provider_request_id: 'raw-request',
  gateway_request_id: 'gateway-1', input_tokens: 13, output_tokens: null,
  finish_reason: 'provider-complete', raw_response_artifact_cid: cid('9'),
  provider_metadata: {provider: {unknown_extension: [null, 0, false, '',
    'raw-e\u0301\r\n'], nested: {complete: false, precision: 99, retry: true}}},
};
export const observationRefusals = [
  ['unknown version', e => {e.version = 'actql-model-invocation-evidence/invalid';}],
  ['missing model observation', e => {delete e.provider_reported_model_id;}],
  ['missing usage is not NULL', e => {delete e.input_tokens;}],
  ['negative usage', e => {e.input_tokens = -1;}],
  ['fractional usage', e => {e.output_tokens = 0.5;}],
  ['empty reported model', e => {e.provider_reported_model_id = '';}],
  ['empty reported finish', e => {e.finish_reason = '';}],
  ['no complete assertion', e => {e.response_complete = false;}],
  ['missing profile', e => {delete e.response_profile_cid;}],
  ['NULL profile', e => {e.response_profile_cid = null;}],
  ['array is not metadata object', e => {e.provider_metadata = [];}],
  ['scalar is not metadata object', e => {e.provider_metadata = 42;}],
  ['unknown field', e => {e.sdk_timestamp = 'fake-provider-timestamp';}],
];
