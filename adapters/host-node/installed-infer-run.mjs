// Installed physical composition of the existing checked Infer, observation
// and publication owners. It neither interprets a Program nor issues proof JSON.
import {checked} from '../host-common/runtime-result.mjs';
import {publishCompletedEffectFreeRun} from
  '../host-common/completed-run-publication.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {inferTaskPublicationPlan} from './local-values-plan.mjs';
import {inferPublicationExecution} from './infer-result-publication.mjs';
import {readInstalledInferCapture} from './installed-infer-capture.mjs';

import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {driveNodeInferOperation} from './infer-run-driver.mjs';

export function installNodeInferRun({moon, core, registry, values, fragment, ordered, selections,
  namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection,
  prepareModelDispatch}) {
  const control = core.publicationControl;
  return async ({preparedProgram, plan, store, principalId, signal,
    retainExecution, acquiredInfer, replay = false, beginPhysicalWork = () => {}}) => {
    const selected = selections.get(preparedProgram);
    if (selected === undefined || selected.graph !== plan.inferGraph) {
      throw new Error('InstalledInferSelectionMissing');
    }
    const dispatch = !replay && prepareModelDispatch !== undefined
      ? await prepareModelDispatch({preparedProgram, selected, plan, store,
        principalId, signal}) : undefined;
    if (dispatch !== undefined && (typeof dispatch.enterCall !== 'function' ||
        typeof dispatch.authorize !== 'function' ||
        typeof dispatch.resume !== 'function')) {
      throw new TypeError('InvalidInstalledInferModelDispatch');
    }
    const savedSlots = replay ? await readInstalledInferCapture({moon,
      control, store, compiled: plan.compiled, runDefinition: plan.runDefinition,
      storeAuthorityCid, signal,
      restoreSource: acquiredInfer === undefined ? undefined : (source, observation) => {
        const sourceValue = checked(moon.strategyRunEvidenceAdmit('source_evidence',
          source.wire, 100000, 10000, 100));
        const observationValue = checked(moon.strategyRunEvidenceAdmit('observation_set',
          observation.wire, 16384, 1024, 20));
        acquiredInfer = {input: checked(moon.clientProgramRestoreInferCapturedInput(
          acquiredInfer.input, sourceValue, observationValue)), sourceEvidence: source};
      }}) : undefined;
    let operation;
    try {
      operation = openNodeInferOperation({moon, preparedProgram,
        step: selected.step, graph: selected.graph, registry, values, fragment, ordered, signal,
        acquiredInput: acquiredInfer?.input,
        computeSuffix: selected.computeSuffix,
        observeProgress: () => faultInjection?.('infer_execution_advanced', {}),
        ...(replay ? {savedSlots} : {provider: selected.provider,
          quantityCapacity: selected.quantityCapacity,
          physicalPreflight: selected.physicalPreflight,
          egressAdmission: selected.egressAdmission,
          ...(dispatch === undefined ? {} : {deferDispatch: true,
            enterCall: dispatch.enterCall})})});
    } finally {
      if (savedSlots !== undefined) {
        moon.clientProgramReleaseInferSlotReplay(savedSlots);
      }
    }
    const captureOwner = openNodeInferCaptureCustody({moon, control, operation,
      plan, store, storeAuthorityCid, replay, faultInjection,
      sourceEvidence: acquiredInfer === undefined ? [] : [acquiredInfer.sourceEvidence],
      publicationFor: ({issuance, modelEvidence}) => inferTaskPublicationPlan({
        moon, control, preparedProgram, admitted: plan, operation, issuance,
        modelEvidence, namespaceId,
        sourceEvidence: acquiredInfer === undefined ? [] : [acquiredInfer.sourceEvidence],
        authorityScopeCid, storeAuthorityCid, now})});
    retainExecution(captureOwner.custody);
    beginPhysicalWork();
    operation.bindRun(control, plan);
    if (!replay && dispatch === undefined) {
      operation.bindDispatch(control, {...plan, account: selected.account,
        principalId, at: now(), observeAccount: selected.observeAccount,
        observeAt: now});
    }
    const result = await driveNodeInferOperation(operation, {dispatch, signal});
    if (result?.status === 'waiting_checkpoint') return result;
    captureOwner.retainCompleted();
    const publication = await captureOwner.persist();
    await faultInjection?.('infer_capture_committed', {});
    signal.throwIfAborted();
    const execution = inferPublicationExecution({moon, core, operation,
      binding: publication.binding, compiled: plan.compiled, preparedProgram});
    await publishCompletedEffectFreeRun({...publication.plan, execution,
      store, control, signal});
  };
}
