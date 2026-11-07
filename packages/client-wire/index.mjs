export {checkReasonSchemaCid, checkOutcomeSchemaCid, checkOutcomeProtocol, runStateProtocol} from './client-host.generated.js';
export {validRunWaitContract} from './client-host.generated.js';
export * from './interactive-control.generated.js';
// Structural Client–Host wire admission only. The Host's MoonBit owners decide
// identities, authorization, state transitions, publication and retry.
import {validDeliveryAttempt, validDeliveryRecord,
  validHostReleaseReceipt} from './publication.generated.js';
import {clientHostOperations, clientHostRequestKeys, validClientRequestOptionalFields,
  validProfileContract, validAdmissionContract, validCancellationShape,
  validCancellationRefShape, validCancellationLookupShape, validCheckpointReviewShape,
  validCheckpointSummaryShape, validConnectionShape, validHeldContract,
  validRequestLookupContract,
  validRequestCancellationShape, validResultDescriptionShape, validResolveItemShape,
  validResolveResultShape, validResourceInspectionShape,
  validResourceListingShape, validResourcePeekShape,
  validRunRefShape, validRunStateShape, validCheckOutcomeContract,
  validSubmitPreparationErrorShape} from './client-host.generated.js';
import {validSubmissionEpochShape, validSubmissionRefShape,
  validSubmissionOutcomeShape, validSubmissionLookupShape, validSubmissionRestartShape} from './client-host.generated.js';
