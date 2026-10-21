// The installed Local Host's existing Result read tuple. Common alone
// evaluates Account entries; identity/scope equality is never an Allow.
import {observeInstalledAccount, createLocalAuthorizationGate} from './local-account-config.mjs';

export function createLocalResultAuthorization({moon, authorization,
  principalId, namespaceId, authorityScopeCid}) {
  const connection = authorization?.siteKey ?? 'actql-remote-host';
  let retainedAccount = observeInstalledAccount(moon, authorization);
  let identity = JSON.parse(moon.executionAuthorizationAccountJson(retainedAccount));
  const originalAccountId = identity.state === 'admitted' ? identity.account_id : undefined;
  // The existing owned public request is the lifetime of this memo. No
  // outcome survives into another operation, even for identical wire/tuples.
  const operations = new WeakMap();
  return async (facts, operation) => {
    if (facts.principalId !== principalId || facts.indexKey?.namespaceId !== namespaceId ||
        facts.indexKey?.authorityScopeCid !== authorityScopeCid ||
        typeof facts.resultName !== 'string' || facts.resultName.length === 0) return false;
    const scope = {connection, resource: `result/${facts.resultName}`, operation: 'read'};
    const sameOperation = operation !== null && typeof operation === 'object' &&
      Object.isFrozen(operation) && operation.principalId === facts.principalId &&
      operation.resultName === facts.resultName && operation.purpose === facts.purpose &&
      operation.indexKey?.namespaceId === facts.indexKey.namespaceId &&
      operation.indexKey?.authorityScopeCid === facts.indexKey.authorityScopeCid &&
      operation.indexKey?.runDefinitionCid === facts.indexKey.runDefinitionCid;
    const retained = sameOperation ? operations.get(operation) : undefined;
    if (retained !== undefined) return retained.allowed;
    const account = observeInstalledAccount(moon, authorization);
    if (account !== retainedAccount) {
      identity = JSON.parse(moon.executionAuthorizationAccountJson(account));
      retainedAccount = account;
    }
    if (originalAccountId === undefined || identity.state !== 'admitted' ||
        identity.account_id !== originalAccountId) return false;
    const evaluation = moon.executionAuthorizationEvaluate(account, principalId,
      scope.connection, scope.resource, scope.operation);
    const outcome = JSON.parse(moon.executionAuthorizationEvaluationJson(evaluation));
    if (outcome.outcome !== 'delegate') {
      const allowed = outcome.outcome === 'allow';
      if (sameOperation) operations.set(operation, {allowed});
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
      if (sameOperation) operations.set(operation, {allowed});
      return allowed;
    } finally { gate.close(); }
  };
}
