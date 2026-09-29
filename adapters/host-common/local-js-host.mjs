import {runtimeCore} from './runtime-core.mjs';
import {checked} from './runtime-result.mjs';
import {withScopedStrategy} from './scoped-strategy.mjs';

// Trusted Host composition only, never request data. The caller selects an
// installed contribution bundle; preparation and execution share one runtime
// (including its Error tags). No environment-specific API is required here.
export function bindLocalJsHost(runtime, installStrategyContributions) {
  const moon = Object.freeze({...runtime});
  return Object.freeze({
    withCapturedStrategy(setup, consume, signal) {
      return withScopedStrategy(setup, runtimeCore(moon),
        installStrategyContributions(moon, setup, checked, {}), consume, signal);
    },
    usage: setup => moon.strategyHostUsage(setup),
  });
}
