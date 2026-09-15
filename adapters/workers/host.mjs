import {instantiate} from '../../_build/workers/modules/bridge.mjs';
import {installStrategyContributions} from '../connectors-workers/strategy.generated.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {withScopedStrategy} from './invocation.mjs';

// Standard Local-only entry: no request-supplied implementations or verifiers.
export function createWorkersHost(hashSeed) {
  return bindWorkersHost(instantiate(hashSeed));
}

// Host-implementation assembly, never request data. Preparation and execution
// must be linked into this same MoonBit runtime, including its Error tag table.
// Snapshot trusted exports before any await; a request cannot swap callbacks.
export function bindWorkersHost(runtime) {
  const moon = Object.freeze({...runtime});
  return Object.freeze({
    withCapturedStrategy(setup, consume, signal) {
      return withScopedStrategy(setup, runtimeCore(moon),
        installStrategyContributions(moon, setup, checked, {}), consume, signal);
    },
    usage: setup => moon.strategyHostUsage(setup),
  });
}
