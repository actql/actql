import {randomUUID} from 'node:crypto';
import {performance} from 'node:perf_hooks';

import {AcquisitionOpenError, acquisitionOutcome} from '../host-common/acquisition-outcome.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';
import {encodeTypedResponseJson} from './typed-response-json-codec.mjs';

import type {createInstalledRowSourceCredentialSite} from './installed-row-source-credential-site.mjs';
import type {createInstalledRowSourceKeyedPreparation} from './installed-row-source-keyed-preparation.mjs';
import type {createInstalledRowSourceReadAuthority} from './installed-row-source-read-authority.mjs';

type RowRun = ReturnType<typeof startInstalledRowRun>;
type AcquisitionState = Parameters<RowRun['closeAfterFailure']>[0] & {started: boolean; closeFailed: boolean};
type TransportRecovery = NonNullable<Parameters<RowRun['closeAfterFailure']>[1]> & {close(): unknown};
type ReadAuthority = ReturnType<typeof createInstalledRowSourceReadAuthority>;
type CurrentPreparation = Parameters<ReadAuthority['currentRead']>[0];
type VerifyRead = () => ReturnType<ReadAuthority['currentRead']>;
type VerificationOptions = Parameters<ReturnType<typeof createInstalledRowSourceKeyedPreparation>['verifyKeyedRead']>[0];
type KeyedPreparation = VerificationOptions['preparedKeyed'];
type SourceAccess = NonNullable<VerificationOptions['sourceAccess']>;
type CredentialSite = Awaited<ReturnType<ReturnType<typeof createInstalledRowSourceCredentialSite>['openRowSourceCredentialSite']>>;
type KeyedSite = Pick<Extract<CredentialSite, {issueReadGrant: unknown}>,
  'connection' | 'admitCheckpointReadApproval' | 'issueReadGrant'>;
