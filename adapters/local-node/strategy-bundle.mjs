// Local connector's Node driver. The kernel and reservation authority stay in
// MoonBit; this wrapper never evaluates an expression or synthesizes a result.
import {readLocalRetainedInput} from './retained-input.mjs';
import {localRetainedStore} from './retained-store.mjs';
import {prepareLocalRetainedOutput} from './retained-output.mjs';
import {planManagedInputRows, registerManagedMemoryInput,
  withManagedInputRows} from '../store-local/managed-memory-representations.mjs';
import {settleFailedManagedOperations} from
  '../host-common/managed-failure.mjs';

const managedSiteCapacity = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;

export function localStrategyContribution(moon, setup, checked, configuration) {
  const createLease = localRetainedStore(configuration);
  const registration = moon.strategyModule_local_Registration(setup);
  const failureAction = (...facts) =>
    moon.strategyHostManagedFailureAction(...facts);
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
          producers.length !== inputCount ||
          checked(moon.strategyHostManagedRequiresLogicalIdentity(setup))) {
        return undefined;
      }
      const inputs = producers.map(producer => outputs.get(producer));
      if (inputs.some(input => input == null)) return undefined;
      const rowPlan = planManagedInputRows(inputs.map(input =>
        input.siteMaterial ?? input.material));
      if (rowPlan === undefined) return undefined;
      const managedConfiguration = checked(
        moon.strategyModule_local_ManagedDispatch(
          setup,
          inputs.map(input => input.completed),
          0n,
        ),
      );
      if (managedConfiguration == null) return undefined;
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
        inputs: Object.freeze(inputs),
        outputs,
        releasableProducers: Object.freeze(
          moon.strategyHostReleasableManagedProducers(setup)),
        configuration: managedConfiguration,
        rowPlan,
      });
    },
    async runPrepared(prepared, signal) {
      signal?.throwIfAborted();
      const plannedMaterials = prepared.inputs.map(input =>
        input.siteMaterial ?? input.material);
      const preparedRowPlan = prepared.rowPlan ??
        planManagedInputRows(plannedMaterials);
      if (preparedRowPlan === undefined) {
        throw new Error('UnsupportedManagedRowRepresentation');
      }
      const operations = checked(
        moon.strategyModule_local_ManagedStart(prepared.configuration),
      );
      let available = true;
      let settled = false;
      try {
        const transfers = operations.inputs;
        if (!Array.isArray(transfers) ||
            transfers.length !== prepared.inputs.length) {
          throw new Error('InvalidLocalManagedInputCount');
        }
        const resolved = typeof prepared.resolveSiteInputs === 'function'
          ? await prepared.resolveSiteInputs(
            transfers.map(transfer => transfer.input), signal,
          )
          : Object.freeze({
            materials: Object.freeze(prepared.inputs.map(input =>
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
          prepared.inputs.map((input, index) => ({
            material: resolved.materials[index],
            input: transfers[index].input,
            codecContractCid: undefined,
          })),
          (input, index) =>
            moon.strategyHostManagedInputMatchesMaterial(
              input,
              prepared.inputs[index].material,
            ),
          (index, row) => checked(transfers[index].append(row)),
          async () => {
            for (const transfer of transfers) checked(transfer.finish());
            checked(operations.execute());
          },
          signal,
          undefined,
          async () => {
            signal?.throwIfAborted();
            if (prepared.siteCompletionReady?.() === false) {
              throw new Error('ExecutionSiteCompletionNotReady');
            }
            checked(operations.settle());
            settled = true;
            completed = checked(operations.complete(
              nextMaterial++,
              operations.storage_bytes,
              () => available,
            ));
          },
          resolvedRowPlan,
        );
        const material = operations.material();
        if (completed == null || material == null) {
          throw new Error('MissingLocalManagedOutput');
        }
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
        throw settleFailedManagedOperations(
          operations, checked, error, settled,
          [], failureAction,
        );
      }
    },
    async run(task, signal, completionPermit) {
      signal?.throwIfAborted();
      const operations = checked(moon.strategyModule_local_Dispatch(setup, task));
      let settled = false;
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
        settled = true;
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
          settled,
          output == null ? [] : [{
            close: () => output.close(),
            cleanupHandle: output.cleanupHandle,
          }],
          failureAction,
        );
      }
    },
  });
}
