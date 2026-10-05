// Installed Store wiring, separate from operator settings or completion evidence.
// Pure factories construct a lease; I/O starts only through that lease after the
// exact Local attempt has installed its retention-release predicate.
const configurations = new WeakMap();
export function installLocalRetainedStore(createLease, faultInjection) {
  if (typeof createLease !== 'function') throw new TypeError('MissingLocalStore');
  if (faultInjection !== undefined && typeof faultInjection !== 'function') {
    throw new TypeError('InvalidLocalFaultInjection');
  }
  const configuration = Object.freeze({});
  configurations.set(configuration, {retained:createLease,snapshot:createLease,
    faultInjection});
  return configuration;
}
// An installed Host can persist a Carrier without switching its Relation
// tasks to file output. Both routes still use the existing physical Store.
export function installLocalSnapshotStore(createLease, faultInjection) {
  if (typeof createLease !== 'function') throw new TypeError('MissingLocalStore');
  if (faultInjection !== undefined && typeof faultInjection !== 'function') {
    throw new TypeError('InvalidLocalFaultInjection');
  }
  const configuration = Object.freeze({});
  configurations.set(configuration, {snapshot:createLease,faultInjection});
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
export function localComputeFaultInjection(configuration) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (!installed) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.faultInjection;
}

// A per-invocation Host callback resumes the SAME Local driver only after
// current authority or Store custody is ready. Existing Store configuration
// remains immutable and can be shared by other runs.
export function withLocalExecutionPauseHandler(configuration, handlePause) {
  if (typeof handlePause !== 'function') {
    throw new TypeError('InvalidLocalExecutionPauseHandler');
  }
  const installed = configuration === undefined ? {} : configurations.get(configuration);
  if (installed === undefined) throw new TypeError('InvalidLocalStoreConfiguration');
  const derived = Object.freeze({});
  configurations.set(derived, {...installed, handlePause});
  return derived;
}
export function localExecutionPauseHandler(configuration) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (installed === undefined) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.handlePause;
}
