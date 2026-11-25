import assert from 'node:assert/strict';
import test from 'node:test';
import {assertAuthorizationAccountCurrent, authorizationDispatchFacts,
  createAuthorizationDecisionBudget, createAuthorizationGate} from
  '../host-common/authorization-gate.mjs';

import type {admitResumedDispatch} from '../host-common/authorization-gate.mjs';
import type {createAccountConstruction} from './account-construction.mjs';

type GateOptions = NonNullable<Parameters<typeof createAuthorizationGate>[0]>;
type Runtime = NonNullable<GateOptions['runtime']>;
type Ask = NonNullable<GateOptions['decide']>;
type FixtureOptions = Readonly<{wire?: string; readConfiguration?: GateOptions['readConfiguration'];
  budget?: GateOptions['decisionBudget']; decide?: (view: Parameters<Ask>[0]) => ReturnType<Ask>}>;
type Evaluation = Readonly<{
  account_id: string; entry_id: string; principal: string; connection: string;
  resource: string; operation: string; outcome: 'allow' | 'deny' | 'delegate';
}>;

type Gate = ReturnType<typeof createAuthorizationGate>;
type Journal = NonNullable<Parameters<typeof admitResumedDispatch>[0]>;
type Admission = ReturnType<NonNullable<Journal['admitResume']>>;
type Entered = ReturnType<NonNullable<Journal['enterResumedDispatch']>>;
type Bound = Extract<ReturnType<typeof admitResumedDispatch>, {admission: unknown}>['admission'];
type Assert<Value extends true> = Value;
type AuthorizationPortCases = [
  Assert<null extends Admission['configurationCid'] ? true : false>,
  Assert<null extends Entered['decisionSubjectCid'] ? true : false>,
  Assert<null extends Bound['configurationCid'] ? false : true>,
  Assert<null extends Bound['decisionSubjectCid'] ? true : false>,
  Assert<(() => Promise<undefined>) extends Gate['assertAccountCurrent'] ? false : true>,
  Assert<(() => PromiseLike<undefined>) extends Gate['assertAccountCurrent'] ? false : true>,
  Assert<(() => Promise<undefined>) extends Gate['assertConfigurationCurrent'] ? false : true>,
  Assert<(() => PromiseLike<undefined>) extends Gate['assertConfigurationCurrent'] ? false : true>,
];

type AccountFactory = Parameters<typeof createAccountConstruction>[0];
type ObserveAccount = ReturnType<typeof createAccountConstruction>['observe'];
type WithAccountObservation = NonNullable<GateOptions['withAccountObservation']>;
type AccountConstructionCases = [
  Assert<(() => Promise<undefined>) extends AccountFactory['current'] ? false : true>,
  Assert<(() => Promise<undefined>) extends AccountFactory['prepareRead'] ? false : true>,
  Assert<(() => Promise<undefined>) extends Parameters<ObserveAccount>[0] ? false : true>,
  Assert<(() => Promise<undefined>) extends WithAccountObservation ? false : true>,
];

// Real adapter with a finite Core double. These controls establish issuer and
// account-observation routing, not compiled Core or physical Provider coverage.
const cid = (value: string) => `sha256:${value.repeat(64)}`;
const context = Object.freeze({principal: 'owner', contextCid: cid('a')});
const scope = Object.freeze({connection: 'connection', resource: 'resource', operation: 'read'});
const subjectCid = cid('b');
const accountWire = (fields: Readonly<Record<string, unknown>> = {}) => JSON.stringify({state: 'admitted',
  account_id: 'account', configuration_cid: cid('c'), outcome: 'allow',
  entry_id: 'entry', ...fields});

