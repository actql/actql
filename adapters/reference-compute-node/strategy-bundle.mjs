// In-process independent Compute implementation. No DB, transport settings or
// attempt settlement in application code; the connector-owned entry completes it.
import {managedInputCodecContractCid, managedInputSupportsRows,
  registerManagedMemoryInput,
  withManagedInputRows} from '../store-local/managed-memory-representations.mjs';

export function numericStrategyContribution(moon, setup, checked) {
  const registration = moon.strategyModule_reference_compute_Registration(setup);
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
          !managedInputSupportsRows(input.material))) return undefined;
      // Normal file-backed work remains with the lower-cost native candidate.
      // Once a representation-neutral candidate has produced an in-memory
      // material, this implementation can continue the checked graph without
      // pretending that material is a DuckDB file representation.
      if (!checked(moon.strategyHostManagedRequiresLogicalIdentity(setup)) &&
          inputs.some(input =>
            managedInputCodecContractCid(input.material) !== undefined)) {
        return undefined;
      }
      let configuration;
      try {
        configuration = checked(
          moon.strategyModule_reference_compute_ManagedDispatch(
            setup,
            inputs.map(input => input.completed),
            0n,
          ),
        );
      } catch {
        return undefined;
      }
      return Object.freeze({
        task,
        durationMilliseconds: 1n,
        inputs: Object.freeze(inputs),
        outputs,
        releasableProducers: Object.freeze(
          moon.strategyHostReleasableManagedProducers(setup)),
        configuration,
      });
    },
    async runPrepared(prepared, signal) {
      for (const producer of prepared.releasableProducers) {
        const output = prepared.outputs.get(producer);
        if (output?.close) await output.close();
        prepared.outputs.delete(producer);
      }
      signal?.throwIfAborted();
      const operations = checked(
        moon.strategyModule_reference_compute_ManagedStart(
          prepared.configuration,
        ),
      );
      let available = true;
      try {
        const transfers = operations.inputs;
        if (!Array.isArray(transfers) ||
            transfers.length !== prepared.inputs.length) {
          throw new Error('InvalidReferenceManagedInputCount');
        }
        let completed;
        await withManagedInputRows(
          prepared.inputs.map((input, index) => ({
            material: input.material,
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
            checked(operations.settle());
            completed = checked(operations.complete(
              nextMaterial++,
              operations.storage_bytes,
              () => available,
            ));
          },
          signal,
        );
        const material = operations.material();
        if (completed == null || material == null) {
          throw new Error('MissingReferenceManagedOutput');
        }
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
        );
        return Object.freeze({
          completed,
          material,
          close: () => memory.close(),
          diagnostic: Object.freeze({
            realization: 'reference-numeric-managed',
            outputRepresentation: 'managed-reference-memory',
          }),
        });
      } catch (error) {
        available = false;
        operations.close();
        throw error;
      }
    },
    async run(task) {
      checked(moon.strategyModule_reference_compute_Dispatch(setup, task));
      return {diagnostic: {realization: 'reference-numeric'}};
    },
  });
}
