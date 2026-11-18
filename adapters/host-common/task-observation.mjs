// Optional copied facts, not task completion authority or live output access.
const observers = new WeakMap();
export function installTaskObservation(project, logicalBoundary) {
  if (typeof project !== 'function') throw new TypeError('InvalidTaskObservation');
  if (logicalBoundary !== undefined && typeof logicalBoundary !== 'function') {
    throw new TypeError('InvalidLogicalTaskObservation');
  }
  const observer = Object.freeze({});
  observers.set(observer, {project, logicalBoundary});
  return observer;
}
export function projectTaskObservation(observer, event, task, durationMs) {
  if (observer === undefined) return;
  // A foreign observer is ignored rather than changing execution semantics.
  const project = observers.get(observer)?.project;
  if (project === undefined) return;
  try { project(Object.freeze({event, task, durationMs})); }
  catch { /* Optional projection never changes the confirmed Owner fact. */ }
}

// Trusted installed supplier only; outside every Owner atomic transition.
// Undefined does not introduce an await/tick on the unarmed Normal path.
export function projectTaskLogicalObservation(observer, phase, task) {
  return observer === undefined ? undefined
    : observers.get(observer)?.logicalBoundary?.(phase, task);
}
