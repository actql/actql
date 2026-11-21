// Common sequencing for one authorized Result delivery. MoonBit owns grant,
// attempt, receipt, serialization, and transition semantics. Store and sink
// adapters own durable effects and exact byte-exposure observations.
import {retainFirstAndLatestCleanupError} from './managed-failure.mjs';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {PublicationContract} from '../store-local/publication-contract-store.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import type {publicationAction} from './publication-action.mjs';

type Awaitable<T> = T | PromiseLike<T>;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Format = 'json' | 'jsonl' | 'csv';
type Exposure = 'exact' | 'unknown_additional';
type LocalStore = Awaited<ReturnType<typeof openLocalPublicationStore>>;
type Store = Pick<LocalStore,
  'confirmCommittedIndex' | 'readPublicationContract' |
  'latestDeliveryRecord' | 'latestDeliveryRecordContract' | 'confirmDeliveryRecord' |
  'appendDeliveryRecord' | 'putPublicationContract' | 'withCommittedResultRows'> &
  Partial<Pick<LocalStore, 'appendDeliveryCompletion' | 'beginDeliveryAttempt'>> & Readonly<{
  createDeliveryAttempt(wire: string, grantWire: string, original?: unknown): Awaitable<AttemptSelection>;
}>;
type ReadDemand = NonNullable<Parameters<Store['confirmCommittedIndex']>[1]>;
type FrameLimits = Parameters<Store['withCommittedResultRows']>[3];
type FrameControl = Parameters<Store['withCommittedResultRows']>[5];
type ResultMetadata = Parameters<Parameters<Store['withCommittedResultRows']>[4]>[0];
type AppendRecord = (record: PublicationContract) => Awaitable<unknown>;
type AttemptRequest = Readonly<{resultName: string; format: Format; attemptId: string}>;
type AttemptSelection = Readonly<{created: boolean; original?: unknown; attempt?: unknown}>;
type RecordData = Readonly<{
  state: 'streaming' | 'succeeded' | 'failed' | 'cancelled';
  confirmedByteCount: number;
  exposure: Exposure;
  possibleUnconfirmedMaxBytes: number | undefined;
  deliveredSha256: string | undefined;
  receipt: PublicationContract | undefined;
  failureCid: string | undefined;
  observedAt: string;
  cleanupOwnerCids: readonly string[];
}>;
type Control = FrameControl & Readonly<{
  admit(name: 'delivery_attempt', wire: string, limits: Limits): PublicationContract;
  issueDeliveryAttempt(index: PublicationContract, manifest: PublicationContract, grant: PublicationContract,
    request: AttemptRequest & Readonly<{requestedAt: string}>, limits: Limits): PublicationContract;
  captureIssuedDeliveryAttempt?(attempt: PublicationContract, index: PublicationContract,
    manifest: PublicationContract, grant: PublicationContract, limits: Limits): unknown;
  deliveryResultDefinitionCid(manifest: PublicationContract, attempt: PublicationContract): string;
  resultReadGrantAllowsBytes(grant: PublicationContract, bytes: number): boolean;
  resultReadGrantValidAt(grant: PublicationContract, observedAt: string): boolean;
  issueDeliveryRecord(attempt: PublicationContract, previous: PublicationContract | undefined,
    record: RecordData, limits: Limits): PublicationContract;
  issueResultDeliveryReceipt(index: PublicationContract, manifest: PublicationContract,
    grant: PublicationContract, attempt: PublicationContract,
    summary: Readonly<{byteCount: number; sha256: string}>, limits: Limits): PublicationContract;
  prepareResultDeliverySerializer(format: Format, schema: string, fields: readonly string[], limits: Limits): unknown;
  beginResultDelivery(serializer: unknown): string;
  nextResultDeliveryRow(serializer: unknown, row: string): string;
  finishResultDelivery(serializer: unknown): string;
  existingDeliveryAttemptAction(record: PublicationContract): ReturnType<typeof publicationAction<'existingDelivery'>>;
  deliveryFailureTerminalAction(cancelled: boolean): ReturnType<typeof publicationAction<'failureTerminal'>>;
  deliveryRecordRetryAction(nextRecord: number, recordCount: number): ReturnType<typeof publicationAction<'recordRetry'>>;
}>;
type SelectedPublication = Readonly<{
  store: Store; control: Control; index: PublicationContract; manifest: PublicationContract;
}>;
type Sink = Readonly<{
  write(bytes: Uint8Array, signal?: AbortSignal): Awaitable<unknown>;
  finish(signal?: AbortSignal): Awaitable<unknown>;
}>;
type Digest = Readonly<{
  update(bytes: Uint8Array): unknown;
  finish(): Awaitable<string>;
}>;
type AuthorityFacts = AttemptRequest & Readonly<{
  index: PublicationContract; manifest: PublicationContract; grant: PublicationContract; observedAt: string;
}> & (
  Readonly<{stage: 'attempt'}> |
  Readonly<{stage: 'read'; attempt: PublicationContract}> & Omit<ResultMetadata, 'resultFields' | 'resultSchemaWire'> |
  Readonly<{stage: 'write'; attempt: PublicationContract; confirmedByteCount: number; nextByteCount: number}> |
  Readonly<{stage: 'finish'; attempt: PublicationContract; confirmedByteCount: number}> |
  Readonly<{stage: 'receipt'; attempt: PublicationContract; confirmedByteCount?: number}>
);
type Authorize = (facts: AuthorityFacts & Readonly<{sinkCallbackCount: number}>) => Awaitable<boolean>;
type DeliveryOptions = AttemptRequest & Readonly<{
  store: Store;
  control: Control;
  indexKey: WireRunRef;
  grant: PublicationContract;
  limits: Limits;
  frameLimits: FrameLimits;
  now: () => unknown;
  sink: Sink;
  createDigest: () => Digest;
  authorize: Authorize;
  signal: AbortSignal | undefined;
}>;
type AdmittedRow = Readonly<{units: number; window: number}>;
type Workspace = Readonly<{
  metadata: ReadDemand;
  prepare(metadata: ResultMetadata): number;
  row(units: number): AdmittedRow;
  row(wire: string): Awaitable<AdmittedRow>;
  serializer(value: unknown): unknown;
}>;
type RecordedReceipt = Readonly<{
  result_delivery_receipt_cid: string;
  confirmed_byte_count: number;
  delivered_sha256: string;
}>;
type SinkProgress = Readonly<{
  confirmedBytes: number;
  exposure: Exposure;
  possibleUnconfirmedMaxBytes?: number;
}>;
type SinkObservation = Readonly<{confirmedBytes: number}> | null | undefined;
type ChildCleanup = Readonly<{status?: unknown; retry?: unknown}>;
type CleanupCause = Readonly<{cleanupHandle?: ChildCleanup}> | null | undefined;
type CleanupStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;

