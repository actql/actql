// Optional copied facts, not task completion authority or live output access.
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type Phase = 'before' | 'settled';
type TaskFacts = Readonly<{event: string; task: number; durationMs: number | undefined}>;
type Observer = Readonly<{
  project(facts: TaskFacts): SynchronousRuntimeData;
  logicalBoundary?: (phase: Phase, task: number) => SynchronousRuntimeData;
}>;
const observers = new WeakMap<object, Observer>();
export function installTaskObservation(project: Observer['project'], logicalBoundary?: Observer['logicalBoundary']) {
  if (typeof project !== 'function') throw new TypeError('InvalidTaskObservation');
  if (logicalBoundary !== undefined && typeof logicalBoundary !== 'function') {
    throw new TypeError('InvalidLogicalTaskObservation');
  }
  const observer = Object.freeze({});
  observers.set(observer, {project, logicalBoundary});
  return observer;
}
export function projectTaskObservation(observer: unknown, event: string, task: number, durationMs?: number) {
  if (observer === undefined) return;
  // A foreign observer is ignored rather than changing execution semantics.
  const project = observers.get(observer as object)?.project;
  if (project === undefined) return;
  try { project(Object.freeze({event, task, durationMs})); }
  catch { /* Optional projection never changes the confirmed Owner fact. */ }
}

// Trusted installed supplier only; outside every Owner atomic transition.
// Undefined does not introduce an await/tick on the unarmed Normal path.
export function projectTaskLogicalObservation(observer: unknown, phase: Phase, task: number) {
  return observer === undefined ? undefined
    : observers.get(observer as object)?.logicalBoundary?.(phase, task);
}
