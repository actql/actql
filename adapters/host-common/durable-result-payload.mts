import {retainFirstAndLatestCleanupError} from './managed-failure.mjs';
// Physical adapter for one MoonBit-owned canonical CompletedOutput export.
// It streams batches directly to an installed durable Store. Logical Result
// identity, Artifact admission, publication commit, and retention remain
// separate common-core decisions.

import type {publicationAction} from './publication-action.mjs';
import type {outputLimitFields, resultOutputLimitFields} from './result-output-limits.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type CommonObject = Extract<SynchronousRuntimeData, object>;
type ExportHandle = CommonObject;
type PayloadLimits = Readonly<Record<typeof outputLimitFields[number], number>>;
type ResultLimits = Readonly<Record<typeof resultOutputLimitFields[number], number>>;
type PayloadIdentity = Readonly<{
  orderedRowsCid: string;
  logicalRelationCid: string;
  resultSchemaCid: string;
  resultSchemaWire: string;
  resultFields: readonly string[];
  codecContractCid: string;
  bytes: number;
  nodes: number;
  rows: number;
  schemaBytes: number;
  schemaNodes: number;
  schemaFields: number;
}>;
type CleanupStatus = Readonly<{pending: boolean; errors?: readonly unknown[]}>;
type CleanupHandle = Readonly<{status(): CleanupStatus; retry(): Awaitable<unknown>}>;
type PreparedOwner = CleanupHandle & Readonly<{release(): Awaitable<unknown>}>;
type CleanupOwner = Readonly<{pending(): boolean; retry?(): Awaitable<unknown>}>;
type Physical = Readonly<{cid: string; bytes: number; created: boolean}>;
type PreparedSchema = Readonly<{semanticCid: string; physical: Physical; created: boolean; prepared: PreparedOwner}>;
type ObjectWriter = Readonly<{
  append(batch: string): Awaitable<unknown>;
  seal(expectedCid: string): Awaitable<Physical & Readonly<{prepared?: PreparedOwner}>>;
  cancel(): Awaitable<unknown>;
  status(): Readonly<{reservationHeld?: boolean; custodyPending?: boolean}>;
}>;
type PayloadStore = Readonly<{
  createObjectWriter(maxBytes: number): ObjectWriter;
  createPreparedObjectWriter?(maxBytes: number): ObjectWriter;
  putPreparedResultSchema?(wire: string, semanticCid: string, runDefinitionCid: string): Awaitable<PreparedSchema>;
  storeAuthorityCid?: string;
}>;
type IssuedEvidence = Readonly<{derivation: CommonObject; ordering: CommonObject}>;
type ResultPublicationEvidence = IssuedEvidence & Readonly<{artifact: CommonObject; snapshot: CommonObject}>;
type CleanupControl = Readonly<{
  cleanupOwnerAction(currentOwner: number, ownerCount: number, statusChecked: boolean,
    pending: boolean, retryAvailable: boolean, retryAttempted: boolean): ReturnType<typeof publicationAction<'cleanupOwner'>>;
}>;
type PayloadControl = CleanupControl & Readonly<{
  begin(output: unknown, limits: PayloadLimits): ExportHandle;
  next(handle: ExportHandle): string | undefined;
  finish(handle: ExportHandle): string;
  identity(handle: ExportHandle): PayloadIdentity;
  cancel(handle: ExportHandle): SynchronousRuntimeData;
  payloadFailureAction(writerExists: boolean, sealed: boolean, writerCancelAttempted: boolean,
    preparedPending: boolean, preparedReleaseAttempted: boolean, exportExists: boolean,
    exportReleased: boolean, exportCancelAttempted: boolean): ReturnType<typeof publicationAction<'durablePayloadFailure'>>;
}>;
type ResultControl = PayloadControl & Readonly<{
  beginResult(host: object, result: number, limits: ResultLimits, output?: unknown,
    transformation?: unknown, signal?: AbortSignal, progress?: unknown): Awaitable<ExportHandle>;
}>;
type PublicationResultControl = ResultControl & Readonly<{
  issueResultEvidence(handle: ExportHandle, context: unknown, limits: unknown): IssuedEvidence;
}>;
type DurableBindingContracts = Readonly<{
  runDefinition: Readonly<{identity: string}>;
  definition: unknown;
  invocation: unknown;
  artifact: CommonObject;
  ordering: CommonObject;
  retention: unknown;
}>;
type ResultPhysicalFacts = Readonly<{
  codecContractCid: string;
  resultFields: readonly string[];
  resultSchemaWire: string;
  materialGenerationCid: string;
  storeAuthorityCid: string | undefined;
  rowCount: number;
  byteCount: number;
  physicalSha256: string;
}>;
type PublicationControl = Readonly<{
  issueResultArtifact(handle: ExportHandle, invocation: unknown, retention: unknown, limits: unknown): CommonObject;
  admitCompletedResultSnapshot(handle: ExportHandle, limits: ResultLimits, signal?: AbortSignal, resource?: unknown): Awaitable<CommonObject>;
  issueDurableResultBinding(contracts: DurableBindingContracts, facts: ResultPhysicalFacts, limits: unknown): CommonObject;
}>;
type PublicationOptions = Readonly<{
  control: PublicationControl;
  runDefinition: DurableBindingContracts['runDefinition'];
  definition: unknown;
  invocation: unknown;
  retention: unknown;
  evidenceContext: unknown;
  limits: unknown;
}>;
type BeginResult = (host: object, result: number, limits: ResultLimits) => Awaitable<ExportHandle>;
type ReadBatch = (handle: ExportHandle, signal?: AbortSignal) => Awaitable<string | undefined>;
type IssueEvidence = (handle: ExportHandle) => Awaitable<ResultPublicationEvidence>;
type IssuePhysicalEvidence = (physical: Physical, orderedRows: PayloadIdentity, evidence: ResultPublicationEvidence) => CommonObject;

