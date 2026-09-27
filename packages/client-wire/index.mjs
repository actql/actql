// Structural Client–Host wire admission only. The Host's MoonBit owners decide
// identities, authorization, state transitions, publication and retry.
import {validDeliveryAttempt, validDeliveryRecord,
  validHostReleaseReceipt} from './publication.generated.js';
import {clientHostOperations, clientHostRequestKeys,
  validAdmissionShape, validCancellationShape, validCheckpointReviewShape,
  validCheckpointSummaryShape, validConnectionShape, validHeldShape,
  validLookupFoundShape, validLookupNotFoundShape, validLookupUnknownShape,
  validProfileShape, validRequestCancellationShape, validResolveItemShape,
  validResolveResultShape, validResourceInspectionShape,
  validResourceListingShape, validResourcePeekShape,
  validRunRefShape, validRunStateShape,
  validSubmitPreparationErrorShape} from './client-host.generated.js';
export {clientHostOperations} from './client-host.generated.js';
const cid = /^sha256:[0-9a-f]{64}$/u;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
  [...keys].sort().join('\0');
// Bounds of the Checkpoint operations. A Host may apply tighter ones.
export const checkpointLimits = Object.freeze({
  maxPageItems: 100,
  maxCursorLength: 512,
  maxReviewBytes: 1024 * 1024,
  maxResolveItems: 16,
});
// Bounds of the Resource discovery operations. A Host may apply tighter ones.
export const resourceLimits = Object.freeze({
  maxQueryLength: 255,
  maxListItems: 1000,
  maxInspectBytes: 1024 * 1024,
  maxPeekFields: 100,
  maxPeekRows: 200,
  maxPeekBytes: 4 * 1024 * 1024,
});
const boundedText = (value, maximum = 256) => typeof value === 'string' &&
  value.length > 0 && value.length <= maximum &&
  !/[\u0000-\u001f\u007f]/u.test(value);

// These are the installed submit boundary's explicit refusal contracts:
// request validation, preparation, connection policy and admission checks.
// A public-looking code, exception class, or an arbitrary 4xx response is not
// evidence of refusal. In particular, journal and start uncertainty are absent.
const submitRejections = new Set([
  'InvalidClientRequest', 'ClientRequestTooLarge',
  'ClientProgramInvalidInput', 'ClientParametersInvalid',
  'ClientParametersTooLarge', 'ClientProgramNeedsInputs',
  'ClientProgramRejected', 'ClientProgramUnsupported',
  'ClientAuthenticationDenied', 'ClientConnectionDenied',
  'ClientRunStartDenied', 'ClientRequestIntentConflict',
  'ACTQL_E_ACCOUNT_DENIED', 'ACTQL_E_ACCOUNT_NO_MATCH',
  'ACTQL_E_DELEGATION_REJECTED',
]);
export function isClientSubmitRejection(code) {
  return submitRejections.has(code);
}
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
  if (operation === 'lookup-request' || operation === 'cancel-request') {
    return boundedText(body.requestId);
  }
  if (operation === 'resources') {
    return boundedText(body.resourceConnection) &&
      typeof body.query === 'string' &&
      body.query.length <= resourceLimits.maxQueryLength &&
      !/[\u0000-\u001f\u007f]/u.test(body.query) &&
      Number.isSafeInteger(body.limit) && body.limit > 0 &&
      body.limit <= resourceLimits.maxListItems;
  }
  if (operation === 'resource-inspect') {
    return boundedText(body.resourceConnection) && boundedText(body.resource) &&
      Number.isSafeInteger(body.maxBytes) && body.maxBytes > 0 &&
      body.maxBytes <= resourceLimits.maxInspectBytes;
  }
  if (operation === 'resource-peek') {
    return boundedText(body.resourceConnection) && boundedText(body.resource) &&
      Array.isArray(body.fields) && body.fields.length > 0 &&
      body.fields.length <= resourceLimits.maxPeekFields &&
      body.fields.every(field => boundedText(field)) &&
      new Set(body.fields).size === body.fields.length &&
      Number.isSafeInteger(body.maxRows) && body.maxRows > 0 &&
      body.maxRows <= resourceLimits.maxPeekRows &&
      Number.isSafeInteger(body.maxBytes) && body.maxBytes > 0 &&
      body.maxBytes <= resourceLimits.maxPeekBytes;
  }
  if (operation === 'checkpoints') {
    return Number.isSafeInteger(body.limit) && body.limit > 0 &&
      body.limit <= checkpointLimits.maxPageItems &&
      (body.after === '' ||
        boundedText(body.after, checkpointLimits.maxCursorLength));
  }
  if (operation === 'checkpoint-review') {
    return typeof body.checkpointCid === 'string' &&
      cid.test(body.checkpointCid) &&
      Number.isSafeInteger(body.maxBytes) && body.maxBytes > 0 &&
      body.maxBytes <= checkpointLimits.maxReviewBytes;
  }
  if (operation === 'resolve') {
    return Array.isArray(body.items) && body.items.length > 0 &&
      body.items.length <= checkpointLimits.maxResolveItems &&
      body.items.every(validResolveItemShape) &&
      new Set(body.items.map(item => item.checkpointCid)).size ===
        body.items.length;
  }
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

// A request the Host holds before any Run exists: waiting on a
// `prepare_attempt` Checkpoint, resuming after an approval, or ended without
// a Run. Once the Run exists the lookup is `found` with its RunRef.
export function validHeldRequest(value, expectedRequestId) {
  if (!boundedText(expectedRequestId) || !validHeldShape(value) ||
      value.requestId !== expectedRequestId) return false;
  if (value.state === 'waiting_checkpoint') {
    return value.checkpoint !== undefined &&
      value.endReason === undefined && value.terminalErrorCode === undefined;
  }
  if (value.state === 'resuming') {
    return value.endReason === undefined &&
      value.terminalErrorCode === undefined;
  }
  return value.endReason !== undefined;
}

