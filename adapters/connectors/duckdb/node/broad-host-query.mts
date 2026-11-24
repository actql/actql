import {randomUUID} from 'node:crypto';
import {setImmediate as yieldToHost} from 'node:timers/promises';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {runBroadQuery} from './broad-query.mjs';
import {computePhysicalCapacity, sourceTransportLimits} from './physical-capacity.mjs';
import {DuckDBTransportError, withCurrentSourceEvidenceRead} from './session.mjs';
import {checked} from './runtime-result.mjs';
import {sourceEvidenceOriginalAccess} from './source-evidence-original.mjs';

import type {BroadAcquisitionPort} from './broad-acquisition.mjs';
import type {SourceChunk, SourceFields, SourceLimits} from './source-acquisition.mjs';
import type {PrepareQuery} from './settled-query.mjs';
import type {OwnedSourceCapture, SourceEvidenceOptions} from './source-evidence-original.mjs';

export type BroadResidualRuntime = Readonly<{
  clientBroadResidualPrepare(run: unknown, maxNameBytes: number): unknown;
  clientBroadResidualAdvance(residual: unknown, quantum: number): unknown;
  clientBroadResidualStopped(residual: unknown): boolean;
  clientBroadResidualCancel(residual: unknown): boolean;
  clientBroadResidualComplete(residual: unknown): unknown;
  clientBroadResidualCleanup(residual: unknown): unknown;
}>;

type Verify = (attempt: unknown) => boolean;
type BroadBridge = ReturnType<PrepareQuery<BroadAcquisitionPort, unknown, unknown,
  [receiver: unknown, inputIndex: number], unknown>>;
type EvidenceBinding = (capture: unknown, context: unknown, identity: unknown,
  logicalInput: unknown, authorityScopeCid: string, effectiveDataPolicyCid: string, observedAt: string) => unknown;

export type BroadHostRuntime = Readonly<{
  broadHostTransportWindow(setup: unknown): unknown;
  broadHostCapacity(setup: unknown, retained: boolean): unknown;
  broadHostPhysicalStart(run: unknown): unknown;
  broadHostPhysicalCharge(run: unknown, bytes: bigint): unknown;
  broadHostPhysicalSettle(run: unknown, confirmed: boolean): unknown;
  broadHostPhysicalComplete(run: unknown, observation: unknown): unknown;
  broadHostOpen(setup: unknown, nonce: string, verify: Verify): unknown;
  broadStrategyHostOpen(setup: unknown, ledger: unknown, nonce: string, verify: Verify,
    transfer: bigint, execution: bigint, releaseConfirmed: () => boolean): unknown;
  broadHostAttempt(run: unknown): unknown;
  broadHostSql(run: unknown, metadata: boolean): string;
  broadHostParameter(run: unknown, index: number): unknown;
  broadHostMetadata(run: unknown, rows: number, fields: string, data: string): unknown;
  broadHostBegin(run: unknown, fields: string): unknown;
  broadHostAccept(run: unknown, rows: number, data: string): unknown;
  broadHostFinish(run: unknown): unknown;
  broadHostAbort(run: unknown): void;
  broadHostComplete(run: unknown): unknown;
  broadHostAcquisition(run: unknown): unknown;
  broadHostMaxNameBytes(run: unknown): number;
  broadHostBind(run: unknown, observation: unknown, receiver: unknown, inputIndex: number): unknown;
  broadHostClose(run: unknown): void;
  broadHostPhysicalRefresh(run: unknown): void;
  broadHostSourceCapture(run: unknown, observation: unknown): unknown;
  broadHostSourceCaptureSourceRef(capture: unknown): string | undefined;
  broadHostIssueSourceEvidenceOriginal: EvidenceBinding;
  broadHostDocument(observation: unknown): string;
  broadHostSourceCaptureSource(capture: unknown): unknown;
  broadHostRetainCapturedTask(run: unknown, dag: unknown, task: number, observation: unknown): unknown;
  broadHostIssueSourceEvidence: EvidenceBinding;
  broadHostSourceCaptureIdentityMatches(capture: unknown, identity: unknown): boolean;
}>;

