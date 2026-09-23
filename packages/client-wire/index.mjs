// Structural Client–Host wire admission only. The Host's MoonBit owners decide
// identities, authorization, state transitions, publication and retry.
import {validDeliveryAttempt, validDeliveryRecord,
  validHostReleaseReceipt} from './publication.generated.js';
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

// Structural Host replies bind connection and request identity without
// deciding Run admission, authorization, retry or state transitions.
const durability = value => value === 'volatile' || value === 'durable';
const positive = value => Number.isSafeInteger(value) && value > 0;
const profileLimits = ['maxReadWireBytes', 'maxRowWireBytes',
  'maxRowRetainedValueBytes', 'maxRetainedValueBytes', 'maxRows',
  'maxBatchRows', 'maxBatchRetainedValueBytes'];

export function validClientProfile(value, selected) {
  return validClientConnection(selected) &&
    exact(value, ['version', 'mode', 'owner', 'durability', 'scopeRef',
      'capabilities', 'limits']) &&
    value.version === 'actql-client-host/0.1' &&
    value.mode === selected.mode && value.owner === selected.owner &&
    durability(value.durability) &&
    !(selected.durability === 'durable' && value.durability !== 'durable') &&
    boundedText(value.scopeRef) &&
    Array.isArray(value.capabilities) &&
    value.capabilities.every(item => boundedText(item)) &&
    exact(value.limits, profileLimits) &&
    Object.values(value.limits).every(positive);
}

export function validClientAdmission(value, selected) {
  return validClientConnection(selected) &&
    exact(value, ['ref', 'durability', 'revision']) &&
    validRunRef(value.ref) && durability(value.durability) &&
    !(selected.durability === 'durable' && value.durability !== 'durable') &&
    Number.isSafeInteger(value.revision) && value.revision >= 0;
}

export function validRequestLookup(value, expectedRequestId) {
  if (!boundedText(expectedRequestId)) return false;
  if (exact(value, ['kind']) && value.kind === 'not_found') return true;
  if (exact(value, ['kind', 'reason']) && value.kind === 'unknown') {
    return boundedText(value.reason);
  }
  return exact(value, ['kind', 'requestId', 'ref', 'durability',
    'lookupExpiresAt']) && value.kind === 'found' &&
    value.requestId === expectedRequestId && validRunRef(value.ref) &&
    durability(value.durability) && boundedText(value.lookupExpiresAt);
}

// Generated guards validate the published shapes. These checks bind the
// requested identity and related owner-issued evidence across those shapes.
const shape = (value, required, optional = []) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  required.every(key => Object.hasOwn(value, key)) &&
  Object.keys(value).every(key => required.includes(key) ||
    optional.includes(key));

export function validDeliveryAttemptLookup(value, expected) {
  if (!shape(expected, ['attemptId', 'runDefinitionCid', 'resultName']) ||
      !boundedText(expected.attemptId) ||
      !cid.test(expected.runDefinitionCid) ||
      !boundedText(expected.resultName)) return false;
  if (exact(value, ['kind']) && value.kind === 'not_found') return true;
  if (!exact(value, ['kind', 'attempt', 'record',
    'hostReleaseReceipt']) || value.kind !== 'found' ||
    !validDeliveryAttempt(value.attempt) ||
    value.attempt.attempt_id !== expected.attemptId ||
    value.attempt.run_definition_cid !== expected.runDefinitionCid ||
    value.attempt.result_name !== expected.resultName) return false;
  const {attempt, record, hostReleaseReceipt: receipt} = value;
  if (record === null) return receipt === null;
  if (!validDeliveryRecord(record) ||
      record.delivery_attempt_cid !== attempt.delivery_attempt_cid ||
      record.sequence === 0 && Object.hasOwn(record, 'prior_record_cid') ||
      record.sequence > 0 && !Object.hasOwn(record, 'prior_record_cid') ||
      record.state !== 'succeeded' &&
        Object.hasOwn(record, 'result_delivery_receipt_cid')) {
    return false;
  }
  if (record.state !== 'succeeded') return receipt === null;
  if (!validHostReleaseReceipt(receipt) ||
      record.result_delivery_receipt_cid !==
        receipt.result_delivery_receipt_cid ||
      record.confirmed_byte_count !== receipt.delivered_byte_count ||
      record.delivered_sha256 !== receipt.delivered_sha256) return false;
  return ['run_definition_cid', 'result_manifest_cid', 'result_name',
    'result_artifact_cid', 'serialization_contract_cid']
    .every(key => attempt[key] === receipt[key]);
}
