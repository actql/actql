// Installed Host supervision, not a replacement completion verifier. The
// standard driver supplies an output only after common atomic publication.
// Static callback views only. Publication/currentness and every payload check
// remain at the original caller/consumer; these types create no task or grant.
type CompletionCallback = (event: Readonly<{task: unknown; output: unknown; [key: string]: unknown}>) => unknown;
type TaskStartCallback = (event: Readonly<{task: unknown; registrationKey: unknown;
  explanation: unknown; usage: unknown; [key: string]: unknown}>) => unknown;
interface ObserverCallbacks {completed: CompletionCallback; beforeTask: TaskStartCallback | undefined}
const observers = new WeakMap<object, Readonly<ObserverCallbacks>>();

export function installCompletionObserver(completed: unknown, beforeTask?: unknown) {
  if (typeof completed !== 'function') throw new TypeError('InvalidCompletionObserver');
  if (beforeTask !== undefined && typeof beforeTask !== 'function') {
    throw new TypeError('InvalidTaskStartObserver');
  }
  const installed = Object.freeze({});
  observers.set(installed, Object.freeze({completed, beforeTask}) as unknown as Readonly<ObserverCallbacks>);
  return installed;
}

export function completionObserver(installed: unknown) {
  if (installed === undefined) return undefined;
  const callback = observers.get(installed as object);
  if (!callback) throw new TypeError('ForeignCompletionObserver');
  return callback.completed;
}

// The installed Host may observe a copied planner explanation and quantities.
// No task/output handle or execution authority crosses this callback.
export function taskStartObserver(installed: unknown) {
  if (installed === undefined) return undefined;
  const callback = observers.get(installed as object);
  if (!callback) throw new TypeError('ForeignCompletionObserver');
  return callback.beforeTask;
}
