// Private plumbing shared by installed row adapters. The adapter keeps its
// provider protocol, page admission and current authority; the existing
// RowRun remains the sole acquisition, capture and release owner.
import {checked} from '../host-common/runtime-result.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };

export function startInstalledRowRun({moon, acquisition, nonce, ledger,
  capacity}) {
  const settled = new Set();
  const run = checked(ledger === undefined
    ? moon.clientProgramRowSourceStart(acquisition, nonce,
      attempt => settled.has(attempt))
    : moon.clientProgramRowSourceStartAccounted(acquisition, nonce,
      attempt => settled.has(attempt), ledger, capacity.transferBytes,
      capacity.executionBytes));
  let closed = false;
  const close = () => {
    if (closed) return;
    if (ledger === undefined) moon.clientProgramRowSourceClose(run);
    else checked(moon.clientProgramRowSourceCloseAccounted(run));
    closed = true;
  };

  // Called only after the adapter has awaited its complete Site transport.
  function complete({owner, prepared, registry, values, fragment, ordered,
    retainedRelationOutput, currentRead}) {
    checked(moon.clientProgramRowSourceFinish(run));
    settled.add(moon.clientProgramRowSourceAttempt(run));
    const capture = checked(moon.clientProgramRowSourceCapture(run));
    const source = () => checked(
      moon.clientProgramRowSourceCaptureSource(capture));
    const {checkedOwner, effectful, occurrence} = owner;
    if ((effectful
      ? occurrence.task === 0
        ? moon.clientProgramEffectCapturedSourceMatches(checkedOwner, source())
        : moon.clientProgramEffectCapturedSourceMatchesAt(checkedOwner,
          source(), occurrence.task)
      : moon.clientProgramCapturedTaskSourceMatches(checkedOwner,
        source(), occurrence.task)) !== true) {
      fail('InstalledSourceProgramMismatch');
    }
    const identity = checked(effectful
      ? moon.clientProgramIdentifyCapturedEffectSourceRelation(source())
      : moon.clientProgramIdentifyCapturedSourceRelation(source()));
    const logicalInput = checked(effectful
      ? occurrence.task === 0
        ? moon.clientProgramEffectIssueCapturedSourceLogical(checkedOwner,
          source(), identity, owner.requirement)
        : moon.clientProgramEffectIssueCapturedSourceLogicalAt(checkedOwner,
          source(), identity, owner.requirement, occurrence.task)
      : moon.clientProgramIssueCapturedTaskSourceLogical(checkedOwner,
        source(), identity, owner.requirement, occurrence.task));
    // Accounted and Effect computation is opened later by the common Host.
    const openHost = retainedRelationOutput
      ? moon.clientProgramOpenCapturedLocalRetainedHost
      : moon.clientProgramOpenCapturedLocalHost;
    const setup = effectful || ledger !== undefined ? undefined :
      openHost(checkedOwner, source(), registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
    if (!effectful && ledger === undefined && setup === undefined) {
      fail('InstalledSourceHostUnavailable');
    }
    return Object.freeze({checkedSource: prepared.checkedSource, identity,
      logicalInput, requirement: owner.requirement, setup, occurrence,
      capture: Object.freeze({source,
        ...(ledger === undefined ? {} : {retainTask: (dag, task) => checked(
          moon.clientProgramRowSourceRetainCapturedTask(capture, dag, task))})}),
      issueSourceEvidence: async ({authorityScopeCid, effectiveDataPolicyCid}) => {
        await currentRead();
        return checked(moon.clientProgramRowSourceIssueSourceEvidence(
          acquisition, capture, identity, logicalInput, authorityScopeCid,
          effectiveDataPolicyCid, new Date().toISOString()));
      },
      close});
  }

  function closeAfterFailure(state) {
    try { close(); }
    catch {
      state.closeFailed = true;
      state.recovery = Object.freeze({
        close() {},
        async cleanup() { close(); return true; },
        cleanupPending: () => !closed,
      });
    }
  }
  return Object.freeze({run, close, complete, closeAfterFailure});
}
