// Installed Host supervision, not a replacement completion verifier. The
// standard driver supplies an output only after common atomic publication.
const observers = new WeakMap();

export function installCompletionObserver(completed) {
  if (typeof completed !== 'function') throw new TypeError('InvalidCompletionObserver');
  const installed = Object.freeze({});
  observers.set(installed, completed);
  return installed;
}

export function completionObserver(installed) {
  if (installed === undefined) return undefined;
  const callback = observers.get(installed);
  if (!callback) throw new TypeError('ForeignCompletionObserver');
  return callback;
}
