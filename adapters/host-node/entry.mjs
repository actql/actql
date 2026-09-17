// Standard composition entry. Callers cannot replace the runtime, installed
// implementation factories, verification or SQL through execution options.
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {installStrategyContributions} from '../connectors-builtin/strategy.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {snapshotConfigurations} from './installation.mjs';
import {completionObserver} from '../host-common/completion-observer.mjs';
import {preparedManagedIdentityPolicy} from './managed-identity-policy.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
let runtime;

export async function runCapturedStrategy(setup, options = {}, signal, observer) {
  signal?.throwIfAborted();
  const observeCompletion = completionObserver(observer);
  const configurations = snapshotConfigurations(options);
  const identityPolicy = preparedManagedIdentityPolicy(
    configurations.managedIdentityPolicy,
  );
  const moon = await (runtime ??= import(runtimeUrl.href));
  signal?.throwIfAborted();
  if (!moon.strategyHostConfigureManagedIdentity(
    setup,
    identityPolicy.publication,
    identityPolicy.consumer,
    identityPolicy.hostPolicy,
  )) {
    throw new TypeError('Managed identity policy is already sealed');
  }
  const core = runtimeCore(moon);
  const installed = await installStrategyContributions(moon, setup, checked, configurations, signal);
  signal?.throwIfAborted();
  return runInstalledStrategy(setup, core, installed, signal, observeCompletion);
}