export function createBroadHostQuery(loadRuntime: () => Promise<BroadHostRuntime>,
  ownedSourceCaptures: WeakMap<object, OwnedSourceCapture>,
  rows: (value: unknown) => number, fieldsFrame: (fields: SourceFields) => string,
) {
  // The broad result binds directly to an owned consumer through the existing
  // captured-input API. No caller-supplied expected producer or success proof.
  async function runBroadHostQuery(grant: object, setup: unknown, limits: SourceLimits,
    signal?: AbortSignal, residualRuntime?: BroadResidualRuntime, ledger?: unknown) {
    if (ledger !== undefined &&
        typeof residualRuntime?.clientBroadResidualPrepare !== 'function') {
      throw new DuckDBTransportError('MissingBoundedResidualRuntime');
    }
    const moon = await loadRuntime();
    const window = moon.broadHostTransportWindow(setup);
    limits = sourceTransportLimits(limits, runtimeField(window, 0) as number, runtimeField(window, 1) as number);
    const capacity = ledger === undefined ? undefined : Object.freeze({
      ...computePhysicalCapacity(limits),
      retentionBytes: checked(moon.broadHostCapacity(setup, true)) as bigint,
      receiverScratchBytes: checked(moon.broadHostCapacity(setup, false)) as bigint,
    });
    let capturedRun: unknown;
    let sessionStarted = false, sessionReleased = false, residualReleased = true;
    const accounting = capacity === undefined ? undefined : Object.freeze({
      started() {
        checked(moon.broadHostPhysicalStart(capturedRun));
        sessionStarted = true;
      },
      chargeTransfer(bytes: number) { checked(moon.broadHostPhysicalCharge(capturedRun, BigInt(bytes))); },
      settled(confirmed: boolean) {
        sessionReleased = confirmed;
        checked(moon.broadHostPhysicalSettle(capturedRun, confirmed));
      },
    });
    const complete = (observation: unknown) => {
      if (capacity !== undefined) checked(moon.broadHostPhysicalComplete(capturedRun, observation));
      return observation;
    };
    const captured = await runBroadQuery(grant, verify => {
      const run = checked(capacity === undefined
        ? moon.broadHostOpen(setup, randomUUID(), verify)
        : moon.broadStrategyHostOpen(setup, ledger, randomUUID(), verify,
          capacity.transferBytes, capacity.executionBytes,
          () => sessionReleased && residualReleased));
      capturedRun = run;
      const attempt = moon.broadHostAttempt(run);
      let view: object | undefined;
      let residual: unknown;
      const localMoon = residualRuntime;
      const owns = (current: object) => {
        if (view === undefined) view = current;
        if (view !== current) throw new DuckDBTransportError('ForeignReadView');
      };
      const port = Object.freeze({
        metadataSql: () => moon.broadHostSql(run, true),
        metadataParameters: () => [0, 1].map(index => JSON.parse(checked(moon.broadHostParameter(run, index)) as string)),
        acceptMetadata(chunk: SourceChunk, current: object) {
          owns(current);
          checked(moon.broadHostMetadata(run, rows(chunk.rowCount), fieldsFrame(chunk.fields), JSON.stringify(chunk.columns)));
        },
        finishMetadata(_fields: SourceFields, current: object) { owns(current); },
        scanSql: () => moon.broadHostSql(run, false),
        beginReceipt(fields: SourceFields, current: object) {
          owns(current);
          checked(moon.broadHostBegin(run, fieldsFrame(fields)));
        },
        acceptChunk(chunk: SourceChunk, current: object) {
          owns(current);
          checked(moon.broadHostAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
        },
        finishReceipt(current: object) {
          owns(current);
          checked(moon.broadHostFinish(run));
          return attempt;
        },
        abort() { moon.broadHostAbort(run); },
      });
      return Object.freeze<BroadBridge>({
        attempt, port,
        complete: () => complete(checked(residual === undefined ?
          moon.broadHostComplete(run) :
          localMoon!.clientBroadResidualComplete(residual))),
        ...(localMoon === undefined ? {} : {async completeBounded(activeSignal?: AbortSignal) {
          residual = checked(localMoon.clientBroadResidualPrepare(
            moon.broadHostAcquisition(run), moon.broadHostMaxNameBytes(run)));
          residualReleased = false;
          try {
            for (;;) {
              activeSignal?.throwIfAborted();
              if (checked(localMoon.clientBroadResidualAdvance(residual, 128))) break;
              await yieldToHost();
            }
            activeSignal?.throwIfAborted();
            return complete(checked(localMoon.clientBroadResidualComplete(residual)));
          } catch (cause) {
            localMoon.clientBroadResidualCancel(residual);
            try {
              while (!localMoon.clientBroadResidualStopped(residual)) {
                try { checked(localMoon.clientBroadResidualAdvance(residual, 128)); }
                catch (stopError) {
                  if (!localMoon.clientBroadResidualStopped(residual)) throw stopError;
                }
                if (!localMoon.clientBroadResidualStopped(residual)) await yieldToHost();
              }
            } catch (stopError) {
              throw new DuckDBTransportError('ResidualStopUnconfirmed', {
                cause: new AggregateError([cause, stopError]),
              });
            }
            throw cause;
          }
        }}),
        stopped: () => residual === undefined ||
          localMoon!.clientBroadResidualStopped(residual),
        bindInput: (observation: unknown, receiver: unknown, inputIndex: number) => checked(moon.broadHostBind(run, observation, receiver, rows(inputIndex))),
        abort() {
          if (residual === undefined) moon.broadHostAbort(run);
          else localMoon!.clientBroadResidualCancel(residual);
        },
        close() {
          if (residual !== undefined &&
              !checked(localMoon!.clientBroadResidualCleanup(residual))) {
            throw new DuckDBTransportError('ResidualCleanupPending');
          }
          residualReleased = true;
          moon.broadHostClose(run);
        },
      });
    }, limits, signal, accounting).catch(error => {
      if (capacity !== undefined && capturedRun !== undefined && !sessionStarted) {
        sessionReleased = true;
        checked(moon.broadHostPhysicalSettle(capturedRun, true));
        moon.broadHostPhysicalRefresh(capturedRun);
      }
      throw error;
    });
    let closed = false;
    let captureReleased = false;
    let sourceCapture: unknown;
    const observedAt = new Date().toISOString();
    const retainedSourceCapture = () => {
      if (closed) throw new DuckDBTransportError('ClosedSourceCapture');
      return sourceCapture ??= checked(moon.broadHostSourceCapture(
        capturedRun, captured.observation));
    };
    const evidenceOriginal = sourceEvidenceOriginalAccess(() => {
      if (closed) throw new DuckDBTransportError('ClosedSourceCapture');
    }, ({context, identity, logicalInput, authorityScopeCid,
      effectiveDataPolicyCid, signal: issuanceSignal}: SourceEvidenceOptions) => {
      const held = retainedSourceCapture();
      const sourceRef = moon.broadHostSourceCaptureSourceRef(held);
      if (sourceRef === undefined) throw new DuckDBTransportError('ClosedSourceCapture');
      return withCurrentSourceEvidenceRead(grant, sourceRef, () => {
        retainedSourceCapture();
        return checked(moon.broadHostIssueSourceEvidenceOriginal(held, context, identity,
          logicalInput, authorityScopeCid, effectiveDataPolicyCid, observedAt));
      }, issuanceSignal);
    });
    const result = Object.freeze({
      observation: captured.observation,
      takeSourceEvidenceOriginal(): unknown {
        if (this !== result) throw new DuckDBTransportError('UnknownSourceCapture');
        return evidenceOriginal.take();
      },
      document: () => moon.broadHostDocument(captured.observation),
      bindInput: (receiver: unknown, inputIndex: number) => captured.bindInput(receiver, inputIndex),
      source: () => checked(moon.broadHostSourceCaptureSource(
        retainedSourceCapture())),
      ...(capacity === undefined ? {} : {
        retainTask: (dag: unknown, task: number) => {
          retainedSourceCapture();
          checked(moon.broadHostRetainCapturedTask(capturedRun, dag,
            rows(task), captured.observation));
        },
        physicalCapacity: capacity,
      }),
      close() {
        if (captureReleased) return;
        closed = true;
        if (evidenceOriginal.pending()) throw new DuckDBTransportError('SourceEvidencePending');
        captured.close();
        evidenceOriginal.retire();
        captureReleased = true;
      },
    });
    ownedSourceCaptures.set(result, Object.freeze<OwnedSourceCapture>({
      prepare: options => evidenceOriginal.prepare(options),
      issue: ({context, identity, logicalInput, authorityScopeCid,
        effectiveDataPolicyCid, signal: issuanceSignal}) => {
        const held = retainedSourceCapture();
        const sourceRef = moon.broadHostSourceCaptureSourceRef(held);
        if (sourceRef === undefined) {
          throw new DuckDBTransportError('ClosedSourceCapture');
        }
        return withCurrentSourceEvidenceRead(grant, sourceRef, () => {
          retainedSourceCapture();
          return checked(moon.broadHostIssueSourceEvidence(held, context, identity,
            logicalInput, authorityScopeCid, effectiveDataPolicyCid, observedAt)) as string;
        }, issuanceSignal);
      },
      matches: identity => !closed &&
        moon.broadHostSourceCaptureIdentityMatches(retainedSourceCapture(), identity),
    }));
    return result;
  }

  return runBroadHostQuery;
}