export class ResultDeliveryError extends Error {
  declare readonly code: string;
  declare readonly primaryFailure: unknown;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw new ResultDeliveryError(code, cause); };
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const digestPattern = /^[0-9a-f]{64}$/u;
const exactKeys = (value: unknown, keys: readonly string[]) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const contractShape = (value: PublicationContract) => exactKeys(value,
  ['name', 'identityField', 'identity', 'wire']) &&
  typeof value.name === 'string' && value.name.length !== 0 &&
  typeof value.identityField === 'string' &&
  cidPattern.test(value.identity) && typeof value.wire === 'string';

function validateStore(store: Store) {
  if (store === null || typeof store !== 'object' ||
      !['confirmCommittedIndex', 'readPublicationContract',
        'createDeliveryAttempt', 'latestDeliveryRecord',
        'latestDeliveryRecordContract', 'confirmDeliveryRecord',
        'appendDeliveryRecord',
        'putPublicationContract', 'withCommittedResultRows']
        .every(name => typeof store[name as keyof Store] === 'function')) {
    fail('InvalidResultDeliveryStore');
  }
}

function validateControl(control: Control) {
  if (control === null || typeof control !== 'object' ||
      !['admit', 'issueDeliveryAttempt', 'deliveryResultDefinitionCid',
        'resultReadGrantAllowsBytes', 'resultReadGrantValidAt',
        'issueDeliveryRecord', 'issueResultDeliveryReceipt',
        'prepareResultDeliverySerializer', 'beginResultDelivery',
        'nextResultDeliveryRow', 'finishResultDelivery',
        'existingDeliveryAttemptAction', 'deliveryFailureTerminalAction',
        'deliveryRecordRetryAction']
        .every(name => typeof control[name as keyof Control] === 'function')) {
    fail('InvalidResultDeliveryControl');
  }
}

