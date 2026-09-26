// Structural Client–Host wire admission only. The Host's MoonBit owners decide
// identities, authorization, state transitions, publication and retry.
import {validDeliveryAttempt, validDeliveryRecord,
  validHostReleaseReceipt} from './publication.generated.js';
import {clientHostOperations, clientHostRequestKeys,
  validAdmissionShape, validConnectionShape, validLookupFoundShape,
  validLookupNotFoundShape, validLookupUnknownShape, validProfileShape,
  validRunRefShape, validRunStateShape, validCancellationShape,
  validSubmitPreparationErrorShape} from './client-host.generated.js';
export {clientHostOperations} from './client-host.generated.js';
const cid = /^sha256:[0-9a-f]{64}$/u;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
  [...keys].sort().join('\0');
const boundedText = (value, maximum = 256) => typeof value === 'string' &&
  value.length > 0 && value.length <= maximum &&
  !/[\u0000-\u001f\u007f]/u.test(value);
export function validRunRef(value) {
  return validRunRefShape(value);
}

// This is one existing Engine-owned Run-state component. The public Client
// snapshot must also carry publication, cancellation and physical stop facts.
export function validRunState(value) {
  return validRunStateShape(value);
}

export function validSubmitPreparationError(value) {
  return validSubmitPreparationErrorShape(value);
}

export function validClientConnection(value) {
  if (!validConnectionShape(value) ||
      !(value.mode === 'remote' && value.owner === 'remote' ||
        value.mode === 'local' && value.owner === 'local' ||
        value.mode === 'hybrid' && ['local', 'cloud'].includes(value.owner))) return false;
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
  const bodyKeys = clientHostRequestKeys(operation);
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
export function validClientProfile(value, selected) {
  return validClientConnection(selected) &&
    validProfileShape(value) &&
    value.mode === selected.mode && value.owner === selected.owner &&
    !(selected.durability === 'durable' && value.durability !== 'durable');
}

export function validClientAdmission(value, selected) {
  return validClientConnection(selected) &&
    validAdmissionShape(value) &&
    !(selected.durability === 'durable' && value.durability !== 'durable');
}

export function validRequestLookup(value, expectedRequestId) {
  if (!boundedText(expectedRequestId)) return false;
  if (validLookupNotFoundShape(value) || validLookupUnknownShape(value)) {
    return true;
  }
  return validLookupFoundShape(value) &&
    value.requestId === expectedRequestId;
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

export const validCancellation = value => validCancellationShape(value);
