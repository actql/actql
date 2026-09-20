// Local connector's Node driver. The kernel and reservation authority stay in
// MoonBit; this wrapper never evaluates an expression or synthesizes a result.
import {readLocalRetainedInput} from './retained-input.mjs';
import {localRetainedStore} from './retained-store.mjs';
import {prepareLocalRetainedOutput} from './retained-output.mjs';
import {planManagedInputRows, registerManagedMemoryInput,
  withManagedInputRows, withManagedOutputRows} from
  '../store-local/managed-memory-representations.mjs';
import {beginManagedFailureProgress, recordManagedFailureExecutionSettled,
  settleFailedManagedOperations} from
  '../host-common/managed-failure.mjs';

const yieldToHost = () => new Promise(resolve => setTimeout(resolve, 0));
const managedWorkQuantum = 256;
const managedFinalizationQuantum = 32;

const validateManagedAdvance = (observation, quantum, errorName) => {
  if (observation == null || typeof observation !== 'object' ||
      typeof observation.complete !== 'boolean' ||
      typeof observation.progress !== 'bigint' ||
      typeof observation.work !== 'bigint' || observation.progress < 0n ||
      observation.work < 0n || observation.work > BigInt(quantum) ||
      (!observation.complete && observation.work === 0n)) {
    throw new Error(errorName);
  }
  return observation;
};

const managedSiteCapacity = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;

const stopBoundedExecution = (operations, checked) => {
  if (typeof operations.request_cancel !== 'function') return;
  if (operations.execution_stopped?.() === true) return;
  try { operations.request_cancel(); } catch {}
  if (typeof operations.advance === 'function' &&
      operations.execution_stopped?.() !== true) {
    try { checked(operations.advance(1)); } catch {}
  }
};

const runManagedExecution = async (operations, checked, signal) => {
  if (typeof operations.advance !== 'function') {
    signal?.throwIfAborted();
    checked(operations.execute());
    return;
  }
  while (true) {
    if (signal?.aborted) {
      stopBoundedExecution(operations, checked);
      signal.throwIfAborted();
    }
    const observation = validateManagedAdvance(
      checked(operations.advance(managedWorkQuantum)),
      managedWorkQuantum,
      'InvalidLocalManagedAdvance',
    );
    if (observation.complete) return;
    await yieldToHost();
  }
};

const runManagedFinalization = async (
  operations, checked, signal, payload, storageBytes, available,
) => {
  signal?.throwIfAborted();
  checked(operations.prepare_finalization(
    payload,
    storageBytes,
    available,
  ));
  while (true) {
    if (signal?.aborted) {
      stopBoundedExecution(operations, checked);
      signal.throwIfAborted();
    }
    const observation = validateManagedAdvance(
      checked(operations.advance_finalization(managedFinalizationQuantum)),
      managedFinalizationQuantum,
      'InvalidLocalManagedFinalizationAdvance',
    );
    if (observation.complete) break;
    await yieldToHost();
  }
  signal?.throwIfAborted();
};

