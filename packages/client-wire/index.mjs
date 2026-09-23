// Structural Client–Host wire admission only. The Host's MoonBit owners decide
// identities, authorization, state transitions, publication and retry.
const cid = /^sha256:[0-9a-f]{64}$/u;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
  [...keys].sort().join('\0');
const boundedText = (value, maximum = 256) => typeof value === 'string' &&
  value.length > 0 && value.length <= maximum &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const refs = value => Array.isArray(value) &&
  value.every(item => boundedText(item)) &&
  new Set(value).size === value.length;

export const clientHostOperations = Object.freeze([
  'connect', 'submit', 'attach', 'lookup-request', 'status', 'wait',
  'cancel', 'reconcile', 'read', 'delivery-attempt',
]);

export function validRunRef(value) {
  return exact(value, ['tenantId', 'authorityScopeCid',
    'runDefinitionCid']) && boundedText(value.tenantId) &&
    cid.test(value.authorityScopeCid) && cid.test(value.runDefinitionCid);
}

export function validClientConnection(value) {
  if (value === null || typeof value !== 'object' ||
      Array.isArray(value)) return false;
  const required = ['mode', 'owner', 'consentRefs', 'runners'];
  const allowed = new Set([...required, 'durability', 'movementPolicyRef',
    'cloudConnectionRef']);
  if (required.some(key => !Object.hasOwn(value, key)) ||
      Object.keys(value).some(key => !allowed.has(key)) ||
      !(value.mode === 'remote' && value.owner === 'remote' ||
        value.mode === 'local' && value.owner === 'local' ||
        value.mode === 'hybrid' && ['local', 'cloud'].includes(value.owner)) ||
      !refs(value.consentRefs) || !refs(value.runners) ||
      value.durability !== undefined &&
        !['volatile', 'durable'].includes(value.durability)) return false;
  if (value.mode === 'hybrid') {
    if (!boundedText(value.movementPolicyRef)) return false;
    return value.owner === 'local'
      ? boundedText(value.cloudConnectionRef)
      : value.cloudConnectionRef === undefined && value.runners.length > 0;
  }
  return value.movementPolicyRef === undefined &&
    value.cloudConnectionRef === undefined && value.runners.length === 0;
}

export function validClientBody(operation, body) {
  const bodyKeys = {
    connect: ['connection'],
    submit: ['connection', 'requestId', 'kind', 'input', 'parameters'],
    attach: ['connection', 'ref'],
    'lookup-request': ['connection', 'requestId'],
    status: ['connection', 'ref'],
    wait: ['connection', 'ref', 'until'],
    cancel: ['connection', 'ref'],
    reconcile: ['connection', 'ref'],
    read: ['connection', 'ref', 'resultName', 'format', 'attemptId'],
    'delivery-attempt': ['connection', 'ref', 'resultName', 'attemptId'],
  }[operation];
  if (bodyKeys === undefined || !exact(body, bodyKeys) ||
      !validClientConnection(body.connection)) return false;
  if (operation === 'connect') return true;
  if (operation === 'submit') {
    return boundedText(body.requestId) &&
      (body.kind === 'aql' && exact(body.input, ['text', 'format']) &&
        typeof body.input.text === 'string' &&
        body.input.text.length > 0 && body.input.text.length <= 65536 &&
        !body.input.text.includes('\u0000') &&
        ['json', 'yaml'].includes(body.input.format) ||
        body.kind === 'program' && body.input !== null &&
        typeof body.input === 'object' && !Array.isArray(body.input));
  }
  if (operation === 'lookup-request') return boundedText(body.requestId);
  if (!validRunRef(body.ref)) return false;
  if (operation === 'read') return boundedText(body.resultName) &&
    boundedText(body.attemptId) &&
    ['json', 'jsonl', 'csv'].includes(body.format);
  if (operation === 'delivery-attempt') return boundedText(body.resultName) &&
    boundedText(body.attemptId);
  if (operation === 'wait') return body.until === null ||
    boundedText(body.until, 128);
  return true;
}

// Validate the published delivery attempt, record and receipt schemas and
// their identity bindings. The Host owns authorization and receipt issuance.
const timestamp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u;
const digest = /^[0-9a-f]{64}$/u;
const count = value => Number.isSafeInteger(value) && value >= 0;
const shape = (value, required, optional = []) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  required.every(key => Object.hasOwn(value, key)) &&
  Object.keys(value).every(key => required.includes(key) ||
    optional.includes(key));
const cidField = (value, key) => cid.test(value[key]);
const optionalCid = (value, key) => !Object.hasOwn(value, key) ||
  cidField(value, key);