function selectDeliveryAttempt(
  control: Control, admitted: AttemptSelection, proposed: PublicationContract,
  index: PublicationContract, manifest: PublicationContract, grant: PublicationContract,
  request: AttemptRequest, limits: Limits, original: unknown,
) {
  try {
    if (typeof admitted?.created !== 'boolean') fail('InvalidResultDeliveryAttemptState');
    if (admitted.original !== undefined) {
      if (original === undefined || admitted.original !== original) {
        fail('InvalidResultDeliveryAttemptState');
      }
      // The physical owner selected this exact issued immutable attempt.
      // The opaque echo is not a claim, durability ACK or read permission.
      return proposed;
    }
    if (admitted.attempt === null ||
        typeof admitted.attempt !== 'object' || Array.isArray(admitted.attempt)) {
      fail('InvalidResultDeliveryAttemptState');
    }
    // Store selects the canonical birth time for a logical attempt. Admit its
    // complete contract, then check every binding through the existing issuer.
    const selected = control.admit('delivery_attempt',
      JSON.stringify(admitted.attempt), limits);
    const expected = control.issueDeliveryAttempt(index, manifest, grant, {
      ...request, requestedAt: (JSON.parse(selected.wire) as Readonly<{requested_at: string}>).requested_at,
    }, limits);
    if (selected.identity !== expected.identity || selected.wire !== expected.wire ||
        admitted.created && selected.wire !== proposed.wire) {
      fail('InvalidResultDeliveryAttemptState');
    }
    return selected;
  } catch (cause) {
    if (cause instanceof ResultDeliveryError) throw cause;
    fail('InvalidResultDeliveryAttemptState', cause);
  }
}

function validateRequest(options: DeliveryOptions) {
  if (!exactKeys(options, [
    'store', 'control', 'indexKey', 'grant', 'resultName', 'format',
    'attemptId', 'limits', 'frameLimits', 'now', 'sink', 'createDigest',
    'authorize', 'signal',
  ]) || !exactKeys(options.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof options.indexKey.namespaceId !== 'string' ||
      options.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(options.indexKey.authorityScopeCid) ||
      !cidPattern.test(options.indexKey.runDefinitionCid) ||
      !contractShape(options.grant) ||
      typeof options.resultName !== 'string' ||
      options.resultName.length === 0 ||
      !['json', 'jsonl', 'csv'].includes(options.format) ||
      typeof options.attemptId !== 'string' ||
      options.attemptId.length === 0 ||
      !exactKeys(options.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(options.limits).every(value =>
        Number.isSafeInteger(value) && value > 0) ||
      !exactKeys(options.frameLimits, [
        'maxRowBytes', 'maxDepth', 'maxFrameBytes',
      ]) || !Object.values(options.frameLimits).every(value =>
        Number.isSafeInteger(value) && value > 0) ||
      typeof options.now !== 'function' ||
      typeof options.sink?.write !== 'function' ||
      typeof options.sink?.finish !== 'function' ||
      typeof options.createDigest !== 'function' ||
      typeof options.authorize !== 'function' ||
      options.signal !== undefined &&
        (options.signal === null ||
          typeof options.signal.throwIfAborted !== 'function')) {
    fail('InvalidResultDeliveryRequest');
  }
}

async function requireCurrentAuthorization(authorize: Authorize, facts: AuthorityFacts, sinkCallbackCount: number) {
  if (await authorize(Object.freeze({...facts, sinkCallbackCount})) !== true) {
    fail('ResultDeliveryDenied');
  }
}

function trustedNow(now: DeliveryOptions['now']) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidResultDeliveryClock');
  }
  return value;
}

class SinkWriteFailure extends Error {
  declare readonly confirmedBytes: number;
  declare readonly exposure: Exposure;
  declare readonly possibleUnconfirmedMaxBytes: number | undefined;

  constructor(cause: unknown, confirmedBytes: number, exposure: Exposure, possibleUnconfirmedMaxBytes: number | undefined) {
    super('ResultDeliverySinkWriteFailed', {cause});
    this.cause = cause;
    this.confirmedBytes = confirmedBytes;
    this.exposure = exposure;
    this.possibleUnconfirmedMaxBytes = possibleUnconfirmedMaxBytes;
  }
}