type Grant = ReturnType<KeyedSite['issueReadGrant']>;
type RowLimits = Readonly<{maxPageBytes: number; maxPages: number}>;
type Target = readonly [resource: string, ...columns: string[]];
type ContentBytes = Readonly<{
  bytes: Uint8Array;
  mediaType: string;
  contentCid: string;
  metadata?: unknown;
  observations?: unknown;
}>;
type ContentCapture = (input: ContentBytes & Readonly<{
  keyedAcquisition: unknown;
  request: unknown;
  readSubjectCid: string;
  verifyRead: VerifyRead;
  signal: AbortSignal;
}>) => unknown;
type ContentCandidate = Readonly<{capture?: unknown; referenceIssuer?: unknown}> | null | undefined;
type KeyedContent = Readonly<{capture: ContentCapture; referenceIssuer: unknown}>;
type KeyedPublication = Readonly<{
  activate(lookup: unknown, request: unknown): unknown;
  retainRawResponse(lookup: unknown, request: unknown, activation: unknown, bytes: Uint8Array): unknown;
  adopt(lookup: unknown, request: unknown, activation: unknown, capture: unknown, raw: unknown): void;
}>;
type OriginalKeyedReadInput = Readonly<{
  checkedOwner: unknown;
  keyedAcquisition: unknown;
  request: unknown;
  declaration: unknown;
  managedRun?: unknown;
  rowLimits: Readonly<{maxPageBytes: number; maxTextBytes: number; maxWork: number}>;
}>;
type ReadPagesInput = Readonly<{
  resource: string;
  columns: readonly string[];
  requestWire: string;
  operation: string;
  signal: AbortSignal;
  verifyRead: VerifyRead;
  retainRawResponse?(bytes: Uint8Array): Promise<void>;
  rowRun: Readonly<{acquisition: unknown; run: unknown; requestId: string; runInvocationCid: string;
    dispatchRequestCid: string; originalKeyedRead?: unknown}>;
  capturedResourcePath?(): Promise<string>;
  chargeVerification?(bytes: number): Promise<void>;
  captureContent?(input: ContentBytes): Promise<unknown>;
  beginRequest(bytes: Uint8Array): Promise<Grant & {useId: string}>;
  chargePage(bytes: Uint8Array): unknown;
  consumeObservation(charge: unknown): unknown;
  consumePage(rows: unknown, options?: Readonly<{charge?: unknown}>): ReturnType<RowRun['consumeKeyedPage']>;
}>;
type OpenKeyedOptions = {
  preparedProgram?: unknown;
  preparedEffect?: unknown;
  managedRun?: unknown;
  keyedAcquisition: unknown;
  request: unknown;
  ledger: unknown;
  signal?: AbortSignal;
  preparedKeyed?: KeyedPreparation;
  chargeVerification?: (bytes: number) => unknown;
  capturedResourcePath?: (verifyRead: VerifyRead, signal: AbortSignal) => Promise<string>;
  keyedContent?: KeyedContent;
  lookupPublication?: KeyedPublication;
  lookupOriginal?: unknown;
  sourceAccess?: SourceAccess;
};
type KeyedOwner = Readonly<{
  preparedProgram?: unknown;
  preparedEffect?: unknown;
  keyedAcquisition: unknown;
  access: SourceAccess;
}>;
type KeyedRuntime = Parameters<typeof startInstalledRowRun>[0]['moon'] & Readonly<{
  clientProgramRowContentReferenceIssuer(resourceIssuer: unknown, contentIssuer: unknown): unknown;
  clientProgramKeyedAcquisitionMatchesProgram(acquisition: unknown, program: unknown): boolean;
  clientProgramKeyedAcquisitionMatchesEffectProgram(acquisition: unknown, effect: unknown): boolean;
  clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition: unknown): unknown;
  clientProgramInstalledKeyedSourceReadCheckCurrent(read: unknown): unknown;
  clientProgramKeyedRowPrepareAcquisition(acquisition: unknown, request: unknown, declaration: unknown,
    maxPageBytes: number, maxTextBytes: number, maxWork: number): unknown;
  clientProgramInstalledKeyedSourceReadAcquisition(read: unknown): unknown;
  clientProgramKeyedRowTarget(acquisition: unknown): unknown;
  clientProgramKeyedRequestWire(request: unknown, maxBytes: number): unknown;
  clientProgramKeyedAcquisitionCoordinates(acquisition: unknown): readonly number[];
  clientProgramKeyedRowBegin(run: unknown, issuer: unknown): unknown;
  clientProgramKeyedRequestObserveAttempt(request: unknown, bytes: bigint, observedMs: bigint): unknown;
  clientProgramKeyedRequestRemainingMs(request: unknown, observedMs: bigint): unknown;
  clientProgramRowSourceChargePage(run: unknown, bytes: Uint8Array): unknown;
  clientProgramKeyedResponseObserve(request: unknown, rawBytes: bigint, decodedBytes: bigint, observedMs: bigint): unknown;
  clientProgramRowSourceConsumeObservationCharge(run: unknown, charge: unknown): unknown;
  clientProgramKeyedSourceResponseEncoding(request: unknown): string | undefined;
  clientProgramKeyedRequestFinishIO(request: unknown, observedMs: bigint): unknown;
  clientProgramKeyedRowCaptureRead(capture: unknown): unknown;
  clientProgramKeyedRowCaptureIdentity(capture: unknown): unknown;
  clientProgramKeyedLookupAcceptCapture(lookup: unknown, acquisition: unknown, request: unknown, capture: unknown): unknown;
  clientProgramKeyedRequestFailIO(request: unknown): void;
  clientProgramInstalledKeyedSourceReadRetire(read: unknown): unknown;
}>;

