// DuckDB-specific execution and resident session lifetime. The common serial
// driver never interprets this resource policy, tables, imports or SQL.
import { runStrategyHostCompute, runRetainedStrategyHostCompute,
  runManagedRetainedStrategyHostCompute, runManagedColumnStrategyHostCompute,
  openResidentStrategyEnvironment,
  importResidentStrategyInput, runResidentStrategyHostCompute } from './host.mjs';

import {preparedStrategyConfiguration} from './configuration.mjs';
import {managedInputCodecContractCid} from '../../../store-local/managed-representations.mjs';
import {managedColumnCodecContractCid} from './managed-column-codec.mjs';
import {managedParquetCodecContractCid} from './managed-parquet-codec.mjs';
import {computePhysicalCapacity} from './physical-capacity.mjs';

const managedSiteCapacity = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;

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
  const registration = moon.strategyModule_duckdb_Registration(setup);
  return Object.freeze({
    registration,
    managedSelectionKey: moon.strategyHostRegistrationSelectionKey(registration),
    async prepareNext(outputs) {
      if (!options.managedOutput) return undefined;
      const task = moon.strategyHostNextTask(setup);
      const producers = moon.strategyHostManagedProducers(setup);
      if (task < 1 || !Array.isArray(producers) || producers.length === 0) {
        return undefined;
      }
      if (checked(moon.strategyHostManagedRequiresLogicalIdentity(setup))) {
        return undefined;
      }
      const inputs = producers.map(producer => outputs.get(producer));
      const inputCodecContractCids = inputs.map(input =>
        managedInputCodecContractCid(
          input == null ? undefined : input.siteMaterial ?? input.material,
        ));
      if (producers.some(producer => producer < 1) ||
          inputs.some(input => input == null) ||
          inputCodecContractCids.some(cid =>
            ![managedColumnCodecContractCid, managedParquetCodecContractCid]
              .includes(cid))) {
        return undefined;
      }
      const managedConfiguration = checked(
        moon.strategyModule_duckdb_ManagedDispatch(
          setup, inputs.map(input => input.completed),
          BigInt(options.managedOutput.wire.max_bytes),
        ),
      );
      if (managedConfiguration == null) return undefined;
      const connectorSiteCapacity = managedSiteCapacity(
        moon.strategyModule_duckdb_ManagedCapacity(managedConfiguration));
      const nativeSiteCapacity = computePhysicalCapacity(limits);
      if (!Array.isArray(connectorSiteCapacity) ||
          connectorSiteCapacity.length !== 2 ||
          connectorSiteCapacity.some(value =>
            typeof value !== 'bigint' || value < 0n)) {
        throw new Error('InvalidDuckDBManagedSiteCapacity');
      }
      return Object.freeze({
        task,
        durationMilliseconds:
          moon.strategyModule_duckdb_ManagedDuration(managedConfiguration),
        inputs: Object.freeze(inputs),
        siteCapacity: Object.freeze({
          retainedBytes: connectorSiteCapacity[0],
          executionBytes:
            connectorSiteCapacity[1] + nativeSiteCapacity.executionBytes,
        }),
        outputs,
        releasableProducers: Object.freeze(
          moon.strategyHostReleasableManagedProducers(setup)),
        inputCodecContractCids: Object.freeze(inputCodecContractCids),
        configuration: managedConfiguration,
      });
    },
    async runPrepared(prepared, signal) {
      const result = await runManagedColumnStrategyHostCompute(
        prepared.configuration,
        prepared.inputs.map(input => input.siteMaterial ?? input.material),
        prepared.inputCodecContractCids,
        limits,
        options.managedOutput,
        signal,
        prepared.siteCompletionReady,
      );
      return Object.freeze({
        ...result,
        diagnostic: Object.freeze({
          realization: 'duckdb-managed',
          transport: result.usage,
          phases: result.diagnostics,
          outputRepresentation: result.representation,
        }),
      });
    },
    async beforeNext() {
      await closeEnvironments([...environments].filter(([, value]) => !value.status().live));
    },
    async run(task, signal, completionPermit) {
      const index = moon.strategyHostTask(task);
      const resident = moon.strategyHostResident(task);
      const inputs = [];
      let mapping;
      let environment;
      let environmentCreated = false;
      let environmentOpenMilliseconds = 0;
      let importMilliseconds = 0;
      const imported = [];
      if (resident) {
        const binding = moon.strategyHostResourceBinding(task);
        if (binding == null) throw new Error('MissingResidentResourceBinding');
        environment = environments.get(binding);
        if (!environment) {
          const openedAt = performance.now();
          environment = await openResidentStrategyEnvironment(moon.strategyHostRun(setup), index, limits);
          environmentOpenMilliseconds = performance.now() - openedAt;
          environments.set(binding, environment);
          environmentCreated = true;
        }
        for (const [producer, bytes, entries, names] of checked(moon.strategyHostResidentInputs(setup, index))) {
          mapping = { maxEntries: Number(entries), maxNameBytes: Number(names) };
          if (!environment.hasTable(Number(producer))) {
            const importedAt = performance.now();
            const result = await importResidentStrategyInput(environment, Number(producer), bytes, limits, mapping, signal);
            const milliseconds = performance.now() - importedAt;
            importMilliseconds += milliseconds;
            imported.push(Object.freeze({producer: Number(producer), rows: result.importedRows,
              milliseconds, transport: result.usage}));
          }
          inputs.push(environment.table(Number(producer)));
        }
      }
      const selected = checked(moon.strategyModule_duckdb_Dispatch(setup, task));
      const result = options.managedOutput
        ? await runManagedRetainedStrategyHostCompute(
          selected, limits, imports, options.managedOutput, signal,
          `task-${index}`, completionPermit?.isAvailable,
        )
        : resident
        ? await runResidentStrategyHostCompute(
          selected, environment, inputs, limits, mapping, signal,
          options.retainedOutput, `task-${index}`,
          completionPermit?.isAvailable,
        )
        : options.retainedOutput
          ? await runRetainedStrategyHostCompute(
            selected, limits, imports, options.retainedOutput, signal,
            `task-${index}`, completionPermit?.isAvailable,
          )
          : await runStrategyHostCompute(
            selected, limits, imports, signal, completionPermit?.isAvailable,
          );
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
          preparation: Object.freeze({environmentCreated, environmentOpenMilliseconds,
            importMilliseconds, imports: Object.freeze(imported)}),
        }),
      });
    },
    async finish() { await closeEnvironments([...environments]); },
  });
}
