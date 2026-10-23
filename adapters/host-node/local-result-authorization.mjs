// The installed Local Host's existing Result read tuple. Common alone
// evaluates Account entries; identity/scope equality is never an Allow.
import {observeInstalledAccount, createLocalAuthorizationGate} from './local-account-config.mjs';
import {isHostObservationProjection} from '../host-common/observation.mjs';

export function createLocalResultAuthorization({moon, authorization,
  principalId, namespaceId, authorityScopeCid, observation}) {
  return createLocalReadAuthorizations({moon, authorization,
    principalId, namespaceId, authorityScopeCid, observation}).result;
}

// Two existing permissions share the installed Account identity, not an
// outcome: run/read never substitutes for result/<actual name>/read.
export function createLocalReadAuthorizations({moon, authorization,
  principalId, namespaceId, authorityScopeCid, observation}) {
  if (observation !== undefined && !isHostObservationProjection(observation)) {
    throw new TypeError('ForeignHostObservationProjection');
  }
  const observeCallbacks = observation?.applicationCallbackState.bind(observation);
  const connection = authorization?.siteKey ?? 'actql-remote-host';
  let retainedAccount = observeInstalledAccount(moon, authorization);
  let identity = JSON.parse(moon.executionAuthorizationAccountJson(retainedAccount));
  const originalAccountId = identity.state === 'admitted' ? identity.account_id : undefined;
  // The existing owned public request is the lifetime of this memo. No
  // outcome survives into another operation, even for identical wire/tuples.
  const operations = new WeakMap();
  const authorize = async (facts, operation, resource) => {
    if (facts.principalId !== principalId || facts.indexKey?.namespaceId !== namespaceId ||
        facts.indexKey?.authorityScopeCid !== authorityScopeCid ||
        resource === undefined) return false;
    const scope = {connection, resource, operation: 'read'};
    const sameOperation = operation !== null && typeof operation === 'object' &&
      Object.isFrozen(operation) && operation.principalId === facts.principalId &&
      operation.resultName === facts.resultName && operation.purpose === facts.purpose &&
      operation.indexKey?.namespaceId === facts.indexKey.namespaceId &&
      operation.indexKey?.authorityScopeCid === facts.indexKey.authorityScopeCid &&
      operation.indexKey?.runDefinitionCid === facts.indexKey.runDefinitionCid;
    // Only an actual application callback advances this observation boundary.
    // Pure internal stages/Store reads/FFI exchanges keep the original memo.
    const callbackState = observeCallbacks?.();
    const sinkCallbackCount = facts.delivery?.sinkCallbackCount ?? 0;
    if (!Number.isSafeInteger(sinkCallbackCount) || sinkCallbackCount < 0) return false;
    const retained = sameOperation ? operations.get(operation) : undefined;
    if (retained !== undefined && retained.account === retainedAccount &&
        callbackState?.active !== true && retained.callbackState === callbackState &&
        retained.sinkCallbackCount === sinkCallbackCount) return retained.allowed;
    const account = observeInstalledAccount(moon, authorization);
    if (account !== retainedAccount) {
      identity = JSON.parse(moon.executionAuthorizationAccountJson(account));
      retainedAccount = account;
    }
    if (retained !== undefined && retained.account === account) {
      // Same immutable Account after application reentry: observing current
      // bytes is not another admission/evaluation of this unchanged tuple.
      operations.set(operation, {...retained, sinkCallbackCount, callbackState});
      return retained.allowed;
    }
    if (originalAccountId === undefined || identity.state !== 'admitted' ||
        identity.account_id !== originalAccountId) return false;
    const evaluation = moon.executionAuthorizationEvaluate(account, principalId,
      scope.connection, scope.resource, scope.operation);
    const outcome = JSON.parse(moon.executionAuthorizationEvaluationJson(evaluation));
    if (outcome.outcome !== 'delegate') {
      const allowed = outcome.outcome === 'allow';
      if (sameOperation) operations.set(operation, {allowed, account, sinkCallbackCount, callbackState});
      return allowed;
    }
    // An immediate configured answer still belongs to the existing gate.
    // A read cannot synthesize a Checkpoint/claim or treat Delegate as Allow.
    const gate = await createLocalAuthorizationGate({...authorization,
      principal: principalId, deferral: undefined});
    try {
      const decision = await gate.authorize('transfer', scope, {
        subjectCid: facts.manifest?.identity ?? facts.indexKey.runDefinitionCid,
        allowDeferral: false});
      const allowed = decision.action === 'dispatch';
      // The application's answer and its post-callback current check have
      // completed. Internal consumption does not call that application again.
      if (sameOperation) operations.set(operation, {allowed, account, sinkCallbackCount, callbackState});
      return allowed;
    } finally { gate.close(); }
  };
  return Object.freeze({
    result(facts, operation) {
      const resource = typeof facts.resultName === 'string' && facts.resultName.length > 0
        ? `result/${facts.resultName}` : undefined;
      return authorize(facts, operation, resource);
    },
    run(facts) {return authorize(facts, undefined, 'run');},
  });
}