export function createInstalledRowSourceKeyedRead({originalReader, captureContent, referenceIssuer, moon, sourceRefs, text,
  prepareKeyedSourceRead, closeKeyedSourceRead, keyedPreparations, declaration, limits, physicalTarget, valueCid,
  keyedTransferBytes, keyedExecutionBytes, connectorRegistration, connectorRevision, bindingCid, currentRead, site,
  cid, operationBindings, readPages, sourceAccess}: Pick<ReadAuthority, 'currentRead'> & {
  originalReader?: object;
  captureContent?: ContentCapture;
  referenceIssuer: unknown;
  moon: KeyedRuntime;
  sourceRefs: ReadonlySet<string>;
  text(value: unknown): value is string;
  prepareKeyedSourceRead?: (input: OriginalKeyedReadInput) => unknown;
  closeKeyedSourceRead?: (read: unknown) => unknown;
  keyedPreparations: Pick<WeakMap<KeyedPreparation, KeyedOwner>, 'has' | 'get'>;
  declaration: unknown;
  limits: RowLimits;
  physicalTarget(resource: string, fields: readonly string[]): unknown;
  valueCid(value: unknown): string;
  keyedTransferBytes: bigint;
  keyedExecutionBytes: bigint;
  connectorRegistration: string;
  connectorRevision: string;
  bindingCid: string;
  site: KeyedSite;
  cid(value: unknown): string;
  operationBindings: ReadonlyMap<string, string>;
  readPages(input: ReadPagesInput): unknown;
  sourceAccess: SourceAccess;
}) {
  // One checked keyed occurrence, not whole-lookup completion. The enclosing
  // Host keeps the original left capture and all right captures until its
  // checked JOIN barrier has completed; this method issues no Source evidence.
  const selectedKeyedContent = (value: unknown) => {
    if (value === undefined) return undefined;
    const capture = (value as ContentCandidate)?.capture, issuer = (value as ContentCandidate)?.referenceIssuer;
    if (typeof capture !== 'function' || issuer === undefined || captureContent !== undefined) {
      fail('InvalidInstalledContentCapture');
    }
    // Select once before any await. Caller mutation cannot replace the Run's
    // capture or issuer between current authorization and row admission.
    return Object.freeze({capture: capture as ContentCapture, referenceIssuer: issuer});
  };
  async function openKeyed({preparedProgram, preparedEffect, managedRun, keyedAcquisition,
    request, ledger, signal, preparedKeyed, chargeVerification, capturedResourcePath,
    keyedContent, lookupPublication, lookupOriginal,
    sourceAccess: access = sourceAccess}: OpenKeyedOptions) {
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    const state: AcquisitionState = {started: false, closeFailed: false, recovery: undefined};
    let session: RowRun | undefined, lookupActivation: unknown, lookupRaw: unknown;
    let originalKeyedRead: unknown, originalClosed = prepareKeyedSourceRead === undefined;
    const closeOriginal = async () => {
      if (originalClosed) return;
      if (originalKeyedRead === undefined) return;
      const observed = await closeKeyedSourceRead!(originalKeyedRead);
      const pending = observed !== null && typeof observed === 'object'
        ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('InstalledSourceCleanupPending');
      }
      originalClosed = true;
    };
    let deadline: ReturnType<typeof setTimeout> | undefined;
    let responsePageActive = false;
    const budgetAbort = new AbortController();
    signal = signal === undefined ? budgetAbort.signal : AbortSignal.any([signal, budgetAbort.signal]);
    try {
      // Per-Run capture custody is selected by the original dispatch owner,
      // never stored on the shared installation. Its issuer admits only the
      // same held content returned by that owner for this exact lookup.
      keyedContent = selectedKeyedContent(keyedContent);
      const captureBytes = keyedContent?.capture ?? captureContent;
      // Content custody belongs to this Run, but the returned Resource still
      // belongs to the installed Source. Do not replace either authority or
      // fall back to the other domain after an issuer refuses a reference.
      const captureIssuer = keyedContent === undefined ? referenceIssuer
        : moon.clientProgramRowContentReferenceIssuer(referenceIssuer,
          keyedContent.referenceIssuer);
      signal?.throwIfAborted();
      if ((preparedProgram === undefined) === (preparedEffect === undefined) ||
          ledger === undefined || (preparedEffect === undefined
            ? moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition,
              preparedProgram)
            : moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition,
              preparedEffect)) !== true) {
        fail('InstalledSourceProgramMismatch');
      }
      const facts = checked(
        moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
      if (!Array.isArray(facts) || facts.length !== 6 ||
          !facts.every(text) || !sourceRefs.has(facts[0])) {
        fail('InstalledSourceEvidenceFactsUnavailable');
      }
      if (prepareKeyedSourceRead !== undefined) {
        if (preparedKeyed === undefined || !keyedPreparations.has(preparedKeyed) ||
            preparedEffect !== undefined && managedRun === undefined) fail('InstalledSourcePreparationMismatch');
        // The same installing Source retains its physical-child duty before
        // returning this Core original. Preserve it before current/getter use.
        originalKeyedRead = prepareKeyedSourceRead(Object.freeze({
          checkedOwner: preparedEffect ?? preparedProgram, keyedAcquisition, request, declaration,
          ...(managedRun === undefined ? {} : {managedRun}),
          rowLimits: Object.freeze({maxPageBytes: limits.maxPageBytes,
            maxTextBytes: limits.maxPageBytes, maxWork: 1000000})}));
        checked(moon.clientProgramInstalledKeyedSourceReadCheckCurrent(originalKeyedRead));
      }
      const acquisition = checked(originalKeyedRead === undefined
        ? moon.clientProgramKeyedRowPrepareAcquisition(keyedAcquisition, request,
          declaration, limits.maxPageBytes, limits.maxPageBytes, 1000000)
        : moon.clientProgramInstalledKeyedSourceReadAcquisition(originalKeyedRead));
      const [resource, ...columns] = checked(
        moon.clientProgramKeyedRowTarget(acquisition)) as Target;
      const physicalBinding = physicalTarget(resource, columns);
      const scope = preparedKeyed === undefined ? undefined : keyedPreparations.get(preparedKeyed);
      if (preparedKeyed !== undefined && (scope === undefined ||
          scope.preparedProgram !== preparedProgram || scope.preparedEffect !== preparedEffect ||
          scope.keyedAcquisition !== keyedAcquisition ||
          scope.access !== access || valueCid(physicalBinding) !== valueCid(preparedKeyed.physicalBinding))) {
        fail('InstalledSourcePreparationMismatch');
      }
      const nonce = randomUUID();
      const backingField = lookupPublication === undefined ? undefined
        : Object.getOwnPropertyDescriptor(lookupPublication, 'responseBackingReleased');
      if (backingField !== undefined && (!Object.hasOwn(backingField, 'value') ||
          typeof backingField.value !== 'function')) fail('ForeignOriginalKeyedRawResponse');
      const responseBackingReleased = backingField === undefined ? undefined
        : () => !responsePageActive && Reflect.apply(backingField.value, lookupPublication, []) === true;
      session = startInstalledRowRun({moon, acquisition, nonce, ledger,
        keyed: true, originalKeyedRead, responseBackingReleased,
        capacity: {transferBytes: keyedTransferBytes, executionBytes: keyedExecutionBytes}});
      const {run} = session;
      // Encode only under the common acquisition's workspace reservation.
      const requestWire = checked(
        moon.clientProgramKeyedRequestWire(request, limits.maxPageBytes)) as string;
      const readSubject = Object.freeze({version: 'actql-keyed-row-source-read/0.1',
        sourceFacts: [...facts],
        occurrence: [...moon.clientProgramKeyedAcquisitionCoordinates(keyedAcquisition)],
        request: JSON.parse(requestWire), physicalBinding,
        connectorRegistration, connectorRevision, bindingCid});
      const prepared = Object.freeze({...preparedKeyed, readSubjectCid: valueCid(readSubject), physicalBinding,
        readTuple: Object.freeze({connection: site.connection, resource,
          operation: 'read' as const})});
      const verifyRead = () => currentRead(prepared as CurrentPreparation, access, signal);
      const decision = await verifyRead();
      signal?.throwIfAborted();
      const granted = decision.basis === 'resumed_approval'
        ? site.admitCheckpointReadApproval(decision) : decision;
      const runInvocationCid = valueCid({version: 'actql-keyed-row-acquisition/0.1',
        readSubject, nonce});
      const dispatchRequestCid = cid({
        version: 'actql-keyed-row-acquisition-dispatch/0.1', runInvocationCid});
      checked(moon.clientProgramKeyedRowBegin(run, captureIssuer));
      const operation = operationBindings.get(resource)!;
      const grant = site.issueReadGrant({operation,
        decision: granted, resource, runInvocationCid, dispatchRequestCid,
        maxUses: limits.maxPages});
      const observedMs = () => BigInt(Math.floor(performance.now()));
      let sendIndex = 0;
      await readPages({resource, columns, requestWire, operation,
        signal, verifyRead,
        ...(lookupPublication === undefined ? {} : {retainRawResponse: async (bytes: Uint8Array) => {
          // The installed driver already brackets this awaited hook with the
          // SAME verifyRead/signal fences. Do not repeat its authorization I/O.
          signal?.throwIfAborted();
          if (lookupActivation === undefined || lookupRaw !== undefined) fail('ForeignOriginalKeyedRawResponse');
          lookupRaw = await lookupPublication.retainRawResponse(lookupOriginal, request, lookupActivation, bytes);
          signal?.throwIfAborted();
        }}),
        rowRun: Object.freeze({acquisition, run, requestId: nonce, runInvocationCid, dispatchRequestCid,
          ...(originalKeyedRead === undefined ? {} : {originalKeyedRead})}),
        capturedResourcePath: capturedResourcePath === undefined ? undefined : async () => {
          await verifyRead();
          signal?.throwIfAborted();
          if (state.started) fail('InstalledFileLocatorAfterSend');
          return await capturedResourcePath(verifyRead, signal);
        },
        chargeVerification: chargeVerification === undefined ? undefined : async bytes => {
          if (!Number.isSafeInteger(bytes) || bytes < 1 || bytes > 4096) {
            fail('InvalidKeyedVerificationObservation');
          }
          await verifyRead();
          signal?.throwIfAborted();
          if (!state.started) fail('InstalledContentCaptureBeforeSend');
          await chargeVerification(bytes);
        },
        // Host-selected capture receives original typed request/Source facts,
        // not a driver-selected request, target or permission. The callback
        // transfers actual verified bytes to the existing holding owner before
        // returning an issued envelope for this keyed row's ordinary admission.
        captureContent: captureBytes === undefined ? undefined : async bytes => {
          await verifyRead();
          signal?.throwIfAborted();
          if (!state.started) fail('InstalledContentCaptureBeforeSend');
          const content = await captureBytes({...bytes, keyedAcquisition,
            request, readSubjectCid: prepared.readSubjectCid, verifyRead, signal});
          await verifyRead();
          signal?.throwIfAborted();
          return content;
        },
        // The driver supplies the actual serialized request before each send.
        // Grants and lookup accounting share this boundary; returning from
        // readPages without an observed send cannot produce a capture.
        beginRequest: async body => {
          if (!(body instanceof Uint8Array)) fail('InvalidKeyedRequestObservation');
          await verifyRead();
          signal?.throwIfAborted();
          if (lookupPublication !== undefined) {
            if (lookupActivation !== undefined || sendIndex !== 0) fail('OriginalKeyedLookupAlreadyActivated');
            // The SAME current activation is durably indexed before this
            // attempt is consumed and before the driver can receive a grant.
            lookupActivation = lookupPublication.activate(lookupOriginal, request);
            await verifyRead();
            signal?.throwIfAborted();
          }
          checked(moon.clientProgramKeyedRequestObserveAttempt(request,
            BigInt(body.byteLength), observedMs()));
          if (deadline === undefined) {
            const remaining = checked(moon.clientProgramKeyedRequestRemainingMs(request, observedMs())) as bigint;
            // Schedule beyond the inclusive exact boundary and clamp only the
            // timer representation. Long policies are rechecked on every
            // observation; the timer must not overflow to immediate expiry.
            const expire = () => {
              try {
                const left = checked(moon.clientProgramKeyedRequestRemainingMs(request, observedMs())) as bigint;
                deadline = setTimeout(expire, Number(left < 2147483646n ? left + 1n : 2147483647n));
                deadline.unref();
              } catch (cause) {
                budgetAbort.abort(Object.assign(new Error('KeyedLookupDurationExceeded', {cause}),
                  {code: 'KeyedLookupDurationExceeded'}));
              }
            };
            deadline = setTimeout(expire, Number(remaining < 2147483646n ? remaining + 1n : 2147483647n));
            deadline.unref();
          }
          state.started = true;
          return {...grant, useId: `${nonce}-read-${sendIndex++}`};
        },
        chargePage: body => {
          if (!(body instanceof Uint8Array)) fail('InvalidKeyedResponseObservation');
          // Preserve the physical Ledger charge even when the lookup ceiling
          // rejects this received body before decoding or private admission.
          const charge = checked(moon.clientProgramRowSourceChargePage(run, body));
          checked(moon.clientProgramKeyedResponseObserve(request,
            BigInt(body.byteLength), 0n, observedMs()));
          return charge;
        },
        // Received native file bytes use this original RowRun's pending
        // ticket before the subsequent encoded row is charged. A lookup
        // verification count is not a physical-byte observation or a grant.
        consumeObservation: charge => checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge)),
        // The Site must await admission before returning protocol completion.
        consumePage: async (rows, {charge} = {}) => {
          // The codec comes from the exact Request's installed execution
          // original. A driver Bool or an earlier current decision cannot
          // select raw evidence or replace its pending activation.
          const identityResponse = lookupPublication !== undefined &&
            moon.clientProgramKeyedSourceResponseEncoding(request) === 'typed_json_row_array';
          if (identityResponse && (backingField === undefined || responsePageActive)) fail('ForeignOriginalKeyedRawResponse');
          if (identityResponse) responsePageActive = true;
          let body;
          try {
          if (identityResponse) {
            await verifyRead(); signal?.throwIfAborted();
            if (moon.clientProgramKeyedSourceResponseEncoding(request) !== 'typed_json_row_array') fail('ForeignOriginalKeyedRawResponse');
          }
          body = identityResponse ? encodeTypedResponseJson(rows, limits.maxPageBytes)
            : Buffer.from(JSON.stringify(rows), 'utf8');
          const ticket = charge ?? checked(moon.clientProgramRowSourceChargePage(run, body));
          checked(moon.clientProgramKeyedResponseObserve(request,
            charge === undefined ? BigInt(body.byteLength) : 0n,
            BigInt(body.byteLength), observedMs()));
          if (identityResponse) {
            if (lookupActivation === undefined || lookupRaw !== undefined) fail('ForeignOriginalKeyedRawResponse');
            lookupRaw = await lookupPublication.retainRawResponse(lookupOriginal,
              request, lookupActivation, body);
            await verifyRead(); signal?.throwIfAborted();
          }
          return await session!.consumeKeyedPage(body,
            {charge: ticket, currentRead: verifyRead, signal});
          } finally {
            body = undefined;
            if (identityResponse) responsePageActive = false;
          }
        }});
      session.confirmTransportStopped();
      const capture = await session.capture({currentRead: verifyRead, signal});
      checked(moon.clientProgramKeyedRequestFinishIO(request, observedMs()));
      if (lookupPublication !== undefined) {
        lookupPublication.adopt(lookupOriginal, request, lookupActivation, capture, lookupRaw);
        await verifyRead(); signal?.throwIfAborted();
      }
      return Object.freeze({capture: Object.freeze({read: () => checked(
        moon.clientProgramKeyedRowCaptureRead(capture)), identity: () => checked(
        moon.clientProgramKeyedRowCaptureIdentity(capture)) as string}),
        verifyRead,
        // Only the actual installed successful capture can enter assembly.
        acceptLookup: (lookup: unknown) => checked(moon.clientProgramKeyedLookupAcceptCapture(
          lookup, keyedAcquisition, request, capture)),
        async close() {session!.close(); await closeOriginal();}});
    } catch (error) {
      if (session !== undefined) {
        moon.clientProgramKeyedRequestFailIO(request);
        // Before dispatch there was no physical reader to stop. Once entered,
        // absence of an explicit transport-end observation remains pending.
        const end = acquisitionOutcome(error) as Readonly<{outcome: unknown; recovery?: TransportRecovery}>;
        if (!state.started || end.outcome === 'stopped' || end.outcome === 'not_started') {
          session.confirmTransportStopped();
        } else if (end.recovery !== undefined) {
          // The physical driver's same recovery owner stops its own resources;
          // it does not settle successful response evidence or the RowRun.
          try { await end.recovery.close(); } catch { /* Keep pending custody. */ }
        }
        session.closeAfterFailure(state, end.recovery);
      }
      if (originalKeyedRead !== undefined) {
        const rowRecovery = state.recovery;
        let cleaned = false;
        const cleanup = async () => {
          if (cleaned) return true;
          if (rowRecovery !== undefined &&
              (await rowRecovery.cleanup() === false || rowRecovery.cleanupPending())) return false;
          if (session === undefined) checked(moon.clientProgramInstalledKeyedSourceReadRetire(originalKeyedRead));
          await closeOriginal();
          cleaned = true;
          return true;
        };
        try {await cleanup();} catch { /* Retain the same original duty below. */ }
        if (!cleaned) {
          state.closeFailed = true;
          state.recovery = Object.freeze({close: () => rowRecovery?.close(),
            cleanup, cleanupPending: () => !cleaned});
        }
      }
      // Do not let an inner transport outcome bypass this RowRun's pending
      // retention/cleanup responsibility through acquisitionFailure's reuse.
      throw new AcquisitionOpenError(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    } finally {
      clearTimeout(deadline);
    }
  }

  return {openKeyed, selectedKeyedContent};
}
