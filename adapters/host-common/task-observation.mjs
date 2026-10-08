// Optional copied facts, not task completion authority or live output access.
const observers = new WeakMap();
export function installTaskObservation(project) {
  if (typeof project !== 'function') throw new TypeError('InvalidTaskObservation');
  const observer = Object.freeze({});
  observers.set(observer, project);
  return observer;
}
export function projectTaskObservation(observer, event, task, durationMs) {
  if (observer === undefined) return;
  // A foreign observer is ignored rather than changing execution semantics.
  const project = observers.get(observer);
  if (project === undefined) return;
  try { project(Object.freeze({event, task, durationMs})); }
  catch { /* Optional projection never changes the confirmed Owner fact. */ }
}