export class DurableResultPayloadError extends Error {
  declare code: string;
  declare primaryFailure?: unknown;
  declare cleanupPending?: boolean;
  declare cleanupErrors?: readonly unknown[];
  declare cleanupHandle?: CleanupHandle;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw new DurableResultPayloadError(code, cause);
};

function validStore(store: unknown): store is PayloadStore {
  return store !== null && typeof store === 'object' &&
    typeof (store as PayloadStore).createObjectWriter === 'function';
}

function validControl(control: unknown): control is PayloadControl {
  return control !== null && typeof control === 'object' &&
    ['begin', 'next', 'finish', 'identity', 'cancel',
      'payloadFailureAction', 'cleanupOwnerAction']
      .every(name => typeof (control as PayloadControl)[name as keyof PayloadControl] === 'function');
}

function validResultControl(control: unknown): control is ResultControl {
  return validControl(control) && typeof (control as ResultControl).beginResult === 'function';
}

function validIdentity(value: PayloadIdentity) {
  return value !== null && typeof value === 'object' &&
    /^sha256:[0-9a-f]{64}$/u.test(value.orderedRowsCid) &&
    /^sha256:[0-9a-f]{64}$/u.test(value.logicalRelationCid) &&
    /^sha256:[0-9a-f]{64}$/u.test(value.resultSchemaCid) &&
    typeof value.resultSchemaWire === 'string' &&
    Array.isArray(value.resultFields) && value.resultFields.length > 0 &&
    new Set(value.resultFields).size === value.resultFields.length &&
    value.resultFields.every(field =>
      typeof field === 'string' && field.length > 0) &&
    /^sha256:[0-9a-f]{64}$/u.test(value.codecContractCid) &&
    (['bytes', 'nodes', 'rows'] as const).every(name =>
      Number.isSafeInteger(value[name]) && value[name] >= 0) &&
    (['schemaBytes', 'schemaNodes', 'schemaFields'] as const).every(name =>
      Number.isSafeInteger(value[name]) && value[name] >= 0) &&
    new TextEncoder().encode(value.resultSchemaWire).byteLength ===
      value.schemaBytes;
}

