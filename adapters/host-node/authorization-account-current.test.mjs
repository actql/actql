import assert from 'node:assert/strict';
import test from 'node:test';
import {assertAuthorizationAccountCurrent, authorizationDispatchFacts,
  createAuthorizationDecisionBudget, createAuthorizationGate} from
  '../host-common/authorization-gate.mjs';

// Real adapter with a finite Core double. These controls establish issuer and
// account-observation routing, not compiled Core or physical Provider coverage.
const cid = value => `sha256:${value.repeat(64)}`;
const context = Object.freeze({principal: 'owner', contextCid: cid('a')});
const scope = Object.freeze({connection: 'connection', resource: 'resource', operation: 'read'});
const subjectCid = cid('b');
const accountWire = (fields = {}) => JSON.stringify({state: 'admitted',
  account_id: 'account', configuration_cid: cid('c'), outcome: 'allow',
  entry_id: 'entry', ...fields});

function fixture({wire = accountWire(), readConfiguration, budget, decide} = {}) {
  let decisions = 0;
  const runtime = {
    executionAuthorizationAdmit: JSON.parse,
    executionAuthorizationMissing: () => ({state: 'missing'}),
    executionAuthorizationAccountJson: JSON.stringify,
    executionAuthorizationEvaluate: (account, principal, connection, resource, operation) =>
      ({...account, principal, connection, resource, operation}),
    executionAuthorizationEvaluationJson: JSON.stringify,
    executionAuthorizationEvaluationAction: evaluation => evaluation.outcome === 'allow'
      ? {action: 'dispatch', basis: 'account_allow'}
      : {action: 'deny', basis: 'account', reason: 'explicit'},
    executionAuthorizationPrepare(evaluation, configurationCid, boundary, subjectCid,
      contextCid, answeringAuthorities, requiredClaims) {
      return {ok: true, subject: {account_id: evaluation.account_id,
        configuration_cid: configurationCid, entry_id: evaluation.entry_id,
        principal: evaluation.principal, connection: evaluation.connection,
        resource: evaluation.resource, operation: evaluation.operation,
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
  return {gate, decisions: () => decisions,
    authorize: (owner = gate) => owner.authorize('acquisition', scope, {subjectCid})};
}

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

test('requested-stop Account observation preserves outcomes without a Host answer or dispatch', () => {
  for (const outcome of ['allow', 'deny', 'delegate']) {
    const x = fixture({wire: accountWire({outcome}), decide() {
      throw new Error('MustNotAskForDelegation');
    }});
    try {
      const before = x.gate.counters();
      const observed = x.gate.observeAccountOutcome(scope);
      assert.deepEqual(observed, {outcome, entryId: 'entry'});
      assert.equal(Object.isFrozen(observed), true);
      assert.equal(authorizationDispatchFacts(observed), undefined);
      assert.throws(() => assertAuthorizationAccountCurrent(observed),
        {code: 'ForeignAuthorizationDecision'});
      assert.deepEqual(x.gate.counters(), before);
      assert.equal(x.decisions(), 0);
    } finally { x.gate.close(); }
    assert.throws(() => x.gate.observeAccountOutcome(scope),
      {code: 'AuthorizationDecisionScopeClosed'});
  }
});

test('requested-stop Account observation refuses a changed original configuration before an answer', () => {
  let wire = accountWire({outcome: 'delegate'});
  const x = fixture({wire, readConfiguration: () => wire});
  try {
    assert.equal(x.gate.observeAccountOutcome(scope).outcome, 'delegate');
    wire = accountWire({configuration_cid: cid('d')});
    assert.throws(() => x.gate.observeAccountOutcome(scope),
      {code: 'AuthorizationCurrentAccountChanged'});
    assert.equal(x.decisions(), 0);
    assert.equal(x.gate.counters().protectedDispatches, 0);
  } finally { x.gate.close(); }
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
      assert.throws(() => assertAuthorizationAccountCurrent(fake), {code: 'ForeignAuthorizationDecision'});
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
    const x = fixture({readConfiguration: read});
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
  let release, started;
  const began = new Promise(resolve => { started = resolve; });
  const held = new Promise(resolve => { release = resolve; });
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
