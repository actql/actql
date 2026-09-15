// Standard composition entry. Callers cannot replace the runtime, installed
// implementation factories, verification or SQL through execution options.
import {runInstalledStrategy} from '../host-node/strategy.mjs';
import {installStrategyContributions} from '../connectors-builtin/strategy.generated.mjs';
import {checked} from './runtime-result.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/duckdb_host_node/duckdb_host_node.js', import.meta.url);
let runtime;
const usageKeys = ['planningWork', 'attempts', 'holdings', 'transferredBytes',
  'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes'];

export async function runCapturedStrategy(setup, transportLimits, importLimits, signal) {
  const moon = await (runtime ??= import(runtimeUrl.href));
  const core = Object.freeze({
    count: moon.strategyHostCount,
    next: value => checked(moon.strategyHostNext(value)),
    task: moon.strategyHostTask,
    registration: moon.strategyHostRegistration,
    completed: moon.strategyHostTaskCompleted,
    finished: moon.strategyHostFinished,
    stop: moon.strategyHostStop,
    closeOutputs: moon.strategyHostCloseOutputs,
    output: moon.strategyHostOutput,
    explain: (value, bytes, nodes) => JSON.parse(checked(moon.strategyHostExplain(value, bytes, nodes))),
    usage: value => Object.freeze(Object.fromEntries(
      moon.strategyHostUsage(value).map((count, index) => [usageKeys[index], count]),
    )),
  });
  const installed = installStrategyContributions(moon, setup, checked, {
    transportLimits, importLimits,
  });
  return runInstalledStrategy(setup, core, installed, signal);
}