function payloadFailure(reason: unknown, cleanupErrors: unknown[], cleanupOwners: readonly CleanupOwner[], control: CleanupControl) {
  const initialErrorCount = cleanupErrors.length;
  // The caller's throwable can be a primitive or an immutable Error. Keep all
  // cleanup metadata on an envelope owned by this adapter.
  const failure = new DurableResultPayloadError(
    'DurableResultPayloadFailed', reason,
  );
  failure.primaryFailure = reason;
  const status = () => Object.freeze({
    pending: cleanupOwners.some(owner => owner.pending()),
    errors: Object.freeze([...cleanupErrors]),
  });
  const update = () => {
    const current = status();
    failure.cleanupPending = current.pending;
    failure.cleanupErrors = current.errors;
    return current;
  };
  if (status().pending) {
    failure.cleanupHandle = Object.freeze({
      status,
      async retry() {
        let currentOwner = 0;
        let statusChecked = false;
        let pending = false;
        let retryAvailable = false;
        let retryAttempted = false;
        while (true) {
          const action = control.cleanupOwnerAction(
            currentOwner,
            cleanupOwners.length,
            statusChecked,
            pending,
            retryAvailable,
            retryAttempted,
          );
          if (action === 'inspect') {
            pending = cleanupOwners[currentOwner].pending();
            retryAvailable = typeof cleanupOwners[currentOwner].retry ===
              'function';
            statusChecked = true;
            continue;
          }
          if (action === 'retry') {
            retryAttempted = true;
            try { await cleanupOwners[currentOwner].retry!(); }
            catch (error) { retainFirstAndLatestCleanupError(cleanupErrors, error, initialErrorCount); }
            continue;
          }
          if (action === 'advance') {
            currentOwner++;
            statusChecked = false;
            pending = false;
            retryAvailable = false;
            retryAttempted = false;
            continue;
          }
          if (action === 'finished') break;
          fail('InvalidDurableResultPayloadCleanupProgress');
        }
        return update();
      },
    });
  }
  update();
  return failure;
}

function preparedResultOwners(physical: PreparedOwner, schema: PreparedOwner) {
  const owners = [physical, schema];
  const status = () => Object.freeze({
    pending: owners.some(owner => owner.status().pending === true),
    errors: Object.freeze(owners.flatMap(owner =>
      owner.status().errors ?? [])),
  });
  const release = async () => {
    let changed = false;
    for (const owner of owners) {
      if (owner.status().pending !== true) continue;
      await owner.release();
      changed = true;
    }
    return changed;
  };
  return Object.freeze({
    status,
    release,
    async retry() {
      await release();
      return status();
    },
  });
}

/// Stream an exact completed output without materializing a whole row array in
/// JavaScript. The ordered-row receipt and physical object identity are kept as
/// distinct typed fields even when this codec makes their SHA-256 values equal.
export async function storeCompletedOutputPayload(
  store: unknown, control: unknown, output: unknown, limits: PayloadLimits, signal?: AbortSignal,
) {
  if (!validStore(store) || !validControl(control)) {
    fail('InvalidDurableResultPayloadAdapter');
  }
  return storeCompletedPayload(
    store, control, () => control.begin(output, limits), limits, signal,
  );
}

/// Stream one exact checked Named Result from the common Host graph. The
/// adapter receives an index only; projection, ordering, and identity remain
/// bound to the opaque occurrence retained by the MoonBit runtime.
export async function storeCompletedResultPayload(
  store: unknown, control: unknown, host: object, result: number, limits: ResultLimits, signal?: AbortSignal,
) {
  if (!validStore(store) || !validResultControl(control) ||
      !Number.isSafeInteger(result) || result < 0) {
    fail('InvalidDurableResultPayloadAdapter');
  }
  return storeCompletedPayload(
    store,
    control,
    () => control.beginResult(host, result, limits,
      undefined, undefined, signal),
    limits,
    signal,
  );
}

