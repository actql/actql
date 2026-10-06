export {checkReasonSchemaCid, checkOutcomeSchemaCid, checkOutcomeProtocol} from './client-host.generated.js';
// Structural Client–Host wire admission only. The Host's MoonBit owners decide
// identities, authorization, state transitions, publication and retry.
import {validDeliveryAttempt, validDeliveryRecord,
  validHostReleaseReceipt} from './publication.generated.js';
import {clientHostOperations, clientHostRequestKeys,
  validProfileContract, validAdmissionContract, validCancellationShape, validCheckpointReviewShape,
  validCheckpointSummaryShape, validConnectionShape, validHeldContract,
  validRequestLookupContract,
  validRequestCancellationShape, validResultDescriptionShape, validResolveItemShape,
  validResolveResultShape, validResourceInspectionShape,
  validResourceListingShape, validResourcePeekShape,
  validRunRefShape, validRunStateShape, validCheckOutcomeShape,
  validSubmitPreparationErrorShape} from './client-host.generated.js';
export {clientHostOperations} from './client-host.generated.js';
// Legacy JSON/YAML spellings remain accepted by the transport Client. The
// named spellings select the corresponding installed source frontend.
export const clientSourceFormats = Object.freeze([
  'json', 'yaml', 'aql-json', 'aql-yaml', 'aql-text', 'sql',
]);
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

// Whole response limits, including the envelope and nested type descriptors.
// These are UTF-8 JSON wire bytes and structural budgets, not payload limits.
export const resultDescriptionLimits = Object.freeze({
  maxWireBytes: 1024 * 1024, maxNodes: 10000, maxDepth: 64,
});
export function withinResultDescriptionLimits(value,
  limits = resultDescriptionLimits) {
  if (!Object.keys(resultDescriptionLimits).every(key =>
    Number.isSafeInteger(limits?.[key]) && limits[key] > 0 &&
    limits[key] <= resultDescriptionLimits[key])) return false;
  let nodes = 0;
  const seen = new Set();
  const work = [[value, 1]];
  while (work.length) {
    const [item, depth] = work.pop();
    if (++nodes > limits.maxNodes || depth > limits.maxDepth) return false;
    if (item !== null && typeof item === 'object') {
      if (seen.has(item)) return false;
      seen.add(item);
      const entries = Object.entries(item);
      // Object keys also occupy nodes in the canonical wire budget.
      if (!Array.isArray(item)) nodes += entries.length;
      if (nodes + work.length + entries.length > limits.maxNodes) return false;
      for (const [, child] of entries) work.push([child, depth + 1]);
    }
  }
  try {
    return new TextEncoder().encode(JSON.stringify(value)).byteLength <=
      limits.maxWireBytes;
  } catch { return false; }
}
export function validResultDescription(value, expected,
  limits = resultDescriptionLimits) {
  if (!withinResultDescriptionLimits(value, limits) ||
      !validResultDescriptionShape(value) || !validRunRef(expected?.ref) ||
      !['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].every(key =>
        value.ref[key] === expected.ref[key]) ||
      value.resultName !== expected.resultName ||
      value.serialization.format !== expected.format ||
      value.serialization.version !== `actql-${expected.format}/0.1` ||
      new Set(value.columns.map(column => column.name)).size !==
        value.columns.length) return false;
  return true;
}

// These are the installed submit boundary's explicit refusal contracts:
// request validation, preparation, connection policy and admission checks.
// A technical delegation failure is here only when the installed Host stops
// before creating a Run; inside a Run it is an observed Run outcome instead.
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
  'ACTQL_E_ACCOUNT_CONFIG_INVALID',
  'ACTQL_E_DELEGATION_REJECTED',
  'ACTQL_E_DELEGATION_UNAVAILABLE',
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

// The registered contract and generated validator enforce verdict/coverage
// consistency as well as shape, without enumerating reason codes.
export function validCheckOutcome(value) {
  if (!validCheckOutcomeShape(value)) return false;
  const report = value.report ?? value.partial_report;
  if (!report) return true;
  const documents = new Map(report.inputs.map(input => [input.document_id, input]));
  if (documents.size !== report.inputs.length || documents.get('source')?.kind !== 'text' ||
      report.inputs.some(input => input.document_id !== 'source' && input.kind !== 'structured')) return false;
  for (const reason of [...report.reasons, ...(report.requirements ?? [])]) {
    const location = reason.location;
    if (!location) continue;
    const input = documents.get(location.document_id);
    if (!input || input.revision !== location.revision || input.kind !== location.kind) return false;
    if (location.kind === 'text' && (location.start_byte > location.end_byte ||
        location.end_byte > input.byte_length)) return false;
  }
  return true;
}

