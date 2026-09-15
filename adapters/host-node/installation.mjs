// Trusted build-time loader wiring, not a runtime plugin or URL registration API.
// Configurations are exact provider-owned immutable handles; never clone their
// contents, interpret their settings, or freeze caller-owned objects here.
export function snapshotConfigurations(options = {}) {
  const descriptors = Object.getOwnPropertyDescriptors(options);
  const snapshot = Object.create(null);
  for (const key of Object.keys(descriptors)) {
    const descriptor = descriptors[key];
    if (!descriptor.enumerable) continue;
    if (!Object.hasOwn(descriptor, 'value')) throw new TypeError('Configuration handles must be data properties');
    snapshot[key] = descriptor.value;
  }
  return Object.freeze(snapshot);
}

export async function installSelectedContributions(loaders, moon, setup, checked, options, signal) {
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
  const selected = keys.map(key => ({load: loaders.get(key), configuration: configurations[key]}));
  const loaded = [];
  for (const entry of selected) {
    signal?.throwIfAborted();
    const factory = await entry.load();
    signal?.throwIfAborted();
    if (typeof factory !== 'function') throw new TypeError('Invalid strategy factory');
    loaded.push({...entry, factory});
  }
  return Object.freeze(loaded.map(entry => {
    signal?.throwIfAborted();
    return entry.factory(moon, setup, checked, entry.configuration);
  }));
}