/// Store and issue evidence for one exact Named Result export. Evidence is
/// issued before the physical object is sealed, so a failed issuance cannot
/// strand an otherwise unreferenced durable payload.
export async function storeCompletedResultPublicationPayload(
  store: unknown,
  control: PublicationResultControl,
  host: object,
  result: number,
  limits: ResultLimits,
  publication: PublicationOptions,
  signal?: AbortSignal,
  beginResult?: BeginResult,
  readBatch?: ReadBatch,
  publicationResource?: unknown,
) {
  if (!validStore(store) ||
      typeof store.createPreparedObjectWriter !== 'function' ||
      typeof store.putPreparedResultSchema !== 'function' ||
      !validResultControl(control) ||
      typeof control.issueResultEvidence !== 'function' ||
      publication === null || typeof publication !== 'object' ||
      typeof publication.control?.issueResultArtifact !== 'function' ||
      typeof publication.control?.issueDurableResultBinding !== 'function' ||
      typeof publication.control?.admitCompletedResultSnapshot !==
        'function' ||
      !/^sha256:[0-9a-f]{64}$/u.test(
        publication.runDefinition?.identity!,
      ) ||
      !Number.isSafeInteger(result) || result < 0) {
    fail('InvalidDurableResultPayloadAdapter');
  }
  return storeCompletedPayload(
    store,
    control,
    () => typeof beginResult === 'function'
      ? beginResult(host, result, limits)
      : control.beginResult(host, result, limits,
        undefined, undefined, signal),
    limits,
    signal,
    async handle => {
      const evidence = control.issueResultEvidence(
        handle, publication.evidenceContext, publication.limits,
      );
      const artifact = publication.control.issueResultArtifact(
        handle,
        publication.invocation,
        publication.retention,
        publication.limits,
      );
      // Snapshot encoding and its captured relation wrapper consume the same
      // original Result output envelope, not small metadata-contract limits.
      const snapshot = await publication.control.admitCompletedResultSnapshot(
        handle,
        limits,
        signal,
        publicationResource,
      );
      return Object.freeze({...evidence, artifact, snapshot});
    },
    (physical, orderedRows, evidence) =>
      publication.control.issueDurableResultBinding({
        runDefinition: publication.runDefinition,
        definition: publication.definition,
        invocation: publication.invocation,
        artifact: evidence.artifact,
        ordering: evidence.ordering,
        retention: publication.retention,
      }, {
        codecContractCid: orderedRows.codecContractCid,
        resultFields: orderedRows.resultFields,
        resultSchemaWire: orderedRows.resultSchemaWire,
        materialGenerationCid: physical.cid,
        storeAuthorityCid: store.storeAuthorityCid,
        rowCount: orderedRows.rows,
        byteCount: physical.bytes,
        physicalSha256: physical.cid.slice('sha256:'.length),
      }, publication.limits),
    true,
    publication.runDefinition.identity,
    readBatch,
  );
}