function fixture({wire = accountWire(), readConfiguration, budget, decide}: FixtureOptions = {}) {
  let decisions = 0;
  const calls = {admit: 0, accountState: 0, evaluate: 0};
  const runtime: Runtime = {
    executionAuthorizationAdmit(text) { calls.admit++; return JSON.parse(text); },
    executionAuthorizationMissing: () => ({state: 'missing'}),
    executionAuthorizationAccountJson(account) { calls.accountState++; return JSON.stringify(account); },
    executionAuthorizationEvaluate(account, principal, connection, resource, operation) {
      calls.evaluate++;
      return {...account, principal, connection, resource, operation};
    },
    executionAuthorizationEvaluationJson: JSON.stringify,
    executionAuthorizationEvaluationAction: evaluation => (evaluation as Evaluation).outcome === 'allow'
      ? {action: 'dispatch', basis: 'account_allow'}
      : {action: 'deny', basis: 'account', reason: 'explicit'},
    executionAuthorizationPrepare(evaluation, configurationCid, boundary, subjectCid,
      contextCid, answeringAuthorities, requiredClaims) {
      return {ok: true, subject: {account_id: (evaluation as Evaluation).account_id,
        configuration_cid: configurationCid, entry_id: (evaluation as Evaluation).entry_id,
        principal: (evaluation as Evaluation).principal, connection: (evaluation as Evaluation).connection,
        resource: (evaluation as Evaluation).resource, operation: (evaluation as Evaluation).operation,
        boundary, subject_cid: subjectCid, context_cid: contextCid},
      answering_authorities: answeringAuthorities, required_claims: requiredClaims};
    },
    executionAuthorizationRequestJson: JSON.stringify,
    executionAuthorizationAnswer: (_request, kind, _subject, authority, claims) =>
      kind === 'permit' ? {action: 'dispatch', authority, claims}
        : {action: 'failure', reason: 'unavailable'},
    executionAuthorizationDecisionJson: JSON.stringify,
  };
  const gate = createAuthorizationGate({runtime, configuration: wire,
    context, readConfiguration, decisionBudget: budget,
    ...(decide === undefined ? {} : {answeringAuthorities: ['host'],
      decide(view) { decisions++; return decide(view); }})});
  return {gate, calls, decisions: () => decisions,
    authorize: (owner = gate) => owner.authorize('acquisition', scope, {subjectCid})};
}

test('unchanged issued Account facts reuse admission and evaluation within the original gate', async () => {
  let reads = 0;
  const wire = accountWire();
  const x = fixture({wire, readConfiguration() { reads++; return wire; }});
  try {
    const original = await x.authorize();
    for (let index = 0; index < 4; index++) {
      x.gate.assertAccountCurrent(original);
    }
    assert.equal(await x.authorize(), original);
    assert.deepEqual(x.calls, {admit: 1, accountState: 1, evaluate: 1});
    // Each actual boundary still observes the file-backed source; no TTL or
    // process-global Allow cache is introduced by retaining pure typed facts.
    assert.equal(reads, 6);
  } finally { x.gate.close(); }
});

test('unchanged delegate facts do not repeat Account evaluation or its Host answer', async () => {
  const x = fixture({wire: accountWire({outcome: 'delegate'}),
    decide: view => ({decision: 'permit', subject: view.subject, authority: 'host', claims: []})});
  try {
    const original = await x.authorize();
    x.gate.assertAccountCurrent(original);
    assert.equal(await x.authorize(), original);
    assert.equal(x.calls.evaluate, 1);
    assert.equal(x.calls.accountState, 1);
    assert.equal(x.decisions(), 1);
  } finally { x.gate.close(); }
});

test('live immutable account validates the same issued decision without a new decision', async () => {
  const x = fixture();
  try {
    const original = await x.authorize();
    const counters = x.gate.counters();
    assert.equal(x.gate.assertAccountCurrent(original), undefined);
    assert.equal(assertAuthorizationAccountCurrent(original), undefined);
    assert.deepEqual(x.gate.counters(), counters);
    assert.equal(await x.authorize(), original);
  } finally { x.gate.close(); }
});

test('the configuration-only fence is non-authorizing and observes original scope lifetime', () => {
  let wire = accountWire({outcome: 'delegate'});
  const x = fixture({wire, readConfiguration: () => wire});
  assert.equal(x.gate.assertConfigurationCurrent(), undefined);
  assert.equal(x.gate.counters().evaluations, 0);
  assert.equal(x.gate.counters().protectedDispatches, 0);
  wire = accountWire({configuration_cid: cid('d')});
  assert.throws(() => x.gate.assertConfigurationCurrent(),
    {code: 'AuthorizationCurrentAccountChanged'});
  x.gate.close();
  assert.throws(() => x.gate.assertConfigurationCurrent(),
    {code: 'AuthorizationDecisionScopeClosed'});
});

test('same original delegate remains delegated without requesting another Host answer', async () => {
  const x = fixture({wire: accountWire({outcome: 'delegate'}),
    decide: view => ({decision: 'permit', subject: view.subject, authority: 'host', claims: []})});
  try {
    const original = await x.authorize();
    assert.equal(original.basis, 'host_permit');
    assertAuthorizationAccountCurrent(original);
    assert.equal(await x.authorize(), original);
    assert.equal(x.decisions(), 1);
  } finally { x.gate.close(); }
});

