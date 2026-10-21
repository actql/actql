// The installed Local Host's existing Result read tuple. Common alone
// evaluates Account entries; identity/scope equality is never an Allow.
import {observeInstalledAccount, createLocalAuthorizationGate} from './local-account-config.mjs';

export function createLocalResultAuthorization({moon, authorization,
  principalId, namespaceId, authorityScopeCid}) {
  const connection = authorization?.siteKey ?? 'actql-remote-host';
  let retainedAccount = observeInstalledAccount(moon, authorization);
  let identity = JSON.parse(moon.executionAuthorizationAccountJson(retainedAccount));
  const originalAccountId = identity.state === 'admitted' ? identity.account_id : undefined;
  let lastEvaluation;
  return async facts => {
    if (facts.principalId !== principalId || facts.indexKey?.namespaceId !== namespaceId ||
        facts.indexKey?.authorityScopeCid !== authorityScopeCid ||
        typeof facts.resultName !== 'string' || facts.resultName.length === 0) return false;
    const scope = {connection, resource: `result/${facts.resultName}`, operation: 'read'};
    const account = observeInstalledAccount(moon, authorization);
    if (account !== retainedAccount) {
      identity = JSON.parse(moon.executionAuthorizationAccountJson(account));
      retainedAccount = account;
    }
    if (originalAccountId === undefined || identity.state !== 'admitted' ||
        identity.account_id !== originalAccountId) return false;
    // One bounded pure tuple observation, never a cached delegated answer.
    // The original configuration was re-read above on every invocation.
    if (lastEvaluation?.account !== account || lastEvaluation.resource !== scope.resource) {
      const evaluation = moon.executionAuthorizationEvaluate(account, principalId,
        scope.connection, scope.resource, scope.operation);
      lastEvaluation = {account, resource: scope.resource,
        outcome: JSON.parse(moon.executionAuthorizationEvaluationJson(evaluation))};
    }
    const outcome = lastEvaluation.outcome;
    if (outcome.outcome === 'allow') return true;
    if (outcome.outcome !== 'delegate') return false;
    // An immediate configured answer still belongs to the existing gate.
    // A read cannot synthesize a Checkpoint/claim or treat Delegate as Allow.
    const gate = await createLocalAuthorizationGate({...authorization,
      principal: principalId, deferral: undefined});
    try {
      const decision = await gate.authorize('transfer', scope, {
        subjectCid: facts.manifest?.identity ?? facts.indexKey.runDefinitionCid,
        allowDeferral: false});
      return decision.action === 'dispatch';
    } finally { gate.close(); }
  };
}
