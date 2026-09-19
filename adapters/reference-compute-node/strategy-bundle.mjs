// In-process independent Compute implementation. No DB, transport settings or
// attempt settlement in application code; the connector-owned entry completes it.
import {managedInputCodecContractCid, managedInputSupportsRows,
  registerManagedMemoryInput,
  withManagedInputRows} from '../store-local/managed-memory-representations.mjs';
import {settleFailedManagedOperations} from
  '../host-common/managed-failure.mjs';

const managedSiteCapacity = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;

export function numericStrategyContribution(moon, setup, checked) {
  const registration = moon.strategyModule_reference_compute_Registration(setup);
  const failureAction = (...facts) =>
    moon.strategyHostManagedFailureAction(...facts);
  let nextMaterial = 1;
  return Object.freeze({
    registration,
    managedSelectionKey: moon.strategyHostRegistrationSelectionKey(registration),
    async prepareNext(outputs) {
      const task = moon.strategyHostNextTask(setup);
      const producers = moon.strategyHostManagedProducers(setup);
      if (task < 1 || !Array.isArray(producers) || producers.length !== 1) {
        return undefined;
      }
      const inputs = producers.map(producer => outputs.get(producer));
      if (inputs.some(input => input == null ||
          !managedInputSupportsRows(input.siteMaterial ?? input.material))) {
        return undefined;
      }
      // Normal file-backed work remains with the lower-cost native candidate.
      // Once a representation-neutral candidate has produced an in-memory
      // material, this implementation can continue the checked graph without
      // pretending that material is a DuckDB file representation.
      if (!checked(moon.strategyHostManagedRequiresLogicalIdentity(setup)) &&
        inputs.some(input =>
            managedInputCodecContractCid(
              input.siteMaterial ?? input.material,
            ) !== undefined)) {
        return undefined;
      }
      const configuration = checked(
        moon.strategyModule_reference_compute_ManagedDispatch(
          setup,
          inputs.map(input => input.completed),
          0n,
        ),
      );
      if (configuration == null) return undefined;
      const siteCapacity = managedSiteCapacity(
        moon.strategyModule_reference_compute_ManagedCapacity(configuration));
      if (!Array.isArray(siteCapacity) || siteCapacity.length !== 2 ||
          siteCapacity.some(value => typeof value !== 'bigint' || value < 0n)) {
        throw new Error('InvalidReferenceManagedSiteCapacity');
      }
      return Object.freeze({
        task,
        durationMilliseconds:
          moon.strategyModule_reference_compute_ManagedDuration(configuration),
        acceptsSiteTransfer: true,
        siteCapacity: Object.freeze({
          retainedBytes: siteCapacity[0],
          executionBytes: siteCapacity[1],
        }),
        inputs: Object.freeze(inputs),
        outputs,
        releasableProducers: Object.freeze(
          moon.strategyHostReleasableManagedProducers(setup)),
        configuration,
      });
    },
    async runPrepared(prepared, signal) {
      signal?.throwIfAborted();
      const operations = checked(
        moon.strategyModule_reference_compute_ManagedStart(
          prepared.configuration,
        ),
      );
      let available = true;
      let settled = false;
      try {
        const transfers = operations.inputs;
        if (!Array.isArray(transfers) ||
            transfers.length !== prepared.inputs.length) {
          throw new Error('InvalidReferenceManagedInputCount');
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
        let completed;
        await withManagedInputRows(
          prepared.inputs.map((input, index) => ({
            material: resolved.materials[index],
            input: transfers[index].input,
            codecContractCid: undefined,
          })),
          (input, index) => moon.strategyHostManagedInputMatchesMaterial(
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
        );
        const material = operations.material();
        if (completed == null || material == null) {
          throw new Error('MissingReferenceManagedOutput');
        }
        const outputRows = operations.output_rows();
        const storageBytes = BigInt(operations.storage_bytes);
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
            realization: 'reference-numeric-managed',
            outputRepresentation: 'managed-reference-memory',
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
    async run(task, _signal, completionPermit) {
      checked(moon.strategyModule_reference_compute_Dispatch(
        setup,
        task,
        () => completionPermit?.isAvailable?.() !== false,
      ));
      return {diagnostic: {realization: 'reference-numeric'}};
    },
  });
}
