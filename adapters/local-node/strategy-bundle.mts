// Local connector's Node driver. The kernel and reservation authority stay in
// MoonBit; this wrapper never evaluates an expression or synthesizes a result.
import {checkedLocalManagedAdvance} from './managed-advance-diagnostic.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {readLocalRetainedInput} from './retained-input.mjs';
import {localComputeFaultInjection, localRetainedStore,
  localSnapshotStore, localExecutionPauseHandler, localExecutionBeforePrepare} from './retained-store.mjs';
import {prepareLocalRetainedOutput} from './retained-output.mjs';
import {closeCompletedLocalManagedOutput, closeCompletedLocalManagedOutputAsync, continueLocalManagedFailureCleanup, refreshCompletedLocalManagedScratch} from './managed-output-custody.mjs';
import {prepareLocalCarrierSnapshot, prepareLocalRelationSnapshot} from './carrier-snapshot.mjs';
import {planManagedInputRows, registerManagedMemoryInput,
  withManagedInputRows, withManagedOutputRows} from
  '../store-local/managed-memory-representations.mjs';
import {beginManagedFailureProgress, recordManagedFailureExecutionSettled,
  settleFailedManagedOperations} from
  '../host-common/managed-failure.mjs';
import type {ManagedFailureOperations} from '../host-common/managed-failure.mjs';
import type {SynchronousResultCheck, SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type RetainedRead = Parameters<typeof readLocalRetainedInput>;
type RetainedOutputPort = Parameters<typeof prepareLocalRetainedOutput>[0];
type CarrierPorts = Parameters<typeof prepareLocalCarrierSnapshot>[0];
type RelationPorts = Parameters<typeof prepareLocalRelationSnapshot>[0];
type FaultInjection = ReturnType<typeof localComputeFaultInjection>;
type PauseHandler = ReturnType<typeof localExecutionPauseHandler>;
type ManagedRowPlan = ReturnType<typeof planManagedInputRows>;
type EmitRow = Parameters<typeof withManagedOutputRows>[1];
type CleanupObservation = Readonly<{cleanupPending?: unknown; cleanupHandle?: unknown}>;
type CheckpointPause = Readonly<{action: 'waiting_checkpoint'; checkpoint: object}>;
type Advance = Readonly<{
  complete: boolean;
  progress: bigint;
  work: bigint;
  waiting?: boolean;
  settlement?: number | null;
}>;
type Execution = ManagedFailureOperations & Readonly<{
  advance?(quantum: number): SynchronousRuntimeData;
  request_cancel?(): boolean;
  execution_stopped?(): boolean;
}>;
type RowTransfer = Readonly<{
  input: unknown;
  append(row: string): SynchronousRuntimeData;
  finish(): SynchronousRuntimeData;
}>;
type ManagedExecution = Execution & Partial<CarrierPorts & RelationPorts> & Readonly<{
  inputs: readonly RowTransfer[];
  retained_inputs?: readonly RetainedRead[1][];
  storage_bytes: bigint;
  prepare_finalization?(payload: number, storageBytes: bigint, available: () => boolean): SynchronousRuntimeData;
  advance_finalization?(quantum: number): SynchronousRuntimeData;
  complete(payload: number, storageBytes: bigint, available: () => boolean): SynchronousRuntimeData;
  complete_carrier(): SynchronousRuntimeData;
  material(): object | null | undefined;
  carrier_material?(): object | null | undefined;
}>;
type MaterializingExecution = Execution & Readonly<{
  inputs: readonly RetainedRead[1][];
  output?: RetainedOutputPort | null;
  complete(): SynchronousRuntimeData;
  guard_usage(): readonly number[];
  publication_output?(): unknown;
}>;
type ManagedInput = Readonly<{
  task: number;
  material?: object;
  siteMaterial?: object;
  completed?: unknown;
  carrierMaterial?: object | null;
  suppliedRelation?: boolean;
  capturedRelation?: boolean;
}>;
type SiteResolution = Readonly<{materials: readonly object[]; records: readonly unknown[]}>;
type PreparedTask = Readonly<{
  task: number;
  configuration: object;
  dispatchInputs?: readonly ManagedInput[];
  inputs: readonly ManagedInput[];
  rowPlan?: ManagedRowPlan;
  resolveSiteInputs?(inputs: readonly unknown[], signal?: AbortSignal): Promise<SiteResolution>;
  siteCompletionReady?(): boolean;
}>;
type LocalBindings = RetainedRead[0] & Parameters<typeof checkedLocalManagedAdvance>[0] &
  Parameters<typeof beginManagedFailureProgress>[0] & Readonly<{
  strategyModule_local_Registration(setup: unknown): unknown;
  strategyHostRegistrationSelectionKey(registration: unknown): string;
  strategyHostNextTask(setup: unknown): number;
  strategyHostTask?(task: unknown): number;
  strategyHostManagedProducers(setup: unknown): readonly number[];
  strategyHostManagedInputCount(setup: unknown): number;
  strategyHostReleasableManagedProducers(setup: unknown): readonly number[];
  strategyHostManagedInputMatchesMaterial(input: unknown, material: object): boolean;
  strategyModule_local_NextCarrierPath?(setup: unknown): boolean;
  strategyModule_local_HasPreparedRelationInput?(setup: unknown, index: number): boolean;
  strategyModule_local_PredecessorIsCarrier?(setup: unknown, producer: number): boolean;
  strategyModule_local_RelationOutput?(completed: unknown): unknown;
  strategyModule_local_CarrierOutput?(completed: unknown, material: object): unknown;
  strategyModule_local_CapturedRelationInput?(): unknown;
  strategyModule_local_SuppliedRelationInput?(): unknown;
  strategyModule_local_ManagedDispatch(setup: unknown, completed: unknown[], fileBytes: bigint): unknown;
  strategyModule_local_ManagedCarrierDispatch?(setup: unknown, completed: unknown[], fileBytes: bigint): unknown;
  strategyModule_local_ManagedUsesProvider?(configuration: object): boolean;
  strategyModule_local_ManagedCapacity(configuration: object): unknown;
  strategyModule_local_ManagedDuration(configuration: object): bigint | null | undefined;
  strategyModule_local_ManagedStart(configuration: object): unknown;
  strategyModule_local_ManagedStartRetained?(configuration: object): unknown;
  strategyModule_local_Dispatch(setup: unknown, task: unknown): unknown;
}>;
type LocalOutput = ReturnType<typeof prepareLocalRetainedOutput>;
type Snapshot = ReturnType<typeof prepareLocalCarrierSnapshot>;
type SnapshotDiagnostic = Awaited<ReturnType<Snapshot['roundtrip']>>;

const yieldToHost = () => new Promise<void>(resolve =>
  typeof setImmediate === 'function' ? setImmediate(resolve) : setTimeout(resolve, 0));
const managedWorkQuantum = 256;
const managedFinalizationQuantum = 32;

const validateManagedAdvance = (observation: Advance, quantum: number, errorName: string, allowPause = false) => {
  const waiting = observation?.waiting === true;
  const settlement = observation?.settlement;
  const settling = settlement !== undefined && settlement !== null;
  const paused = waiting || settling;
  if (observation == null || typeof observation !== 'object' ||
      typeof observation.complete !== 'boolean' ||
      typeof observation.progress !== 'bigint' ||
      typeof observation.work !== 'bigint' || observation.progress < 0n ||
      observation.work < 0n || observation.work > BigInt(quantum) ||
      (observation.waiting !== undefined && typeof observation.waiting !== 'boolean') ||
      (settling && (!Number.isSafeInteger(settlement) || settlement < 0)) ||
      (paused && (!allowPause || observation.complete || waiting && settling)) ||
      (!observation.complete && !paused && observation.work === 0n)) {
    throw new Error(errorName);
  }
  return observation;
};

const managedSiteCapacity = (value: unknown) => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [runtimeField(value, 0), runtimeField(value, 1)]
    : undefined;

const stopBoundedExecution = (operations: Execution, checked: SynchronousResultCheck) => {
  if (typeof operations.request_cancel !== 'function') return;
  // This is a best-effort logical stop. An observation failure must not
  // replace the original execution error; the ordinary managed-failure owner
  // still separately confirms physical cleanup and retains pending custody.
  const stopped = () => {
    try { return operations.execution_stopped?.() === true; }
    catch { return false; }
  };
  if (stopped()) return;
  try { operations.request_cancel(); } catch {}
  if (typeof operations.advance === 'function' &&
      !stopped()) {
    try { checked(operations.advance(1)); } catch {}
  }
};

// Local computation is bounded on every path: there is no synchronous
// whole-task execute fallback.
const runManagedExecution = async (
  operations: Execution, checked: SynchronousResultCheck, signal: AbortSignal | undefined,
  faultInjection: FaultInjection, task: number | undefined, handlePause: PauseHandler,
  checkpointPause: (decision: CheckpointPause) => void, moon: LocalBindings,
) => {
  if (typeof operations.advance !== 'function') {
    throw new Error('MissingBoundedLocalExecution');
  }
  while (true) {
    if (signal?.aborted) {
      stopBoundedExecution(operations, checked);
      signal.throwIfAborted();
    }
    const observation = validateManagedAdvance(
      checkedLocalManagedAdvance(moon, operations.advance(managedWorkQuantum), checked, task) as Advance,
      managedWorkQuantum,
      'InvalidLocalManagedAdvance',
      true,
    );
    if (faultInjection !== undefined && observation.work > 0n &&
        !observation.complete) {
      await faultInjection('local_compute_advanced', {
        task, progress: observation.progress.toString(),
        work: observation.work.toString(),
      });
    }
    if (signal?.aborted) {
      stopBoundedExecution(operations, checked);
      signal.throwIfAborted();
    }
    if (observation.complete) return;
    if (observation.waiting === true || observation.settlement != null) {
      if (typeof handlePause !== 'function') {
        throw new Error('MissingLocalExecutionPauseHandler');
      }
      const onAbort = () => stopBoundedExecution(operations, checked);
      signal?.addEventListener('abort', onAbort, {once: true});
      let decision: Readonly<{action?: unknown; checkpoint?: unknown}> | null | undefined;
      try {
        // No timer or further advance runs while the physical Store or the
        // existing authority owner handles this explicit pause.
        decision = await handlePause(Object.freeze({task,
          status: observation.waiting === true ? 'waiting' : 'settling',
          ...(observation.settlement == null ? {} : {slot: observation.settlement}),
          signal})) as typeof decision;
      } finally { signal?.removeEventListener('abort', onAbort); }
      signal?.throwIfAborted();
      if (decision?.action === 'waiting_checkpoint' && decision.checkpoint != null) {
        checkpointPause(decision as CheckpointPause);
        // Unwind representation uses before handing physical cleanup to the
        // caller. This private control signal is never a Run failure.
        throw decision;
      }
      if (decision?.action !== 'resume') {
        throw new Error('InvalidLocalExecutionPauseDecision');
      }
      continue;
    }
    await yieldToHost();
  }
};

const runManagedFinalization = async (
  operations: ManagedExecution, checked: SynchronousResultCheck, signal: AbortSignal | undefined,
  payload: number, storageBytes: bigint, available: () => boolean, moon: LocalBindings, task: number,
) => {
  signal?.throwIfAborted();
  checkedLocalManagedAdvance(moon, operations.prepare_finalization!(
    payload,
    storageBytes,
    available,
  ), checked, task);
  while (true) {
    if (signal?.aborted) {
      stopBoundedExecution(operations, checked);
      signal.throwIfAborted();
    }
    const observation = validateManagedAdvance(
      checkedLocalManagedAdvance(moon, operations.advance_finalization!(managedFinalizationQuantum), checked, task) as Advance,
      managedFinalizationQuantum,
      'InvalidLocalManagedFinalizationAdvance',
    );
    if (observation.complete) break;
    await yieldToHost();
  }
  signal?.throwIfAborted();
};

export function localStrategyContribution(moon: LocalBindings, setup: unknown,
  checked: SynchronousResultCheck, configuration?: object) {
  const createLease = localRetainedStore(configuration);
  const createSnapshotLease = localSnapshotStore(configuration);
  const faultInjection = localComputeFaultInjection(configuration);
  const handlePause = localExecutionPauseHandler(configuration);
  const beforePrepare = localExecutionBeforePrepare(configuration);
  const registration = moon.strategyModule_local_Registration(setup);
  let nextMaterial = 1;
  return Object.freeze({
    registration,
    managedSelectionKey: moon.strategyHostRegistrationSelectionKey(registration),
    async beforeNext(physicalSource?: unknown) {
      if (beforePrepare === undefined) return;
      const task = moon.strategyHostNextTask(setup);
      if (task >= 0 && beforePrepare !== undefined) {
        // The existing Host beforeNext boundary precedes candidate planning
        // and input selection/dispatch. It may attach its actual completed keyed read;
        // it cannot replace the selected task or replay a producer.
        await beforePrepare(task, physicalSource);
        if (moon.strategyHostNextTask(setup) !== task) throw new Error('LocalTaskChangedDuringPreparation');
      }
    },
    async prepareNext(outputs: ReadonlyMap<number, ManagedInput>) {
      // An installed row Store selects retained-file Relations. A typed
      // Carrier path still keeps its exact managed generations and snapshots;
      // a temporary snapshot must not replace the selected row-file lifetime.
      const carrierPath = createLease != null &&
        moon.strategyModule_local_NextCarrierPath?.(setup) === true;
      const task = moon.strategyHostNextTask(setup);
      const producers = moon.strategyHostManagedProducers(setup);
      if (task < 0 || !Array.isArray(producers)) return undefined;
      const inputCount = moon.strategyHostManagedInputCount(setup);
      if (!Number.isInteger(inputCount) || inputCount < 0 ||
          producers.length !== inputCount) {
        return undefined;
      }
      const inputs = producers.map((producer: number, index): ManagedInput | undefined => {
        if (producer === -1) return Object.freeze({
          task: producer,
          suppliedRelation: true,
        });
        // A preconsumer Unit may already retain its exact physical bridge
        // as this Run's receiving read. Reuse the existing captured-relation
        // route; importing the managed producer again creates another body.
        if (producer >= 0 && moon.strategyModule_local_HasPreparedRelationInput?.(setup, index) === true) {
          return Object.freeze({task: producer, capturedRelation: true});
        }
        const managed = outputs.get(producer);
        if (managed != null) return managed;
        // Common captured_task_input checks the exact completed predecessor,
        // operation binding, and live retained representation. It also covers
        // a preceding row-file task without inventing a managed output.
        return (producer >= 0 && (createLease == null ||
          moon.strategyModule_local_PredecessorIsCarrier?.(setup, producer) ===
            false)) ? Object.freeze({
          task: producer,
          capturedRelation: true,
        }) : undefined;
      });
      if (inputs.some(input => input == null)) return undefined;
      if (createLease && !carrierPath) {
        return undefined;
      }
      const relationInputs = inputs.filter(input =>
        input!.carrierMaterial == null &&
        input!.capturedRelation !== true &&
        input!.suppliedRelation !== true);
      const rowPlan = planManagedInputRows(relationInputs.map(input =>
        (input!.siteMaterial ?? input!.material)!));
      if (rowPlan === undefined) return undefined;
      const carrierAware =
        typeof moon.strategyModule_local_RelationOutput === 'function' &&
        typeof moon.strategyModule_local_CarrierOutput === 'function' &&
        typeof moon.strategyModule_local_ManagedCarrierDispatch === 'function';
      if (inputs.some(input => input!.capturedRelation === true) &&
          typeof moon.strategyModule_local_CapturedRelationInput !==
            'function') {
        return undefined;
      }
      if (inputs.some(input => input!.suppliedRelation === true) &&
          typeof moon.strategyModule_local_SuppliedRelationInput !==
            'function') {
        return undefined;
      }
      if (!carrierAware && inputs.some(input => input!.carrierMaterial != null)) {
        return undefined;
      }
      const managedOutputs = carrierAware
        ? inputs.map(input => input!.capturedRelation === true
          ? moon.strategyModule_local_CapturedRelationInput!()
          : input!.suppliedRelation === true
          ? moon.strategyModule_local_SuppliedRelationInput!()
          : input!.carrierMaterial == null
          ? moon.strategyModule_local_RelationOutput!(input!.completed)
          : moon.strategyModule_local_CarrierOutput!(
            input!.completed,
            input!.carrierMaterial,
          ))
        : inputs.map(input => input!.completed);
      const managedConfiguration = checked(
        (carrierAware
          ? moon.strategyModule_local_ManagedCarrierDispatch!
          : moon.strategyModule_local_ManagedDispatch)(
          setup,
          managedOutputs,
          0n,
        ),
      ) as object | null | undefined;
      if (managedConfiguration == null) return undefined;
      if (((createLease != null && !carrierPath) ||
           inputs.some(input => input!.capturedRelation === true)) &&
          (typeof moon.strategyModule_local_ManagedUsesProvider !==
            'function' ||
           moon.strategyModule_local_ManagedUsesProvider(
             managedConfiguration) !== true)) {
        return undefined;
      }
      const siteCapacity = managedSiteCapacity(
        moon.strategyModule_local_ManagedCapacity(managedConfiguration));
      if (!Array.isArray(siteCapacity) || siteCapacity.length !== 2 ||
          siteCapacity.some(value => typeof value !== 'bigint' || value < 0n)) {
        throw new Error('InvalidLocalManagedSiteCapacity');
      }
      return Object.freeze({
        task,
        durationMilliseconds:
          moon.strategyModule_local_ManagedDuration(managedConfiguration) ??
          null,
        acceptsSiteTransfer: inputs.every(
          input => input!.carrierMaterial == null,
        ),
        siteCapacity: Object.freeze({
          retainedBytes: siteCapacity[0] as bigint,
          executionBytes: siteCapacity[1] as bigint,
        }),
        inputs: Object.freeze(inputs.filter((input): input is ManagedInput =>
          input!.capturedRelation !== true &&
          input!.suppliedRelation !== true)),
        dispatchInputs: Object.freeze(inputs as ManagedInput[]),
        outputs,
        releasableProducers: Object.freeze(
          moon.strategyHostReleasableManagedProducers(setup)),
        configuration: managedConfiguration,
        rowPlan,
      });
    },
    async runPrepared(prepared: PreparedTask, signal?: AbortSignal) {
      signal?.throwIfAborted();
      const dispatchInputs = prepared.dispatchInputs ?? prepared.inputs;
      const plannedMaterials = dispatchInputs.map(input =>
        input.carrierMaterial == null &&
        input.capturedRelation !== true &&
        input.suppliedRelation !== true
          ? input.siteMaterial ?? input.material
          : undefined).filter(material => material !== undefined);
      const preparedRowPlan = prepared.rowPlan ??
        planManagedInputRows(plannedMaterials as object[]);
      if (preparedRowPlan === undefined) {
        throw new Error('UnsupportedManagedRowRepresentation');
      }
      const operations = checked(
        (createLease != null &&
          typeof moon.strategyModule_local_ManagedStartRetained === 'function'
          ? moon.strategyModule_local_ManagedStartRetained
          : moon.strategyModule_local_ManagedStart)(prepared.configuration),
      ) as ManagedExecution;
      const failureProgress = beginManagedFailureProgress(
        moon,
        createSnapshotLease == null || typeof operations.prepare_carrier_snapshot !== 'function',
        false,
      );
      let available = true;
      let snapshot: Snapshot | undefined, snapshotDiagnostic: SnapshotDiagnostic, relationSnapshotDiagnostic: SnapshotDiagnostic;
      let checkpointPause: CheckpointPause | undefined;
      try {
        const transfers = operations.inputs;
        const relationInputs = dispatchInputs.filter(input =>
          input.carrierMaterial == null &&
          input.capturedRelation !== true &&
          input.suppliedRelation !== true);
        const siteInputs = dispatchInputs.filter(
          input => input.capturedRelation !== true &&
            input.suppliedRelation !== true,
        );
        if (!Array.isArray(transfers) ||
            transfers.length !== relationInputs.length) {
          throw new Error('InvalidLocalManagedInputCount');
        }
        const resolved = typeof prepared.resolveSiteInputs === 'function'
          ? await prepared.resolveSiteInputs((() => {
            let relation = 0;
            return siteInputs.map(input => input.carrierMaterial == null
              ? transfers[relation++].input
              : undefined);
          })(), signal).then(value => {
            const materials: object[] = [];
            for (let index = 0; index < siteInputs.length; index++) {
              if (siteInputs[index].carrierMaterial == null) {
                materials.push(value.materials[index]);
              }
            }
            return Object.freeze({
              materials: Object.freeze(materials),
              records: value.records,
            });
          })
          : Object.freeze({
            materials: Object.freeze(relationInputs.map(input =>
              (input.siteMaterial ?? input.material)!)),
            records: Object.freeze([]),
          });
        const resolvedRowPlan = resolved.materials.length ===
            plannedMaterials.length && resolved.materials.every(
          (material, index) => material === plannedMaterials[index],
        )
          ? preparedRowPlan
          : planManagedInputRows(resolved.materials);
        if (resolvedRowPlan === undefined) {
          throw new Error('UnsupportedManagedRowRepresentation');
        }
        const retainedTransfers = operations.retained_inputs ?? [];
        if (!Array.isArray(retainedTransfers)) {
          throw new Error('InvalidLocalManagedRetainedInputs');
        }
        for (const input of retainedTransfers) {
          signal?.throwIfAborted();
          await readLocalRetainedInput(moon, input, checked, signal);
        }
        let completed: SynchronousRuntimeData | undefined;
        await withManagedInputRows(
          relationInputs.map((input, index) => ({
            material: resolved.materials[index],
            input: transfers[index].input,
            codecContractCid: undefined,
          })),
          (input, index) =>
            moon.strategyHostManagedInputMatchesMaterial(
              input,
              relationInputs[index].material!,
            ),
          (index, row) => checked(transfers[index].append(row)),
          async () => {
            for (const transfer of transfers) checked(transfer.finish());
            await runManagedExecution(operations, checked, signal,
              faultInjection, prepared.task, handlePause,
              decision => { checkpointPause = decision; }, moon);
          },
          signal,
          undefined,
          async () => {
            signal?.throwIfAborted();
            if (prepared.siteCompletionReady?.() === false) {
              throw new Error('ExecutionSiteCompletionNotReady');
            }
            const carrierMaterial = operations.carrier_material?.();
            if (carrierMaterial != null && createSnapshotLease != null &&
                typeof operations.prepare_carrier_snapshot === 'function') {
              // Keep the physical handle before the first allocation can run;
              // failures hand it to the existing common failure progression.
              snapshot = prepareLocalCarrierSnapshot(
                operations as CarrierPorts, createSnapshotLease, checked, signal,
              );
              snapshotDiagnostic = await snapshot.roundtrip();
            }
            if (carrierMaterial == null && createSnapshotLease != null &&
                typeof operations.prepare_relation_snapshot === 'function') {
              // These snapshot Results retain the SAME LocalDispatchIssue
              // error family. The existing projector reads only Err; success
              // payloads remain checked by their original snapshot consumer.
              // Reload replaces the revoked output on this SAME Task. Later
              // consumers/publication borrow that restored generation, not the
              // original memory or an unused temporary file.
              snapshot = prepareLocalRelationSnapshot(
                operations as RelationPorts, createSnapshotLease,
                result => checkedLocalManagedAdvance(moon, result, checked, prepared.task),
                signal, moon,
              );
              relationSnapshotDiagnostic = await snapshot.roundtrip();
            }
            if (carrierMaterial == null && createLease != null &&
                relationSnapshotDiagnostic == null) {
              throw new Error('LocalRelationSnapshotRequired');
            }
            const payload = nextMaterial++;
            const boundedFinalization =
              typeof operations.prepare_finalization === 'function' &&
              typeof operations.advance_finalization === 'function';
            if (carrierMaterial == null && boundedFinalization) {
              await runManagedFinalization(
                operations,
                checked,
                signal,
                payload,
                operations.storage_bytes,
                () => available,
                moon,
                prepared.task,
              );
            }
            checkedLocalManagedAdvance(moon, operations.settle(), checked, prepared.task);
            recordManagedFailureExecutionSettled(failureProgress);
            completed = carrierMaterial == null
              ? checkedLocalManagedAdvance(moon, operations.complete(
                payload,
                operations.storage_bytes,
                () => available,
              ), checked, prepared.task)
              : checkedLocalManagedAdvance(moon, operations.complete_carrier(), checked, prepared.task);
          },
          resolvedRowPlan,
        );
        const material = operations.material();
        const carrierMaterial = operations.carrier_material?.();
        if (completed == null || (material == null && carrierMaterial == null)) {
          throw new Error('MissingLocalManagedOutput');
        }
        if (carrierMaterial != null) return Object.freeze({
          completed,
          carrierMaterial,
          close: () => closeCompletedLocalManagedOutputAsync(operations, checked, failureProgress),
          diagnostic: Object.freeze({
            realization: 'local-managed',
            outputRepresentation: 'managed-local-carrier',
            outputRows: 0,
            siteTransfers: resolved.records.length,
            siteTransferRecords: resolved.records,
            ...(snapshotDiagnostic == null ? {} : {snapshot: snapshotDiagnostic}),
          }),
        });
        // Finish only runnable retirement of this completed Local scratch.
        // The same live material and any retained provider cleanup remain
        // owned; the next task cannot depend on a whole-Run cleanup pass.
        await refreshCompletedLocalManagedScratch(operations, () => available);
        const outputRows = operations.output_rows!();
        const storageBytes = BigInt(operations.storage_bytes);
        // Safe Transfer advertisement for the row-wire fallback. It covers a
        // conservative UTF-8 expansion, destination UTF-16 strings, row/index
        // administration and one bounded 1 MiB construction batch.
        const transferBytes = storageBytes * 4n + BigInt(outputRows) * 64n;
        const transferEstimate = Object.freeze({
          transferBytes,
          retainedBytes: transferBytes * 2n + BigInt(outputRows) * 96n + 128n,
          executionBytes: 1024n * 1024n,
        });
        const memory = registerManagedMemoryInput(
          material!,
          input => moon.strategyHostManagedInputMatchesMaterial(input, material!),
          () => available,
          Object.freeze({
            async read(_file, emit, readSignal) {
              const rows = operations.output_rows!();
              for (let row = 0; row < rows; row++) {
                readSignal?.throwIfAborted();
                await emit(checked(operations.output_row!(row)) as string);
              }
            },
          }),
          () => {
            available = false;
            closeCompletedLocalManagedOutput(operations, checked, failureProgress);
          },
          transferEstimate,
        );
        return Object.freeze({
          completed,
          material,
          // Retire only stopped-provider scratch, keeping this SAME live
          // material/Reference/holding available to later Effect consumers.
          refreshCompletedScratch: () => refreshCompletedLocalManagedScratch(
            operations, () => available,
          ),
          withRows: <Value,>(emit: EmitRow, readSignal: AbortSignal | undefined, commit: () => Value) => withManagedOutputRows(
            material!, emit, readSignal, commit,
          ),
          // The standard completion observer can inspect this exact retained
          // generation while the existing physical use pin is held. This is
          // not a Named Result, a new material or an independent read owner.
          readRetained: (emit: EmitRow, readSignal?: AbortSignal) => withManagedOutputRows(
            material!, emit, readSignal, () => undefined,
          ),
          close: () => closeCompletedLocalManagedOutputAsync(operations, checked, failureProgress, memory),
          diagnostic: Object.freeze({
            realization: 'local-managed',
            outputRepresentation: 'managed-local-memory',
            outputRows,
            siteTransfers: resolved.records.length,
            siteTransferRecords: resolved.records,
            ...(relationSnapshotDiagnostic == null ? {} : {relationSnapshot:relationSnapshotDiagnostic}),
          }),
        });
      } catch (error) {
        available = false;
        stopBoundedExecution(operations, checked);
        const stopped = settleFailedManagedOperations(
          operations, checked, error, failureProgress,
          snapshot == null ? [] : [{
            close: snapshot.close, cleanupHandle: snapshot.cleanupHandle,
          }],
        );
        await continueLocalManagedFailureCleanup(stopped, operations);
        if (checkpointPause !== undefined) return Object.freeze({
          status: 'waiting_checkpoint', checkpoint: (checkpointPause as CheckpointPause).checkpoint,
          cleanupPending: (stopped as CleanupObservation | null | undefined)?.cleanupPending === true,
          cleanupHandle: (stopped as CleanupObservation | null | undefined)?.cleanupHandle,
        });
        throw stopped;
      }
    },
    async run(task: unknown, signal?: AbortSignal, completionPermit?: Readonly<{assertAvailable?(): void}>) {
      signal?.throwIfAborted();
      const operations = checked(moon.strategyModule_local_Dispatch(setup, task)) as MaterializingExecution;
      const failureProgress = beginManagedFailureProgress(
        moon,
        false,
        false,
      );
      let importedRows = 0, importedBytes = 0n;
      let output: LocalOutput | undefined;
      let checkpointPause: CheckpointPause | undefined;
      try {
        if (operations.output != null) output = prepareLocalRetainedOutput(
          operations.output, createLease, checked, signal, faultInjection,
        );
        for (const input of operations.inputs) {
          signal?.throwIfAborted();
          const usage = await readLocalRetainedInput(
            moon, input, checked, signal,
          );
          importedRows += usage.rows;
          importedBytes += BigInt(usage.bytes);
        }
        await runManagedExecution(operations, checked, signal,
          faultInjection,
          typeof moon.strategyHostTask === 'function' ? moon.strategyHostTask(task) : undefined, handlePause,
          decision => { checkpointPause = decision; }, moon);
        const exported = output ? await output.write() : {};
        checked(operations.settle());
        recordManagedFailureExecutionSettled(failureProgress);
        completionPermit?.assertAvailable?.();
        checked(operations.complete());
        const guardUsage = operations.guard_usage();
        if (!Array.isArray(guardUsage) ||
            (guardUsage.length !== 0 && guardUsage.length !== 3) ||
            !guardUsage.every(value => Number.isSafeInteger(value) && value >= 0)) {
          throw new Error('MissingLocalGuardUsage');
        }
        const measuredGuardUsage = guardUsage.length === 3 ? {
          measuredGuardWork: guardUsage[0],
          measuredGuardBytes: guardUsage[1],
          measuredGuardNodes: guardUsage[2],
        } : {};
        return {diagnostic: {realization: 'local', importedRows,
          importedBytes: String(importedBytes),
          ...measuredGuardUsage, ...exported},
          publicationOutput: operations.publication_output?.(),
          close: async () => {
            try {
              output?.close();
              if (output) {
                // The output refresh verifies a disposed execution ticket.
                // Close is idempotent; physical cleanup still owns the holding.
                operations.close();
                await output.cleanupHandle.retry();
                if (output.cleanupHandle.status().pending) throw new Error('LocalOutputCleanupPending');
              }
            } catch (error) {
              // Keep both the physical Store and installed execution owner.
              // Retrying cleanup cannot re-enter Compute or re-import inputs.
              const failure = settleFailedManagedOperations(operations, checked, error,
                failureProgress, output == null ? [] : [{
                  close: () => output!.close(), cleanupHandle: output.cleanupHandle,
                }]);
              if (failure === error && output != null) {
                // The common owner has already confirmed cleanup. Still hand
                // its physical observer to the Site owner so a lost close
                // acknowledgement cannot strand an otherwise released holding.
                // A borrowed Error can be frozen or have read-only fields.
                // Keep the original failure without annotating that object.
                const reported = new Error('LocalOutputCleanupFailed', {cause: error}) as Error & {primaryFailure: unknown; cleanupPending: boolean; cleanupHandle: LocalOutput['cleanupHandle']};
                reported.primaryFailure = error;
                reported.cleanupPending = true;
                reported.cleanupHandle = output.cleanupHandle;
                throw reported;
              }
              throw failure;
            }
            await closeCompletedLocalManagedOutputAsync(operations, checked, failureProgress);
          }};
      } catch (error) {
        stopBoundedExecution(operations, checked);
        const stopped = settleFailedManagedOperations(
          operations,
          checked,
          error,
          failureProgress,
          output == null ? [] : [{
            close: () => output!.close(),
            cleanupHandle: output.cleanupHandle,
          }],
        );
        await continueLocalManagedFailureCleanup(stopped, operations);
        if (checkpointPause !== undefined) return Object.freeze({
          status: 'waiting_checkpoint', checkpoint: (checkpointPause as CheckpointPause).checkpoint,
          cleanupPending: (stopped as CleanupObservation | null | undefined)?.cleanupPending === true,
          cleanupHandle: (stopped as CleanupObservation | null | undefined)?.cleanupHandle,
        });
        throw stopped;
      }
    },
  });
}
