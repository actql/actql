import {randomUUID} from 'node:crypto';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {createLocalRetainedStore} from '../../../store-local/files.mjs';
import {createProcessStoreLease} from '../../../store-local/process-client.mjs';
import {registerRetainedInput} from '../../../store-local/representations.mjs';
import {runNativeQuery} from './native-query.mjs';
import {computePhysicalCapacity, sourceTransportLimits} from './physical-capacity.mjs';
import {retainedProcessStore} from './retained-configuration.mjs';
import {checked} from './runtime-result.mjs';
import {DuckDBTransportError, withCurrentSourceEvidenceRead} from './session.mjs';
import {sourceAcquisitionFailure} from './source-acquisition.mjs';
import {sourceEvidenceOriginalAccess} from './source-evidence-original.mjs';

import type {LocalRetainedStore} from '../../../store-local/files.mjs';
import type {NativeAcquisitionPort} from './native-acquisition.mjs';
import type {retainedConfiguration} from './retained-configuration.mjs';
import type {PrepareQuery} from './settled-query.mjs';
import type {SourceFields, SourceLimits} from './source-acquisition.mjs';
import type {OwnedSourceCapture, SourceEvidenceOptions} from './source-evidence-original.mjs';

type RetainedConfiguration = ReturnType<typeof retainedConfiguration>;
type NativeStore = LocalRetainedStore | ReturnType<typeof createProcessStoreLease>;
type NativeWriter = ReturnType<NativeStore['reserve']>;
type NativeBody = Awaited<ReturnType<NativeWriter['seal']>>;
type NativeBridge = ReturnType<PrepareQuery<NativeAcquisitionPort, unknown, unknown, [], object>>;
type AcquisitionFailure = Error & {
  cleanupHandle?: Readonly<{status(): {pending: boolean}; retry(): unknown}>;
};
export type HeldRetainedComputation = Readonly<{
  readable: Parameters<typeof registerRetainedInput>[1];
  body: Parameters<typeof registerRetainedInput>[2];
  configuration: RetainedConfiguration;
}>;

export type NativeHostRuntime = Readonly<{
  nativeHostAbort(run: unknown): void;
  nativeHostAccept(run: unknown, rows: number, data: string): unknown;
  nativeHostAttempt(run: unknown): unknown;
  nativeHostBegin(run: unknown, native: boolean, fields: string): unknown;
  nativeHostCapacity(setup: unknown, retained: boolean): unknown;
  nativeHostClose(run: unknown): void;
  nativeHostComparisonUsage(observation: unknown): unknown;
  nativeHostComplete(run: unknown): unknown;
  nativeHostDocument(observation: unknown): string;
  nativeHostFinish(run: unknown): unknown;
  nativeHostIssueSourceEvidence(capture: unknown, context: unknown, identity: unknown,
    logicalInput: unknown, authorityScopeCid: string, effectiveDataPolicyCid: string, observedAt: string): unknown;
  nativeHostIssueSourceEvidenceOriginal(capture: unknown, context: unknown, identity: unknown,
    logicalInput: unknown, authorityScopeCid: string, effectiveDataPolicyCid: string, observedAt: string): unknown;
  nativeHostMeasurementUsage(observation: unknown): unknown;
  nativeHostMetadata(run: unknown, rows: number, fields: string, data: string): unknown;
  nativeHostOpen(setup: unknown, nonce: string, verify: (attempt: unknown) => boolean): unknown;
  nativeHostOpenDAG(run: unknown, graph: unknown, observation: unknown): unknown;
  nativeHostOutput(run: unknown, observation: unknown): unknown;
  nativeHostParameter(run: unknown, index: number): unknown;
  nativeHostPhysicalCharge(run: unknown, bytes: bigint): unknown;
  nativeHostPhysicalRefresh(run: unknown): void;
  nativeHostPhysicalSettle(run: unknown, confirmed: boolean): unknown;
  nativeHostPhysicalStart(run: unknown): unknown;
  nativeHostReceiptDocument(observation: unknown, index: number): unknown;
  nativeHostRecordDocument(observation: unknown, index: number): unknown;
  nativeHostRetainCapturedTask(run: unknown, dag: unknown, task: number, observation: unknown): unknown;
  nativeHostSourceCapture(run: unknown, observation: unknown): unknown;
  nativeHostSourceCaptureIdentityMatches(capture: unknown, identity: unknown): boolean;
  nativeHostSourceCaptureSource(capture: unknown): unknown;
  nativeHostSourceCaptureSourceRef(capture: unknown): string | undefined;
  nativeHostSql(run: unknown, kind: number): unknown;
  nativeHostStreamDrain(run: unknown): unknown;
  nativeHostStreamFinish(run: unknown): unknown;
  nativeHostStreamIdentity(token: unknown): unknown;
  nativeHostStreamMaterial(handle: unknown): object;
  nativeHostStreamPrepare(run: unknown, maxBatchBytes: number): unknown;
  nativeHostStreamReadable(handle: unknown, input: unknown): boolean;
  nativeHostStreamRetain(run: unknown, token: unknown, available: () => boolean): unknown;
  nativeHostTransportWindow(setup: unknown): unknown;
  nativeRetainedHostCapacity(setup: unknown, retained: boolean): unknown;
  nativeRetainedStrategyHostOpen(setup: unknown, ledger: unknown, nonce: string,
    verify: (attempt: unknown) => boolean, transfer: bigint, execution: bigint, fileBytes: bigint, maxBatchBytes: number, releaseConfirmed: () => boolean): unknown;
  nativeStrategyHostOpen(setup: unknown, ledger: unknown, nonce: string,
    verify: (attempt: unknown) => boolean, transfer: bigint, execution: bigint): unknown;
}>;

