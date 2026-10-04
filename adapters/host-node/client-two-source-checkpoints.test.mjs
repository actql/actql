// Focused Checkpoint-owner tests. They use the existing real journal, account
// gates and encrypted evidence Store, with a Host physical port that records
// starts. Runtime preparation belongs to the caller; this file never builds.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate} from
  './local-account-config.mjs';
import {loadPrivateEvidenceKey, openContinuationEvidence} from
  './local-continuation-evidence.mjs';

const moon = await import(new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);
const contractControl = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const keys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, keys.privateKey)};
const configuration = (account, outcome, operation) => canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: account,
  entries: [{entry_id: `${account}-entry`, outcome,
    principal: {all: true}, connection: {all: true}, resource: {all: true},
    operation: {any_of: [operation]}, exclusions: []}],
});
const source = (side, outcome = 'delegate') => ({
  sourceRef: `connector://fixture/${side}/r#v`,
  accountConfiguration: configuration(`${side}-account`, outcome, 'read'),
  context: {principal: 'owner', contextCid: contentCid({source: side})},
});
const acquisition = (side, index) => ({stage: index, input: 0, task: index,
  checkedSource: {sourceRef: `connector://fixture/${side}/r#v`,
    requirementCid: cid(String(index + 1)), sourceContractCid: cid('a')},
  // Both occurrences deliberately use the same tuple: a tuple/source cache
  // must never turn one approval into authorization for the other occurrence.
  readTuple: {connection: 'database', resource: '/shared.db', operation: 'read'},
  physicalBinding: {database: '/shared.db', schema: 'main', table: side},
});
const submission = () => ({
  version: 'actql-remote-multi-source-submission/0.1',
  kind: 'program', requestId: 'pair-request', principalId: 'owner',
  input: {stages: [{fixture: 'left'}, {fixture: 'right'}]}, parameters: {},
  resultNames: ['joined'], acquisitions: [acquisition('left', 0),
    acquisition('right', 1)],
});
const requested = {logicalRequestScopeCid: cid('3'), intentFingerprintCid: cid('4')};

async function fixture(t, {runOutcome = 'allow', sources = [source('left'),
  source('right')], single, authorization = {}} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-two-source-checkpoint-'));
  const clock = {ms: Date.parse('2026-10-02T08:00:00.000Z')};
  const opened = new Set();
  const diagnostics = [];
  const open = async (overrides = {}) => {
    const checkpoints = await installRemoteCheckpoints({root, namespaceId: 'ns',
      authorityScopeCid: cid('5'), ownerPrincipal: 'owner', siteKey: 'site',
      realizationKey: 'realization', environmentCid: cid('6'), contractControl,
      now: () => clock.ms,
      ...(single === undefined ? {sources} : {source: single}),
      authorization: {
        accountConfiguration: configuration('host-account', runOutcome, 'write'),
        reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
          principalId: 'reviewer-principal', publicKey: pem(keys.publicKey)}],
        reviewReaders: ['reader'],
        hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)},
        resumeAfterAnswer: false, checkpointTtlMs: 2000, leaseMs: 10_000,
        observe: (name, detail) => diagnostics.push({name, detail}),
        ...authorization,
      }, ...overrides});
    opened.add(checkpoints);
    return checkpoints;
  };
  const close = async checkpoints => {
    await checkpoints.close();
    opened.delete(checkpoints);
  };
  t.after(async () => {
    for (const checkpoints of opened) await checkpoints.close();
    await rm(root, {recursive: true, force: true});
  });
  const list = async checkpoints => (await checkpoints.listCheckpoints({
    principalId: 'owner', after: '', limit: 100})).items;
  const answer = async (checkpoints, summary, decision = 'approved') => {
    const item = await signedAnswer(summary, decision, signer,
      new Date(clock.ms).toISOString());
    const result = await checkpoints.resolve({principalId: 'reviewer-principal',
      items: [item]});
    assert.equal(result.results[0].status, 'committed', JSON.stringify(result));
  };
  const review = async (checkpoints, summary) => JSON.parse(Buffer.from(
    (await checkpoints.reviewCheckpoint({principalId: 'reader',
      checkpointCid: summary.checkpointCid, maxBytes: 256 * 1024}))
      .contentBase64, 'base64'));
  const capturedEvidence = async (checkpoints, summary) => {
    const stateDirectory = join(root, 'checkpoints');
    const evidence = openContinuationEvidence({stateDirectory,
      isTerminalRunOutcome: checkpoints.journal.isTerminalRunOutcome,
      ...await loadPrivateEvidenceKey(stateDirectory), contractControl,
      preparation: () => ({status: 'waiting_checkpoint'})});
    try {
      const records = await evidence.open(summary.subject.prepareAttemptId);
      const view = checkpoints.journal.inspect(summary.checkpointCid);
      const continuation = await records.record('continuation_record',
        view.continuationStateCid);
      const get = name => records.record(name,
        continuation.evidence.find(item => item.name === name).semantic_cid);
      return {continuation, captured: await get('captured_input'),
        intent: await get('prepared_invocation')};
    } finally { await evidence.close(); }
  };
  const port = (checkpoints, {before, atStart} = {}) => {
    const state = {starts: 0, abandoned: 0, inspections: 0, captured: undefined};
    return {state,
      async inspect() { state.inspections++;
        return state.starts > 0 ? {state: 'started', runId: 'run-pair'}
          : state.abandoned > 0 ? {state: 'abandoned'} : {state: 'absent'}; },
      async resume(context) {
        await before?.(context);
        try { context.beforePhysicalStart(); }
        catch (error) { return {refused: error}; }
        state.starts++;
        state.captured = context.captured;
        await atStart?.(context);
        context.started('run-pair');
        return 'started';
      },
      async abandon() { state.abandoned++; },
      async cancelRun() {}, async observe() { return 'running'; },
    };
  };
  return {root, clock, open, close, list, answer, review, capturedEvidence,
    port, diagnostics};
}

