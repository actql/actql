// Static ports for the generated package build inputs, available before their emit.
declare module '*_build/workers/modules/bridge.mjs' {
  export function instantiate(hashSeed: number): import('./finite.mjs').WorkersRuntime;
}

declare module '*connectors-workers/strategy.generated.mjs' {
  type Factory = typeof import('../local-node/strategy-bundle.mjs').localStrategyContribution;
  type Runtime = Parameters<Factory>[0] & Readonly<{strategyHostModules(setup: unknown): string[]}>;
  export function installStrategyContributions(moon: Runtime, setup: unknown,
    checked: Parameters<Factory>[2], options?: object): readonly ReturnType<Factory>[];
}
