import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {AcquisitionOpenError, acquisitionOutcome} from '../host-common/acquisition-outcome.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

import type {createInstalledRowSourceKeyedPreparation} from './installed-row-source-keyed-preparation.mjs';
import type {createInstalledRowSourceKeyedRead} from './installed-row-source-keyed-read.mjs';
import type {prepareOriginalSourceQuery} from './original-query-preparation.mjs';

type KeyedPreparation = ReturnType<typeof createInstalledRowSourceKeyedPreparation>;
type VerificationOptions = Parameters<KeyedPreparation['verifyKeyedRead']>[0];
type KeyedPrepared = VerificationOptions['preparedKeyed'];
type SourceAccess = NonNullable<VerificationOptions['sourceAccess']>;
type ContractInputs = Pick<Parameters<typeof prepareOriginalSourceQuery>[0], 'registry' | 'values' | 'fragment' | 'ordered'>;
type SourceCapture = Readonly<{source(): unknown; originalRead?(): unknown}>;
type KeyedRead = ReturnType<typeof createInstalledRowSourceKeyedRead>;
type KeyedReadOptions = Parameters<KeyedRead['openKeyed']>[0];
type KeyedReadPublication = NonNullable<KeyedReadOptions['lookupPublication']>;
type LookupPublication = Partial<KeyedReadPublication> & Readonly<{
  protocol?: 'generic-source';
  initialize(lookup: unknown): void;
  finishInput(lookup: unknown): unknown;
}>;
type LookupOptions = {
  preparedProgram?: unknown;
  preparedEffect?: unknown;
  keyedAcquisition: unknown;
  left: unknown;
  ledger: unknown;
  signal?: AbortSignal;
  preparedKeyed?: KeyedPrepared;
  originalCapture?: SourceCapture;
  originalCaptures?: readonly SourceCapture[];
  managedRun?: unknown;
  keyedContent?: KeyedReadOptions['keyedContent'];
  publication?: LookupPublication;
  sourceLookup?: unknown;
  sourceAccess?: SourceAccess;
  maxWork?: number;
  maxNodes?: number;
  quantum?: number;
};
type LookupChild = Awaited<ReturnType<KeyedRead['openKeyed']>>;
type AcquisitionRecovery = Readonly<{
  close(): unknown;
  cleanup(): boolean | PromiseLike<boolean>;
  cleanupPending(): boolean;
}>;
type ObservationOptions = Readonly<{authorityScopeCid: string; observedAt: string}>;
type LookupHostOptions = ContractInputs & Readonly<{
  retainedRelationOutput?: boolean;
  managedRun?: unknown;
  requestIdentity?: unknown;
}>;
type JoinPrepare = (owner: unknown, lookup: unknown, registry: ContractInputs['registry'],
  values: string, fragment: string | undefined, ordered: string | undefined) => unknown;