async function submit(checkpoints, captured) {
  const run = await checkpoints.acceptRun({requested, captured});
  return run.kind === 'dispatch'
    ? checkpoints.acceptAcquisition({requested, captured}) : run;
}

async function baseAccess(configuration) {
  return {authorization: await createLocalAuthorizationGate(configuration)};
}

test('two source approvals hold the full inventory and survive restart', async t => {
  const f = await fixture(t);
  const captured = submission();
  const first = await f.open();
  assert.equal((await submit(first, captured)).kind, 'held');
  const [left] = await f.list(first);
  const stored = await f.capturedEvidence(first, left);
  assert.deepEqual(stored.captured, captured);
  assert.equal(stored.intent.version,
    'actql-remote-multi-source-acquisition-intent/0.1');
  assert.equal(stored.intent.captured_submission_cid, contentCid(captured));
  assert.deepEqual(stored.intent.occurrence,
    {stage: 0, input: 0, task: 0, requirement_cid: cid('1')});
  const leftReview = await f.review(first, left);
  assert.equal(leftReview.execution_context_cid, source('left').context.contextCid);
  assert.equal(leftReview.host_policy_cid,
    contentCid(JSON.parse(source('left').accountConfiguration)));
  await f.answer(first, left);
  const firstPort = f.port(first);
  await first.start(firstPort);
  assert.equal(firstPort.state.starts, 0, JSON.stringify(f.diagnostics));
  const [right] = await f.list(first);
  assert.equal(right.kind, 'read_access');
  assert.notEqual(right.checkpointCid, left.checkpointCid);
  const rightStored = await f.capturedEvidence(first, right);
  assert.deepEqual(rightStored.continuation.earlier_approvals, [left.checkpointCid]);
  assert.deepEqual(rightStored.captured, captured);
  assert.equal((await f.review(first, right)).execution_context_cid,
    source('right').context.contextCid);
  await f.close(first);
  // Installation order is not occurrence identity. Exact sourceRef selects
  // authorization, while the capture keeps the immutable task order.
  const second = await f.open({sources: [source('right'), source('left')]});
  assert.deepEqual(await f.list(second), [right]);
  await f.answer(second, right);
  const bases = await Promise.all([source('left'), source('right')].map(baseAccess));
  t.after(() => bases.forEach(base => base.authorization.close()));
  const secondPort = f.port(second, {atStart: async ({captured: resumed}) => {
    for (const [index, occurrence] of resumed.acquisitions.entries()) {
      const access = second.acquisitionAccess(captured.requestId, bases[index], occurrence);
      const decision = await access.authorization.authorize('acquisition', occurrence.readTuple);
      assert.equal(decision.action, 'dispatch');
      const facts = checkpointApprovalFacts(decision);
      assert.deepEqual(facts.checkedSource, occurrence.checkedSource);
      assert.deepEqual(facts.physicalBinding, occurrence.physicalBinding);
      assert.equal(facts.occurrence.task, index);
      assert.equal(second.acquisitionAccess(captured.requestId, bases[index]), bases[index]);
      assert.equal(second.acquisitionAccess(captured.requestId, bases[index],
        {...occurrence, checkedSource: {...occurrence.checkedSource,
          requirementCid: cid('9')}}), bases[index]);
    }
  }});
  await second.start(secondPort);
  assert.equal(secondPort.state.starts, 1, JSON.stringify(f.diagnostics));
  assert.deepEqual(secondPort.state.captured, captured);
  await second.sweep();
  assert.equal(secondPort.state.starts, 1);
  second.releaseAcquisition(captured.requestId);
  assert.equal(second.acquisitionAccess(captured.requestId, bases[0], captured.acquisitions[0]), bases[0]);
});