export function createNativeHostQuery(loadRuntime: () => Promise<NativeHostRuntime>,
  ownedSourceCaptures: WeakMap<object, OwnedSourceCapture>,
  retainedComputations: WeakMap<object, HeldRetainedComputation>, rows: (value: unknown) => number,
  fieldsFrame: (fields: SourceFields) => string,
  logicalMeasurementAccounting: (values: unknown, prefix: 'measuredGuard') => Readonly<Record<string, number>>,
  logicalComparisonAccounting: (values: unknown) => Readonly<{
    comparisonWork: number; comparisonBytes: number; comparisonNodes: number;
  }>,
) {
  async function runHostNativeQuery(grant: object, setup: unknown, limits: SourceLimits, signal?: AbortSignal,
    ledger?: unknown, retained?: RetainedConfiguration, outputKey?: string) {
    const moon = await loadRuntime();
    const window = moon.nativeHostTransportWindow(setup);
    limits = sourceTransportLimits(limits, runtimeField(window, 0) as number, runtimeField(window, 1) as number);
    const semantic = {
      nativeSemanticRows: 0,
      nativeSemanticCells: 0,
      nativeSemanticBytes: 0,
      jsMaterializedCells: 0,
    };
    const capacity = ledger === undefined ? undefined : Object.freeze({
      ...computePhysicalCapacity(limits),
      retentionBytes: (checked((retained ? moon.nativeRetainedHostCapacity : moon.nativeHostCapacity)(setup, true)) as bigint) + BigInt(retained?.wire.max_bytes ?? 0),
      receiverScratchBytes: checked((retained ? moon.nativeRetainedHostCapacity : moon.nativeHostCapacity)(setup, false)) as bigint,
    });
    let capturedRun: unknown;
    let store: NativeStore | undefined, writer: NativeWriter | undefined, body: NativeBody | undefined,
      retainedHandle: unknown, retainedOutput: object | undefined;
    const retainedCleanup = Object.freeze({
      status: () => ({ pending: store?.status().cleanupPending ?? false }),
      retry: async () => {
        if (store) await store.cleanup();
        if (capacity !== undefined && capturedRun !== undefined) moon.nativeHostPhysicalRefresh(capturedRun);
        return retainedCleanup.status();
      },
    });
    let sessionStarted = false;
    const accounting = capacity === undefined ? undefined : Object.freeze({
      started() {
        checked(moon.nativeHostPhysicalStart(capturedRun));
        sessionStarted = true;
      },
      chargeTransfer(bytes: number) { checked(moon.nativeHostPhysicalCharge(capturedRun, BigInt(bytes))); },
      settled(confirmed: boolean) { checked(moon.nativeHostPhysicalSettle(capturedRun, confirmed)); },
    });
    const captured = await runNativeQuery(grant, verify => {
      const run = checked(capacity === undefined
        ? moon.nativeHostOpen(setup, randomUUID(), verify)
        : retained
          ? moon.nativeRetainedStrategyHostOpen(setup, ledger, randomUUID(), verify,
            capacity.transferBytes, capacity.executionBytes, BigInt(retained.wire.max_bytes),
            retained.maxFrameBytes,
            () => !store || store.status().reservedBytes === 0)
          : moon.nativeStrategyHostOpen(setup, ledger, randomUUID(), verify,
            capacity.transferBytes, capacity.executionBytes));
      capturedRun = run;
      if (retained && capacity === undefined) checked(moon.nativeHostStreamPrepare(run, retained.maxFrameBytes));
      const attempt = moon.nativeHostAttempt(run);
      let view: object | undefined;
      const owns = (current: object) => {
        if (view === undefined) view = current;
        if (current !== view) throw new DuckDBTransportError('ForeignReadView');
      };
      const port = Object.freeze<NativeAcquisitionPort>({
        metadataSql: () => checked(moon.nativeHostSql(run, 0)) as string,
        metadataParameters: () => [0, 1].map(index => JSON.parse(checked(moon.nativeHostParameter(run, index)) as string)),
        acceptMetadata(chunk, current) {
          owns(current);
          checked(moon.nativeHostMetadata(run, rows(chunk.rowCount), fieldsFrame(chunk.fields), JSON.stringify(chunk.columns)));
        },
        async finishMetadata(_fields, current) {
          owns(current);
          if (retained) {
            signal?.throwIfAborted();
            const binding = retainedProcessStore(retained);
            store = binding
              ? createProcessStoreLease(binding, outputKey!, retained.wire.max_bytes, retained.maxFrameBytes, signal)
              : await createLocalRetainedStore({ parentDirectory: retained.parentDirectory,
                capacityBytes: retained.wire.max_bytes, maxFrameBytes: retained.maxFrameBytes, maxEntries: 1 });
            signal?.throwIfAborted();
            writer = store.reserve(retained.wire.max_bytes);
            await writer.start();
            signal?.throwIfAborted();
          }
        },
        validationSql: () => checked(moon.nativeHostSql(run, 1)) as string,
        nativeSql: () => checked(moon.nativeHostSql(run, 2)) as string,
        nativeParameters: () => [JSON.parse(checked(moon.nativeHostParameter(run, 2)) as string)],
        beginReceipt(role, fields, current) {
          owns(current);
          checked(moon.nativeHostBegin(run, role === 'native_result', fieldsFrame(fields)));
        },
        async acceptChunk(role, chunk, current) {
          owns(current);
          const text = JSON.stringify(chunk.columns);
          semantic.nativeSemanticRows += chunk.rowCount;
          semantic.nativeSemanticCells += chunk.rowCount * chunk.fields.length;
          semantic.nativeSemanticBytes += Buffer.byteLength(text);
          semantic.jsMaterializedCells += chunk.rowCount * chunk.fields.length;
          checked(moon.nativeHostAccept(run, rows(chunk.rowCount), text));
          if (retained && role === 'native_result') {
            let parts: string[] = [], bytes = 0;
            const flush = async () => {
              if (parts.length) await writer!.append(parts.join(''));
              parts = []; bytes = 0;
              signal?.throwIfAborted();
            };
            for (;;) {
              signal?.throwIfAborted();
              const text = checked(moon.nativeHostStreamDrain(run)) as string | undefined;
              if (text == null) break;
              const size = Buffer.byteLength(text, 'utf8');
              if (size > retained.maxFrameBytes) throw new DuckDBTransportError('RetainedFrameLimit');
              if (size > retained.maxFrameBytes - bytes) await flush();
              if (size) { parts.push(text); bytes += size; }
            }
            await flush();
          }
        },
        async finishReceipt(role, current) {
          owns(current);
          checked(moon.nativeHostFinish(run));
          if (retained && role === 'native_result') {
            const finished = checked(moon.nativeHostStreamFinish(run));
            if (finished != null) {
              let compilerTuple5: unknown = finished;
              const token = runtimeField(compilerTuple5, 0), tail = runtimeField(compilerTuple5, 1) as string;
              compilerTuple5 = undefined;
              await writer!.append(tail);
              let compilerTuple6 = moon.nativeHostStreamIdentity(token);
              const cid = runtimeField(compilerTuple6, 0) as string, bytes = runtimeField(compilerTuple6, 1) as number;
              compilerTuple6 = undefined;
              body = await writer!.seal({ cid, bytes });
              signal?.throwIfAborted();
              retainedHandle = checked(moon.nativeHostStreamRetain(run, token, () => body!.available()));
            }
          }
          return attempt;
        },
        abort() { moon.nativeHostAbort(run); },
      });
      return Object.freeze<NativeBridge>({
        attempt, port,
        complete: () => checked(moon.nativeHostComplete(run)),
        bindInput: observation => checked(moon.nativeHostOutput(run, observation)) as object,
        abort() { moon.nativeHostAbort(run); },
        close() { moon.nativeHostClose(run); },
      });
    }, limits, signal, accounting).catch(error => {
      store?.close();
      if (capacity !== undefined && capturedRun !== undefined && !sessionStarted) {
        checked(moon.nativeHostPhysicalSettle(capturedRun, true));
      }
      // prepare() may fail before the settlement driver receives its bridge.
      // The exact run was already captured here and still owns issuer cleanup.
      if (capturedRun !== undefined) moon.nativeHostClose(capturedRun);
      if (store) {
        const prior = (error as AcquisitionFailure | null | undefined)?.cleanupHandle;
        const failure = (error instanceof Error ? error : new DuckDBTransportError('RetainedAcquisitionFailed')) as AcquisitionFailure;
        failure.cleanupHandle = Object.freeze({
          status: () => ({ pending: retainedCleanup.status().pending || !!prior?.status().pending }),
          async retry() {
            const failures = [];
            for (const handle of [prior, retainedCleanup]) {
              try { await handle?.retry(); } catch (error) { failures.push(error); }
            }
            if (failures.length) throw new AggregateError(failures, 'Retained acquisition cleanup failed');
            return { pending: retainedCleanup.status().pending || !!prior?.status().pending };
          },
        });
        // A stopped provider session does not release this acquisition's Store.
        // Give the same combined owner to both the Run handoff and transport
        // cleanup API; no acquisition or Compute is repeated during recovery.
        if (failure.cleanupHandle.status().pending) {
          const handle = failure.cleanupHandle;
          const recovery = Object.freeze({
            close() {},
            async cleanup() {
              await handle.retry();
              return !handle.status().pending;
            },
            cleanupPending: () => handle.status().pending,
          });
          throw sourceAcquisitionFailure(failure, 'unknown', recovery);
        }
        throw failure;
      }
      throw error;
    });
    if (retained) {
      registerRetainedInput(moon.nativeHostStreamMaterial(retainedHandle),
        input => moon.nativeHostStreamReadable(retainedHandle, input), body!, retained);
    }
    let closed = false;
    const liveRun = () => {
      if (closed) throw new DuckDBTransportError('IssuerClosed');
      return capturedRun;
    };
    const output = () => {
      liveRun();
      if (!retained) return captured.bindInput();
      if (retainedOutput === undefined) {
        retainedOutput = captured.bindInput();
        // The shared material is already installed for both source() and output()
        // access. Do not register it twice when an output getter is used later.
        retainedComputations.set(retainedOutput, Object.freeze({
          readable: (input: unknown) => moon.nativeHostStreamReadable(retainedHandle, input),
          body, configuration: retained,
        }) as HeldRetainedComputation);
      }
      return retainedOutput;
    };
    const evidence = () => {
      liveRun();
      return Object.freeze({
        receipts: Object.freeze([0, 1].map(index =>
          JSON.parse(checked(moon.nativeHostReceiptDocument(
            captured.observation,
            index,
          )) as string))),
        records: Object.freeze([0, 1, 2].map(index =>
          JSON.parse(checked(moon.nativeHostRecordDocument(
            captured.observation,
            index,
          )) as string))),
        observation: JSON.parse(moon.nativeHostDocument(captured.observation)),
      });
    };
    const acquisitionMeasurement = logicalMeasurementAccounting(
      moon.nativeHostMeasurementUsage(captured.observation),
      'measuredGuard',
    );
    const acquisitionComparison = logicalComparisonAccounting(
      moon.nativeHostComparisonUsage(captured.observation),
    );
    const observedAt = new Date().toISOString();
    let sourceCapture: unknown;
    let captureReleased = false;
    const retainedSourceCapture = () => {
      liveRun();
      return sourceCapture ??= checked(moon.nativeHostSourceCapture(
        capturedRun, captured.observation));
    };
    const evidenceOriginal = sourceEvidenceOriginalAccess(() => {
      liveRun();
    }, ({context, identity, logicalInput, authorityScopeCid,
      effectiveDataPolicyCid, signal: issuanceSignal}: SourceEvidenceOptions) => {
      const held = retainedSourceCapture();
      const sourceRef = moon.nativeHostSourceCaptureSourceRef(held);
      if (sourceRef === undefined) throw new DuckDBTransportError('ClosedSourceCapture');
      return withCurrentSourceEvidenceRead(grant, sourceRef, () => {
        retainedSourceCapture();
        return checked(moon.nativeHostIssueSourceEvidenceOriginal(held, context, identity,
          logicalInput, authorityScopeCid, effectiveDataPolicyCid, observedAt));
      }, issuanceSignal);
    });
    const result = Object.freeze({
      observation: captured.observation,
      takeSourceEvidenceOriginal(): unknown {
        if (this !== result) throw new DuckDBTransportError('UnknownSourceCapture');
        return evidenceOriginal.take();
      },
      usage: captured.usage,
      diagnostics: Object.freeze({
        ...captured.diagnostics as Readonly<Record<string, unknown>>,
        ...semantic,
        ...acquisitionMeasurement,
        reusedGuardWork: 0,
        reusedGuardBytes: 0,
        reusedGuardNodes: 0,
        ...acquisitionComparison,
      }),
      physicalCapacity: capacity === undefined ? undefined : Object.freeze({
        ...capacity, executionBytes: capacity.executionBytes + capacity.receiverScratchBytes,
      }),
      document: () => moon.nativeHostDocument(captured.observation),
      evidence,
      storageUsage: () => store?.status(),
      cleanupHandle: retained ? retainedCleanup : undefined,
      source: () => checked(moon.nativeHostSourceCaptureSource(
        retainedSourceCapture())),
      ...(capacity === undefined ? {
        output,
      } : {
        openDAG: (graph: unknown) => checked(moon.nativeHostOpenDAG(liveRun(), graph, captured.observation)),
        retainTask: (dag: unknown, task: number) => checked(moon.nativeHostRetainCapturedTask(
          liveRun(), dag, task, captured.observation)),
      }),
      close() {
        if (captureReleased) return;
        closed = true;
        if (evidenceOriginal.pending()) throw new DuckDBTransportError('SourceEvidencePending');
        if (retainedOutput !== undefined) retainedComputations.delete(retainedOutput);
        body?.close();
        store?.close();
        captured.close();
        // Drop cached source custody only after the original issuer confirms
        // close. Failed close retries retain that same owner; the weak entry's
        // liveRun guard preserves the established closed-evidence failure.
        sourceCapture = undefined;
        evidenceOriginal.retire();
        captureReleased = true;
      },
    });
    ownedSourceCaptures.set(result, Object.freeze<OwnedSourceCapture>({
      prepare: options => evidenceOriginal.prepare(options),
      issue: ({context, identity, logicalInput, authorityScopeCid,
        effectiveDataPolicyCid, signal: issuanceSignal}) => {
        const held = retainedSourceCapture();
        const sourceRef = moon.nativeHostSourceCaptureSourceRef(held);
        if (sourceRef === undefined) {
          throw new DuckDBTransportError('ClosedSourceCapture');
        }
        return withCurrentSourceEvidenceRead(grant, sourceRef, () => {
          liveRun();
          return checked(moon.nativeHostIssueSourceEvidence(held, context, identity,
            logicalInput, authorityScopeCid, effectiveDataPolicyCid,
            observedAt)) as string;
        }, issuanceSignal);
      },
      matches: identity => !closed &&
        moon.nativeHostSourceCaptureIdentityMatches(
          retainedSourceCapture(), identity),
    }));
    return result;
  }

  return runHostNativeQuery;
}