export function localStrategyContribution(moon, setup, checked, configuration) {
  const createLease = localRetainedStore(configuration);
  const registration = moon.strategyModule_local_Registration(setup);
  let nextMaterial = 1;
  return Object.freeze({
    registration,
    managedSelectionKey: moon.strategyHostRegistrationSelectionKey(registration),
    async prepareNext(outputs) {
      const task = moon.strategyHostNextTask(setup);
      const producers = moon.strategyHostManagedProducers(setup);
      if (task < 1 || !Array.isArray(producers)) return undefined;
      const inputCount = moon.strategyHostManagedInputCount(setup);
      if (!Number.isInteger(inputCount) || inputCount < 0 ||
          producers.length !== inputCount) {
        return undefined;
      }
      const inputs = producers.map(producer => {
        const managed = outputs.get(producer);
        if (managed != null) return managed;
        // Producer zero is the checked Acquisition boundary. Other ordinary
        // task outputs remain on the legacy dispatcher until a common Host
        // contract admits their mixed lifecycle explicitly.
        return producer === 0 ? Object.freeze({
          task: producer,
          capturedRelation: true,
        }) : undefined;
      });
      if (inputs.some(input => input == null)) return undefined;
      const relationInputs = inputs.filter(input =>
        input.carrierMaterial == null && input.capturedRelation !== true);
      const rowPlan = planManagedInputRows(relationInputs.map(input =>
        input.siteMaterial ?? input.material));
      if (rowPlan === undefined) return undefined;
      const carrierAware =
        typeof moon.strategyModule_local_RelationOutput === 'function' &&
        typeof moon.strategyModule_local_CarrierOutput === 'function' &&
        typeof moon.strategyModule_local_ManagedCarrierDispatch === 'function';
      if (inputs.some(input => input.capturedRelation === true) &&
          typeof moon.strategyModule_local_CapturedRelationInput !==
            'function') {
        return undefined;
      }
      if (!carrierAware && inputs.some(input => input.carrierMaterial != null)) {
        return undefined;
      }
      const managedOutputs = carrierAware
        ? inputs.map(input => input.capturedRelation === true
          ? moon.strategyModule_local_CapturedRelationInput()
          : input.carrierMaterial == null
          ? moon.strategyModule_local_RelationOutput(input.completed)
          : moon.strategyModule_local_CarrierOutput(
            input.completed,
            input.carrierMaterial,
          ))
        : inputs.map(input => input.completed);
      const managedConfiguration = checked(
        (carrierAware
          ? moon.strategyModule_local_ManagedCarrierDispatch
          : moon.strategyModule_local_ManagedDispatch)(
          setup,
          managedOutputs,
          0n,
        ),
      );
      if (managedConfiguration == null) return undefined;
      if (inputs.some(input => input.capturedRelation === true) &&
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
          moon.strategyModule_local_ManagedDuration(managedConfiguration),
        acceptsSiteTransfer: true,
        siteCapacity: Object.freeze({
          retainedBytes: siteCapacity[0],
          executionBytes: siteCapacity[1],
        }),
        inputs: Object.freeze(inputs.filter(input =>
          input.capturedRelation !== true)),
        dispatchInputs: Object.freeze(inputs),
        outputs,
        releasableProducers: Object.freeze(
          moon.strategyHostReleasableManagedProducers(setup)),
        configuration: managedConfiguration,
        rowPlan,
      });
    },
    async runPrepared(prepared, signal) {
      signal?.throwIfAborted();
      const dispatchInputs = prepared.dispatchInputs ?? prepared.inputs;
      const plannedMaterials = dispatchInputs.map(input =>
        input.carrierMaterial == null && input.capturedRelation !== true
          ? input.siteMaterial ?? input.material
          : undefined).filter(material => material !== undefined);
      const preparedRowPlan = prepared.rowPlan ??
        planManagedInputRows(plannedMaterials);
      if (preparedRowPlan === undefined) {
        throw new Error('UnsupportedManagedRowRepresentation');
      }
      const operations = checked(
        moon.strategyModule_local_ManagedStart(prepared.configuration),
      );
      const failureProgress = beginManagedFailureProgress(
        moon,
        true,
        typeof operations.cleanup_refresh !== 'function',
      );
      let available = true;
      try {
        const transfers = operations.inputs;
        const relationInputs = dispatchInputs.filter(input =>
          input.carrierMaterial == null && input.capturedRelation !== true);
        if (!Array.isArray(transfers) ||
            transfers.length !== relationInputs.length) {
          throw new Error('InvalidLocalManagedInputCount');
        }
        const resolved = typeof prepared.resolveSiteInputs === 'function'
          ? await prepared.resolveSiteInputs(
            transfers.map(transfer => transfer.input), signal,
          )
          : Object.freeze({
            materials: Object.freeze(relationInputs.map(input =>
              input.siteMaterial ?? input.material)),
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
        let completed;
        await withManagedInputRows(
          relationInputs.map((input, index) => ({
            material: resolved.materials[index],
            input: transfers[index].input,
            codecContractCid: undefined,
          })),
          (input, index) =>
            moon.strategyHostManagedInputMatchesMaterial(
              input,
              relationInputs[index].material,
            ),
          (index, row) => checked(transfers[index].append(row)),
          async () => {
            for (const transfer of transfers) checked(transfer.finish());
            await runManagedExecution(operations, checked, signal);
          },
          signal,
          undefined,
          async () => {
            signal?.throwIfAborted();
            if (prepared.siteCompletionReady?.() === false) {
              throw new Error('ExecutionSiteCompletionNotReady');
            }
            const carrierMaterial = operations.carrier_material?.();
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
              );
            }
            checked(operations.settle());
            recordManagedFailureExecutionSettled(failureProgress);
            completed = carrierMaterial == null
              ? checked(operations.complete(
                payload,
                operations.storage_bytes,
                () => available,
              ))
              : checked(operations.complete_carrier());
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
          close: () => operations.close(),
          diagnostic: Object.freeze({
            realization: 'local-managed',
            outputRepresentation: 'managed-local-carrier',
            outputRows: 0,
            siteTransfers: resolved.records.length,
            siteTransferRecords: resolved.records,
          }),
        });
        const outputRows = operations.output_rows();
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
          material,
          input => moon.strategyHostManagedInputMatchesMaterial(input, material),
          () => available,
          Object.freeze({
            async read(_file, emit, readSignal) {
              const rows = operations.output_rows();
              for (let row = 0; row < rows; row++) {
                readSignal?.throwIfAborted();
                await emit(checked(operations.output_row(row)));
              }
            },
          }),
          () => {
            available = false;
            operations.close();
          },
          transferEstimate,
        );
        return Object.freeze({
          completed,
          material,
          withRows: (emit, readSignal, commit) => withManagedOutputRows(
            material, emit, readSignal, commit,
          ),
          close: () => memory.close(),
          diagnostic: Object.freeze({
            realization: 'local-managed',
            outputRepresentation: 'managed-local-memory',
            outputRows,
            siteTransfers: resolved.records.length,
            siteTransferRecords: resolved.records,
          }),
        });
      } catch (error) {
        available = false;
        stopBoundedExecution(operations, checked);
        throw settleFailedManagedOperations(
          operations, checked, error, failureProgress,
        );
      }
    },
    async run(task, signal, completionPermit) {
      signal?.throwIfAborted();
      const operations = checked(moon.strategyModule_local_Dispatch(setup, task));
      const failureProgress = beginManagedFailureProgress(
        moon,
        false,
        typeof operations.cleanup_refresh !== 'function',
      );
      let importedRows = 0, importedBytes = 0n;
      let output;
      try {
        if (operations.output != null) output = prepareLocalRetainedOutput(operations.output, createLease, checked, signal);
        for (const input of operations.inputs) {
          signal?.throwIfAborted();
          const usage = await readLocalRetainedInput(
            moon, input, checked, signal,
          );
          importedRows += usage.rows;
          importedBytes += BigInt(usage.bytes);
        }
        signal?.throwIfAborted();
        checked(operations.execute());
        const exported = output ? await output.write() : {};
        checked(operations.settle());
        recordManagedFailureExecutionSettled(failureProgress);
        completionPermit?.assertAvailable?.();
        checked(operations.complete());
        return {diagnostic: {realization: 'local', importedRows, importedBytes: String(importedBytes), ...exported},
          close: output ? async () => {
            output?.close();
            operations.close();
            if (output) {
              try {
                await output.cleanupHandle.retry();
                if (output.cleanupHandle.status().pending) throw new Error('LocalOutputCleanupPending');
              } catch (error) {
                const failure = error instanceof Error ? error : new Error('LocalOutputCleanupFailed');
                failure.cleanupHandle = output.cleanupHandle;
                throw failure;
              }
            }
          } : () => operations.close()};
      } catch (error) {
        throw settleFailedManagedOperations(
          operations,
          checked,
          error,
          failureProgress,
          output == null ? [] : [{
            close: () => output.close(),
            cleanupHandle: output.cleanupHandle,
          }],
        );
      }
    },
  });
}