import {validOperationAttemptRefShape, validCancellationAttemptShape, validSubmissionAttemptShape} from './client-host.generated.js';
import {validSubmissionNameShape, validNamedSubmissionAttemptShape} from './client-host.generated.js';
import {validOwnerRefShape, validOwnerCursorShape, validOwnerObservationsShape} from './client-host.generated.js';
export {clientHostOperations} from './client-host.generated.js';
// Legacy JSON/YAML spellings remain accepted by the transport Client. The
// named spellings select the corresponding installed source frontend.
export const clientSourceFormats = Object.freeze([
  'json', 'yaml', 'aql-json', 'aql-yaml', 'aql', 'aql-text', 'sql',
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
  'ClientProgramRejected', 'ClientProgramUnsupported', 'ClientProgramAnalysisLimit',
  'ClientProgramImplementationLimit',
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

export function validSubmissionEpoch(value) {
  return validSubmissionEpochShape(value) &&
    !Object.is(value.notBefore, -0) && !Object.is(value.expiresAt, -0) &&
    value.expiresAt > value.notBefore;
}

export function validSubmissionRef(value) {
  return validSubmissionRefShape(value) && validSubmissionEpoch(value.epoch) &&
    value.nonce.isWellFormed() && value.nonce.normalize('NFC') === value.nonce &&
    !/[\u0080-\u009f]/u.test(value.nonce) &&
    new TextEncoder().encode(value.nonce).byteLength <= 256;
}

export function validSubmissionName(value) {
  return validSubmissionNameShape(value) && value.isWellFormed() &&
    value.normalize('NFC') === value && !/[\u0080-\u009f]/u.test(value) &&
    new TextEncoder().encode(value).byteLength <= 256;
}

export function sameSubmissionRef(left, right) {
  return validSubmissionRef(left) && validSubmissionRef(right) &&
    left.nonce === right.nonce && ['version', 'authorityScopeCid', 'epochNonce',
      'notBefore', 'expiresAt', 'authenticator'].every(key => left.epoch[key] === right.epoch[key]);
}

export function validSubmissionRestart(value, fresh) {
  return validSubmissionRestartShape(value) && validSubmissionRef(value.submissionRef) &&
    validSubmissionRef(fresh) &&
    value.submissionRef.epoch.authorityScopeCid === fresh.epoch.authorityScopeCid &&
    value.submissionRef.epoch.expiresAt < fresh.epoch.expiresAt;
}

function restartMatches(actual, expected) {
  if (actual === undefined || expected === undefined) return actual === expected;
  return actual.acknowledgement === expected.acknowledgement &&
    sameSubmissionRef(actual.submissionRef, expected.submissionRef);
}

function submissionFactsMatch(value, expected, intentCid) {
  if (!sameSubmissionRef(value.submissionRef, expected) ||
      intentCid !== undefined && value.intentCid !== intentCid ||
      value.unresolvedHistory !== undefined && !validSubmissionRestart(value.unresolvedHistory, expected)) return false;
  if (value.kind === 'ready') return value.admission.ref.authorityScopeCid === expected.epoch.authorityScopeCid;
  if (value.kind === 'held') return validHeldRequest(value.held, expected.nonce);
  return true;
}

// Durable journal facts have no negotiated transport connection. Their Run
// binding is checked by the journal; a received reply additionally needs the
// selected connection below.
export function validStoredSubmissionOutcome(value, expected, intentCid) {
  return validSubmissionOutcomeShape(value) && value.checkObservation === undefined && submissionFactsMatch(value, expected, intentCid) &&
    (value.kind !== 'ready' || value.admission.durability === 'durable');
}

export function validSubmissionOutcome(value, selected, expected, intentCid, unresolvedHistory) {
  return validSubmissionOutcomeShape(value) &&
    (value.checkObservation === undefined || validCheckOutcome(value.checkObservation)) &&
    (arguments.length < 5 || restartMatches(value.unresolvedHistory, unresolvedHistory)) &&
    submissionFactsMatch(value, expected, intentCid) &&
    (value.kind !== 'ready' || validClientAdmission(value.admission, selected)) &&
    (value.kind !== 'held' || validSubmitReply(value.held, selected, expected.nonce));
}

export function validSubmissionLookup(value, selected, expected) {
  return validSubmissionLookupShape(value) && submissionFactsMatch(value, expected) &&
    (value.kind !== 'ready' || validClientAdmission(value.admission, selected)) &&
    (value.kind !== 'held' || validSubmitReply(value.held, selected, expected.nonce));
}

export function validSubmissionAttempt(value, selected, expected, intentCid, attemptRef, unresolvedHistory) {
  if (!validSubmissionRef(expected) || !validOperationAttemptRef(attemptRef) ||
      attemptRef.operation !== 'submit' || !validSubmissionAttemptShape(value) ||
      !validOperationAttemptRef(value.attemptRef) || value.attemptRef.operation !== 'submit' ||
      value.attemptRef.attemptId !== attemptRef.attemptId) return false;
  if (value.kind === 'recorded' || value.kind === 'already_satisfied') {
    return validSubmissionOutcome(value.outcome, selected, expected, intentCid, unresolvedHistory) &&
      (value.kind !== 'already_satisfied' || value.outcome.kind !== 'preparing');
  }
  return value.kind === 'refused' && value.reason === 'authorization' ||
    sameSubmissionRef(value.submissionRef, expected) && value.intentCid === intentCid;
}

// A scoped name can resolve a reference issued under an earlier connection's
// epoch. This separate envelope never relaxes explicit-epoch correlation.
export function validNamedSubmissionAttempt(value, selected, name, candidate, intentCid, attemptRef) {
  if (!validClientConnection(selected) || !validSubmissionName(name) || !validSubmissionRef(candidate) ||
      !validOperationAttemptRef(attemptRef) || attemptRef.operation !== 'submit' ||
      !validNamedSubmissionAttemptShape(value) || value.requestName !== name ||
      value.intentCid !== intentCid || !validOperationAttemptRef(value.attemptRef) ||
      value.attemptRef.operation !== 'submit' || value.attemptRef.attemptId !== attemptRef.attemptId) return false;
  if (value.kind !== 'observed') return true;
  const original = value.outcome.submissionRef;
  return validSubmissionRef(original) &&
    original.epoch.authorityScopeCid === candidate.epoch.authorityScopeCid &&
    (value.outcome.kind === 'unresolvable'
      ? validSubmissionLookup(value.outcome, selected, original)
      : validSubmissionOutcome(value.outcome, selected, original, intentCid));
}

// This is one existing Engine-owned Run-state component. The public Client
// snapshot must also carry publication, cancellation and physical stop facts.
export function validRunState(value) {
  return validRunStateShape(value);
}

export const ownerObservationLimits = Object.freeze({maxEntries:1000,maxWireBytes:65536});
export const validOwnerRef = validOwnerRefShape;
export const validOwnerCursor = validOwnerCursorShape;
const ownerIdentity = owner => JSON.stringify([owner.kind,owner.scopeCid,owner.streamCid]);
export function validOwnerObservations(value, ref, limits = ownerObservationLimits) {
  if (!validRunRef(ref) || !Number.isSafeInteger(limits.maxEntries) || limits.maxEntries < 1 ||
      limits.maxEntries > ownerObservationLimits.maxEntries || !Number.isSafeInteger(limits.maxWireBytes) ||
      limits.maxWireBytes < 1024 || limits.maxWireBytes > ownerObservationLimits.maxWireBytes ||
      !withinResultDescriptionLimits(value,{maxWireBytes:limits.maxWireBytes,maxNodes:10000,maxDepth:64}) ||
      !validOwnerObservationsShape(value) ||
      !['namespaceId','authorityScopeCid','runDefinitionCid'].every(key => value.ref[key] === ref[key])) return false;
  if(value.unmatchedCursors !== undefined &&
      (new Set(value.unmatchedCursors.map(item=>item.index)).size !== value.unmatchedCursors.length ||
       limits.cursors !== undefined && value.unmatchedCursors.some(item=>item.index >= limits.cursors.length)))return false;
  const vectors = new Map();
  for (const vector of value.revisionVector) {
    const key = ownerIdentity(vector.owner);
    if (vectors.has(key)) return false;
    vectors.set(key,vector);
  }
  const seen = new Set();
  for (const view of value.owners) {
    if (view.kind === 'unavailable') continue;
    const key = ownerIdentity(view.ownerRef), vector = vectors.get(key);
    if (view.owner !== view.ownerRef.kind || seen.has(key) || vector === undefined ||
        Object.hasOwn(view,'snapshot') !== Object.hasOwn(vector,'snapshotCid')) return false;
    seen.add(key);
    const history = view.history;
    if (history.kind !== 'page') {
      if (Object.hasOwn(vector,'historyHead')) return false;
      continue;
    }
    if (!Object.hasOwn(vector,'historyHead') || history.entries.length > limits.maxEntries ||
        history.cursor !== undefined && ownerIdentity(history.cursor.owner) !== key) return false;
    const head = vector.historyHead;
    if (head === null) {
      if (history.entries.length || history.cursor !== undefined) return false;
      continue;
    }
    if (history.cursor === undefined) return false;
    for (let index=0;index<history.entries.length;index++) {
      const entry = history.entries[index], previous = history.entries[index-1];
      if (previous !== undefined && entry.revision !== previous.revision+1 ||
          entry.revision > head.revision || entry.revision === head.revision && entry.entryCid !== head.entryCid ||
          entry.revision === 1 && entry.entryCid !== head.generation) return false;
    }
  }
  return seen.size === vectors.size;
}

// The registered contract and generated validator enforce verdict/coverage
// consistency as well as shape, without enumerating reason codes.
export function validCheckOutcome(value) {
  return validCheckOutcomeContract(value);
}

export function validSubmitPreparationError(value) {
  return validSubmitPreparationErrorShape(value);
}

export const validClientConnection = validConnectionShape;

// A target assertion is separate from authorization. The second argument must
// come from the Host's authenticated/installed Workspace binding, never from
// a caller's connection or Run reference. No assertion preserves the existing
// endpoint contract; a Host with no binding cannot accept an asserted target.
export const clientWorkspaceMatches = (connection, authenticatedWorkspaceId) =>
  connection.workspaceId === undefined ||
  boundedText(authenticatedWorkspaceId) &&
    connection.workspaceId === authenticatedWorkspaceId;

// Native brands are captured once; inspecting a caller's prototype or
// Symbol.toStringTag would add observable getters/Proxy traps to the snapshot.
const snapshotStringValueOf = String.prototype.valueOf;
const snapshotRawJSONBrand = JSON.isRawJSON;

// Client requests observe the JSON value actually submitted at this boundary.
// Preserve ordinary JSON serialization, but never replace source numbers.
function snapshotRequest(value, numberError, observe) {
  let units = 0, reserved = 0, values = 0, reservedValues = 0;
  const document = JSON.stringify(value, (key, item) => {
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
      throw new TypeError(numberError);
    }
    let selected = boxed ? number : item;
    let rawUnits = 0;
    if (observe !== undefined && !boxed && item !== null && typeof item === 'object') {
      let stringObject = false;
      try {snapshotStringValueOf.call(item);stringObject = true;}
      catch { /* Ordinary objects retain their native serialization. */ }
      // JSON performs ToString with the string hint for actual String boxes.
      // Return that primitive so native serialization cannot coerce it again.
      if (stringObject) selected = `${item}`;
      else if (typeof snapshotRawJSONBrand === 'function' && snapshotRawJSONBrand(item)) {
        // The native brand excludes copied objects and Proxies. Its original
        // frozen rawJSON field is DATA, not another caller property getter.
        rawUnits = item.rawJSON.length;
      }
    }
    if (observe !== undefined) {
      // Observe the SAME native traversal after its existing numeric rule.
      // Reading primitive String lengths does not repeat a getter/toJSON,
      // enumerate a Proxy or coerce a boxed Number again. Geometric growth
      // avoids a Resource/current callback for every field or array item.
      units += 1 + key.length + rawUnits + (typeof selected === 'string' ? selected.length : 0);
      values++;
      if (!Number.isSafeInteger(units) || !Number.isSafeInteger(values)) {
        throw new RangeError('ClientSnapshotSizeOverflow');
      }
      if (units > reserved || values > reservedValues) {
        const nextValues = values > reservedValues ? Math.max(values, reservedValues * 2) : reservedValues;
        const next = Math.max(nextValues, units > reserved ? Math.max(units, reserved * 2) : reserved);
        if (!Number.isSafeInteger(next) || !Number.isSafeInteger(nextValues)) {
          throw new RangeError('ClientSnapshotSizeOverflow');
        }
        observe(next, undefined, nextValues);
        reserved = next;reservedValues = nextValues;
      }
    }
    return selected;
  });
  if (observe !== undefined) observe(reserved, document, reservedValues);
  return JSON.parse(document);
}

// One serialization owner for check and submit. Preserve the existing check
// helper's error spelling for direct consumers. SDK callers map local refusal.
export const snapshotClientRequest = (value, observe) =>
  snapshotRequest(value, 'UnrepresentableClientNumber', observe);
export const snapshotCheckRequest = value =>
  snapshotRequest(value, 'UnrepresentableCheckNumber');

// Synchronous Host ingress preparation. Capture the original Workspace target
// before serialization or an awaited authentication/authorization boundary.
// Authentication, authorization and transport-specific reading stay outside.
function freezeCapturedRequest(value) {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freezeCapturedRequest(child);
    Object.freeze(value);
  }
  return value;
}