function validAttempt(value) {
  return shape(value, ['version', 'attempt_id', 'result_read_grant_cid',
    'run_definition_cid', 'result_manifest_cid', 'result_name',
    'result_artifact_cid', 'serialization_contract_cid', 'requested_at',
    'delivery_attempt_cid']) &&
    value.version === 'actql-delivery-attempt/0.1' &&
    boundedText(value.attempt_id) && boundedText(value.result_name) &&
    ['result_read_grant_cid', 'run_definition_cid',
      'result_manifest_cid', 'result_artifact_cid',
      'serialization_contract_cid', 'delivery_attempt_cid']
      .every(key => cidField(value, key)) &&
    timestamp.test(value.requested_at);
}

function validRecord(value) {
  if (!shape(value, ['version', 'delivery_attempt_cid', 'sequence',
    'state', 'confirmed_byte_count', 'exposure', 'observed_at',
    'cleanup_owner_cids', 'delivery_record_cid'],
  ['prior_record_cid', 'possible_unconfirmed_max_bytes',
    'delivered_sha256', 'result_delivery_receipt_cid', 'failure_cid']) ||
    value.version !== 'actql-delivery-record/0.1' ||
    !['delivery_attempt_cid', 'delivery_record_cid', 'prior_record_cid',
      'result_delivery_receipt_cid', 'failure_cid']
      .every(key => optionalCid(value, key)) ||
    !count(value.sequence) || !count(value.confirmed_byte_count) ||
    !['streaming', 'succeeded', 'failed', 'cancelled'].includes(value.state) ||
    !['exact', 'unknown_additional'].includes(value.exposure) ||
    !timestamp.test(value.observed_at) ||
    !Array.isArray(value.cleanup_owner_cids) ||
    !value.cleanup_owner_cids.every(item => cid.test(item)) ||
    new Set(value.cleanup_owner_cids).size !==
      value.cleanup_owner_cids.length ||
    Object.hasOwn(value, 'possible_unconfirmed_max_bytes') &&
      !count(value.possible_unconfirmed_max_bytes) ||
    Object.hasOwn(value, 'delivered_sha256') &&
      !digest.test(value.delivered_sha256) ||
    value.exposure === 'unknown_additional' &&
      !Object.hasOwn(value, 'possible_unconfirmed_max_bytes') ||
    value.sequence === 0 && Object.hasOwn(value, 'prior_record_cid') ||
    value.sequence > 0 && !Object.hasOwn(value, 'prior_record_cid')) {
    return false;
  }
  return value.state === 'succeeded'
    ? value.exposure === 'exact' &&
      Object.hasOwn(value, 'delivered_sha256') &&
      Object.hasOwn(value, 'result_delivery_receipt_cid')
    : !Object.hasOwn(value, 'result_delivery_receipt_cid');
}

function validReceipt(value) {
  return shape(value, ['version', 'run_definition_cid', 'invocation_cid',
    'result_manifest_cid', 'result_name', 'result_artifact_cid',
    'serialization_contract_cid', 'delivered_byte_count',
    'delivered_sha256', 'authorization_context_cid',
    'egress_admission_cid', 'result_delivery_receipt_cid']) &&
    value.version === 'actql-result-delivery-receipt/0.1' &&
    boundedText(value.result_name) && count(value.delivered_byte_count) &&
    digest.test(value.delivered_sha256) &&
    ['run_definition_cid', 'invocation_cid', 'result_manifest_cid',
      'result_artifact_cid', 'serialization_contract_cid',
      'authorization_context_cid', 'egress_admission_cid',
      'result_delivery_receipt_cid'].every(key => cidField(value, key));
}

export function validDeliveryAttemptLookup(value, expected) {
  if (!shape(expected, ['attemptId', 'runDefinitionCid', 'resultName']) ||
      !boundedText(expected.attemptId) ||
      !cid.test(expected.runDefinitionCid) ||
      !boundedText(expected.resultName)) return false;
  if (exact(value, ['kind']) && value.kind === 'not_found') return true;
  if (!exact(value, ['kind', 'attempt', 'record',
    'hostReleaseReceipt']) || value.kind !== 'found' ||
    !validAttempt(value.attempt) ||
    value.attempt.attempt_id !== expected.attemptId ||
    value.attempt.run_definition_cid !== expected.runDefinitionCid ||
    value.attempt.result_name !== expected.resultName) return false;
  const {attempt, record, hostReleaseReceipt: receipt} = value;
  if (record === null) return receipt === null;
  if (!validRecord(record) ||
      record.delivery_attempt_cid !== attempt.delivery_attempt_cid) {
    return false;
  }
  if (record.state !== 'succeeded') return receipt === null;
  if (!validReceipt(receipt) ||
      record.result_delivery_receipt_cid !==
        receipt.result_delivery_receipt_cid ||
      record.confirmed_byte_count !== receipt.delivered_byte_count ||
      record.delivered_sha256 !== receipt.delivered_sha256) return false;
  return ['run_definition_cid', 'result_manifest_cid', 'result_name',
    'result_artifact_cid', 'serialization_contract_cid']
    .every(key => attempt[key] === receipt[key]);
}