test('unused declared view does not take an acquisition approval', async t => {
  const f = await fixture(t, {sources: [source('unused', 'deny'),
    source('right'), source('left')]});
  const checkpoints = await f.open();
  const captured = submission();
  assert.equal((await submit(checkpoints, captured)).kind, 'held');
  const first = (await f.list(checkpoints))[0];
  assert.equal(first.kind, 'read_access');
  await f.answer(checkpoints, first);
  const physical = f.port(checkpoints);
  await checkpoints.start(physical);
  assert.equal(physical.state.starts, 0);
  const second = (await f.list(checkpoints))[0];
  assert.equal(second.kind, 'read_access');
  await f.answer(checkpoints, second);
  await checkpoints.start(physical);
  assert.equal(physical.state.starts, 1);
  assert.deepEqual(await f.list(checkpoints), []);
  assert.deepEqual(physical.state.captured, captured);
});

test('plural read-authority inventory accepts 128 views and refuses 129',
  async t => {
    const f = await fixture(t);
    const views = Array.from({length: 128}, (_, index) =>
      source(`view-${index}`, 'deny'));
    const admitted = await f.open({sources: views});
    await f.close(admitted);
    await assert.rejects(f.open({sources: Array.from({length: 129}, (_, index) =>
      source(`view-${index}`, 'deny'))}),
    {code: 'InvalidRemoteHostSources'});
  });

test('Run approval chains both occurrences, even for the same source and requirement', async t => {
  const f = await fixture(t, {runOutcome: 'delegate', sources: [source('left')]});
  const checkpoints = await f.open();
  const captured = submission();
  captured.acquisitions[1] = {...structuredClone(captured.acquisitions[0]), stage: 1, task: 1};
  assert.equal((await submit(checkpoints, captured)).kind, 'held');
  const physical = f.port(checkpoints);
  await checkpoints.start(physical);
  const answered = [];
  for (const kind of ['run_scope', 'read_access', 'read_access']) {
    const [summary] = await f.list(checkpoints);
    assert.equal(summary.kind, kind);
    const evidence = await f.capturedEvidence(checkpoints, summary);
    assert.deepEqual(evidence.continuation.earlier_approvals ?? [], answered);
    assert.equal(physical.state.starts, 0);
    answered.push(summary.checkpointCid);
    await f.answer(checkpoints, summary);
    await checkpoints.sweep();
  }
  assert.equal(new Set(answered).size, 3);
  assert.equal(physical.state.starts, 1, JSON.stringify(f.diagnostics));
});

test('an earlier occurrence approval is rechecked immediately before physical start', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  const captured = submission();
  await submit(checkpoints, captured);
  const [left] = await f.list(checkpoints);
  await f.answer(checkpoints, left);
  f.clock.ms += 1000;
  const physical = f.port(checkpoints, {before: async () => { f.clock.ms += 1001; }});
  await checkpoints.start(physical);
  const [right] = await f.list(checkpoints);
  assert.ok(Date.parse(right.expiresAt) > Date.parse(left.expiresAt));
  await f.answer(checkpoints, right);
  await checkpoints.sweep();
  assert.equal(physical.state.starts, 0);
  assert.equal(physical.state.abandoned, 1, JSON.stringify(f.diagnostics));
  assert.equal(checkpoints.heldLookup(captured.requestId).state, 'ended');
});

