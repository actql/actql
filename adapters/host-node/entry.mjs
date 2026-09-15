// Standard composition entry. Callers cannot replace the runtime, installed
// implementation factories, verification or SQL through execution options.
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {installStrategyContributions} from '../connectors-builtin/strategy.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {snapshotConfigurations} from './installation.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
let runtime;

export async function runCapturedStrategy(setup, options = {}, signal) {
  signal?.throwIfAborted();
  const configurations = snapshotConfigurations(options);
  const moon = await (runtime ??= import(runtimeUrl.href));
  signal?.throwIfAborted();
  const core = runtimeCore(moon);
  const installed = await installStrategyContributions(moon, setup, checked, configurations, signal);
  signal?.throwIfAborted();
  return runInstalledStrategy(setup, core, installed, signal);
}