async function storeCompletedPayload(
  store: PayloadStore,
  control: PayloadControl,
  beginExport: () => Awaitable<ExportHandle>,
  limits: PayloadLimits,
  signal?: AbortSignal,
  issueEvidence?: IssueEvidence,
  issuePhysicalEvidence?: IssuePhysicalEvidence,
  preparePhysical = false,
  schemaRunDefinitionCid?: string,
  readBatch?: ReadBatch,
) {
  signal?.throwIfAborted();
  let exportHandle: ExportHandle | undefined;
  let writer: ObjectWriter | undefined;
  let prepared: PreparedOwner | undefined;
  let schema: PreparedSchema | undefined;
  let sealed = false;
  let exportReleased = false;
  try {
    exportHandle = await beginExport();
    writer = preparePhysical
      ? store.createPreparedObjectWriter!(limits.maxWireBytes)
      : store.createObjectWriter(limits.maxWireBytes);
    for (;;) {
      signal?.throwIfAborted();
      const part = readBatch === undefined
        ? control.next(exportHandle)
        : await readBatch(exportHandle, signal);
      if (part === undefined) break;
      if (typeof part !== 'string') fail('InvalidDurableResultPayloadBatch');
      if (part.length !== 0) await writer.append(part);
    }
    signal?.throwIfAborted();
    const tail = control.finish(exportHandle);
    if (typeof tail !== 'string') fail('InvalidDurableResultPayloadBatch');
    if (tail.length !== 0) await writer.append(tail);
    signal?.throwIfAborted();
    const orderedRows = control.identity(exportHandle);
    if (!validIdentity(orderedRows)) {
      fail('InvalidDurableResultPayloadIdentity');
    }
    const publication = await issueEvidence?.(exportHandle);
    signal?.throwIfAborted();
    if (publication !== undefined) {
      schema = await store.putPreparedResultSchema!(
        orderedRows.resultSchemaWire,
        orderedRows.resultSchemaCid,
        schemaRunDefinitionCid!,
      );
      prepared = schema.prepared;
    }
    signal?.throwIfAborted();
    const sealedPhysical = await writer.seal(orderedRows.orderedRowsCid);
    if (schema !== undefined) {
      prepared = preparedResultOwners(sealedPhysical.prepared!, schema.prepared);
    } else {
      prepared = sealedPhysical.prepared;
    }
    const physical = Object.freeze({
      cid: sealedPhysical.cid,
      bytes: sealedPhysical.bytes,
      created: sealedPhysical.created,
    });
    sealed = true;
    if (physical.bytes !== orderedRows.bytes ||
        physical.cid !== orderedRows.orderedRowsCid) {
      fail('DurableResultPayloadIdentityMismatch');
    }
    const durableBinding = issuePhysicalEvidence?.(
      physical, orderedRows, publication!,
    );
    control.cancel(exportHandle!);
    exportReleased = true;
    return Object.freeze({
      physical: Object.freeze({...physical}),
      orderedRows: Object.freeze({...orderedRows}),
      ...(publication === undefined ? {} : {
        publication: Object.freeze({...publication, durableBinding}),
        schema: Object.freeze({
          semanticCid: schema!.semanticCid,
          physical: schema!.physical,
          created: schema!.created,
        }),
        physicalPrepared: sealedPhysical.prepared,
        prepared,
      }),
    });
  } catch (reason) {
    const cleanupErrors: unknown[] = [];
    const cleanupOwners: CleanupOwner[] = [];
    if ((reason as DurableResultPayloadError | null | undefined)?.cleanupPending === true &&
        (reason as DurableResultPayloadError).cleanupHandle !== undefined) {
      cleanupOwners.push(Object.freeze({
        pending: () => (reason as DurableResultPayloadError).cleanupHandle!.status().pending === true,
        retry: () => (reason as DurableResultPayloadError).cleanupHandle!.retry(),
      }));
    }
    let writerCancelAttempted = false;
    let preparedReleaseAttempted = false;
    let exportCancelAttempted = false;
    let preparedPending = false;
    if (prepared !== undefined) {
      try { preparedPending = prepared.status().pending === true; }
      catch (error) {
        cleanupErrors.push(error);
        preparedPending = true;
      }
    }
    while (true) {
      const action = control.payloadFailureAction(
        writer !== undefined,
        sealed,
        writerCancelAttempted,
        preparedPending,
        preparedReleaseAttempted,
        exportHandle !== undefined,
        exportReleased,
        exportCancelAttempted,
      );
      if (action === 'cancel_writer') {
        writerCancelAttempted = true;
        try { await writer!.cancel(); }
        catch (error) {
          cleanupErrors.push(error);
          cleanupOwners.push(Object.freeze({
            pending: () => writer!.status().reservationHeld === true ||
              writer!.status().custodyPending === true,
            retry: () => writer!.cancel(),
          }));
        }
        continue;
      }
      if (action === 'release_prepared') {
        preparedReleaseAttempted = true;
        try { await prepared!.release(); }
        catch (error) {
          cleanupErrors.push(error);
          cleanupOwners.push(Object.freeze({
            pending: () => prepared!.status().pending === true,
            retry: () => prepared!.retry(),
          }));
        }
        continue;
      }
      if (action === 'cancel_export') {
        exportCancelAttempted = true;
        try {
          control.cancel(exportHandle!);
          exportReleased = true;
        } catch (error) {
          cleanupErrors.push(error);
          cleanupOwners.push(Object.freeze({
            pending: () => !exportReleased,
            retry: async () => {
              control.cancel(exportHandle!);
              exportReleased = true;
            },
          }));
        }
        continue;
      }
      if (action === 'finished') break;
      fail('InvalidDurableResultPayloadFailureProgress');
    }
    throw payloadFailure(reason, cleanupErrors, cleanupOwners, control);
  }
}