type LookupRuntime = Readonly<{
  clientProgramKeyedLeftReadRows(left: unknown): number | undefined;
  clientProgramKeyedLeftMatchesAcquisition(left: unknown, acquisition: unknown): boolean;
  clientProgramKeyedAcquisitionMatchesProgram(acquisition: unknown, prepared: unknown): boolean;
  clientProgramKeyedAcquisitionMatchesEffectProgram(acquisition: unknown, prepared: unknown): boolean;
  clientProgramKeyedLookupStart(left: unknown, ledger: unknown, maxBytes: number, maxWork: number): unknown;
  clientProgramInstalledEffectKeyedLookupOriginal(run: unknown, effect: unknown, sourceLookup: unknown): unknown;
  clientProgramKeyedLookupLeft(lookup: unknown): unknown;
  clientProgramKeyedLookupStop(lookup: unknown): void;
  clientProgramKeyedRequestCancel(preparation: unknown): void;
  clientProgramKeyedLookupCleanup(lookup: unknown, quantum: number): unknown;
  clientProgramKeyedLookupNextPlannedRow(lookup: unknown): unknown;
  clientProgramKeyedLookupPlannedRequest(lookup: unknown, row: number): unknown;
  clientProgramKeyedLookupRequestStart(lookup: unknown, row: number): unknown;
  clientProgramKeyedLookupRequestAdvance(lookup: unknown, preparation: unknown): unknown;
  clientProgramKeyedLookupRequestPlanRetain(lookup: unknown, request: unknown): unknown;
  clientProgramKeyedLookupFind(lookup: unknown, request: unknown): unknown;
  clientProgramKeyedLookupReuse(lookup: unknown, request: unknown, index: number): unknown;
  clientProgramComposedKeyedFileLocatorStart(lookup: unknown, request: unknown,
    captures: readonly unknown[], reads: readonly unknown[]): unknown;
  clientProgramKeyedFileLocatorStart(lookup: unknown, request: unknown, capture: unknown, read: unknown): unknown;
  clientProgramKeyedFileLocatorAdvance(locator: unknown): unknown;
  clientProgramKeyedFileLocatorCancel(locator: unknown): void;
  clientProgramKeyedLookupChargeVerification(lookup: unknown, request: unknown, bytes: number): unknown;
  clientProgramKeyedLookupAdvance(lookup: unknown, quantum: number): unknown;
  clientProgramKeyedLookupRequestPlanFinish(lookup: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramKeyedLookupPublicationInput(lookup: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramKeyedLookupRead(lookup: unknown): unknown;
  clientProgramKeyedLookupIdentity(lookup: unknown): string | undefined;
  clientProgramKeyedLookupWork(lookup: unknown): bigint;
  clientProgramKeyedLookupIssueObservation(lookup: unknown, authorityScopeCid: string, observedAt: string): unknown;
  clientProgramKeyedLookupObservationWires(observation: unknown): unknown;
  clientProgramKeyedLookupOpenDag(prepared: unknown, lookup: unknown, ledger: unknown): unknown;
  clientProgramOpenInstalledManagedKeyedCaptureHost?(run: unknown, prepared: unknown, request: unknown, lookup: unknown): unknown;
  clientProgramKeyedLookupOpenLocalHost(prepared: unknown, lookup: unknown, ledger: unknown,
    registry: ContractInputs['registry'], values: string, fragment: string | undefined, ordered: string | undefined,
    retainedRelationOutput: boolean): unknown;
  clientProgramKeyedLookupJoinPrepare: JoinPrepare;
  clientProgramEffectKeyedLookupJoinPrepare: JoinPrepare;
}>;

export function createInstalledRowSourceKeyedLookup({moon, limits, originalReader, selectedKeyedContent,
  sourceAccess, managedPageLimits, pageLimits, openKeyed}: {
  moon: LookupRuntime;
  limits: Readonly<{maxPageBytes: number}>;
  originalReader?: object;
  selectedKeyedContent: KeyedRead['selectedKeyedContent'];
  sourceAccess: SourceAccess;
  managedPageLimits?: Readonly<{maxDepth: number}>;
  pageLimits?: Readonly<{maxDepth: number}>;
  openKeyed: KeyedRead['openKeyed'];
}) {
  // Exact-key sharing changes physical reads, not original left multiplicity.
  // This assembles a right Relation input; it is not Source/task evidence.
  async function openKeyedLookup({preparedProgram, preparedEffect,
    keyedAcquisition, left, ledger, signal, preparedKeyed, originalCapture, originalCaptures, managedRun,
    keyedContent, publication, sourceLookup,
    sourceAccess: access = sourceAccess, maxWork = 1000000, maxNodes = maxWork, quantum = 64}: LookupOptions) {
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    keyedContent = selectedKeyedContent(keyedContent);
    if (!Number.isSafeInteger(maxWork) || maxWork < 1 || maxWork > 2147483647 ||
        !Number.isSafeInteger(maxNodes) || maxNodes < 1 || maxNodes > 2147483647 ||
        !Number.isSafeInteger(quantum) || quantum < 1 || quantum > 1024) {
      fail('InstalledKeyedLookupLimits');
    }
    const rows = moon.clientProgramKeyedLeftReadRows(left);
    if (rows === undefined || ledger === undefined ||
        moon.clientProgramKeyedLeftMatchesAcquisition(left, keyedAcquisition) !== true ||
        (preparedProgram === undefined) === (preparedEffect === undefined) ||
        (preparedEffect === undefined
          ? moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram)
          : moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition, preparedEffect)) !== true) {
      fail('InstalledSourceProgramMismatch');
    }
    signal?.throwIfAborted();
    const lookup = sourceLookup === undefined
      ? checked(moon.clientProgramKeyedLookupStart(left, ledger, limits.maxPageBytes, maxWork))
      : preparedEffect === undefined || managedRun === undefined
        ? fail('InstalledSourceProgramMismatch')
        : checked(moon.clientProgramInstalledEffectKeyedLookupOriginal(managedRun,
          preparedEffect, sourceLookup));
    if (sourceLookup !== undefined && moon.clientProgramKeyedLookupLeft(lookup) !== left) {
      fail('InstalledSourceProgramMismatch');
    }
    const children: LookupChild[] = [];
    const released = new Set<LookupChild>();
    let pendingRecovery: AcquisitionRecovery | undefined;
    let unownedUncertainty = false;
    let preparation: unknown;
    let ioStarted = false;
    let closed = false;
    const stop = () => {
      moon.clientProgramKeyedLookupStop(lookup);
      if (preparation !== undefined) {
        moon.clientProgramKeyedRequestCancel(preparation);
        preparation = undefined;
      }
    };
    const cleanup = async () => {
      if (closed) return true;
      stop();
      let pending = unownedUncertainty;
      for (const child of children) {
        if (released.has(child)) continue;
        try { await child.close(); released.add(child); }
        catch { pending = true; }
      }
      if (pendingRecovery !== undefined) {
        try {
          await pendingRecovery.close();
          if (await pendingRecovery.cleanup() === false || pendingRecovery.cleanupPending()) pending = true;
          else pendingRecovery = undefined;
        } catch { pending = true; }
      }
      // Keep assembly custody until all original physical children settle.
      // Cleanup never obtains a new Request or sends again.
      if (pending) return false;
      while (!checked(moon.clientProgramKeyedLookupCleanup(lookup, quantum))) {
        await yieldEventLoop();
      }
      children.length = 0;
      released.clear();
      closed = true;
      return true;
    };
    const close = async () => {
      if (!await cleanup()) fail('InstalledSourceCleanupPending');
    };
    const recovery = Object.freeze({close: stop, cleanup, cleanupPending: () => !closed});
    try {
      const publicationInput = preparedEffect !== undefined;
      // Generic content_ref Sources use their actual Store/Row capture, not a
      // Native declared-JSON activation, raw-response Journal or page history.
      const nativePublication = publicationInput && publication?.protocol !== 'generic-source';
      const publicationDepth = (managedPageLimits ?? pageLimits)?.maxDepth ?? 32;
      if (publicationInput) {
        if (typeof publication?.initialize !== 'function' || typeof publication?.finishInput !== 'function' ||
            nativePublication && (typeof publication?.activate !== 'function' ||
              typeof publication?.retainRawResponse !== 'function' || typeof publication?.adopt !== 'function')) {
          fail('OriginalKeyedLookupPublicationUnavailable');
        }
        publication.initialize(lookup);
      }
      // Prepare each original request once, then dispatch those SAME originals.
      // No response or Model read can precede the closed typed key inventory.
      for (let phase = 0; phase < (nativePublication ? 2 : 1); phase++) {
        for (let row = 0; row < rows; row++) {
          signal?.throwIfAborted();
          let request: unknown;
          if (nativePublication && phase === 1) {
            const originalRow = checked(moon.clientProgramKeyedLookupNextPlannedRow(lookup)) as number;
            request = checked(moon.clientProgramKeyedLookupPlannedRequest(lookup, originalRow));
          } else {
            preparation = checked(moon.clientProgramKeyedLookupRequestStart(lookup, row));
            while (request === undefined) {
              signal?.throwIfAborted();
              for (let poll = 0; poll < quantum; poll++) {
                let compilerTuple1 = moon.clientProgramKeyedLookupRequestAdvance(lookup, preparation);
                const status = runtimeField(compilerTuple1, 0), value = runtimeField(compilerTuple1, 2), issue = runtimeField(compilerTuple1, 3);
                compilerTuple1 = undefined;
                if (status === 2) fail('InstalledKeyedRequestFailed', issue);
                if (status === 1) { request = value; break; }
              }
              if (request === undefined) await yieldEventLoop();
            }
            preparation = undefined;
          }
          if (nativePublication && phase === 0) {
            checked(moon.clientProgramKeyedLookupRequestPlanRetain(lookup, request));
            continue;
          }
          const index = checked(moon.clientProgramKeyedLookupFind(lookup, request)) as number;
          if (index >= 0) {
            await children[index].verifyRead();
            signal?.throwIfAborted();
            checked(moon.clientProgramKeyedLookupReuse(lookup, request, index));
            continue;
          }
          let acquired;
          try {
            acquired = await openKeyed({preparedProgram, preparedEffect,
              keyedContent, managedRun,
              lookupPublication: nativePublication ? publication as KeyedReadPublication : undefined, lookupOriginal: lookup,
              keyedAcquisition, request, ledger, signal, preparedKeyed, sourceAccess: access,
              capturedResourcePath: async (verifyRead, activeSignal) => {
                let locator;
                if (originalCaptures !== undefined) {
                  if (!Array.isArray(originalCaptures) || originalCaptures.length !== 2) fail('InstalledFileLocatorUnavailable');
                  locator = checked(moon.clientProgramComposedKeyedFileLocatorStart(lookup, request,
                    originalCaptures.map(capture => capture.source()),
                    originalCaptures.map(capture => capture.originalRead?.())));
                } else {
                  if (typeof originalCapture?.originalRead !== 'function') fail('InstalledFileLocatorUnavailable');
                  const read = originalCapture.originalRead();
                  if (read === undefined) fail('InstalledFileLocatorUnavailable');
                  locator = checked(moon.clientProgramKeyedFileLocatorStart(lookup, request,
                    originalCapture.source(), read));
                }
                try {
                  for (;;) {
                    await verifyRead();
                    activeSignal?.throwIfAborted();
                    for (let poll = 0; poll < quantum; poll++) {
                      const path = checked(moon.clientProgramKeyedFileLocatorAdvance(locator)) as string | undefined;
                      if (path !== undefined) return path;
                    }
                    await yieldEventLoop();
                  }
                } finally {
                  moon.clientProgramKeyedFileLocatorCancel(locator);
                }
              },
              chargeVerification: bytes => checked(
                moon.clientProgramKeyedLookupChargeVerification(lookup, request, bytes))});
            ioStarted = true;
          } catch (error) {
            const end = acquisitionOutcome(error);
            if (end.outcome !== 'not_started') ioStarted = true;
            if (end.outcome === 'unknown') {
              pendingRecovery = end.recovery as AcquisitionRecovery | undefined;
              unownedUncertainty = end.recovery === undefined;
            }
            throw error;
          }
          // Preserve the physical close handle before copying can fail.
          children.push(acquired);
          acquired.acceptLookup(lookup);
          while (!checked(moon.clientProgramKeyedLookupAdvance(lookup, quantum))) {
            signal?.throwIfAborted();
            await acquired.verifyRead();
            signal?.throwIfAborted();
            await yieldEventLoop();
          }
        }
        if (nativePublication && phase === 0) {
          checked(moon.clientProgramKeyedLookupRequestPlanFinish(lookup,
            limits.maxPageBytes, maxNodes, publicationDepth));
        }
      }
      for (const child of children) {
        await child.verifyRead();
        signal?.throwIfAborted();
      }
      signal?.throwIfAborted();
      const read = publicationInput && preparedEffect !== undefined
        ? publication!.finishInput(lookup)
        : checked(publicationInput
          ? moon.clientProgramKeyedLookupPublicationInput(lookup,
            limits.maxPageBytes, maxNodes, publicationDepth)
          : moon.clientProgramKeyedLookupRead(lookup));
      return Object.freeze({capture: Object.freeze({
        read: () => closed ? fail('InstalledSourceClosed')
          : checked(moon.clientProgramKeyedLookupRead(lookup)),
        identity: () => {
          const identity = moon.clientProgramKeyedLookupIdentity(lookup);
          if (identity === undefined) fail('InstalledSourceClosed');
          return identity;
        }}), close, cleanup, cleanupPending: recovery.cleanupPending,
        work: () => moon.clientProgramKeyedLookupWork(lookup), read,
        async issueObservation({authorityScopeCid, observedAt}: ObservationOptions) {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          const observation = checked(moon.clientProgramKeyedLookupIssueObservation(
            lookup, authorityScopeCid, observedAt));
          const wires = moon.clientProgramKeyedLookupObservationWires(observation);
          if (wires === undefined) fail('InstalledSourceClosed');
          return Object.freeze({observation,
            inputLogicalWire: runtimeField(wires, 0) as string, sourceEvidenceWire: runtimeField(wires, 1) as string});
        },
        async openDag() {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (preparedEffect !== undefined) {
            fail('InstalledKeyedEffectDagRequiresRunOwner');
          }
          if (closed) fail('InstalledSourceClosed');
          return checked(moon.clientProgramKeyedLookupOpenDag(preparedProgram,
            lookup, ledger));
        },
        async openHost({registry, values, fragment, ordered, retainedRelationOutput = false,
          managedRun, requestIdentity}: LookupHostOptions) {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          if (preparedEffect !== undefined) fail('InstalledKeyedEffectDagRequiresRunOwner');
          if (managedRun !== undefined || requestIdentity !== undefined) {
            if (managedRun === undefined || requestIdentity === undefined ||
                typeof moon.clientProgramOpenInstalledManagedKeyedCaptureHost !== 'function') {
              fail('InstalledKeyedHostOriginalRunUnavailable');
            }
            return checked(moon.clientProgramOpenInstalledManagedKeyedCaptureHost(
              managedRun, preparedProgram, requestIdentity, lookup));
          }
          const host = moon.clientProgramKeyedLookupOpenLocalHost(preparedProgram,
            lookup, ledger, registry, values, fragment, ordered, retainedRelationOutput);
          if (host === undefined) fail('InstalledKeyedHostPreparation');
          return host;
        },
        // Original Local preparation, not a replacement acquisition Program.
        // The normal dispatcher must reserve its capacity and own its child.
        async borrowSerializationInput() {
          if (closed) fail('InstalledSourceClosed');
          signal?.throwIfAborted();
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          if (closed) fail('InstalledSourceClosed');
          // This is the original sealed lookup, not a new task completion or
          // a transfer of custody. The dependent prefix must stop first.
          checked(moon.clientProgramKeyedLookupRead(lookup));
          return lookup;
        },
        async prepareJoin({registry, values, fragment, ordered}: ContractInputs) {
          if (closed) fail('InstalledSourceClosed');
          for (const child of children) {
            await child.verifyRead();
            signal?.throwIfAborted();
          }
          const prepared = preparedEffect === undefined
            ? moon.clientProgramKeyedLookupJoinPrepare(preparedProgram, lookup,
              registry, values, fragment, ordered)
            : moon.clientProgramEffectKeyedLookupJoinPrepare(preparedEffect, lookup,
              registry, values, fragment, ordered);
          if (prepared === undefined) fail('InstalledKeyedJoinPreparation');
          return prepared;
        }});
    } catch (error) {
      let complete = false;
      try { complete = await cleanup(); } catch { /* Same recovery retains custody. */ }
      throw new AcquisitionOpenError(error, complete
        ? ioStarted ? 'stopped' : 'not_started' : 'unknown', complete ? undefined : recovery);
    }
  }

  return openKeyedLookup;
}