test('either source configuration or trusted context change invalidates a held pair', async t => {
  for (const change of ['configuration', 'context']) await t.test(change, async t => {
    const f = await fixture(t);
    const first = await f.open();
    const captured = submission();
    await submit(first, captured);
    await f.answer(first, (await f.list(first))[0]);
    await first.start(f.port(first));
    const [right] = await f.list(first);
    await f.answer(first, right);
    await f.close(first);
    const changed = source('left');
    if (change === 'configuration') changed.accountConfiguration =
      configuration('left-account', 'deny', 'read');
    else changed.context = {...changed.context, contextCid: cid('8')};
    const second = await f.open({sources: [changed, source('right')]});
    const physical = f.port(second);
    await second.start(physical);
    assert.equal(physical.state.starts, 0);
    assert.equal(second.heldLookup(captured.requestId).endReason, 'revalidation_failed');
  });
});

test('cancelling after the first source approval starts neither source', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  const captured = submission();
  await submit(checkpoints, captured);
  await f.answer(checkpoints, (await f.list(checkpoints))[0]);
  const physical = f.port(checkpoints);
  await checkpoints.start(physical);
  const [right] = await f.list(checkpoints);
  checkpoints.cancelHeld(captured.requestId);
  await checkpoints.sweep();
  assert.equal(physical.state.starts, 0);
  assert.equal(checkpoints.heldLookup(captured.requestId).state, 'ended');
  assert.equal(checkpoints.journal.inspect(right.checkpointCid).closure, 'cancelled');
});

test('immediate permits are account-specific and exact-occurrence-only', async t => {
  const decisions = [];
  const f = await fixture(t, {authorization: {
    decide: view => { decisions.push(view); return {decision: 'permit',
      subject: view.subject, authority: 'host-policy'}; },
    answeringAuthorities: ['host-policy'],
  }});
  const checkpoints = await f.open();
  const captured = submission();
  assert.equal((await submit(checkpoints, captured)).kind, 'dispatch');
  assert.deepEqual(decisions.map(view => view.subject.account_id),
    ['left-account', 'right-account']);
  assert.deepEqual(decisions.map(view => view.subject.context_cid),
    [source('left').context.contextCid, source('right').context.contextCid]);
  const base = await baseAccess(source('left'));
  t.after(() => base.authorization.close());
  const occurrence = captured.acquisitions[0];
  const access = checkpoints.acquisitionAccess(captured.requestId, base, occurrence);
  assert.equal((await access.authorization.authorize('acquisition', occurrence.readTuple)).action, 'dispatch');
  assert.equal(checkpoints.acquisitionAccess(captured.requestId, base,
    {...occurrence, task: 1}), base);
  assert.equal(checkpoints.acquisitionAccess(captured.requestId, base,
    {...occurrence, physicalBinding: {...occurrence.physicalBinding, table: 'other'}}), base);
  checkpoints.releaseAcquisition(captured.requestId);
  assert.equal(checkpoints.acquisitionAccess(captured.requestId, base, occurrence), base);
});

test('a later deny discards an earlier permit before any physical start', async t => {
  const f = await fixture(t, {sources: [source('left'), source('right', 'deny')],
    authorization: {decide: view => ({decision: 'permit', subject: view.subject,
      authority: 'host-policy'}), answeringAuthorities: ['host-policy']}});
  const checkpoints = await f.open();
  const captured = submission();
  await assert.rejects(submit(checkpoints, captured), {code: 'ACTQL_E_ACCOUNT_DENIED'});
  assert.deepEqual(await f.list(checkpoints), []);
  const base = await baseAccess(source('left'));
  t.after(() => base.authorization.close());
  assert.equal(checkpoints.acquisitionAccess(captured.requestId, base,
    captured.acquisitions[0]), base);
});

