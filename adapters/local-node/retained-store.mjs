// Installed Store wiring, separate from operator settings or completion evidence.
// Pure factories construct a lease; I/O starts only through that lease after the
// exact Local attempt has installed its retention-release predicate.
const configurations = new WeakMap();
export function installLocalRetainedStore(createLease) {
  if (typeof createLease !== 'function') throw new TypeError('MissingLocalStore');
  const configuration = Object.freeze({});
  configurations.set(configuration, createLease);
  return configuration;
}
export function localRetainedStore(configuration) {
  if (configuration === undefined) return undefined;
  const createLease = configurations.get(configuration);
  if (!createLease) throw new TypeError('InvalidLocalStoreConfiguration');
  return createLease;
}
