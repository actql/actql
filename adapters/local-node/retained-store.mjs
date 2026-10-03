// Installed Store wiring, separate from operator settings or completion evidence.
// Pure factories construct a lease; I/O starts only through that lease after the
// exact Local attempt has installed its retention-release predicate.
const configurations = new WeakMap();
export function installLocalRetainedStore(createLease) {
  if (typeof createLease !== 'function') throw new TypeError('MissingLocalStore');
  const configuration = Object.freeze({});
  configurations.set(configuration, {retained:createLease,snapshot:createLease});
  return configuration;
}
// An installed Host can persist a Carrier without switching its Relation
// tasks to file output. Both routes still use the existing physical Store.
export function installLocalSnapshotStore(createLease) {
  if (typeof createLease !== 'function') throw new TypeError('MissingLocalStore');
  const configuration = Object.freeze({});
  configurations.set(configuration, {snapshot:createLease});
  return configuration;
}
export function localRetainedStore(configuration) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (!installed) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.retained;
}
export function localSnapshotStore(configuration) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (!installed) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.snapshot;
}
