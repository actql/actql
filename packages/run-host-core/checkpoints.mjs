// Exact existing Owner calls over the portable string ABI. The Host provides
// trusted authentication, durable transactions and physical continuation.
export {checkpointAdmit, checkpointWaitingState, checkpointSealBody,
  checkpointLifecycleState, waitingExitState, revalidationFailedState, checkpointExpiredAt, runStateAdmit,
  runTransitionAllowed, resumeCompletionAllowed, effectSettlementCompletionAllowed,
  resolutionProofPreimage, resolutionAdmit, resolutionDecide,
  verifiedAttestationPreimage, resumedApprovalAt,
  effectResumeClaimDecide, resumeFenceDecide} from
  './dist/checkpoint_runtime_node.js';

// One actual compiled Run observation owner in this package instance. This
// token is DATA custody only, never a Run, current permission or cleanup ACK.
import * as runStateOwner from './dist/checkpoint_runtime_node.js';
import {runtimeIsOk, runtimeIsError, runtimeField} from './compiler-binding.generated.mjs';
const runStateObservations = new WeakMap();
const runStateMethods = ['runStateObservationPrepare', 'runStateObservationKey',
  'runStateObservationNextRevision', 'runStateObservationWire', 'runStateWaitDecision'];

function requireRunStateOwner() {
  if (runStateMethods.some(name => typeof runStateOwner[name] !== 'function')) {
    throw Object.assign(new Error('RunStateObservationRuntimeUnavailable'),
      {code: 'RunStateObservationRuntimeUnavailable'});
  }
}
function observationResult(result) {
  if (runtimeIsOk(result)) return runtimeField(result, 0);
  if (runtimeIsError(result) && typeof runtimeField(result, 0) === 'string') {
    const code = runtimeField(result, 0);
    throw Object.assign(new Error(code), {code});
  }
  throw new TypeError('InvalidRunStateOwnerResult');
}
function observationValue(token) {
  const value = token !== null && typeof token === 'object'
    ? runStateObservations.get(token) : undefined;
  if (value === undefined) throw new TypeError('ForeignRunStateObservation');
  return value;
}
function observationRevision(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw Object.assign(new Error('InvalidRunStateRevision'), {code: 'InvalidRunStateRevision'});
  }
  return BigInt(value);
}
function observationLimits(limits) {
  if (!limits || typeof limits !== 'object' || Array.isArray(limits)) {
    throw new TypeError('InvalidRunStateObservationLimits');
  }
  const {maxWireBytes, maxNodes, maxDepth} = limits;
  if ([maxWireBytes, maxNodes, maxDepth].some(value =>
    !Number.isSafeInteger(value) || value <= 0 || value > 2147483647)) {
    throw new TypeError('InvalidRunStateObservationLimits');
  }
  return [maxWireBytes, maxNodes, maxDepth];
}

export function prepareRunStateObservation(wire, runId, currentRevision, limits) {
  requireRunStateOwner();
  if (typeof wire !== 'string' || typeof runId !== 'string') {
    throw new TypeError('InvalidRunStateObservation');
  }
  const value = observationResult(runStateOwner.runStateObservationPrepare(
    wire, runId, observationRevision(currentRevision), ...observationLimits(limits)));
  const token = Object.freeze(Object.create(null));
  runStateObservations.set(token, value);
  return token;
}
export function runStateObservationKey(token) {
  requireRunStateOwner();
  return runStateOwner.runStateObservationKey(observationValue(token));
}
export function nextRunStateRevision(token, priorKey, currentRevision) {
  requireRunStateOwner();
  if (priorKey !== null && typeof priorKey !== 'string') {
    throw new TypeError('InvalidPriorRunStateObservation');
  }
  return Number(observationResult(runStateOwner.runStateObservationNextRevision(
    observationValue(token), priorKey !== null, priorKey ?? '', observationRevision(currentRevision))));
}
export function runStateObservationWire(token, revision) {
  requireRunStateOwner();
  return observationResult(runStateOwner.runStateObservationWire(
    observationValue(token), observationRevision(revision)));
}
export function runWaitDecision(wire, since, limits) {
  requireRunStateOwner();
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('InvalidRunWaitState'), {code: 'InvalidRunWaitState'});
  }
  if (since !== null && (!Number.isSafeInteger(since) || since < 0)) {
    throw Object.assign(new Error('InvalidWaitRevision'), {code: 'InvalidWaitRevision'});
  }
  const decision = runStateOwner.runStateWaitDecision(wire, since !== null,
    BigInt(since ?? 0), ...observationLimits(limits));
  if (decision === 'ready' || decision === 'pending') return decision;
  if (decision === 'InvalidWaitRevision' || decision === 'InvalidRunWaitState') {
    throw Object.assign(new Error(decision), {code: decision});
  }
  throw new TypeError('InvalidRunStateOwnerResult');
}