export function prepareClientHostRequest(operation, original, retainSnapshot = false) {
  if (!validClientBody(operation, original)) return undefined;
  const suppliedConnection = original.connection;
  const connection = Object.freeze({...suppliedConnection,
    consentRefs: Object.freeze([...suppliedConnection.consentRefs]),
    runners: Object.freeze([...suppliedConnection.runners])});
  if (!validClientConnection(connection)) return undefined;
  let body = original, snapshotted = false;
  if (operation === 'check') {
    // Observe the original serializer once, before spreading can erase it.
    try { body = snapshotCheckRequest(body); }
    catch { return undefined; }
    if (!validClientBody(operation, body)) return undefined;
    snapshotted = true;
  }
  // A serializer cannot remove or replace the captured Workspace assertion.
  body = {...body, connection};
  if (['submit-intent', 'submit-named-intent', 'restart-intent', 'lookup-submission', 'owner-observations', 'plan', 'inspect-run', 'run-plan'].includes(operation)) {
    try { body = snapshotClientRequest(body); }
    catch { return undefined; }
    if (!validClientBody(operation, body)) return undefined;
    snapshotted = true;
  }
  if (retainSnapshot === true) {
    if (!snapshotted) {
      try { body = snapshotClientRequest(body); }
      catch { return undefined; }
      if (!validClientBody(operation, body)) return undefined;
    }
    // Both are Owner-captured values. Retain the original Workspace target,
    // not a second representation of its identical immutable connection.
    body.connection = connection;
    freezeCapturedRequest(body);
  }
  return Object.freeze({body, connection});
}