export function validRequestLookup(value, expectedRequestId) {
  if (!boundedText(expectedRequestId)) return false;
  if (validLookupNotFoundShape(value) || validLookupUnknownShape(value)) {
    return true;
  }
  if (value?.kind === 'held') {
    return validHeldRequest(value, expectedRequestId);
  }
  return validLookupFoundShape(value) &&
    value.requestId === expectedRequestId;
}

// A submit reply: the admitted Run, or the held request (no Run yet).
export function validSubmitReply(value, selected, expectedRequestId) {
  if (value?.kind === 'held') {
    return validClientConnection(selected) &&
      validHeldRequest(value, expectedRequestId);
  }
  return validClientAdmission(value, selected);
}

// One authorized page of waiting Checkpoints (safe metadata only).
export function validCheckpointPage(value, limit) {
  if (!Number.isSafeInteger(limit) || limit < 1 ||
      limit > checkpointLimits.maxPageItems ||
      !shape(value, ['items'], ['next']) || !Array.isArray(value.items) ||
      value.items.length > limit ||
      !value.items.every(validCheckpointSummaryShape) ||
      new Set(value.items.map(item => item.checkpointCid)).size !==
        value.items.length) return false;
  return value.next === undefined ||
    boundedText(value.next, checkpointLimits.maxCursorLength);
}

// The exact review projection a Checkpoint names, within the requested
// bound. The caller still checks the decoded bytes against `artifactCid`.
export function validCheckpointReview(value, expected) {
  if (!shape(expected, ['checkpointCid', 'maxBytes']) ||
      !validCheckpointReviewShape(value) ||
      value.checkpointCid !== expected.checkpointCid ||
      value.byteLength > expected.maxBytes) return false;
  const padding = value.contentBase64.endsWith('==') ? 2
    : value.contentBase64.endsWith('=') ? 1 : 0;
  return value.contentBase64.length % 4 === 0 &&
    value.contentBase64.length / 4 * 3 - padding === value.byteLength;
}

export function validResolveItem(value) {
  return validResolveItemShape(value);
}

// Per-item answers, in request order, one per submitted Checkpoint.
export function validResolveResults(value, items) {
  if (!Array.isArray(items) || !exact(value, ['results']) ||
      !Array.isArray(value.results) ||
      value.results.length !== items.length) return false;
  return value.results.every((result, index) =>
    validResolveResultShape(result) &&
    result.checkpointCid === items[index].checkpointCid &&
    (['committed', 'duplicate'].includes(result.status)
      ? result.decision !== undefined && result.resolutionCid !== undefined
      : result.reason !== undefined));
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

// The reply to a request cancellation. `accepted` means the cancellation is
// durable, not that anything stopped or was cleaned up. A reply for a
// request whose Run exists names that Run.
export function validRequestCancellation(value, expectedRequestId) {
  return boundedText(expectedRequestId) &&
    validRequestCancellationShape(value) &&
    value.requestId === expectedRequestId &&
    (value.ref === undefined) === (value.revision === undefined);
}

const utf8Bytes = text => new TextEncoder().encode(text).length;
const jsonObject = text => {
  try {
    const value = JSON.parse(text);
    return value !== null && typeof value === 'object' &&
      !Array.isArray(value) ? value : undefined;
  } catch { return undefined; }
};

// One page of Resource names answering the exact request. Names are unique.
export function validResourceListing(value, expected) {
  if (!shape(expected, ['resourceConnection', 'limit']) ||
      !validResourceListingShape(value) ||
      value.resourceConnection !== expected.resourceConnection ||
      value.resources.length > expected.limit) return false;
  return new Set(value.resources.map(item => item.name)).size ===
    value.resources.length;
}

// A ready inspection carries only its bounded summary object; a Resource
// that needs Catalog evidence carries only the reason.
export function validResourceInspection(value, expected) {
  if (!shape(expected, ['resourceConnection', 'resource', 'maxBytes']) ||
      !validResourceInspectionShape(value) ||
      value.resourceConnection !== expected.resourceConnection ||
      value.resource !== expected.resource) return false;
  if (value.status === 'ready') {
    return value.reason === undefined && value.summaryJson !== undefined &&
      utf8Bytes(value.summaryJson) <= expected.maxBytes &&
      jsonObject(value.summaryJson) !== undefined;
  }
  return value.summaryJson === undefined && value.reason !== undefined;
}

// A bounded preview: at most the requested rows, each with exactly the
// requested fields and scalar JSON values. `limited` marks a prefix.
export function validResourcePeek(value, expected) {
  if (!shape(expected, ['resourceConnection', 'resource', 'fields',
        'maxRows', 'maxBytes']) ||
      !validResourcePeekShape(value) ||
      value.resourceConnection !== expected.resourceConnection ||
      value.resource !== expected.resource ||
      value.fields.length !== expected.fields.length ||
      value.fields.some((field, index) => field !== expected.fields[index]) ||
      utf8Bytes(value.rowsJson) > expected.maxBytes) return false;
  let rows;
  try { rows = JSON.parse(value.rowsJson); } catch { return false; }
  const keys = [...value.fields].sort().join('\0');
  return Array.isArray(rows) && rows.length <= expected.maxRows &&
    (value.limited || rows.length < expected.maxRows) &&
    rows.every(row => row !== null && typeof row === 'object' &&
      !Array.isArray(row) && Object.keys(row).sort().join('\0') === keys &&
      Object.values(row).every(cell => cell === null ||
        ['string', 'boolean'].includes(typeof cell) ||
        typeof cell === 'number' && Number.isFinite(cell)));
}
