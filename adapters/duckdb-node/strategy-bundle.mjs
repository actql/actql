// DuckDB-specific execution and resident session lifetime. The common serial
// driver never interprets this resource policy, tables, imports or SQL.
import { runStrategyHostCompute, runRetainedStrategyHostCompute,
  runManagedRetainedStrategyHostCompute, runManagedColumnStrategyHostCompute,
  managedColumnCodecContractCid, openResidentStrategyEnvironment,
  importResidentStrategyInput, runResidentStrategyHostCompute } from './host.mjs';

import {preparedStrategyConfiguration} from './configuration.mjs';

export function duckdbStrategyContribution(moon, setup, checked, configuration) {
  const options = preparedStrategyConfiguration(configuration);
  const limits = Object.freeze({ ...options.transportLimits });
  const imports = Object.freeze({ ...options.importLimits });
  const environments = new Map();
  async function closeEnvironments(entries) {
    const failures = [];
    for (const [binding, environment] of entries) {
      try {
        await environment.close();
        environments.delete(binding);
      } catch (error) { failures.push(error); }
    }
    if (failures.length) {
      // Keep every unsettled environment reachable; one failed close must not
      // prevent other bindings from being reclaimed.
      throw Object.assign(new AggregateError(failures, 'ResidentCleanupPending'), {
        cleanupPending: true,
        cleanupHandle: Object.freeze({
          status: () => ({pending: environments.size !== 0}),
          retry: () => closeEnvironments([...environments]),
        }),
      });
    }
  }
  return Object.freeze({
    registration: moon.strategyModule_duckdb_Registration(setup),
    prepareNext(outputs) {
      if (!options.managedOutput) return undefined;
      const task = moon.strategyHostNextTask(setup);
      const producer = moon.strategyHostManagedProducer(setup);
      const input = outputs.get(producer);
      if (task < 1 || producer < 1 || input == null) return undefined;
      return Object.freeze({
        task,
        input,
        configuration: checked(
          moon.strategyModule_duckdb_ManagedDispatch(
            setup, input.completed, BigInt(options.managedOutput.wire.max_bytes),
          ),
        ),
      });
    },
    async runPrepared(prepared, signal) {
      const result = await runManagedColumnStrategyHostCompute(
        prepared.configuration,
        prepared.input.material,
        managedColumnCodecContractCid,
        limits,
        options.managedOutput,
        signal,
      );
      return Object.freeze({
        ...result,
        diagnostic: Object.freeze({
          realization: 'duckdb-managed',
          transport: result.usage,
          phases: result.diagnostics,
          outputRepresentation: 'managed-column-file',
        }),
      });
    },
    async beforeNext() {
      await closeEnvironments([...environments].filter(([, value]) => !value.status().live));
    },
    async run(task, signal) {
      const index = moon.strategyHostTask(task);
      const resident = moon.strategyHostResident(task);
      const inputs = [];
      let mapping;
      let environment;
      let environmentCreated = false;
      const imported = [];
      if (resident) {
        const binding = moon.strategyHostResourceBinding(task);
        if (binding == null) throw new Error('MissingResidentResourceBinding');
        environment = environments.get(binding);
        if (!environment) {
          environment = await openResidentStrategyEnvironment(moon.strategyHostRun(setup), index, limits);
          environments.set(binding, environment);
          environmentCreated = true;
        }
        for (const [producer, bytes, entries, names] of checked(moon.strategyHostResidentInputs(setup, index))) {
          mapping = { maxEntries: Number(entries), maxNameBytes: Number(names) };
          if (!environment.hasTable(Number(producer))) {
            const result = await importResidentStrategyInput(environment, Number(producer), bytes, limits, mapping, signal);
            imported.push(Object.freeze({producer: Number(producer), rows: result.importedRows, transport: result.usage}));
          }
          inputs.push(environment.table(Number(producer)));
        }
      }
      const selected = checked(moon.strategyModule_duckdb_Dispatch(setup, task));
      const result = options.managedOutput
        ? await runManagedRetainedStrategyHostCompute(
          selected, limits, imports, options.managedOutput, signal, `task-${index}`,
        )
        : resident
        ? await runResidentStrategyHostCompute(selected, environment, inputs, limits, mapping, signal,
          options.retainedOutput, `task-${index}`)
        : options.retainedOutput
          ? await runRetainedStrategyHostCompute(selected, limits, imports, options.retainedOutput, signal, `task-${index}`)
          : await runStrategyHostCompute(selected, limits, imports, signal);
      return Object.freeze({
        completed: result.completed,
        material: result.material,
        close: () => result.close(),
        diagnostic: Object.freeze({
          realization: options.managedOutput ? 'duckdb-managed'
            : resident ? 'duckdb-resident' : 'duckdb', transport: result.usage,
          phases: result.diagnostics,
          outputRepresentation: options.managedOutput ? 'managed-column-file'
            : options.retainedOutput ? 'retained-file' : 'memory',
          preparation: Object.freeze({environmentCreated, imports: Object.freeze(imported)}),
        }),
      });
    },
    async finish() { await closeEnvironments([...environments]); },
  });
}