test('singular capture and acquisition intent retain the original shape', async t => {
  const f = await fixture(t, {single: source('left')});
  const checkpoints = await f.open();
  const {acquisitions, ...common} = submission();
  const {stage, input, task, ...acquisition} = acquisitions[0];
  const captured = {...common, version: 'actql-remote-captured-submission/0.1', acquisition};
  assert.equal((await submit(checkpoints, captured)).kind, 'held');
  const [summary] = await f.list(checkpoints);
  assert.equal(summary.checkpointId,
    `${checkpoints.prepareAttemptIdOf(captured.requestId)}-acquisition`);
  const stored = await f.capturedEvidence(checkpoints, summary);
  assert.deepEqual(stored.captured, captured);
  // Independently pinned from the singular 0.1 preimages, not product output.
  assert.equal(contentCid(stored.captured),
    'sha256:d50df1643e212ebbd9e54caebbf096b7da6a5cc449d9f181ebb314bdac425cee');
  assert.deepEqual(stored.intent, {
    version: 'actql-remote-acquisition-intent/0.1',
    request_cid: stored.intent.request_cid,
    captured_submission_cid: contentCid(captured),
    checked_source: acquisition.checkedSource,
    read_tuple: acquisition.readTuple,
    physical_binding: acquisition.physicalBinding,
  });
  assert.equal(summary.requiredArtifact.cid,
    'sha256:da3f92f1adbccf1462b3bdd8009887ac1f191653afc7e2caacd3efbbdd5a45ca');
  assert.equal((await f.review(checkpoints, summary)).displayed_scope.occurrence, undefined);
  await f.answer(checkpoints, summary);
  const base = await baseAccess(source('left'));
  t.after(() => base.authorization.close());
  const physical = f.port(checkpoints, {atStart: async () => {
    const access = checkpoints.acquisitionAccess(captured.requestId, base);
    assert.equal((await access.authorization.authorize('acquisition', acquisition.readTuple)).action, 'dispatch');
  }});
  await checkpoints.start(physical);
  assert.equal(physical.state.starts, 1, JSON.stringify(f.diagnostics));
});

test('plural capture requires its tag and exact bounded occurrence inventory', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  for (const change of [
    value => { value.version = 'actql-remote-captured-submission/0.1'; },
    value => { value.acquisition = value.acquisitions[0]; },
    value => { value.acquisitions.reverse(); },
    value => { value.acquisitions.pop(); },
    value => { value.acquisitions[1].task = 0; },
    value => { value.acquisitions[1].checkedSource.sourceRef = 'connector://other/r#v'; },
  ]) {
    const captured = submission();
    change(captured);
    await assert.rejects(submit(checkpoints, captured), {code: 'HeldAcquisitionChanged'});
  }
  assert.deepEqual(await f.list(checkpoints), []);
});

test('same public request cannot reuse a held approval with a changed private inventory', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  const captured = submission();
  assert.equal((await submit(checkpoints, captured)).kind, 'held');
  assert.equal((await submit(checkpoints, structuredClone(captured))).kind, 'held');
  const reencoded = {...structuredClone(captured),
    input: {stages: [{equivalentRepresentation: true}]}};
  // The upstream checked request identity already established equivalence;
  // raw transport differences cannot replace the held execution capture.
  assert.equal((await submit(checkpoints, reencoded)).kind, 'held');
  const [summary] = await f.list(checkpoints);
  assert.deepEqual((await f.capturedEvidence(checkpoints, summary)).captured,
    captured);
  const changed = structuredClone(captured);
  changed.acquisitions[1].physicalBinding.table = 'replacement';
  await assert.rejects(submit(checkpoints, changed), {code: 'HeldAcquisitionChanged'});
  assert.equal((await f.list(checkpoints)).length, 1);
});

test('a process-local permit before a later hold is re-decided after restart', async t => {
  let leftDecision = 'permit';
  const accounts = [];
  const f = await fixture(t, {authorization: {
    decide: view => {
      accounts.push(view.subject.account_id);
      return {decision: view.subject.account_id === 'left-account'
        ? leftDecision : 'defer', subject: view.subject, authority: 'host-policy'};
    }, answeringAuthorities: ['host-policy'],
  }});
  const captured = submission();
  const first = await f.open();
  await submit(first, captured);
  const [right] = await f.list(first);
  assert.equal((await f.review(first, right)).displayed_scope.occurrence.task, 1);
  await f.answer(first, right);
  await f.close(first);
  leftDecision = 'reject';
  const second = await f.open();
  const physical = f.port(second);
  await second.start(physical);
  assert.equal(physical.state.starts, 0);
  assert.equal(physical.state.abandoned, 1, JSON.stringify(f.diagnostics));
  assert.deepEqual(accounts, ['left-account', 'right-account', 'left-account']);
});