test('copies and another scope cannot borrow an original issuer', async () => {
  const x = fixture();
  const sibling = x.gate.withContext(context);
  try {
    const original = await x.authorize();
    assert.throws(() => sibling.assertAccountCurrent(original), {code: 'ForeignAuthorizationDecision'});
    assert.throws(() => assertAuthorizationAccountCurrent(Object.freeze({...original})),
      {code: 'ForeignAuthorizationDecision'});
    for (const fake of [undefined, null, {}, Object.freeze({action: 'dispatch'})]) {
      assert.throws(() => assertAuthorizationAccountCurrent(fake as Parameters<typeof assertAuthorizationAccountCurrent>[0]), {code: 'ForeignAuthorizationDecision'});
    }
  } finally { sibling.close(); x.gate.close(); }
});

test('historical provenance cannot make a closed original issuer current', async () => {
  const x = fixture();
  const original = await x.authorize();
  x.gate.close();
  assert.notEqual(authorizationDispatchFacts(original), undefined);
  assert.throws(() => assertAuthorizationAccountCurrent(original),
    {code: 'AuthorizationDecisionScopeClosed'});
});

test('parent scope closure preserves a sibling while installation budget closure retires it', async () => {
  const budget = createAuthorizationDecisionBudget();
  const x = fixture({budget});
  const sibling = x.gate.withContext(context);
  const original = await x.authorize(sibling);
  x.gate.close();
  assertAuthorizationAccountCurrent(original);
  budget.close();
  assert.throws(() => assertAuthorizationAccountCurrent(original),
    {code: 'AuthorizationDecisionScopeClosed'});
});

test('the original account identity and configuration must both remain exact', async () => {
  for (const changed of [{account_id: 'other'}, {configuration_cid: cid('d')}]) {
    let wire = accountWire();
    const x = fixture({readConfiguration: () => wire});
    try {
      const original = await x.authorize();
      wire = accountWire(changed);
      assert.throws(() => assertAuthorizationAccountCurrent(original),
        {code: 'AuthorizationCurrentAccountChanged', runtimeCode: 'ACTQL_E_ACCOUNT_CONFIG_INVALID'});
      await assert.rejects(x.authorize(), {code: 'AuthorizationCurrentAccountChanged'});
      assert.equal(x.gate.counters().protectedDispatches, 1);
    } finally { x.gate.close(); }
  }
});

test('missing rejected malformed asynchronous or failed observations cannot dispatch', async () => {
  for (const read of [() => undefined, () => JSON.stringify({state: 'rejected'}),
    () => '{', () => Promise.resolve(accountWire()), () => { throw new Error('read unavailable'); }]) {
    // Include the intentionally asynchronous invalid port in this runtime refusal test.
    const x = fixture({readConfiguration: read as GateOptions['readConfiguration']});
    try {
      await assert.rejects(x.authorize(), {code: 'AuthorizationCurrentAccountUnavailable',
        runtimeCode: 'ACTQL_E_ACCOUNT_CONFIG_INVALID'});
      assert.equal(x.gate.counters().protectedDispatches, 0);
    } finally { x.gate.close(); }
  }
});

test('a current deny or changed selected entry never converts an original decision to allow', async () => {
  for (const changed of [{outcome: 'deny'}, {entry_id: 'other'}]) {
    const x = fixture({readConfiguration: () => accountWire(changed)});
    try {
      await assert.rejects(x.authorize(), {code: 'AuthorizationCurrentAccountChanged'});
    } finally { x.gate.close(); }
  }
});

test('account change during the original Host answer await fences its returned permit', async () => {
  let wire = accountWire({outcome: 'delegate'});
  let release!: () => void, started!: () => void;
  const began = new Promise<void>(resolve => { started = resolve; });
  const held = new Promise<void>(resolve => { release = resolve; });
  const x = fixture({wire, readConfiguration: () => wire,
    decide: async view => { started(); await held;
      return {decision: 'permit', subject: view.subject, authority: 'host', claims: []}; }});
  try {
    const pending = x.authorize();
    await began;
    wire = accountWire({configuration_cid: cid('d'), outcome: 'deny'});
    release();
    await assert.rejects(pending, {code: 'AuthorizationCurrentAccountChanged'});
    assert.equal(x.decisions(), 1);
    assert.equal(x.gate.counters().protectedDispatches, 0);
  } finally { release(); x.gate.close(); }
});

test('an observer that retires the original scope cannot report successful currency', async () => {
  let close = false;
  const x = fixture({readConfiguration() { if (close) x.gate.close(); return accountWire(); }});
  const original = await x.authorize();
  close = true;
  assert.throws(() => assertAuthorizationAccountCurrent(original),
    {code: 'AuthorizationDecisionScopeClosed'});
});
