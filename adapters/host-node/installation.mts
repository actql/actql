type StrategyRuntime = {strategyHostModules(setup: unknown): unknown};
type LoadedFactory<M, S, C> = {load: () => unknown; configuration: unknown;
  factory: (moon: M, setup: S, checked: C, configuration: unknown) => unknown};

// Trusted build-time loader wiring, not a runtime plugin or URL registration API.
// Configurations are exact provider-owned immutable handles; never clone their
// contents, interpret their settings, or freeze caller-owned objects here.
export function snapshotConfigurations(options: unknown = {}) {
  const descriptors = Object.getOwnPropertyDescriptors(options as object);
  const snapshot = Object.create(null) as Record<PropertyKey, unknown>;
  for (const key of Object.keys(descriptors)) {
    const descriptor = descriptors[key];
    if (!descriptor.enumerable) continue;
    if (!Object.hasOwn(descriptor, 'value')) throw new TypeError('Configuration handles must be data properties');
    snapshot[key] = descriptor.value;
  }
  return Object.freeze(snapshot);
}

export async function installSelectedContributions<M extends StrategyRuntime, S, C>(
  loaders: ReadonlyMap<unknown, () => unknown>, moon: M, setup: S, checked: C,
  options?: unknown, signal?: Pick<AbortSignal, 'throwIfAborted'>,
) {
  signal?.throwIfAborted();
  const supplied = moon.strategyHostModules(setup);
  const keys = Array.isArray(supplied) ? [...supplied] : undefined;
  if (!keys || new Set(keys).size !== keys.length || keys.some(key => !loaders.has(key))) {
    throw new Error('Configured module has no unique Node implementation');
  }
  const configurations = snapshotConfigurations(options);
  // Pin the full selection before loading. Loading failure never drops a module
  // and retries another realization. Factories are pure and run only after all
  // selected modules load. Observe each started import even when cancelled.
  const selected = keys.map(key => ({load: loaders.get(key)!, configuration: configurations[key as PropertyKey]}));
  const loaded: LoadedFactory<M, S, C>[] = [];
  for (const entry of selected) {
    signal?.throwIfAborted();
    const factory = await entry.load();
    signal?.throwIfAborted();
    if (typeof factory !== 'function') throw new TypeError('Invalid strategy factory');
    loaded.push({...entry, factory} as LoadedFactory<M, S, C>);
  }
  return Object.freeze(loaded.map(entry => {
    signal?.throwIfAborted();
    return entry.factory(moon, setup, checked, entry.configuration);
  }));
}