// Program size belongs to the selected Host preparation owner, whose one
// snapshot observer reserves actual demand. This closed envelope does not add
// an independent UTF-16 support ceiling or relax transport ingress policy.
function validProgramInput(body) {
  return (body.kind === 'aql' &&
    (exact(body.input, ['text', 'format']) ||
      exact(body.input, ['text', 'format', 'parameterDeclarations'])) &&
    typeof body.input.text === 'string' &&
    body.input.text.length > 0 &&
    !body.input.text.includes('\u0000') &&
    clientSourceFormats.includes(body.input.format) &&
    (body.input.parameterDeclarations === undefined ||
      ['aql', 'aql-text', 'sql'].includes(body.input.format) &&
      body.input.parameterDeclarations !== null &&
      typeof body.input.parameterDeclarations === 'object' &&
      !Array.isArray(body.input.parameterDeclarations)) ||
    body.kind === 'program' && body.input !== null &&
    typeof body.input === 'object' && !Array.isArray(body.input));
}

export function validClientBody(operation, body) {
  const bodyKeys = clientHostRequestKeys(operation, body);
  // Template requests contain no submitted bindings. The scope is selected
  // before input admission; even null or an empty binding object is refused.
  const selectedKeys = operation === 'check' && body?.scope === 'template_only'
    ? bodyKeys?.filter(key => key !== 'parameters') : bodyKeys;
  if (selectedKeys === undefined || !exact(body, selectedKeys) ||
      !validClientConnection(body.connection) ||
      !validClientRequestOptionalFields(operation, body)) return false;
  if (operation === 'connect') return true;
  if (operation === 'submit-intent' || operation === 'submit-named-intent' || operation === 'restart-intent') {
    if (!validSubmissionRef(body.submissionRef) || !cid.test(body.intentCid) ||
        !validOperationAttemptRef(body.attemptRef) || body.attemptRef.operation !== 'submit') return false;
    if (operation === 'restart-intent' && !validSubmissionRestart(body.unresolvedHistory, body.submissionRef)) return false;
    if (operation === 'submit-named-intent' && !validSubmissionName(body.requestName)) return false;
    return validClientBody('submit', {connection: body.connection,
      requestId: body.submissionRef.nonce, kind: body.kind,
      input: body.input, parameters: body.parameters,
      ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: body.stopBefore} : {}),
      ...(Object.hasOwn(body, 'readOnly') ? {readOnly: body.readOnly} : {})}) &&
      (body.parameters === null || typeof body.parameters === 'object' &&
        !Array.isArray(body.parameters));
  }
  if (operation === 'lookup-submission') return validSubmissionRef(body.submissionRef);
  if (operation === 'inspect-run' || operation === 'run-plan') {
    return validRunRef(body.ref) &&
      Number.isSafeInteger(body.maxWireBytes) && body.maxWireBytes >= 1024 && body.maxWireBytes <= 65536 &&
      Number.isSafeInteger(body.maxNodes) && body.maxNodes > 0 && body.maxNodes <= 10000 &&
      Number.isSafeInteger(body.maxDepth) && body.maxDepth > 0 && body.maxDepth <= 64;
  }
  if (operation === 'plan') {
    return validProgramInput(body) &&
      (body.parameters === null || typeof body.parameters === 'object' &&
        !Array.isArray(body.parameters)) &&
      Number.isSafeInteger(body.maxWireBytes) && body.maxWireBytes > 0 && body.maxWireBytes <= 65536 &&
      Number.isSafeInteger(body.maxNodes) && body.maxNodes > 0 && body.maxNodes <= 10000 &&
      Number.isSafeInteger(body.maxDepth) && body.maxDepth > 0 && body.maxDepth <= 64;
  }
  if (operation === 'submit') {
    return boundedText(body.requestId) && validProgramInput(body);
  }
  // This validates the closed request envelope only. Program/language meaning
  // belongs to the same common checker selected by the Host.
  if (operation === 'check') {
    if (!['template_only', 'bound_input'].includes(body.scope) ||
        !['text', 'program'].includes(body.kind) ||
        body.scope === 'bound_input' && !(body.parameters === null ||
          body.parameters !== null && typeof body.parameters === 'object' &&
          !Array.isArray(body.parameters))) return false;
    if (body.kind === 'program') return body.input !== null &&
      typeof body.input === 'object' && !Array.isArray(body.input);
    return (exact(body.input, ['text', 'format']) ||
        exact(body.input, ['text', 'format', 'parameterDeclarations'])) &&
      typeof body.input.text === 'string' &&
      body.input.text.length > 0 &&
      body.input.text.isWellFormed() &&
      !body.input.text.includes('\u0000') &&
      ['aql', 'aql-text', 'sql'].includes(body.input.format) &&
      (body.input.parameterDeclarations === undefined ||
        body.input.parameterDeclarations !== null &&
        typeof body.input.parameterDeclarations === 'object' &&
        !Array.isArray(body.input.parameterDeclarations));
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
  if (operation === 'owner-observations') return Array.isArray(body.cursors) && body.cursors.length <= 5 &&
    body.cursors.every(validOwnerCursor) &&
    new Set(body.cursors.map(cursor => ownerIdentity(cursor.owner))).size === body.cursors.length &&
    Number.isSafeInteger(body.maxEntries) && body.maxEntries > 0 && body.maxEntries <= ownerObservationLimits.maxEntries &&
    Number.isSafeInteger(body.maxWireBytes) && body.maxWireBytes >= 1024 && body.maxWireBytes <= ownerObservationLimits.maxWireBytes;
  if (operation === 'cancel' || operation === 'lookup-cancellation') {
    if (operation === 'cancel' && (!validOperationAttemptRef(body.attemptRef) ||
        body.attemptRef.operation !== 'cancel')) return false;
    return validCancellationRef({...body.ref, cancelId: body.cancelId,
      expectedRevision: body.expectedRevision});
  }
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
  if (operation === 'wait') return (body.until === null || boundedText(body.until, 128)) &&
    (body.since === null || Number.isSafeInteger(body.since) && body.since >= 0);
  return true;
}

