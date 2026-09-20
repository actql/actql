import {DuckDBTransportError} from './configuration.mjs';

export const failureMember = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};

// Cleanup state is Host-owned metadata. Never require an arbitrary JavaScript
// throwable to be truthy, extensible, or an Error instance.
export function ownedHostFailure(reason, fallbackCode) {
  const reasonCode = failureMember(reason, 'code');
  const failure = new DuckDBTransportError(
    typeof reasonCode === 'string' ? reasonCode : fallbackCode,
    {cause: reason},
  );
  failure.primaryFailure = reason;
  const cleanupErrors = failureMember(reason, 'cleanupErrors');
  failure.cleanupErrors = Object.freeze(
    Array.isArray(cleanupErrors) ? [...cleanupErrors] : [],
  );
  const cleanupHandle = failureMember(reason, 'cleanupHandle');
  if (failureMember(reason, 'cleanupPending') === true && cleanupHandle) {
    failure.cleanupPending = true;
    failure.cleanupHandle = cleanupHandle;
  }
  return failure;
}
