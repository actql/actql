// Run observation admission and this handle's control revision observation.
// Weak associations retain explanations, never a second Run or Effect ledger.
import {projectCancellationAttemptExplanation, projectCancellationExplanation,
  projectEffectUncertainty, projectOwnerObservations, projectRejectedRunObservation,
  projectUnavailableRunObservation, localizeOperation} from '../operation-presentation.mjs';
import {bytesCid, canonicalJson, contentCid} from '../checkpoints.mjs';
import {captureResponse, freezeInput, structuralKey} from './data.mjs';
import {ClientError, fail, requestCancellationCause} from './errors.mjs';
import {createResultFactory} from './result-read.mjs';
import {ownerObservationLimits, runStateProtocol, snapshotClientRequest, validCancellationAttempt,
  validCancellationLookup, validCancellationRef, validClientBody,
  validOperationAttemptRef, validOwnerObservations, validRunState, validRunWaitContract, validWireRunPlanViewShape,
  validWireRunViewShape} from '@actql/client-wire';

const runObservationFailures = new WeakMap();

const ownerObservationExplanations = new WeakMap();

// Only a rejected observation of this SDK's attached Run retains its lookup
// candidate. No rejected state, effect, revision or write permission is kept.
const effectUncertainties = new WeakMap();
// Presentation retains validated Run-control observations, not another owner.
const cancellationExplanations = new WeakMap();

export function explainRunObservationFailure(error, options) {
  return localizeOperation(runObservationFailures.get(error), 'observation', options);
}

// Only an admitted original SDK result carries this call's observation custody.
export function explainOwnerObservations(result, options) {
  return localizeOperation(ownerObservationExplanations.get(result), 'ownerObservations', options);
}

const retainOwnerObservations = (answer, input, lookupContext) => {
  ownerObservationExplanations.set(answer, projectOwnerObservations(answer, input, lookupContext));
  return answer;
};

const rejectedRunObservation = (ref, operation, problem, code = 'InvalidHostRunState') => {
  const error = new ClientError(code);
  runObservationFailures.set(error, projectRejectedRunObservation(ref, operation, problem));
  return error;
};

const unavailableRunObservation = (failure, ref, operation) => {
  let error;
  try { error = requestCancellationCause(failure); }
  catch { error = new ClientError('ClientTransportUnknown'); }
  runObservationFailures.set(error, projectUnavailableRunObservation(ref, operation));
  return error;
};

const rejectedRunProblem = value => {
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return 'malformed_response';
    const version = Object.getOwnPropertyDescriptor(value, 'version')?.value;
    const status = Object.getOwnPropertyDescriptor(value, 'status')?.value;
    if (typeof version !== 'string' || !version || typeof status !== 'string' || !status) return 'malformed_response';
    if (version !== runStateProtocol.version) return 'contract_mismatch';
    return runStateProtocol.statuses.includes(status) ? 'malformed_response' : 'unknown_state';
  } catch { return 'malformed_response'; }
};

export function explainEffectUncertainty(state, options) {
  return localizeOperation(effectUncertainties.get(state), 'effect', options);
}

const retainEffectUncertainty = (state, ref) => {
  const explanation = projectEffectUncertainty(state, ref);
  if (explanation !== undefined) effectUncertainties.set(state, explanation);
  return state;
};

export function explainCancellation(result, options) {
  return localizeOperation(cancellationExplanations.get(result), 'cancellation', options);
}

const retainCancellationAttemptExplanation = (result, context) => {
  cancellationExplanations.set(result, projectCancellationAttemptExplanation(result, context));
  return result;
};

export const retainCancellationExplanation = (result, context, observation, revision) => {
  if (!context) return result;
  cancellationExplanations.set(result, projectCancellationExplanation(result, context, observation, revision));
  return result;
};

