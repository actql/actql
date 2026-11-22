// The installed Local Host's existing Result read tuple. Common alone
// evaluates Account entries; identity/scope equality is never an Allow.
import {observeInstalledAccount, createLocalAuthorizationGate} from './local-account-config.mjs';
import {isHostObservationProjection} from '../host-common/observation.mjs';

import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {loadExecutionAuthorizationRuntime} from './authorization.mjs';

type AuthorizationRuntime = Awaited<ReturnType<typeof loadExecutionAuthorizationRuntime>>;
type Account = ReturnType<typeof observeInstalledAccount>;
type Runtime = Parameters<typeof observeInstalledAccount>[0] & Pick<AuthorizationRuntime,
  'executionAuthorizationEvaluate' | 'executionAuthorizationAccountJson' | 'executionAuthorizationEvaluationJson'>;
type GateOptions = NonNullable<Parameters<typeof createLocalAuthorizationGate>[0]> & Readonly<{siteKey?: string}>;
type Options = Readonly<{
  moon: Runtime;
  authorization?: GateOptions | null;
  principalId: string;
  namespaceId: string;
  authorityScopeCid: string;
  observation?: unknown;
}>;
type ReadFacts = Readonly<{
  principalId: string;
  indexKey?: Pick<WireRunRef, 'namespaceId' | 'authorityScopeCid'> & Partial<Pick<WireRunRef, 'runDefinitionCid'>>;
  resultName?: unknown;
  purpose?: string;
  delivery?: Readonly<{sinkCallbackCount?: number}>;
  manifest?: Readonly<{identity?: string}>;
}>;
type Operation = Pick<ReadFacts, 'principalId' | 'indexKey' | 'resultName' | 'purpose'> | null | undefined;
type Scope = Readonly<{connection: string; resource: string; operation: 'read'}>;
type Observation = typeof isHostObservationProjection extends (input: unknown) => input is infer Projection ? Projection : never;
type CallbackState = ReturnType<Observation['applicationCallbackState']> | undefined;
type Memo = Readonly<{
  allowed: boolean;
  account: Account;
  resource: string;
  sinkCallbackCount: number;
  callbackState: CallbackState;
}>;
type Authorize = {
  (facts: ReadFacts, operation: Operation, resource: string | undefined, interactive: true, reobserve: true): boolean | undefined;
  (facts: ReadFacts, operation: Operation, resource: string | undefined, interactive: false): boolean | undefined;
  (facts: ReadFacts, operation: Operation, resource: string | undefined): boolean | Promise<boolean>;
};

export function createLocalResultAuthorization({moon, authorization,
  principalId, namespaceId, authorityScopeCid, observation}: Options) {
  return createLocalReadAuthorizations({moon, authorization,
    principalId, namespaceId, authorityScopeCid, observation}).result;
}