function sinkFailure(reason: unknown, length: number) {
  const progress = reason !== null && typeof reason === 'object'
    ? (reason as Readonly<{deliveryProgress?: SinkProgress}>).deliveryProgress : undefined;
  if (progress !== null && typeof progress === 'object' &&
      Number.isSafeInteger(progress.confirmedBytes) &&
      progress.confirmedBytes >= 0 && progress.confirmedBytes <= length &&
      ['exact', 'unknown_additional'].includes(progress.exposure) &&
      (progress.exposure === 'exact' &&
        progress.possibleUnconfirmedMaxBytes === undefined ||
        progress.exposure === 'unknown_additional' &&
        Number.isSafeInteger(progress.possibleUnconfirmedMaxBytes) &&
        progress.possibleUnconfirmedMaxBytes! >= 0 &&
        progress.possibleUnconfirmedMaxBytes! <=
          length - progress.confirmedBytes)) {
    return new SinkWriteFailure(
      reason,
      progress.confirmedBytes,
      progress.exposure,
      progress.possibleUnconfirmedMaxBytes,
    );
  }
  return new SinkWriteFailure(reason, 0, 'unknown_additional', length);
}

async function appendExactRecord(store: Store, record: PublicationContract) {
  return store.appendDeliveryRecord(record.wire);
}

class DeliveryRecordDurabilityFailure extends ResultDeliveryError {
  declare cleanupErrors: readonly unknown[];
  declare cleanupPending: boolean;
  declare cleanupHandle: Readonly<{
    status(): CleanupStatus;
    retry(): Promise<CleanupStatus>;
  }>;
}

function pendingRecordFailure(
  code: string,
  reason: unknown,
  store: Store,
  control: Control,
  records: readonly PublicationContract[],
  recordFailure: unknown,
  appendRecord: AppendRecord = record => appendExactRecord(store, record),
) {
  const failure = new DeliveryRecordDurabilityFailure(code, reason);
  const errors = [recordFailure];
  let pending = true;
  let nextRecord = 0;
  let retrying: Promise<CleanupStatus> | undefined;
  let pendingChild: (ChildCleanup & Readonly<{child: ChildCleanup}>) | undefined;
  const retainChild = (error: unknown) => {
    const child = (error as CleanupCause)?.cleanupHandle;
    if (child !== undefined) {
      pendingChild = {child, status: child.status, retry: child.retry};
    }
  };
  retainChild(recordFailure);
  const status = () => Object.freeze({
    pending,
    errors: Object.freeze([...errors]),
  });
  const update = () => {
    const current = status();
    failure.cleanupPending = current.pending;
    failure.cleanupErrors = current.errors;
    return current;
  };
  failure.cleanupHandle = Object.freeze({
    status,
    retry() {
      if (retrying !== undefined) return retrying;
      // Install the shared flight before invoking either port. Only this loop
      // may advance the retained cursor; a later flight resumes after failure.
      retrying = Promise.resolve().then(async () => {
        while (true) {
          const action = control.deliveryRecordRetryAction(
            nextRecord, records.length,
          );
          if (action === 'finished') {
            pending = false;
            break;
          }
          if (action !== 'append_next_record') {
            fail('InvalidResultDeliveryRecordRetry');
          }
          try {
            if (pendingChild !== undefined) {
              const {child, status, retry} = pendingChild;
              if (typeof status !== 'function' || typeof retry !== 'function') {
                fail('ResultDeliveryDurabilityPending');
              }
              let observation: unknown = await Reflect.apply(status, child, []);
              if (Object.getOwnPropertyDescriptor(observation ?? {}, 'pending')?.value !== false) {
                await Reflect.apply(retry, child, []);
                observation = await Reflect.apply(status, child, []);
              }
              if (Object.getOwnPropertyDescriptor(observation ?? {}, 'pending')?.value !== false) {
                fail('ResultDeliveryDurabilityPending');
              }
              pendingChild = undefined;
            }
            await appendRecord(records[nextRecord]);
            nextRecord++;
          } catch (error) {
            if (pendingChild === undefined) retainChild(error);
            retainFirstAndLatestCleanupError(errors, error);
            break;
          }
        }
        pending = nextRecord < records.length;
        return update();
      }).finally(() => { retrying = undefined; });
      return retrying;
    },
  });
  update();
  return failure;
}

function pendingTerminalFailure(
  reason: unknown, store: Store, control: Control, terminal: PublicationContract, recordFailure: unknown,
) {
  return pendingRecordFailure(
    'ResultDeliveryFailed', reason, store, control, [terminal], recordFailure,
  );
}