test('a previously reserved physical start is reconciled without reauthorization', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  await submit(checkpoints, submission());
  await f.answer(checkpoints, (await f.list(checkpoints))[0]);
  const physical = f.port(checkpoints);
  // The real Host returns this conservative state from its existing durable
  // acquisition/start owner after a crash. The Checkpoint owner never retries.
  physical.inspect = async () => ({state: 'started', runId: 'run-already-reserved'});
  await checkpoints.start(physical);
  assert.equal(physical.state.starts, 0);
  assert.deepEqual(await f.list(checkpoints), []);
  assert.equal(checkpoints.journal.getRunState('run-already-reserved').status, 'running');
});

test('a singular request under plural installation selects only its exact source account', async t => {
  const f = await fixture(t, {sources: [source('left', 'deny'), source('right')]});
  const checkpoints = await f.open();
  const {acquisitions, ...common} = submission();
  const {stage, input, task, ...acquisition} = acquisitions[1];
  const captured = {...common, version: 'actql-remote-captured-submission/0.1', acquisition};
  assert.equal((await submit(checkpoints, captured)).kind, 'held');
  const [summary] = await f.list(checkpoints);
  assert.equal((await f.review(checkpoints, summary)).execution_context_cid,
    source('right').context.contextCid);
  assert.equal((await f.capturedEvidence(checkpoints, summary)).intent.version,
    'actql-remote-acquisition-intent/0.1');
  await f.answer(checkpoints, summary);
  const physical = f.port(checkpoints);
  await checkpoints.start(physical);
  assert.equal(physical.state.starts, 1, JSON.stringify(f.diagnostics));
});

test('plural captures cannot borrow singular installed authorization', async t => {
  const f = await fixture(t, {single: source('left')});
  const checkpoints = await f.open();
  await assert.rejects(submit(checkpoints, submission()), {code: 'HeldAcquisitionChanged'});
  assert.deepEqual(await f.list(checkpoints), []);
});

test('singular installation binds two distinct occurrences of its own view', async t => {
  const f = await fixture(t, {runOutcome: 'allow',
    single: source('left', 'allow')});
  const checkpoints = await f.open();
  const captured = submission();
  captured.acquisitions[1].checkedSource.sourceRef = source('left').sourceRef;
  assert.notEqual(captured.acquisitions[0].checkedSource.requirementCid,
    captured.acquisitions[1].checkedSource.requirementCid);
  assert.equal((await submit(checkpoints, captured)).kind, 'dispatch');
  const foreign = structuredClone(captured);
  foreign.acquisitions[1].checkedSource.sourceRef = source('right').sourceRef;
  await assert.rejects(submit(checkpoints, foreign),
    {code: 'HeldAcquisitionChanged'});
  assert.deepEqual(await f.list(checkpoints), []);
});


for (const [observed, terminal] of [
  ['preparing', false], ['running', false], ['waiting_checkpoint', false],
  ['resuming', false], ['needs_reconciliation', false], ['succeeded', true],
  ['failed', true], ['cancelled', true], ['unknown', false], ['', false],
  ['Succeeded', false], [undefined, false], [null, false],
]) {
  test(`recovery classifies observed outcome ${JSON.stringify(observed)} through Core`,
    async t => {
      const f = await fixture(t, {runOutcome: 'delegate', sources: [
        source('left', 'allow'), source('right', 'allow')]});
      const checkpoints = await f.open();
      const captured = submission();
      assert.equal((await submit(checkpoints, captured)).kind, 'held');
      const physical = f.port(checkpoints);
      await checkpoints.start(physical);
      const [summary] = await f.list(checkpoints);
      await f.answer(checkpoints, summary);
      await checkpoints.sweep();
      assert.equal(physical.state.starts, 1, JSON.stringify(f.diagnostics));
      assert.equal(checkpoints.journal.getRunState('run-pair').status, 'running');
      physical.observe = async () => observed;
      await checkpoints.sweep();
      assert.equal(checkpoints.journal.getRunState('run-pair').status,
        terminal && observed !== 'cancelled' ? observed : 'running',
        JSON.stringify(f.diagnostics));
      if (observed === 'cancelled') {
        // Terminality does not expand the existing transition table:
        // Running -> Cancelled is rejected independently by the journal.
        assert.equal(f.diagnostics.at(-1).detail.code, 'RunTransitionRejected');
      }
      assert.equal(physical.state.starts, 1);
      if (terminal && observed !== 'cancelled') {
        // A late completion cannot rewrite a terminal outcome or restart it.
        checkpoints.runFinished('run-pair', 'failed');
        assert.equal(checkpoints.journal.getRunState('run-pair').status, observed);
      }
    });
}
