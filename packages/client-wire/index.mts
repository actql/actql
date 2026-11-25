import {validWireSampleSelectorShape, validWireControlCommandShape, validWireControlOperationRefShape,
  validWireControlOperationLookupShape} from './interactive-control.generated.js';
import type {WireControlCommand, WireControlOperationLookup, WireControlOperationRef} from './interactive-control.generated.js';
import type * as Public from './index.js';

// Unchecked private field views derive from the existing public DTO union.
// The original runtime validators below remain the sole structural admission.
type UnionKeys<T> = T extends unknown ? keyof T : never;
type Field<T, K extends PropertyKey> = T extends unknown ? K extends keyof T ? T[K] : never : never;
type Fields<T> = {[K in UnionKeys<T>]: Field<T, K>};
type RequestFields = Fields<Public.WireClientBody>;
type SubmissionAttemptFields = Fields<Public.WireSubmissionAttempt>;
type TextInputFields = Extract<Public.WireClientBodyByOperation['submit'], {kind: 'aql'}>['input'];
type SnapshotObserver = Parameters<typeof Public.snapshotClientRequest>[1];
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
export const clientSourceFormats: typeof Public.clientSourceFormats = Object.freeze([
  'json', 'yaml', 'aql-json', 'aql-yaml', 'aql', 'aql-text', 'sql',
]);
const cid = /^sha256:[0-9a-f]{64}$/u;
const exact = (value: unknown, keys: readonly string[]): value is Record<string, unknown> => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
  [...keys].sort().join('\0');
// Bounds of the Checkpoint operations. A Host may apply tighter ones.
export const checkpointLimits: typeof Public.checkpointLimits = Object.freeze({
  maxPageItems: 100,
  maxCursorLength: 512,
  maxReviewBytes: 1024 * 1024,
  maxResolveItems: 16,
});
// Bounds of the Resource discovery operations. A Host may apply tighter ones.
export const resourceLimits: typeof Public.resourceLimits = Object.freeze({
  maxQueryLength: 255,
  maxListItems: 1000,
  maxInspectBytes: 1024 * 1024,
  maxPeekFields: 100,
  maxPeekRows: 200,
  maxPeekBytes: 4 * 1024 * 1024,
});
const boundedText = (value: unknown, maximum = 256): value is string => typeof value === 'string' &&
  value.length > 0 && value.length <= maximum &&
  !/[\u0000-\u001f\u007f]/u.test(value);

