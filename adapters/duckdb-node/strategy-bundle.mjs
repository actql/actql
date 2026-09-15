// DuckDB-specific execution and resident session lifetime. The common serial
// driver never interprets this resource policy, tables, imports or SQL.
import { runStrategyHostCompute, openResidentStrategyEnvironment,
  importResidentStrategyInput, runResidentStrategyHostCompute } from './host.mjs';

export function duckdbStrategyContribution(moon, setup, checked, options) {
  const limits = Object.freeze({ ...options.transportLimits });
  const imports = Object.freeze({ ...options.importLimits });
  let environment;
  return Object.freeze({
    registration: moon.strategyHostDuckdbRegistration(setup),
    async beforeNext() {
      if (environment && !environment.status().live) {
        await environment.close();
        environment = undefined;
      }
    },
    async run(task, signal) {
      const index = moon.strategyHostTask(task);
      const resident = moon.strategyHostResident(task);
      const inputs = [];
      let mapping;
      if (resident) {
        environment ??= await openResidentStrategyEnvironment(moon.strategyHostRun(setup), index, limits);
        for (const [producer, bytes, entries, names] of checked(moon.strategyHostResidentInputs(setup, index))) {
          mapping = { maxEntries: Number(entries), maxNameBytes: Number(names) };
          if (!environment.hasTable(Number(producer))) {
            await importResidentStrategyInput(environment, Number(producer), bytes, limits, mapping, signal);
          }
          inputs.push(environment.table(Number(producer)));
        }
      }
      const selected = checked(moon.strategyHostTakeNative(task));
      const result = resident
        ? await runResidentStrategyHostCompute(selected, environment, inputs, limits, mapping, signal)
        : await runStrategyHostCompute(selected, limits, imports, signal);
      return Object.freeze({
        close: () => result.close(),
        diagnostic: Object.freeze({
          realization: resident ? 'duckdb-resident' : 'duckdb', transport: result.usage,
        }),
      });
    },
    async finish() { if (environment) await environment.close(); },
  });
}