async function finishSink(sink: Sink, signal?: AbortSignal) {
  let result: Readonly<{confirmed: unknown}> | null | undefined;
  try { result = await sink.finish(signal) as typeof result; }
  catch (cause) {
    fail('ResultDeliverySinkCompletionFailed', cause);
  }
  if (!exactKeys(result, ['confirmed']) || result!.confirmed !== true) {
    fail('ResultDeliverySinkCompletionUnknown');
  }
}

export async function deliverPublishedResult(
  options: DeliveryOptions, resolvedPublication?: SelectedPublication, workspace?: Workspace,
) {
  validateRequest(options);
  validateStore(options.store);
  validateControl(options.control);
  const {store, control, indexKey, grant, resultName, format, attemptId,
    limits, frameLimits, now, sink, createDigest, authorize, signal} = options;
  // Existing delivery-local state identifies actual application output
  // callbacks, not internal awaits or another public authorization frame.
  let sinkCallbackCount = 0;
  const readDemand = workspace?.metadata;
  const demandArgument: [ReadDemand?] = readDemand === undefined ? [] : [readDemand];
  const appendCompletion = store.appendDeliveryCompletion;
  if (appendCompletion !== undefined && typeof appendCompletion !== 'function') {
    fail('InvalidResultDeliveryStore');
  }
  const beginAttempt = store.beginDeliveryAttempt;
  if (beginAttempt !== undefined && typeof beginAttempt !== 'function') {
    fail('InvalidResultDeliveryStore');
  }
  // The access owner has already read these immutable typed contracts. This
  // operation-local handoff is neither a read grant nor a cross-call cache.
  // Capture it before the current-head await and preserve the generic path
  // for callers that have not resolved a publication in this operation.
  let retainedIndex, retainedManifest, indexCid, manifestCid;
  if (resolvedPublication !== undefined) {
    if (!exactKeys(resolvedPublication, ['store', 'control', 'index', 'manifest']) ||
        resolvedPublication.store !== store || resolvedPublication.control !== control ||
        !contractShape(resolvedPublication.index) ||
        !contractShape(resolvedPublication.manifest) ||
        resolvedPublication.index.name !== 'public_index_entry' ||
        resolvedPublication.manifest.name !== 'result_manifest' ||
        !Object.isFrozen(resolvedPublication.index) ||
        !Object.isFrozen(resolvedPublication.manifest)) {
      fail('InvalidResultDeliveryRequest');
    }
    retainedIndex = resolvedPublication.index;
    retainedManifest = resolvedPublication.manifest;
    indexCid = retainedIndex.identity;
    manifestCid = retainedManifest.identity;
  }
  signal?.throwIfAborted();

  const entry = await store.confirmCommittedIndex(indexKey, ...demandArgument);
  if (entry === undefined) fail('ResultDeliveryDenied');
  if (retainedIndex !== undefined &&
      (entry.public_index_entry_cid !== indexCid ||
       entry.result_manifest_cid !== manifestCid)) fail('ResultDeliveryDenied');
  const index = retainedIndex ?? await store.readPublicationContract(
    entry.public_index_entry_cid, 'public_index_entry', ...demandArgument,
  );
  const manifest = retainedManifest ?? await store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest', ...demandArgument,
  );
  const requestedAt = trustedNow(now);
  const authorizationFacts = Object.freeze({
    index,
    manifest,
    grant,
    resultName,
    format,
    attemptId,
  });
  await requireCurrentAuthorization(authorize, {
    ...authorizationFacts,
    stage: 'attempt',
    observedAt: requestedAt,
  }, sinkCallbackCount);
  const proposed = control.issueDeliveryAttempt(
    index,
    manifest,
    grant,
    {resultName, format, attemptId, requestedAt},
    limits,
  );
  const original = typeof control.captureIssuedDeliveryAttempt === 'function'
    ? control.captureIssuedDeliveryAttempt(proposed, index, manifest, grant, limits)
    : undefined;
  // The same issued attempt and initial state can become durable together.
  // No sink or material reader runs before the physical owner returns.
  const initialStreaming = beginAttempt === undefined || original === undefined ? undefined :
    control.issueDeliveryRecord(proposed, undefined, {
      state: 'streaming', confirmedByteCount: 0, exposure: 'exact',
      possibleUnconfirmedMaxBytes: undefined, deliveredSha256: undefined,
      receipt: undefined, failureCid: undefined, observedAt: requestedAt,
      cleanupOwnerCids: [],
    }, limits);
  const admitted: AttemptSelection = initialStreaming === undefined ? await store.createDeliveryAttempt(
    proposed.wire, grant.wire, original,
  ) : await Reflect.apply(beginAttempt!, store, [original, initialStreaming]);
  const attempt = selectDeliveryAttempt(control, admitted, proposed, index,
    manifest, grant, {resultName, format, attemptId}, limits, original);
  if (!admitted.created) {
    const existing = await store.latestDeliveryRecordContract(
      attempt.identity,
    );
    // Another caller may own the first record commit. Absence is not authority
    // to start a second stream or consume another grant use.
    if (existing === undefined) fail('ResultDeliveryAttemptUnresolved');
    if (existing !== undefined) {
      const action = control.existingDeliveryAttemptAction(existing);
      const value = JSON.parse(existing.wire) as RecordedReceipt;
      if (action === 'confirm_succeeded_record') {
        try { await store.confirmDeliveryRecord(existing.wire); }
        catch (recordFailure) {
          throw pendingRecordFailure(
            'ResultDeliveryDurabilityPending',
            recordFailure,
            store,
            control,
            [existing],
            recordFailure,
          );
        }
        await requireCurrentAuthorization(authorize, {
          ...authorizationFacts,
          attempt,
          stage: 'receipt',
          observedAt: trustedNow(now),
        }, sinkCallbackCount);
        const receipt = await store.readPublicationContract(
          value.result_delivery_receipt_cid,
          'result_delivery_receipt',
        );
        return Object.freeze({
          attempt,
          record: existing,
          receipt,
          byteCount: value.confirmed_byte_count,
          sha256: value.delivered_sha256,
          idempotent: true,
        });
      }
      if (action === 'reject_unresolved_attempt') {
        fail('ResultDeliveryAttemptUnresolved');
      }
      if (action === 'reject_terminal_attempt') {
        fail('ResultDeliveryAttemptTerminal');
      }
      fail('InvalidResultDeliveryAttemptState');
    }
  }

  let streaming: PublicationContract | undefined;
  let ownsStreaming = false;
  let confirmedByteCount = 0;
  let writeFailure: SinkWriteFailure | undefined;
  try {
    streaming = initialStreaming ?? control.issueDeliveryRecord(attempt, undefined, {
      state: 'streaming',
      confirmedByteCount: 0,
      exposure: 'exact',
      possibleUnconfirmedMaxBytes: undefined,
      deliveredSha256: undefined,
      receipt: undefined,
      failureCid: undefined,
      observedAt: trustedNow(now),
      cleanupOwnerCids: [],
    }, limits);
    try {
      if (initialStreaming === undefined) await store.appendDeliveryRecord(streaming.wire);
    }
    catch (recordFailure) {
      const terminal = control.issueDeliveryRecord(attempt, streaming, {
        state: 'failed',
        confirmedByteCount: 0,
        exposure: 'exact',
        possibleUnconfirmedMaxBytes: undefined,
        deliveredSha256: undefined,
        receipt: undefined,
        failureCid: undefined,
        observedAt: trustedNow(now),
        cleanupOwnerCids: [],
      }, limits);
      throw pendingRecordFailure(
        'ResultDeliveryFailed',
        recordFailure,
        store,
        control,
        [streaming, terminal],
        recordFailure,
      );
    }
    ownsStreaming = true;

    const resultDefinitionCid = control.deliveryResultDefinitionCid(
      manifest, attempt,
    );
    const digest = createDigest();
    if (digest === null || typeof digest !== 'object' ||
        typeof digest.update !== 'function' ||
        typeof digest.finish !== 'function') {
      fail('InvalidResultDeliveryDigest');
    }
    const encoder = new TextEncoder();
    const write = async (text: unknown) => {
      if (typeof text !== 'string') fail('InvalidResultDeliveryChunk');
      const bytes = encoder.encode(text);
      if (bytes.byteLength === 0) return;
      const observedAt = trustedNow(now);
      if (!control.resultReadGrantValidAt(grant, observedAt)) {
        fail('ResultDeliveryGrantExpired');
      }
      if (!control.resultReadGrantAllowsBytes(
        grant, confirmedByteCount + bytes.byteLength,
      )) {
        fail('ResultDeliveryByteLimit');
      }
      await requireCurrentAuthorization(authorize, {
        ...authorizationFacts,
        attempt,
        stage: 'write',
        observedAt,
        confirmedByteCount,
        nextByteCount: confirmedByteCount + bytes.byteLength,
      }, sinkCallbackCount);
      const dispatchAt = trustedNow(now);
      if (!control.resultReadGrantValidAt(grant, dispatchAt)) {
        fail('ResultDeliveryGrantExpired');
      }
      signal?.throwIfAborted();
      let result: SinkObservation;
      sinkCallbackCount++;
      try { result = await sink.write(bytes, signal) as SinkObservation; }
      catch (reason) {
        writeFailure = sinkFailure(reason, bytes.byteLength);
        confirmedByteCount += writeFailure.confirmedBytes;
        throw writeFailure;
      }
      if (!exactKeys(result, ['confirmedBytes']) ||
          result!.confirmedBytes !== bytes.byteLength) {
        writeFailure = new SinkWriteFailure(
          new ResultDeliveryError('InvalidResultDeliverySinkResult'),
          Number.isSafeInteger(result?.confirmedBytes) &&
            result!.confirmedBytes >= 0 &&
            result!.confirmedBytes <= bytes.byteLength
            ? result!.confirmedBytes : 0,
          'unknown_additional',
          bytes.byteLength -
            (Number.isSafeInteger(result?.confirmedBytes) &&
              result!.confirmedBytes >= 0 &&
              result!.confirmedBytes <= bytes.byteLength
              ? result!.confirmedBytes : 0),
        );
        confirmedByteCount += writeFailure.confirmedBytes;
        throw writeFailure;
      }
      digest.update(bytes);
      confirmedByteCount += bytes.byteLength;
    };

    await store.withCommittedResultRows(
      indexKey,
      resultDefinitionCid,
      authorization =>
        authorization.resultDefinitionCid === resultDefinitionCid,
      frameLimits,
      async (metadata, readRows) => {
        await requireCurrentAuthorization(authorize, {
          ...authorizationFacts,
          attempt,
          stage: 'read',
          observedAt: trustedNow(now),
          durableResultBindingCid: metadata.durableResultBindingCid,
          logicalResultCid: metadata.logicalResultCid,
          resultSchemaCid: metadata.resultSchemaCid,
          rowCount: metadata.rowCount,
          payloadBytes: metadata.payloadBytes,
        }, sinkCallbackCount);
        let window = workspace?.prepare(metadata);
        if (window !== undefined && (!Number.isSafeInteger(window) || window < 1 ||
            window > frameLimits.maxFrameBytes || window > limits.maxWireBytes)) {
          fail('InvalidResultDeliveryWorkspace');
        }
        const serializer = control.prepareResultDeliverySerializer(
          format,
          metadata.resultSchemaWire,
          metadata.resultFields,
          limits,
        );
        workspace?.serializer(serializer);
        await write(control.beginResultDelivery(serializer));
        if (workspace === undefined) {
          // Independent raw/manual services retain their original one-row
          // path. A failed installed resource claim never reaches this branch.
          await readRows(row => write(control.nextResultDeliveryRow(serializer, row)));
        } else {
          let staged = '', stagedBytes = 0, rowUnits = 0;
          const flush = async () => {
            if (stagedBytes === 0) return;
            const text = staged;
            staged = ''; stagedBytes = 0;
            // The original write owns current authority, grant/expiry/bytes,
            // cancellation, sink-confirmed progress and each callback count.
            await write(text);
          };
          try {
            await readRows(async row => {
              signal?.throwIfAborted();
              if (row.length > rowUnits) {
                await flush();
                const admitted = workspace.row(row.length);
                if (!Number.isSafeInteger(admitted?.units) || admitted.units < row.length ||
                    !Number.isSafeInteger(admitted.window) || admitted.window < 1 ||
                    admitted.window > window!) fail('InvalidResultDeliveryWorkspace');
                rowUnits = admitted.units; window = admitted.window;
              }
              // Equal-length rows may have different node geometry. Fund the
              // SAME complete raw row before the existing JSON/canonical parse.
              // The complete-row phase retains the current staged window;
              // only the flushed physical-frame phase may shrink that window.
              const admitted = await workspace.row(row);
              if (!Number.isSafeInteger(admitted?.units) || admitted.units < row.length ||
                  !Number.isSafeInteger(admitted.window) || admitted.window < 1 ||
                  admitted.window > window!) fail('InvalidResultDeliveryWorkspace');
              rowUnits = admitted.units; window = admitted.window;
              const text = control.nextResultDeliveryRow(serializer, row);
              const bytes = encoder.encode(text).byteLength;
              if (bytes > window!) {
                await flush();
                await write(text);
              } else {
                if (bytes > window! - stagedBytes) await flush();
                staged += text; stagedBytes += bytes;
              }
            }, async needed => {
              await flush();
              const admitted = workspace.row(needed);
              if (!Number.isSafeInteger(admitted?.units) || admitted.units < needed ||
                  !Number.isSafeInteger(admitted.window) || admitted.window < 1 ||
                  admitted.window > window!) fail('InvalidResultDeliveryWorkspace');
              rowUnits = admitted.units; window = admitted.window;
              return admitted.units;
            });
            await flush();
          } finally { staged = ''; stagedBytes = 0; }
        }
        await write(control.finishResultDelivery(serializer));
      },
      control,
      attempt.identity,
      ...demandArgument,
    );
    const finishedAt = trustedNow(now);
    await requireCurrentAuthorization(authorize, {
      ...authorizationFacts,
      attempt,
      stage: 'finish',
      observedAt: finishedAt,
      confirmedByteCount,
    }, sinkCallbackCount);
    signal?.throwIfAborted();
    sinkCallbackCount++;
    await finishSink(sink, signal);
    const committedAt = trustedNow(now);
    if (!control.resultReadGrantValidAt(grant, committedAt)) {
      fail('ResultDeliveryGrantExpired');
    }
    await requireCurrentAuthorization(authorize, {
      ...authorizationFacts,
      attempt,
      stage: 'receipt',
      observedAt: committedAt,
      confirmedByteCount,
    }, sinkCallbackCount);
    const deliveredSha256 = await digest.finish();
    if (!digestPattern.test(deliveredSha256)) {
      fail('InvalidResultDeliveryDigest');
    }
    const receipt = control.issueResultDeliveryReceipt(
      index,
      manifest,
      grant,
      attempt,
      {byteCount: confirmedByteCount, sha256: deliveredSha256},
      limits,
    );
    if (appendCompletion === undefined) {
      await store.putPublicationContract(receipt.name, receipt.wire);
    }
    const succeeded = control.issueDeliveryRecord(attempt, streaming, {
      state: 'succeeded',
      confirmedByteCount,
      exposure: 'exact',
      possibleUnconfirmedMaxBytes: undefined,
      deliveredSha256,
      receipt,
      failureCid: undefined,
      observedAt: committedAt,
      cleanupOwnerCids: [],
    }, limits);
    const appendSucceeded = appendCompletion === undefined ? undefined : (record: PublicationContract) =>
      Reflect.apply(appendCompletion, store, [attempt, receipt, record]);
    try {
      if (appendSucceeded === undefined) await appendExactRecord(store, succeeded);
      else await appendSucceeded(succeeded);
    }
    catch (recordFailure) {
      throw pendingRecordFailure(
        'ResultDeliveryDurabilityPending',
        recordFailure,
        store,
        control,
        [succeeded],
        recordFailure,
        appendSucceeded,
      );
    }
    return Object.freeze({
      attempt,
      record: succeeded,
      receipt,
      byteCount: confirmedByteCount,
      sha256: deliveredSha256,
      idempotent: false,
    });
  } catch (reason) {
    if (reason instanceof DeliveryRecordDurabilityFailure) throw reason;
    if (!ownsStreaming) throw reason;
    const terminalAction = control.deliveryFailureTerminalAction(
      signal?.aborted === true,
    );
    if (terminalAction !== 'failed' && terminalAction !== 'cancelled') {
      fail('InvalidResultDeliveryTerminalAction');
    }
    const terminal = control.issueDeliveryRecord(attempt, streaming, {
      state: terminalAction,
      confirmedByteCount,
      exposure: writeFailure?.exposure ?? 'exact',
      possibleUnconfirmedMaxBytes:
        writeFailure?.possibleUnconfirmedMaxBytes,
      deliveredSha256: undefined,
      receipt: undefined,
      failureCid: undefined,
      observedAt: trustedNow(now),
      cleanupOwnerCids: [],
    }, limits);
    try { await appendExactRecord(store, terminal); }
    catch (recordFailure) {
      throw pendingTerminalFailure(
        reason, store, control, terminal, recordFailure,
      );
    }
    throw reason;
  }
}
