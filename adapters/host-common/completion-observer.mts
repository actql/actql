// Installed Host supervision, not a replacement completion verifier. The
// standard driver supplies an output only after common atomic publication.
const observers = new WeakMap();

export function installCompletionObserver(completed, beforeTask) {
  if (typeof completed !== 'function') throw new TypeError('InvalidCompletionObserver');
  if (beforeTask !== undefined && typeof beforeTask !== 'function') {
    throw new TypeError('InvalidTaskStartObserver');
  }
  const installed = Object.freeze({});
  observers.set(installed, Object.freeze({completed, beforeTask}));
  return installed;
}

export function completionObserver(installed) {
  if (installed === undefined) return undefined;
  const callback = observers.get(installed);
  if (!callback) throw new TypeError('ForeignCompletionObserver');
  return callback.completed;
}

// The installed Host may observe a copied planner explanation and quantities.
// No task/output handle or execution authority crosses this callback.
export function taskStartObserver(installed) {
  if (installed === undefined) return undefined;
  const callback = observers.get(installed);
  if (!callback) throw new TypeError('ForeignCompletionObserver');
  return callback.beforeTask;
}