export function createExecutionFactory(selected, confirmed, transport, lifecycle) {
  const {exchange, responseValue, wasCancellationDispatched} = transport;
  return admission => {
    // Both callers supply their captured, validated admission: the submit
    // envelope or the attach boundary. Handle construction adds no boundary.
    const ref = Object.freeze({...admission.ref});
    const runProfile = Object.freeze({...confirmed,
      durability: admission.durability});
    const runRequest = (operation, body = {}, signal, cancellationContext) =>
      exchange(operation, {ref, ...body}, signal, undefined, cancellationContext);
    const readControl = async (operation, body, signal, cancellationContext) => {
      const response = await runRequest(operation, body, signal, cancellationContext);
      try { return await responseValue(response); }
      catch (cause) {
        throw retainCancellationExplanation(new ClientError('InvalidHostResponse', {cause}),
          cancellationContext, 'outcome_unknown');
      }
    };

    // Compare only this Owner's control component. Its revision is not an
    // Effect, publication or whole-Run revision, and carries no retry authority.
    let latestControl;
    let latestState;
    const readRunObservation = async (operation, body, signal) => {
      // Failure to obtain an observation admits no Run facts, including when
      // credentials or a closed connection prevent dispatch entirely.
      let response;
      try { response = await runRequest(operation, body, signal); }
      catch (failure) { throw unavailableRunObservation(failure, ref, operation); }
      let state;
      try { state = await responseValue(response); }
      catch { throw rejectedRunObservation(ref, operation, 'malformed_response', 'InvalidHostResponse'); }
      try { state = captureResponse(state); }
      catch { throw rejectedRunObservation(ref, operation, 'malformed_response'); }
      const problem = rejectedRunProblem(state);
      try {
        // The wait contract includes the Run shape. Admit the captured reply
        // once; every later operation still obtains its own Host observation.
        if (!(operation === 'wait' ? validRunWaitContract(state, body.since)
          : validRunState(state))) throw rejectedRunObservation(ref, operation, problem);
        if (latestState !== undefined && (state.run_id !== latestState.runId ||
            state.revision < latestState.revision)) {
          throw rejectedRunObservation(ref, operation, 'stale_observation');
        }
        // Each observation already owns its data even if a Local port reuses
        // a reply. No application callback runs between capture and admission.
        const observation = state;
        if (observation.control !== undefined) {
          const control = observation.control;
          if (latestControl !== undefined && (control.revision < latestControl.revision ||
              control.revision === latestControl.revision &&
              structuralKey(control) !== structuralKey(latestControl))) {
            throw rejectedRunObservation(ref, operation, 'stale_observation');
          }
          latestControl = freezeInput({...control});
        }
        latestState = Object.freeze({runId:observation.run_id, revision:observation.revision});
        if (observation.checkpoint !== undefined) {
          // SDK presentation only: preserve the exact closed wire and JSON
          // bytes. No checkpoint is manufactured for a nonwaiting state.
          Object.defineProperty(observation.checkpoint, 'id', {
            value: observation.checkpoint.checkpoint_id,
            enumerable: false, writable: false, configurable: false,
          });
          Object.freeze(observation.checkpoint);
        }
        return retainEffectUncertainty(observation, ref);
      } catch (cause) {
        if (runObservationFailures.has(cause)) throw cause;
        throw rejectedRunObservation(ref, operation, 'malformed_response');
      }
    };

    const result = createResultFactory({ref, limits: confirmed.limits,
      lookupContext: {endpoint: selected.endpoint, scopeRef: confirmed.scopeRef},
      redactErrors: selected.redactCredentialErrors === true, typedRows: transport.typedRows,
      beforeResultRead: transport.sourcePreparation?.beforeResultRead,
      assertResultReadCurrent: transport.sourcePreparation?.assertResultReadCurrent},
    {runRequest, responseValue}, lifecycle, () => handle);
    const handle = Object.freeze({
      ref, profile: runProfile, result,
      observeOwners: async ({signal,cursors=[],maxEntries=100,maxWireBytes=ownerObservationLimits.maxWireBytes} = {}) => {
        const input = freezeInput(snapshotClientRequest({ref,cursors,maxEntries,maxWireBytes}));
        if (!validClientBody('owner-observations',{connection:selected.wire,...input})) {
          fail('InvalidOwnerObservationRequest');
        }
        const response = await runRequest('owner-observations',input,signal);
        let answer;
        try {answer=captureResponse(await responseValue(response));}
        catch {fail('InvalidHostOwnerObservations');}
        if (!validOwnerObservations(answer,ref,input)) fail('InvalidHostOwnerObservations');
        for (const vector of answer.revisionVector) {
          if (vector.snapshotCid === undefined) continue;
          const view=answer.owners.find(value=>value.kind==='observed' &&
            value.ownerRef.kind===vector.owner.kind && value.ownerRef.scopeCid===vector.owner.scopeCid &&
            value.ownerRef.streamCid===vector.owner.streamCid);
          if (await bytesCid(new TextEncoder().encode(canonicalJson({version:'actql-owner-snapshot/0.1',ref,
            owner:vector.owner,snapshot:view.snapshot},{dataKeys:true}))) !== vector.snapshotCid) {
            fail('InvalidHostOwnerObservations');
          }
        }
        freezeInput(answer);
        retainOwnerObservations(answer, input,
          {endpoint: selected.endpoint, scopeRef: confirmed.scopeRef});
        return answer;
      },
      // Read the immutable compiler map of this admitted Run. Never compile
      // today's input or allocate a replacement Run for missing old evidence.
      plan: async ({signal, maxWireBytes = 65536, maxNodes = 10000, maxDepth = 64} = {}) => {
        const input = freezeInput(snapshotClientRequest({ref, maxWireBytes, maxNodes, maxDepth}));
        if (!validClientBody('run-plan', {connection: selected.wire, ...input})) {
          fail('InvalidRunPlanRequest');
        }
        const response = await runRequest('run-plan', input, signal);
        const view = captureResponse(await responseValue(response, maxWireBytes));
        if (new TextEncoder().encode(JSON.stringify(view)).byteLength > maxWireBytes ||
            !validWireRunPlanViewShape(view) || structuralKey(view.run_ref) !== structuralKey(ref)) {
          fail('InvalidClientHostRunPlanView');
        }
        const plan = view.plan_view, map = plan.logical_map;
        const {self_cid: observed, ...preimage} = map;
        if (map.compiled_plan_cid !== plan.compiled_plan_cid ||
            await contentCid(preimage) !== observed) fail('InvalidClientHostRunPlanView');
        return freezeInput(view);
      },
      inspect: async ({signal, maxWireBytes = 65536, maxNodes = 10000, maxDepth = 64} = {}) => {
        const input = freezeInput(snapshotClientRequest({ref, maxWireBytes, maxNodes, maxDepth}));
        if (!validClientBody('inspect-run', {connection: selected.wire, ...input})) {
          fail('InvalidRunInspectRequest');
        }
        const response = await runRequest('inspect-run', input, signal);
        const view = captureResponse(await responseValue(response));
        if (!validWireRunViewShape(view) || structuralKey(view.run_ref) !== structuralKey(ref) ||
            view.run_state.legacy_state !== undefined &&
            (view.run_state.legacy_state.run_id !== view.run_state.run_id ||
             view.run_state.legacy_state.status !== view.run_state.status ||
             view.run_state.legacy_state.updated_at !== view.run_state.updated_at ||
             view.run_state.legacy_state.control?.revision !== view.run_state.control_revision)) {
          fail('InvalidClientHostRunView');
        }
        return freezeInput(view);
      },
      status: async ({signal} = {}) => {
        return readRunObservation('status', {}, signal);
      },
      wait: async ({until, since, signal} = {}) => {
        const body = {until:until ?? null, since:since ?? null};
        if (!validClientBody('wait', {connection:selected.wire, ref, ...body})) {
          fail('InvalidWaitRevision');
        }
        if (signal?.aborted) fail(signal.reason?.name === 'TimeoutError' ? 'WaitTimeout' : 'WaitAborted');
        try { return await readRunObservation('wait', body, signal); }
        catch (failure) {
          if (signal?.aborted && (failure?.code === 'ClientTransportUnknown' ||
              failure?.code === 'WaitAborted')) {
            fail(signal.reason?.name === 'TimeoutError' ? 'WaitTimeout' : 'WaitAborted');
          }
          throw failure;
        }
      },
      cancel: async ({signal, cancelId = crypto.randomUUID(), expectedRevision,
        attemptId = crypto.randomUUID()} = {}) => {
        const attemptRef = freezeInput({operation: 'cancel', attemptId});
        if (!validOperationAttemptRef(attemptRef)) fail('InvalidOperationAttemptReference');
        if (!validCancellationRef({...ref, cancelId,
          expectedRevision: expectedRevision === undefined ? 0 : expectedRevision})) {
          fail('InvalidCancellationReference');
        }
        // A fresh operation may first observe the current control revision.
        // Replay/lookup must use the revision retained in the original ref.
        if (expectedRevision === undefined) {
          const state = await readRunObservation('status', {}, signal);
          if (state.control === undefined) fail('CancellationRevisionUnavailable');
          expectedRevision = state.control.revision;
        }
        const cancelRef = freezeInput({...ref, cancelId, expectedRevision});
        if (!validCancellationRef(cancelRef)) fail('InvalidCancellationReference');
        const context = freezeInput({ref: {...ref}, cancelRef, attemptRef});
        let response;
        try { response = await readControl('cancel', {cancelId, expectedRevision, attemptRef}, signal, context); }
        catch (cause) {
          // Local validation, Client closure and credential failure before
          // dispatch cannot have admitted this cancellation operation.
          if (!wasCancellationDispatched(context)) throw cause;
          // A transported code or HTTP status is not an Owner certificate for
          // this invocation. It can follow a committed original operation or
          // describe another attempt. Only a validated typed outcome can
          // establish Refused or Conflict; lost error replies stay unknown.
          const error = new ClientError('CancellationUnknown', {
            cancelRef, attemptRef, cause: requestCancellationCause(cause),
          });
          throw retainCancellationExplanation(error, context, 'outcome_unknown');
        }
        let received;
        try {
          received = captureResponse(response);
          if (!validCancellationAttempt(received, cancelRef, attemptRef)) fail('InvalidHostCancellation');
        } catch {
          throw retainCancellationExplanation(new ClientError('CancellationUnknown', {
            cancelRef, attemptRef, cause: new ClientError('InvalidHostCancellation'),
          }), context, 'outcome_unknown');
        }
        received = freezeInput(received);
        return retainCancellationAttemptExplanation(received, context);
      },
      lookupCancellation: async (reference, {signal} = {}) => {
        let cancelRef;
        try {
          const capturedReference = captureResponse(reference);
          if (!validCancellationRef(capturedReference)) fail('InvalidCancellationReference');
          cancelRef = freezeInput(capturedReference);
          if (['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].some(key => cancelRef[key] !== ref[key])) {
            fail('InvalidCancellationReference');
          }
        } catch { fail('InvalidCancellationReference'); }
        const context = freezeInput({ref: {...ref}, cancelRef});
        let response;
        try {
          response = await readControl('lookup-cancellation', {
            cancelId: cancelRef.cancelId, expectedRevision: cancelRef.expectedRevision,
          }, signal);
        } catch (cause) {
          const safe = requestCancellationCause(cause);
          throw retainCancellationExplanation(new ClientError(safe.code, {cancelRef,
            ...(safe.status === undefined ? {} : {status: safe.status})}), context, 'outcome_unknown');
        }
        try {
          const captured = captureResponse(response);
          if (!validCancellationLookup(captured, cancelRef)) fail('InvalidHostCancellationLookup');
          return retainCancellationExplanation(freezeInput(captured), context,
            captured.kind === 'found' ? captured.cancellation.kind : 'outcome_unknown',
            captured.kind === 'found' ? captured.cancellation.revision : undefined);
        } catch {
          throw retainCancellationExplanation(new ClientError('InvalidHostCancellationLookup', {cancelRef}),
            context, 'outcome_unknown');
        }
      },
      // The Run's current state after the Host's reconciliation attempt. An
      // unknown Effect outcome stays `needs_reconciliation` until the Host
      // has provider evidence; nothing is resent to find out.
      reconcile: async ({signal} = {}) => {
        return readRunObservation('reconcile', {}, signal);
      },
    });
    return handle;
  };

}

export function copyRunObservationFailure(cause, error) {
  const failure = runObservationFailures.get(cause);
  if (failure) runObservationFailures.set(error, failure);
}