// Whole response limits, including the envelope and nested type descriptors.
// These are UTF-8 JSON wire bytes and structural budgets, not payload limits.
export const resultDescriptionLimits: typeof Public.resultDescriptionLimits = Object.freeze({
  maxWireBytes: 1024 * 1024, maxNodes: 10000, maxDepth: 64,
});
export function withinResultDescriptionLimits(value: unknown,
  limits: typeof resultDescriptionLimits = resultDescriptionLimits): boolean {
  if (!(Object.keys(resultDescriptionLimits) as (keyof typeof resultDescriptionLimits)[]).every(key =>
    Number.isSafeInteger(limits?.[key]) && limits[key] > 0 &&
    limits[key] <= resultDescriptionLimits[key])) return false;
  let nodes = 0;
  const seen = new Set();
  const work: [unknown, number][] = [[value, 1]];
  while (work.length) {
    const [item, depth] = work.pop()!;
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
export function validResultDescription(value: unknown, expected: Readonly<{ref: Public.WireRunRef; resultName: string;
    format: 'json' | 'jsonl' | 'csv'}>,
  limits: typeof resultDescriptionLimits = resultDescriptionLimits): value is Public.WireResultDescription {
  if (!withinResultDescriptionLimits(value, limits) ||
      !validResultDescriptionShape(value) || !validRunRef(expected?.ref) ||
      !(['namespaceId', 'authorityScopeCid', 'runDefinitionCid'] as const).every(key =>
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
const submitRejections = new Set<unknown>([
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
export function isClientSubmitRejection(code: unknown): boolean {
  return submitRejections.has(code);
}
export function validRunRef(value: unknown): value is Public.WireRunRef {
  return validRunRefShape(value);
}

export function validSubmissionEpoch(value: unknown): value is Public.WireSubmissionEpoch {
  return validSubmissionEpochShape(value) &&
    !Object.is(value.notBefore, -0) && !Object.is(value.expiresAt, -0) &&
    value.expiresAt > value.notBefore;
}

export function validSubmissionRef(value: unknown): value is Public.WireSubmissionRef {
  return validSubmissionRefShape(value) && validSubmissionEpoch(value.epoch) &&
    value.nonce.isWellFormed() && value.nonce.normalize('NFC') === value.nonce &&
    !/[\u0080-\u009f]/u.test(value.nonce) &&
    new TextEncoder().encode(value.nonce).byteLength <= 256;
}

export function validSubmissionName(value: unknown): value is Public.WireSubmissionName {
  return validSubmissionNameShape(value) && value.isWellFormed() &&
    value.normalize('NFC') === value && !/[\u0080-\u009f]/u.test(value) &&
    new TextEncoder().encode(value).byteLength <= 256;
}

export function sameSubmissionRef(left: unknown, right: unknown): boolean {
  return validSubmissionRef(left) && validSubmissionRef(right) &&
    left.nonce === right.nonce && (['version', 'authorityScopeCid', 'epochNonce',
      'notBefore', 'expiresAt', 'authenticator'] as const).every(key => left.epoch[key] === right.epoch[key]);
}

export function validSubmissionRestart(value: unknown, fresh: Public.WireSubmissionRef): value is Public.WireSubmissionRestart {
  return validSubmissionRestartShape(value) && validSubmissionRef(value.submissionRef) &&
    validSubmissionRef(fresh) &&
    value.submissionRef.epoch.authorityScopeCid === fresh.epoch.authorityScopeCid &&
    value.submissionRef.epoch.expiresAt < fresh.epoch.expiresAt;
}

function restartMatches(actual: Public.WireSubmissionRestart | undefined, expected: Public.WireSubmissionRestart | undefined) {
  if (actual === undefined || expected === undefined) return actual === expected;
  return actual.acknowledgement === expected.acknowledgement &&
    sameSubmissionRef(actual.submissionRef, expected.submissionRef);
}

function submissionFactsMatch(value: Public.WireSubmissionOutcome | Public.WireSubmissionLookup, expected: Public.WireSubmissionRef, intentCid?: string) {
  if (!sameSubmissionRef(value.submissionRef, expected) ||
      intentCid !== undefined && (value as {intentCid?: unknown}).intentCid !== intentCid ||
      value.unresolvedHistory !== undefined && !validSubmissionRestart(value.unresolvedHistory, expected)) return false;
  if (value.kind === 'ready') return value.admission.ref.authorityScopeCid === expected.epoch.authorityScopeCid;
  if (value.kind === 'held') return validHeldRequest(value.held, expected.nonce);
  return true;
}

// Durable journal facts have no negotiated transport connection. Their Run
// binding is checked by the journal; a received reply additionally needs the
// selected connection below.
export function validStoredSubmissionOutcome(value: unknown, expected: Public.WireSubmissionRef, intentCid: string): value is Public.WireSubmissionOutcome {
  return validSubmissionOutcomeShape(value) && (value as {checkObservation?: Public.WireCheckOutcome}).checkObservation === undefined && submissionFactsMatch(value, expected, intentCid) &&
    (value.kind !== 'ready' || value.admission.durability === 'durable');
}

export function validSubmissionOutcome(value: unknown, selected: Public.WireConnection, expected: Public.WireSubmissionRef, intentCid?: string, unresolvedHistory?: Public.WireSubmissionRestart): value is Public.WireSubmissionOutcome {
  return validSubmissionOutcomeShape(value) &&
    ((value as {checkObservation?: Public.WireCheckOutcome}).checkObservation === undefined || validCheckOutcome((value as {checkObservation?: Public.WireCheckOutcome}).checkObservation)) &&
    (arguments.length < 5 || restartMatches(value.unresolvedHistory, unresolvedHistory)) &&
    submissionFactsMatch(value, expected, intentCid) &&
    (value.kind !== 'ready' || validClientAdmission(value.admission, selected)) &&
    (value.kind !== 'held' || validSubmitReply(value.held, selected, expected.nonce));
}

export function validSubmissionLookup(value: unknown, selected: Public.WireConnection, expected: Public.WireSubmissionRef): value is Public.WireSubmissionLookup {
  return validSubmissionLookupShape(value) && submissionFactsMatch(value, expected) &&
    (value.kind !== 'ready' || validClientAdmission(value.admission, selected)) &&
    (value.kind !== 'held' || validSubmitReply(value.held, selected, expected.nonce));
}

export function validSubmissionAttempt(value: unknown, selected: Public.WireConnection, expected: Public.WireSubmissionRef, intentCid: string, attemptRef: Public.WireOperationAttemptRef, unresolvedHistory?: Public.WireSubmissionRestart): value is Public.WireSubmissionAttempt {
  if (!validSubmissionRef(expected) || !validOperationAttemptRef(attemptRef) ||
      attemptRef.operation !== 'submit' || !validSubmissionAttemptShape(value) ||
      !validOperationAttemptRef(value.attemptRef) || value.attemptRef.operation !== 'submit' ||
      value.attemptRef.attemptId !== attemptRef.attemptId) return false;
  if (value.kind === 'recorded' || value.kind === 'already_satisfied') {
    return validSubmissionOutcome(value.outcome, selected, expected, intentCid, unresolvedHistory) &&
      (value.kind !== 'already_satisfied' || value.outcome.kind !== 'preparing');
  }
  return value.kind === 'refused' && value.reason === 'authorization' ||
    sameSubmissionRef((value as SubmissionAttemptFields).submissionRef, expected) && (value as SubmissionAttemptFields).intentCid === intentCid;
}

// A scoped name can resolve a reference issued under an earlier connection's
// epoch. This separate envelope never relaxes explicit-epoch correlation.
export function validNamedSubmissionAttempt(value: unknown, selected: Public.WireConnection, name: Public.WireSubmissionName, candidate: Public.WireSubmissionRef, intentCid: string, attemptRef: Public.WireOperationAttemptRef): value is Public.WireNamedSubmissionAttempt {
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
export function validRunState(value: unknown): value is Public.WireRunState {
  return validRunStateShape(value);
}

export const ownerObservationLimits: typeof Public.ownerObservationLimits = Object.freeze({maxEntries:1000,maxWireBytes:65536});
export const validOwnerRef: typeof Public.validOwnerRef = validOwnerRefShape;
export const validOwnerCursor: typeof Public.validOwnerCursor = validOwnerCursorShape;
const ownerIdentity = (owner: Public.WireOwnerRef) => JSON.stringify([owner.kind,owner.scopeCid,owner.streamCid]);
export function validOwnerObservations(value: unknown, ref: Public.WireRunRef, limits: typeof ownerObservationLimits & Readonly<{cursors?:readonly Public.WireOwnerCursor[]}> = ownerObservationLimits): value is Public.WireOwnerObservations {
  if (!validRunRef(ref) || !Number.isSafeInteger(limits.maxEntries) || limits.maxEntries < 1 ||
      limits.maxEntries > ownerObservationLimits.maxEntries || !Number.isSafeInteger(limits.maxWireBytes) ||
      limits.maxWireBytes < 1024 || limits.maxWireBytes > ownerObservationLimits.maxWireBytes ||
      !withinResultDescriptionLimits(value,{maxWireBytes:limits.maxWireBytes,maxNodes:10000,maxDepth:64}) ||
      !validOwnerObservationsShape(value) ||
      !(['namespaceId','authorityScopeCid','runDefinitionCid'] as const).every(key => value.ref[key] === ref[key])) return false;
  if(value.unmatchedCursors !== undefined &&
      (new Set(value.unmatchedCursors.map(item=>item.index)).size !== value.unmatchedCursors.length ||
       limits.cursors !== undefined && value.unmatchedCursors.some(item=>item.index >= limits.cursors!.length)))return false;
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
export function validCheckOutcome(value: unknown): value is Public.WireCheckOutcome {
  return validCheckOutcomeContract(value);
}

export function validSubmitPreparationError(value: unknown): value is Public.WireSubmitPreparationError {
  return validSubmitPreparationErrorShape(value);
}

export const validClientConnection: typeof Public.validClientConnection = validConnectionShape as typeof Public.validClientConnection;

// A target assertion is separate from authorization. The second argument must
// come from the Host's authenticated/installed Workspace binding, never from
// a caller's connection or Run reference. No assertion preserves the existing
// endpoint contract; a Host with no binding cannot accept an asserted target.
export const clientWorkspaceMatches: typeof Public.clientWorkspaceMatches = (connection, authenticatedWorkspaceId) =>
  connection.workspaceId === undefined ||
  boundedText(authenticatedWorkspaceId) &&
    connection.workspaceId === authenticatedWorkspaceId;

// Native brands are captured once; inspecting a caller's prototype or
// Symbol.toStringTag would add observable getters/Proxy traps to the snapshot.
const snapshotStringValueOf = String.prototype.valueOf;
const snapshotRawJSONBrand = (JSON as typeof JSON & {isRawJSON?: (value: unknown) => boolean}).isRawJSON;

// Client requests observe the JSON value actually submitted at this boundary.
// Preserve ordinary JSON serialization, but never replace source numbers.
function snapshotRequest(value: unknown, numberError: string, observe?: SnapshotObserver): unknown {
  let units = 0, reserved = 0, values = 0, reservedValues = 0;
  const document = JSON.stringify(value, (key, item: unknown) => {
    let number = item, boxed = false;
    if (item !== null && typeof item === 'object') {
      // Brand-check without invoking user coercion, including across realms.
      try { Number.prototype.valueOf.call(item); boxed = true; }
      catch { /* Ordinary objects retain their JSON serialization. */ }
    }
    // JSON unwraps Number objects with ToNumber, including custom coercion.
    // Return that primitive so serialization cannot coerce it again unchecked.
    if (boxed) number = +(item as number);
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
        rawUnits = (item as {rawJSON: string}).rawJSON.length;
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
  return JSON.parse(document as string) as unknown;
}

// One serialization owner for check and submit. Preserve the existing check
// helper's error spelling for direct consumers. SDK callers map local refusal.
export const snapshotClientRequest: typeof Public.snapshotClientRequest = (value, observe) =>
  snapshotRequest(value, 'UnrepresentableClientNumber', observe);
export const snapshotCheckRequest: typeof Public.snapshotCheckRequest = value =>
  snapshotRequest(value, 'UnrepresentableCheckNumber');

// Synchronous Host ingress preparation. Capture the original Workspace target
// before serialization or an awaited authentication/authorization boundary.
// Authentication, authorization and transport-specific reading stay outside.
function freezeCapturedRequest<T>(value: T): T {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freezeCapturedRequest(child);
    Object.freeze(value);
  }
  return value;
}

export function prepareClientHostRequest(operation: Public.ClientHostOperation, original: unknown, retainSnapshot: boolean = false): Readonly<{body: unknown; connection: Public.WireConnection}> | undefined {
  if (!validClientBody(operation, original)) return undefined;
  const suppliedConnection = (original as RequestFields).connection;
  const connection = Object.freeze({...suppliedConnection,
    consentRefs: Object.freeze([...suppliedConnection.consentRefs]),
    runners: Object.freeze([...suppliedConnection.runners])});
  if (!validClientConnection(connection)) return undefined;
  let body = original as RequestFields, snapshotted = false;
  if (operation === 'check') {
    // Observe the original serializer once, before spreading can erase it.
    try { body = snapshotCheckRequest(body) as RequestFields; }
    catch { return undefined; }
    if (!validClientBody(operation, body)) return undefined;
    snapshotted = true;
  }
  // A serializer cannot remove or replace the captured Workspace assertion.
  body = {...body, connection};
  if (['submit-intent', 'submit-named-intent', 'restart-intent', 'lookup-submission', 'owner-observations',
    'plan', 'static-explanation', 'inspect-run', 'run-plan', 'run-explanation',
    'run-explanation-context', 'run-sample', 'lookup-control-operation', 'resume-run'].includes(operation)) {
    try { body = snapshotClientRequest(body) as RequestFields; }
    catch { return undefined; }
    if (!validClientBody(operation, body)) return undefined;
    snapshotted = true;
  }
  // The structural read's original ref cannot change during awaited Host
  // authentication/authorization. This is its already-captured private copy.
  if (operation === 'run-explanation' || operation === 'run-explanation-context') Object.freeze(body.ref);
  if (operation === 'run-sample' || operation === 'lookup-control-operation' || operation === 'resume-run') {
    Object.freeze(body.ref);
    freezeCapturedRequest(operation === 'run-sample' ? body.selector :
      operation === 'resume-run' ? body.command : body.operationRef);
  }
  if (retainSnapshot === true) {
    if (!snapshotted) {
      try { body = snapshotClientRequest(body) as RequestFields; }
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
function validProgramInput(body: RequestFields) {
  return (body.kind === 'aql' &&
    (exact(body.input, ['text', 'format']) ||
      exact(body.input, ['text', 'format', 'parameterDeclarations'])) &&
    typeof body.input.text === 'string' &&
    body.input.text.length > 0 &&
    !body.input.text.includes('\u0000') &&
    clientSourceFormats.includes(body.input.format as Public.ClientSourceFormat) &&
    (body.input.parameterDeclarations === undefined ||
      ['aql', 'aql-text', 'sql'].includes(body.input.format as string) &&
      body.input.parameterDeclarations !== null &&
      typeof body.input.parameterDeclarations === 'object' &&
      !Array.isArray(body.input.parameterDeclarations)) ||
    body.kind === 'program' && body.input !== null &&
    typeof body.input === 'object' && !Array.isArray(body.input));
}

export function validClientBody<O extends Public.ClientHostOperation>(operation: O, body: unknown): body is Public.WireClientBodyByOperation[O] {
  const bodyKeys = clientHostRequestKeys(operation, body);
  // Template requests contain no submitted bindings. The scope is selected
  // before input admission; even null or an empty binding object is refused.
  const selectedKeys = operation === 'check' && (body as RequestFields | undefined)?.scope === 'template_only'
    ? bodyKeys?.filter(key => key !== 'parameters') : bodyKeys;
  if (selectedKeys === undefined || !exact(body, selectedKeys) ||
      !validClientConnection((body as RequestFields).connection) ||
      !validClientRequestOptionalFields(operation, body)) return false;
  if (operation === 'connect') return true;
  if (operation === 'submit-intent' || operation === 'submit-named-intent' || operation === 'restart-intent') {
    if (!validSubmissionRef((body as RequestFields).submissionRef) || !cid.test((body as RequestFields).intentCid) ||
        !validOperationAttemptRef((body as RequestFields).attemptRef) || (body as RequestFields).attemptRef.operation !== 'submit') return false;
    if (operation === 'restart-intent' && !validSubmissionRestart((body as RequestFields).unresolvedHistory, (body as RequestFields).submissionRef)) return false;
    if (operation === 'submit-named-intent' && !validSubmissionName((body as RequestFields).requestName)) return false;
    return validClientBody('submit', {connection: (body as RequestFields).connection,
      requestId: (body as RequestFields).submissionRef.nonce, kind: (body as RequestFields).kind,
      input: (body as RequestFields).input, parameters: (body as RequestFields).parameters,
      ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: (body as RequestFields).stopBefore} : {}),
      ...(Object.hasOwn(body, 'readOnly') ? {readOnly: (body as RequestFields).readOnly} : {}),
      ...(Object.hasOwn(body, 'executionProfile') ? {executionProfile: (body as RequestFields).executionProfile} : {})}) &&
      ((body as RequestFields).parameters === null || typeof (body as RequestFields).parameters === 'object' &&
        !Array.isArray((body as RequestFields).parameters));
  }
  if (operation === 'lookup-submission') return validSubmissionRef((body as RequestFields).submissionRef);
  if (operation === 'inspect-run' || operation === 'run-plan' ||
      operation === 'run-explanation' || operation === 'run-explanation-context' || operation === 'run-sample' ||
      operation === 'lookup-control-operation' || operation === 'resume-run') {
    const fields = body as RequestFields;
    return validRunRef(fields.ref) &&
      (operation !== 'run-sample' || validWireSampleSelectorShape(fields.selector) &&
        (!Object.hasOwn(body, 'nextRevision') || fields.selector.role === 'input' &&
          fields.selector.step.by === 'id' && fields.selector.input_port_id !== undefined)) &&
      (operation !== 'lookup-control-operation' || validWireControlOperationRefShape(fields.operationRef) &&
        boundedText(fields.operationRef.operation_id) && sameRunRef(fields.ref, fields.operationRef.run_ref)) &&
      (operation !== 'resume-run' || validWireControlCommandShape(fields.command) &&
        fields.command.operation === 'resume' && boundedText(fields.command.operation_id) &&
        sameRunRef(fields.ref, fields.command.run_ref) && fields.command.interval?.guards === null &&
        ['step', 'terminal'].includes(fields.command.interval.until)) &&
      Number.isSafeInteger((body as RequestFields).maxWireBytes) && (body as RequestFields).maxWireBytes >= 1024 && (body as RequestFields).maxWireBytes <= 65536 &&
      Number.isSafeInteger((body as RequestFields).maxNodes) && (body as RequestFields).maxNodes > 0 && (body as RequestFields).maxNodes <= 10000 &&
      Number.isSafeInteger((body as RequestFields).maxDepth) && (body as RequestFields).maxDepth > 0 && (body as RequestFields).maxDepth <= 64;
  }
  if (operation === 'plan' || operation === 'static-explanation') {
    return validProgramInput(body as RequestFields) &&
      ((body as RequestFields).parameters === null || typeof (body as RequestFields).parameters === 'object' &&
        !Array.isArray((body as RequestFields).parameters)) &&
      Number.isSafeInteger((body as RequestFields).maxWireBytes) && (body as RequestFields).maxWireBytes > 0 && (body as RequestFields).maxWireBytes <= 65536 &&
      Number.isSafeInteger((body as RequestFields).maxNodes) && (body as RequestFields).maxNodes > 0 && (body as RequestFields).maxNodes <= 10000 &&
      Number.isSafeInteger((body as RequestFields).maxDepth) && (body as RequestFields).maxDepth > 0 && (body as RequestFields).maxDepth <= 64;
  }
  if (operation === 'submit') {
    return boundedText((body as RequestFields).requestId) && validProgramInput(body as RequestFields);
  }
  // This validates the closed request envelope only. Program/language meaning
  // belongs to the same common checker selected by the Host.
  if (operation === 'check') {
    if (!['template_only', 'bound_input'].includes((body as RequestFields).scope) ||
        !['text', 'program'].includes((body as RequestFields).kind) ||
        (body as RequestFields).scope === 'bound_input' && !((body as RequestFields).parameters === null ||
          (body as RequestFields).parameters !== null && typeof (body as RequestFields).parameters === 'object' &&
          !Array.isArray((body as RequestFields).parameters))) return false;
    if ((body as RequestFields).kind === 'program') return (body as RequestFields).input !== null &&
      typeof (body as RequestFields).input === 'object' && !Array.isArray((body as RequestFields).input);
    return (exact((body as RequestFields).input, ['text', 'format']) ||
        exact((body as RequestFields).input, ['text', 'format', 'parameterDeclarations'])) &&
      typeof ((body as RequestFields).input as TextInputFields).text === 'string' &&
      ((body as RequestFields).input as TextInputFields).text.length > 0 &&
      ((body as RequestFields).input as TextInputFields).text.isWellFormed() &&
      !((body as RequestFields).input as TextInputFields).text.includes('\u0000') &&
      ['aql', 'aql-text', 'sql'].includes(((body as RequestFields).input as TextInputFields).format) &&
      (((body as RequestFields).input as TextInputFields).parameterDeclarations === undefined ||
        ((body as RequestFields).input as TextInputFields).parameterDeclarations !== null &&
        typeof ((body as RequestFields).input as TextInputFields).parameterDeclarations === 'object' &&
        !Array.isArray(((body as RequestFields).input as TextInputFields).parameterDeclarations));
  }
  if (operation === 'lookup-request' || operation === 'cancel-request') {
    return boundedText((body as RequestFields).requestId);
  }
  if (operation === 'resources') {
    return boundedText((body as RequestFields).resourceConnection) &&
      typeof (body as RequestFields).query === 'string' &&
      (body as RequestFields).query.length <= resourceLimits.maxQueryLength &&
      !/[\u0000-\u001f\u007f]/u.test((body as RequestFields).query) &&
      Number.isSafeInteger((body as RequestFields).limit) && (body as RequestFields).limit > 0 &&
      (body as RequestFields).limit <= resourceLimits.maxListItems;
  }
  if (operation === 'resource-inspect') {
    return boundedText((body as RequestFields).resourceConnection) && boundedText((body as RequestFields).resource) &&
      Number.isSafeInteger((body as RequestFields).maxBytes) && (body as RequestFields).maxBytes > 0 &&
      (body as RequestFields).maxBytes <= resourceLimits.maxInspectBytes;
  }
  if (operation === 'resource-peek') {
    return boundedText((body as RequestFields).resourceConnection) && boundedText((body as RequestFields).resource) &&
      Array.isArray((body as RequestFields).fields) && (body as RequestFields).fields.length > 0 &&
      (body as RequestFields).fields.length <= resourceLimits.maxPeekFields &&
      (body as RequestFields).fields.every(field => boundedText(field)) &&
      new Set((body as RequestFields).fields).size === (body as RequestFields).fields.length &&
      Number.isSafeInteger((body as RequestFields).maxRows) && (body as RequestFields).maxRows > 0 &&
      (body as RequestFields).maxRows <= resourceLimits.maxPeekRows &&
      Number.isSafeInteger((body as RequestFields).maxBytes) && (body as RequestFields).maxBytes > 0 &&
      (body as RequestFields).maxBytes <= resourceLimits.maxPeekBytes;
  }
  if (operation === 'checkpoints') {
    return Number.isSafeInteger((body as RequestFields).limit) && (body as RequestFields).limit > 0 &&
      (body as RequestFields).limit <= checkpointLimits.maxPageItems &&
      ((body as RequestFields).after === '' ||
        boundedText((body as RequestFields).after, checkpointLimits.maxCursorLength));
  }
  if (operation === 'checkpoint-review') {
    return typeof (body as RequestFields).checkpointCid === 'string' &&
      cid.test((body as RequestFields).checkpointCid) &&
      Number.isSafeInteger((body as RequestFields).maxBytes) && (body as RequestFields).maxBytes > 0 &&
      (body as RequestFields).maxBytes <= checkpointLimits.maxReviewBytes;
  }
  if (operation === 'resolve') {
    return Array.isArray((body as RequestFields).items) && (body as RequestFields).items.length > 0 &&
      (body as RequestFields).items.length <= checkpointLimits.maxResolveItems &&
      (body as RequestFields).items.every(validResolveItemShape) &&
      new Set((body as RequestFields).items.map(item => item.checkpointCid)).size ===
        (body as RequestFields).items.length;
  }
  if (!validRunRef((body as RequestFields).ref)) return false;
  if (operation === 'owner-observations') return Array.isArray((body as RequestFields).cursors) && (body as RequestFields).cursors.length <= 5 &&
    (body as RequestFields).cursors.every(validOwnerCursor) &&
    new Set((body as RequestFields).cursors.map(cursor => ownerIdentity(cursor.owner))).size === (body as RequestFields).cursors.length &&
    Number.isSafeInteger((body as RequestFields).maxEntries) && (body as RequestFields).maxEntries > 0 && (body as RequestFields).maxEntries <= ownerObservationLimits.maxEntries &&
    Number.isSafeInteger((body as RequestFields).maxWireBytes) && (body as RequestFields).maxWireBytes >= 1024 && (body as RequestFields).maxWireBytes <= ownerObservationLimits.maxWireBytes;
  if (operation === 'cancel' || operation === 'lookup-cancellation') {
    if (operation === 'cancel' && (!validOperationAttemptRef((body as RequestFields).attemptRef) ||
        (body as RequestFields).attemptRef.operation !== 'cancel')) return false;
    return validCancellationRef({...(body as RequestFields).ref, cancelId: (body as RequestFields).cancelId,
      expectedRevision: (body as RequestFields).expectedRevision});
  }
  if (operation === 'result-describe') return boundedText((body as RequestFields).resultName) &&
    boundedText((body as RequestFields).attemptId) && ['json', 'jsonl', 'csv'].includes((body as RequestFields).format) &&
    (Object.keys(resultDescriptionLimits) as (keyof typeof resultDescriptionLimits)[]).every(key =>
      Number.isSafeInteger(body[key]) && (body[key] as number) > 0 &&
      (body[key] as number) <= resultDescriptionLimits[key]);
  if (operation === 'read') return boundedText((body as RequestFields).resultName) &&
    boundedText((body as RequestFields).attemptId) &&
    ['json', 'jsonl', 'csv'].includes((body as RequestFields).format);
  if (operation === 'delivery-attempt') return boundedText((body as RequestFields).resultName) &&
    boundedText((body as RequestFields).attemptId);
  if (operation === 'wait') return ((body as RequestFields).until === null || boundedText((body as RequestFields).until, 128)) &&
    ((body as RequestFields).since === null || Number.isSafeInteger((body as RequestFields).since) && ((body as RequestFields).since as number) >= 0);
  return true;
}

// The caller admits the closed static response before checking its original bindings.
export function validStaticExplanationBinding(view: Public.WireStaticExplanationView): boolean {
  const {facts, context: {binding}, plan} = view;
  const effectful = plan.version === 'actql-effectful-static-plan-view/0.1';
  const component = effectful ? plan.computation.plan_view : plan;
  const map = component.logical_map;
  return map.compiled_plan_cid === component.compiled_plan_cid &&
    facts.program_definition_cid === map.program_definition_cid &&
    binding.program_definition_cid === map.program_definition_cid &&
    facts.compiled_plan_cid === component.compiled_plan_cid &&
    binding.compiled_plan_cid === component.compiled_plan_cid &&
    facts.logical_map_cid === map.self_cid && binding.logical_map_cid === map.self_cid &&
    facts.parameter_values_cid === binding.parameter_values_cid &&
    (!effectful || map.program_definition_cid === plan.program_definition_cid &&
      facts.parameter_values_cid === plan.parameter_values_cid &&
      binding.check_environment_cid === plan.check_environment_cid);
}

// Structural Host replies bind connection and request identity without
// deciding Run admission, authorization, retry or state transitions.
export const validClientProfile: typeof Public.validClientProfile = (value: unknown, selected: Public.WireConnection): value is Public.WireClientProfile => validProfileContract(value, selected) &&
  (value.submissionEpoch === undefined || validSubmissionEpoch(value.submissionEpoch));
export const validClientAdmission: typeof Public.validClientAdmission = validAdmissionContract;

// A request the Host holds before any Run exists: waiting on a
// `prepare_attempt` Checkpoint, resuming after an approval, or ended without
// a Run. Once the Run exists the lookup is `found` with its RunRef.
export const validHeldRequest: typeof Public.validHeldRequest = validHeldContract;
export const validRequestLookup: typeof Public.validRequestLookup = validRequestLookupContract;

// A submit reply: the admitted Run, or the held request (no Run yet).
export function validSubmitReply(value: unknown, selected: Public.WireConnection, expectedRequestId: string): value is Public.WireSubmitReply {
  if ((value as {kind?: unknown} | null | undefined)?.kind === 'held') {
    return validClientConnection(selected) &&
      validHeldRequest(value, expectedRequestId);
  }
  return validClientAdmission(value, selected);
}

// One authorized page of waiting Checkpoints (safe metadata only).
export function validCheckpointPage(value: unknown, limit: number): value is Public.WireCheckpointPage {
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
export function validCheckpointLookup(value: unknown, checkpointId: string): value is Public.WireCheckpointPage {
  return clientHostRequestKeys('checkpoints', {checkpointId})!.includes('checkpointId') &&
    validClientRequestOptionalFields('checkpoints', {checkpointId}) &&
    validCheckpointPage(value, 1) && !Object.hasOwn(value, 'next') &&
    value.items.every(item => item.checkpointId === checkpointId);
}

// The exact review projection a Checkpoint names, within the requested
// bound. The caller still checks the decoded bytes against `artifactCid`.
export function validCheckpointReview(value: unknown, expected: Readonly<{checkpointCid: string; maxBytes: number}>): value is Public.WireCheckpointReview {
  if (!shape(expected, ['checkpointCid', 'maxBytes']) ||
      !validCheckpointReviewShape(value) ||
      value.checkpointCid !== expected.checkpointCid ||
      value.byteLength > expected.maxBytes) return false;
  const padding = value.contentBase64.endsWith('==') ? 2
    : value.contentBase64.endsWith('=') ? 1 : 0;
  return value.contentBase64.length % 4 === 0 &&
    value.contentBase64.length / 4 * 3 - padding === value.byteLength;
}

export function validResolveItem(value: unknown): value is Public.WireResolveItem {
  return validResolveItemShape(value);
}

// Per-item answers, in request order, one per submitted Checkpoint.
export function validResolveResults(value: unknown, items: readonly Readonly<{checkpointCid: string}>[]): value is Readonly<{results: readonly Public.WireResolveResult[]}> {
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
const shape = (value: unknown, required: readonly string[], optional: readonly string[] = []): value is Record<string, unknown> => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  required.every(key => Object.hasOwn(value, key)) &&
  Object.keys(value).every(key => required.includes(key) ||
    optional.includes(key));

export function validDeliveryAttemptLookup(value: unknown, expected: Readonly<{attemptId: string; runDefinitionCid: string;
    resultName: string}>): value is Public.WireDeliveryAttemptLookup {
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
  return (['run_definition_cid', 'result_manifest_cid', 'result_name',
    'result_artifact_cid', 'serialization_contract_cid'] as const)
    .every(key => attempt[key] === receipt[key]);
}

export const validCancellationRef: typeof Public.validCancellationRef = (value: unknown): value is Public.WireCancellationRef => validCancellationRefShape(value) &&
  value.namespaceId.isWellFormed() && value.cancelId.isWellFormed();
const sameRunRef = (left: Public.WireRunRef, right: Public.WireRunRef) => (['namespaceId', 'authorityScopeCid', 'runDefinitionCid'] as const)
  .every(key => left[key] === right[key]);
const sameControlOperationRef = (left: WireControlOperationRef, right: WireControlOperationRef) => sameRunRef(left.run_ref, right.run_ref) &&
  left.operation_id === right.operation_id && left.command_cid === right.command_cid &&
  left.accepted_from_revision === right.accepted_from_revision;

export const resumeControlOperationRef = (command: WireControlCommand): WireControlOperationRef => ({
  run_ref: command.run_ref, operation_id: command.operation_id, command_cid: command.self_cid,
  accepted_from_revision: command.expected_control_revision,
});

export function validControlOperationLookup(value: unknown, operationRef: WireControlOperationRef): value is WireControlOperationLookup {
  if (!validWireControlOperationRefShape(operationRef) || !validWireControlOperationLookupShape(value)) return false;
  if (value.state !== 'found') return true;
  const {receipt, observation} = value;
  const origin = receipt.observed_state.resume_origin;
  return sameControlOperationRef(receipt.operation_ref, operationRef) &&
    sameControlOperationRef(observation.operation_ref, operationRef) &&
    observation.original_receipt_cid === receipt.self_cid &&
    (receipt.outcome !== 'accepted' || origin?.kind !== 'manual' || origin.command_cid === operationRef.command_cid);
}

const sameCancellationRef = (left: Public.WireCancellationRef, right: Public.WireCancellationRef) => sameRunRef(left, right) &&
  left.cancelId === right.cancelId && left.expectedRevision === right.expectedRevision;
export const validCancellation: typeof Public.validCancellation = (value: unknown, expected?: Public.WireCancellationRef): value is Public.WireCancellation => validCancellationShape(value) &&
  validCancellationRef(value.cancelRef) && sameRunRef(value.ref, value.cancelRef) &&
  value.revision >= value.cancelRef.expectedRevision &&
  (value.kind !== 'accepted' || value.revision > value.cancelRef.expectedRevision) &&
  (expected === undefined || validCancellationRef(expected) &&
    sameCancellationRef(value.cancelRef, expected));
export function validCancellationLookup(value: unknown, expected: Public.WireCancellationRef): value is Public.WireCancellationLookup {
  return validCancellationRef(expected) && validCancellationLookupShape(value) &&
    (value.kind === 'found' ? validCancellation(value.cancellation, expected) :
      validCancellationRef(value.cancelRef) && sameCancellationRef(value.cancelRef, expected));
}

export const validOperationAttemptRef: typeof Public.validOperationAttemptRef = (value: unknown): value is Public.WireOperationAttemptRef => validOperationAttemptRefShape(value) &&
  value.attemptId.isWellFormed();
export function validCancellationAttempt(value: unknown, expected: Public.WireCancellationRef, attemptRef: Public.WireOperationAttemptRef): value is Public.WireCancellationAttempt {
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
export function validRequestCancellation(value: unknown, expectedRequestId: string): value is Public.WireRequestCancellation {
  return boundedText(expectedRequestId) &&
    validRequestCancellationShape(value) &&
    value.requestId === expectedRequestId &&
    (value.ref === undefined) === (value.revision === undefined);
}

const utf8Bytes = (text: string) => new TextEncoder().encode(text).length;
const jsonObject = (text: string) => {
  try {
    const value: unknown = JSON.parse(text);
    return value !== null && typeof value === 'object' &&
      !Array.isArray(value) ? value : undefined;
  } catch { return undefined; }
};

// One page of Resource names answering the exact request. Names are unique.
export function validResourceListing(value: unknown, expected: Readonly<{resourceConnection: string; limit: number}>): value is Public.WireResourceListing {
  if (!shape(expected, ['resourceConnection', 'limit']) ||
      !validResourceListingShape(value) ||
      value.resourceConnection !== expected.resourceConnection ||
      value.resources.length > expected.limit) return false;
  return new Set(value.resources.map(item => item.name)).size ===
    value.resources.length;
}

// A ready inspection carries only its bounded summary object; a Resource
// that needs Catalog evidence carries only the reason.
export function validResourceInspection(value: unknown, expected: Readonly<{resourceConnection: string; resource: string;
    maxBytes: number}>): value is Public.WireResourceInspection {
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
export function validResourcePeek(value: unknown, expected: Readonly<{resourceConnection: string; resource: string;
    fields: readonly string[]; maxRows: number; maxBytes: number}>): value is Public.WireResourcePeek {
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
    rows.every((row: unknown) => row !== null && typeof row === 'object' &&
      !Array.isArray(row) && Object.keys(row).sort().join('\0') === keys &&
      Object.values(row).every((cell: unknown) => cell === null ||
        ['string', 'boolean'].includes(typeof cell) ||
        typeof cell === 'number' && Number.isFinite(cell)));
}