export function validSubmitPreparationError(value) {
  return validSubmitPreparationErrorShape(value);
}

export const validClientConnection = validConnectionShape;

// A check observes the JSON value actually submitted at this boundary.
// Preserve ordinary JSON serialization, but never replace source numbers.
export function snapshotCheckRequest(value) {
  return JSON.parse(JSON.stringify(value, (_key, item) => {
    let number = item, boxed = false;
    if (item !== null && typeof item === 'object') {
      // Brand-check without invoking user coercion, including across realms.
      try { Number.prototype.valueOf.call(item); boxed = true; }
      catch { /* Ordinary objects retain their JSON serialization. */ }
    }
    // JSON unwraps Number objects with ToNumber, including custom coercion.
    // Return that primitive so serialization cannot coerce it again unchecked.
    if (boxed) number = +item;
    if (typeof number === 'number' &&
        (!Number.isFinite(number) || Object.is(number, -0))) {
      throw new TypeError('UnrepresentableCheckNumber');
    }
    return boxed ? number : item;
  }));
}

export function validClientBody(operation, body) {
  const bodyKeys = clientHostRequestKeys(operation);
  if (bodyKeys === undefined || !exact(body, bodyKeys) ||
      !validClientConnection(body.connection)) return false;
  if (operation === 'connect') return true;
  if (operation === 'submit') {
    return boundedText(body.requestId) &&
      (body.kind === 'aql' &&
        (exact(body.input, ['text', 'format']) ||
          exact(body.input, ['text', 'format', 'parameterDeclarations'])) &&
        typeof body.input.text === 'string' &&
        body.input.text.length > 0 && body.input.text.length <= 65536 &&
        !body.input.text.includes('\u0000') &&
        clientSourceFormats.includes(body.input.format) &&
        (body.input.parameterDeclarations === undefined ||
          ['aql-text', 'sql'].includes(body.input.format) &&
          body.input.parameterDeclarations !== null &&
          typeof body.input.parameterDeclarations === 'object' &&
          !Array.isArray(body.input.parameterDeclarations)) ||
        body.kind === 'program' && body.input !== null &&
        typeof body.input === 'object' && !Array.isArray(body.input));
  }
  // Checking reads authored source only; Program documents are not checked
  // through this operation.
  if (operation === 'check') {
    return (exact(body.input, ['text', 'format']) ||
        exact(body.input, ['text', 'format', 'parameterDeclarations'])) &&
      typeof body.input.text === 'string' &&
      body.input.text.length > 0 && body.input.text.length <= 65536 &&
      body.input.text.isWellFormed() &&
      !body.input.text.includes('\u0000') &&
      ['aql-text', 'sql'].includes(body.input.format) &&
      (body.input.parameterDeclarations === undefined ||
        body.input.parameterDeclarations !== null &&
        typeof body.input.parameterDeclarations === 'object' &&
        !Array.isArray(body.input.parameterDeclarations)) &&
      (body.parameters === null || typeof body.parameters === 'object' &&
        !Array.isArray(body.parameters));
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
  if (operation === 'result-describe') return boundedText(body.resultName) &&
    boundedText(body.attemptId) && ['json', 'jsonl', 'csv'].includes(body.format) &&
    Object.keys(resultDescriptionLimits).every(key =>
      Number.isSafeInteger(body[key]) && body[key] > 0 &&
      body[key] <= resultDescriptionLimits[key]);
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
export const validClientProfile = validProfileContract;
export const validClientAdmission = validAdmissionContract;

// A request the Host holds before any Run exists: waiting on a
// `prepare_attempt` Checkpoint, resuming after an approval, or ended without
// a Run. Once the Run exists the lookup is `found` with its RunRef.
export const validHeldRequest = validHeldContract;
export const validRequestLookup = validRequestLookupContract;

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