// Two existing permissions share the installed Account identity, not an
// outcome: run/read never substitutes for result/<actual name>/read.
export function createLocalReadAuthorizations({moon, authorization,
  principalId, namespaceId, authorityScopeCid, observation}: Options) {
  if (observation !== undefined && !isHostObservationProjection(observation)) {
    throw new TypeError('ForeignHostObservationProjection');
  }
  const observeCallbacks = observation?.applicationCallbackState.bind(observation);
  const connection = authorization?.siteKey ?? 'actql-remote-host';
  const staticPlanScope = Object.freeze({namespaceId, authorityScopeCid});
  let retainedAccount = observeInstalledAccount(moon, authorization);
  let identity = JSON.parse(moon.executionAuthorizationAccountJson(retainedAccount)) as {state?: unknown; account_id?: unknown};
  const originalAccountId = identity.state === 'admitted' ? identity.account_id : undefined;
  // The existing owned public request is the lifetime of this memo. No
  // outcome survives into another operation, even for identical wire/tuples.
  const operations = new WeakMap<NonNullable<Operation>, Memo>();
  const authorize = ((facts: ReadFacts, operation: Operation, resource: string | undefined, interactive: boolean = true, reobserve: boolean = false) => {
    if (facts.principalId !== principalId || facts.indexKey?.namespaceId !== namespaceId ||
        facts.indexKey?.authorityScopeCid !== authorityScopeCid ||
        resource === undefined) return false;
    const scope: Scope = {connection, resource, operation: 'read'};
    // Immediate metadata never consumes or installs an async read's allowed
    // memo. Observe current Account/Common at EACH actual boundary instead.
    const sameOperation = interactive && operation !== null && typeof operation === 'object' &&
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
    // A metadata read and a Result read can share an original Run tuple,
    // but never the permission's outcome. Keep the selected resource in the
    // owned operation memo even when a caller presents the same operation.
    const candidate = sameOperation ? operations.get(operation) : undefined;
    const retained = candidate?.resource === resource ? candidate : undefined;
    if (!reobserve && retained !== undefined && retained.account === retainedAccount &&
        callbackState?.active !== true && retained.callbackState === callbackState &&
        retained.sinkCallbackCount === sinkCallbackCount) return retained.allowed;
    const account = observeInstalledAccount(moon, authorization);
    if (account !== retainedAccount) {
      identity = JSON.parse(moon.executionAuthorizationAccountJson(account)) as typeof identity;
      retainedAccount = account;
    }
    if (retained !== undefined && retained.account === account) {
      // Same immutable Account after application reentry: observing current
      // bytes is not another admission/evaluation of this unchanged tuple.
      operations.set(operation!, {...retained, sinkCallbackCount, callbackState});
      return retained.allowed;
    }
    if (originalAccountId === undefined || identity.state !== 'admitted' ||
        identity.account_id !== originalAccountId) return false;
    const evaluation = moon.executionAuthorizationEvaluate(account, principalId,
      scope.connection, scope.resource, scope.operation);
    const outcome = JSON.parse(moon.executionAuthorizationEvaluationJson(evaluation)) as {outcome?: unknown};
    if (outcome.outcome !== 'delegate') {
      const allowed = outcome.outcome === 'allow';
      if (sameOperation) operations.set(operation!, {allowed, account, resource, sinkCallbackCount, callbackState});
      return allowed;
    }
    // Optional task metadata may consume only an immediate original decision.
    // Delegate remains unavailable; this path cannot ask an application or
    // pause Compute while waiting for a metadata-only authorization answer.
    if (!interactive || reobserve) return undefined;
    return authorizeDelegated(facts, operation, scope, sameOperation, account,
      resource, sinkCallbackCount, callbackState);
  }) as Authorize;
  const authorizeDelegated = async (facts: ReadFacts, operation: Operation, scope: Scope, sameOperation: boolean,
    account: Account, resource: string, sinkCallbackCount: number, callbackState: CallbackState) => {
    // An immediate configured answer still belongs to the existing gate.
    // A read cannot synthesize a Checkpoint/claim or treat Delegate as Allow.
    const gate = await createLocalAuthorizationGate({...authorization,
      principal: principalId, deferral: undefined});
    try {
      const decision = await gate.authorize('transfer', scope, {
        subjectCid: facts.manifest?.identity ?? facts.indexKey!.runDefinitionCid!,
        allowDeferral: false});
      const allowed = decision.action === 'dispatch';
      // The application's answer and its post-callback current check have
      // completed. Internal consumption does not call that application again.
      if (sameOperation) operations.set(operation!, {allowed, account, resource, sinkCallbackCount, callbackState});
      return allowed;
    } finally { gate.close(); }
  };
  // Preserve the original async contract, including a rejection for a
  // synchronous Account/current failure, without another per-read state bag.
  const promised = (facts: ReadFacts, operation: Operation, resource: string | undefined) => {
    try {return Promise.resolve(authorize(facts, operation, resource));}
    catch (cause) {return Promise.reject(cause);}
  };
  return Object.freeze({
    result(facts: ReadFacts, operation?: Operation) {
      const resource = typeof facts.resultName === 'string' && facts.resultName.length > 0
        ? `result/${facts.resultName}` : undefined;
      return promised(facts, operation, resource);
    },
    run(facts: ReadFacts, operation?: Operation) {return promised(facts, operation, 'run');},
    // A completed delegated decision survives only on the same current
    // Account and operation. The synchronous check never starts a callback.
    runCurrent(facts: ReadFacts, operation?: Operation) {return authorize(facts, operation, 'run', true, true);},
    // Internal installed metadata consumer, never a public permission field.
    runImmediate(facts: ReadFacts, operation?: Operation) {return authorize(facts, operation, 'run', false);},
    // Static metadata has the installed scope and no Run reference. Check the
    // current Account at every boundary, including immediately before egress.
    staticPlanImmediate({principalId: actual}: Pick<ReadFacts, 'principalId'>) {
      return authorize({principalId: actual, indexKey: staticPlanScope}, undefined, 'run', false);
    },
  });
}
