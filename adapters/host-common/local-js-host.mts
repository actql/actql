// @ts-expect-error TS7016: the Common runtime facade is still authored in JS.
import {runtimeCore} from './runtime-core.mjs';
import {checked} from './runtime-result.mjs';
import {withScopedStrategy} from './scoped-strategy.mjs';
import type {ScopedStrategyConsumer} from './scoped-strategy.mjs';

type Setup = Parameters<typeof withScopedStrategy>[0];
type Runtime = Readonly<{strategyHostUsage(setup: Setup): unknown}>;
type InstallContributions<Moon extends Runtime> = (
  runtime: Readonly<Moon>, setup: Setup, check: typeof checked, context: object,
) => Parameters<typeof withScopedStrategy>[2];

// Trusted Host composition only, never request data. The caller selects an
// installed contribution bundle; preparation and execution share one runtime
// (including its Error tags). No environment-specific API is required here.
export function bindLocalJsHost<Moon extends Runtime>(
  runtime: Moon, installStrategyContributions: InstallContributions<Moon>,
) {
  const moon = Object.freeze({...runtime});
  return Object.freeze({
    withCapturedStrategy<Result>(setup: Setup, consume: ScopedStrategyConsumer<Result>, signal?: AbortSignal) {
      return withScopedStrategy(setup, runtimeCore(moon),
        installStrategyContributions(moon, setup, checked, {}), consume, signal);
    },
    usage: (setup: Setup) => moon.strategyHostUsage(setup) as ReturnType<Moon['strategyHostUsage']>,
  });
}
