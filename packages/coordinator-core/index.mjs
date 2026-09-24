import * as owner from './dist/remote_coordinator_abi.js';

function checked(result) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) {
    throw Object.assign(new Error('CoordinatorOwnerRejected', {cause: result._0}),
      {code: 'CoordinatorOwnerRejected'});
  }
  throw Object.assign(new Error('InvalidCoordinatorOwnerResult'),
    {code: 'InvalidCoordinatorOwnerResult'});
}

export const createJournal = authority =>
  checked(owner.coordinatorCreateJournal(authority));

export const prepareDispatch = input => checked(owner.coordinatorPrepareDispatch(
  input.coordinatorAuthority, input.runDefinitionCid, input.taskKey,
  input.taskAttempt, input.dispatchId, input.siteKey, input.siteGeneration,
  input.runtimeBundleCid, input.connectorRegistration,
  input.connectorRevision, input.strategyRevision, input.inputBindingCid,
  input.obligationsCid, input.budgetCid,
  input.evidenceIssuerCapabilityCid, input.grantCid,
));

export const dispatchCid = owner.coordinatorDispatchCid;
export const dispatchJson = request => checked(owner.coordinatorDispatchJson(request));
export const prepareIntent = (journal, request) =>
  checked(owner.coordinatorPrepareIntent(journal, request));
export const admissionDurableJson = admission =>
  checked(owner.coordinatorAdmissionDurableJson(admission));
export const commitIntent = admission =>
  checked(owner.coordinatorCommitIntent(admission));
export const admitDurableJson = body =>
  checked(owner.coordinatorAdmitDurableJson(body));
export const restoreDurable = (journal, durable) =>
  checked(owner.coordinatorRestoreDurable(journal, durable));
export const durableRevision = owner.coordinatorDurableRevision;
export const durableDispatchCid = owner.coordinatorDurableDispatchCid;
export const prepareUnknown = record =>
  checked(owner.coordinatorPrepareUnknown(record));
export const transitionExpectedRevision =
  owner.coordinatorTransitionExpectedRevision;
export const transitionDurableJson = (durable, transition) =>
  checked(owner.coordinatorTransitionDurableJson(durable, transition));
export const commitTransition = transition =>
  checked(owner.coordinatorCommitTransition(transition));
export const recordStateCodes = owner.coordinatorRecordStateCodes;