// Structural Host replies bind connection and request identity without
// deciding Run admission, authorization, retry or state transitions.
export const validClientProfile = (value, selected) => validProfileContract(value, selected) &&
  (value.submissionEpoch === undefined || validSubmissionEpoch(value.submissionEpoch));
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

// Exact pending-ID metadata only; it issues no approval or completion fact.
export function validCheckpointLookup(value, checkpointId) {
  return clientHostRequestKeys('checkpoints', {checkpointId}).includes('checkpointId') &&
    validClientRequestOptionalFields('checkpoints', {checkpointId}) &&
    validCheckpointPage(value, 1) && !Object.hasOwn(value, 'next') &&
    value.items.every(item => item.checkpointId === checkpointId);
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

export const validCancellationRef = value => validCancellationRefShape(value) &&
  value.namespaceId.isWellFormed() && value.cancelId.isWellFormed();
const sameRunRef = (left, right) => ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
  .every(key => left[key] === right[key]);
const sameCancellationRef = (left, right) => sameRunRef(left, right) &&
  left.cancelId === right.cancelId && left.expectedRevision === right.expectedRevision;
export const validCancellation = (value, expected) => validCancellationShape(value) &&
  validCancellationRef(value.cancelRef) && sameRunRef(value.ref, value.cancelRef) &&
  value.revision >= value.cancelRef.expectedRevision &&
  (value.kind !== 'accepted' || value.revision > value.cancelRef.expectedRevision) &&
  (expected === undefined || validCancellationRef(expected) &&
    sameCancellationRef(value.cancelRef, expected));
export function validCancellationLookup(value, expected) {
  return validCancellationRef(expected) && validCancellationLookupShape(value) &&
    (value.kind === 'found' ? validCancellation(value.cancellation, expected) :
      validCancellationRef(value.cancelRef) && sameCancellationRef(value.cancelRef, expected));
}

export const validOperationAttemptRef = value => validOperationAttemptRefShape(value) &&
  value.attemptId.isWellFormed();
export function validCancellationAttempt(value, expected, attemptRef) {
  if (!validCancellationRef(expected) || !validOperationAttemptRef(attemptRef) ||
      attemptRef.operation !== 'cancel' || !validCancellationAttemptShape(value) ||
      !validOperationAttemptRef(value.attemptRef) ||
      value.attemptRef.operation !== attemptRef.operation ||
      value.attemptRef.attemptId !== attemptRef.attemptId) return false;
  if (value.kind === 'accepted' || value.kind === 'already_satisfied') {
    return validCancellation(value.cancellation, expected) &&
      (value.kind === 'accepted' ? value.cancellation.kind === 'accepted'
        : ['already_requested', 'already_terminal'].includes(value.cancellation.kind));
  }
  return value.cancelRef === undefined || validCancellationRef(value.cancelRef) &&
    sameCancellationRef(value.cancelRef, expected);
}

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
