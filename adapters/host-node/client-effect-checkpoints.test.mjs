// Installed Checkpoint service with its real MoonBit gate, SQLite journal,
// encrypted evidence Store and public Client signature format. Full Program
// capture/apply/publication acceptance is a separate installed-Host test.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import './effect-authorization-options.test.mjs';
import './client-effect-target-checkpoints.test.mjs';
import './client-two-source-checkpoints.test.mjs';
import './effect-target-read-continuation.test.mjs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {authorizationDispatchFacts} from
  '../host-common/authorization-gate.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const reviewer = generateKeyPairSync('ed25519');
const host = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const scope = {connection: 'reference', resource: 'records'};
const configuration = read => canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: 'local',
  entries: [
    {entry_id: 'read', outcome: read, principal: {all: true},
      connection: {any_of: ['reference']}, resource: {any_of: ['records']},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'write', outcome: 'delegate', principal: {all: true},
      connection: {any_of: ['reference']}, resource: {any_of: ['records']},
      operation: {any_of: ['effect']}, exclusions: []},
  ],
});

async function fixture(t, {read = 'allow', effectRequiredClaims = [],
  accountConfiguration = configuration(read), leaseMs = 60_000, source} = {}) {
  const scratch = new URL('../../_build/client-effect-checkpoints/',
    import.meta.url);
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch.pathname, 'host-'));
  const opened = new Set();
  let clock = Date.parse('2026-09-27T00:00:00.000Z');
  const open = async () => {
    const installed = await installRemoteCheckpoints({root, namespaceId: 'local',
      authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
      realizationKey: 'source-free-values', environmentCid: cid('4'), source,
      contractControl: runtimeCore(moon).publicationControl, now: () => clock,
      authorization: {accountConfiguration, leaseMs,
        effectRequiredClaims, resumeAfterAnswer: false,
        reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
          principalId: 'reviewer', publicKey: pem(reviewer.publicKey)}],
        reviewReaders: ['reviewer'],
        hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}}});
    opened.add(installed);
    return installed;
  };
  const close = async installed => {
    await installed.close();
    opened.delete(installed);
  };
  t.after(async () => {
    for (const installed of opened) await close(installed);
    await rm(root, {recursive: true, force: true});
  });
  return {open, close, clock, advance(ms) { clock += ms; }};
}

test('a stale terminal preparation claim retains settlement responsibility',
  async t => {
    const {open, clock, advance} = await fixture(t, {leaseMs: 1000,
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'local',
        entries: [{entry_id: 'accept', outcome: 'delegate',
          principal: {all: true}, connection: {any_of: ['local']},
          resource: {any_of: ['source-free-values']},
          operation: {any_of: ['write']}, exclusions: []}],
      })});
    const installed = await open();
    let inspections = 0;
    let executions = 0;
    let reobserved;
    const nextObservation = new Promise(resolve => { reobserved = resolve; });
    await installed.start({
      async inspect() {
        inspections++;
        if (inspections === 1) advance(1001);
        else reobserved();
        return {state: 'cancelled', runId: 'cancelled-run'};
      },
      async resume() { executions++; throw new Error('MustNotExecute'); },
      async abandon() { throw new Error('MustNotAbandon'); },
    });
    const accepted = await installed.acceptRun({
      requested: {logicalRequestScopeCid: cid('5'),
        intentFingerprintCid: cid('6')},
      captured: {requestId: 'cancelled-request', kind: 'aql',
        input: {format: 'json', text: '{}'}, parameters: {},
        resultNames: ['answer'], principalId: 'owner'},
    });
    assert.equal(accepted.kind, 'held');
    const summary = (await installed.listCheckpoints({
      principalId: 'reviewer', after: '', limit: 10})).items[0];
    const answer = await signedAnswer(summary, 'approved', {
      keyId: 'reviewer-key', reviewerId: 'reviewer',
      authorityScopeCid: cid('3'),
      sign: bytes => sign(null, bytes, reviewer.privateKey),
    }, new Date(clock).toISOString());
    const resolved = await installed.resolve({principalId: 'reviewer',
      items: [answer]});
    assert.equal(resolved.results[0].status, 'committed');
    await installed.sweep();
    assert.equal(inspections, 1);
    assert.equal(installed.journal.getPreparation(
      summary.subject.prepareAttemptId).status, 'resuming');
    // No explicit wake: the failed completion must retain its own retry.
    // This deadline bounds the test; it is not a lease or a retry policy.
    let timeout;
    try {
      await Promise.race([nextObservation, new Promise((_, reject) => {
        timeout = setTimeout(() => reject(
          new Error('TerminalSettlementRetryMissing')), 5000);
      })]);
    } finally { clearTimeout(timeout); }
    // Join the active owned sweep before checking durable completion.
    await installed.sweep();
    assert.equal(inspections, 2);
    const ended = installed.journal.getPreparation(
      summary.subject.prepareAttemptId);
    assert.equal(ended.status, 'ended');
    assert.equal(ended.endReason, 'cancelled');
    assert.equal(executions, 0);
  });

const continuation = beforeDefer => ({runId: 'run-a',
  runDefinitionCid: cid('1'), unitId: 'unit-a', declaredResults: ['answer'],
  reviewWire: canonicalJson({message: 'Review the whole Effect Set'}),
  continuationWire: canonicalJson({requestId: 'request-a'}), beforeDefer});

test('an acquired Effect Source wait retains its capture and resumes only the exact read',
  async t => {
    const source = {accountConfiguration: configuration('delegate'),
      context: {principal: 'owner', contextCid: cid('7')}};
    const {open, close, clock} = await fixture(t, {source});
    let installed = await open();
    let sourceCalls = 0;
    let retained = 0;
    const captureWire = '{"source":"first","rows":[["é",17],["é",-4]]}';
    let captureCid;
    const occurrence = {stage: 1, input: 0, task: 1,
      checkedSource: {sourceRef: 'second', requirementCid: cid('8')},
      readTuple: {...scope, operation: 'read'},
      physicalBinding: {database: 'reference-db', schema: 'public', table: 'second'}};
    const options = () => ({runId: 'run-source', runDefinitionCid: cid('1'),
      unitId: 'source-unit-1', occurrence, declaredResults: ['answer'],
      async beforeDefer() {
        retained++;
        captureCid = await installed.retainComputationSource('run-source', cid('1'), captureWire);
      },
      continuation: async () => JSON.stringify({requestId: 'request-source',
        occurrence: 1, captures: [captureCid]})});
    let gate = await installed.computationSourceAuthorization(options());
    const waiting = await gate.authorize();
    assert.equal(waiting.action, 'waiting', JSON.stringify(waiting));
    assert.equal(retained, 1);
    assert.equal(sourceCalls, 0);
    gate.close();
    const summary = (await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10})).items[0];
    assert.equal(summary.kind, 'read_access');
    assert.equal(summary.subject.runId, 'run-source');
    const review = await installed.reviewCheckpoint({principalId: 'reviewer',
      checkpointCid: summary.checkpointCid, maxBytes: 65536});
    const reviewed = JSON.parse(Buffer.from(review.contentBase64, 'base64'));
    assert.deepEqual(reviewed.scope.occurrence, occurrence);
    assert.equal(reviewed.scope.run_definition_cid, cid('1'));
    const answer = await signedAnswer(summary, 'approved', {
      keyId: 'reviewer-key', reviewerId: 'reviewer', authorityScopeCid: cid('3'),
      sign: bytes => sign(null, bytes, reviewer.privateKey)}, new Date(clock).toISOString());
    const resolution = await installed.resolve({principalId: 'reviewer', items: [answer]});
    assert.equal(resolution.results[0].status, 'committed', JSON.stringify(resolution));
    await close(installed);
    installed = await open();
    const view = installed.journal.inspect(summary.checkpointCid);
    assert.deepEqual(await installed.computationContinuation(view),
      {requestId: 'request-source', occurrence: 1, captures: [captureCid]});
    assert.equal((await installed.readComputationSource(view, captureCid, 65536))
      .toString('utf8'), captureWire);
    const claimed = installed.journal.claimResume('run-source', {
      claimant: 'source-resumer', leaseMs: 60000, binding: installed.binding});
    assert.equal(claimed.action, 'claimed');
    const resumption = {claim: {checkpointCid: summary.checkpointCid, claim: claimed.claim}};
    gate = await installed.computationSourceAuthorization(options());
    const resumed = await gate.resume({resumption});
    assert.equal(resumed.action, 'dispatch', JSON.stringify(resumed));
    const mismatched = await installed.computationSourceAuthorization({
      ...options(), occurrence: {...occurrence, physicalBinding: {
        ...occurrence.physicalBinding, table: 'other'}}});
    assert.notEqual((await mismatched.resume({resumption})).action, 'dispatch');
    mismatched.close();
    const effect = await installed.effectAuthorization(continuation(async () => {}));
    assert.notEqual((await effect.resume('effect_commit', {...scope, operation: 'effect'},
      {subjectCid: cid('2'), resumption})).action, 'dispatch');
    effect.close();
    resumed.admission.enter();
    sourceCalls++;
    assert.throws(() => resumed.admission.enter(), {code: 'ResumeAdmissionConsumed'});
    assert.equal(sourceCalls, 1);
    assert.equal(retained, 1, 'approval does not recreate the retained capture');
    gate.close();
  });

const readOccurrence = () => ({stage: 0, input: 0, task: 0,
  checkedSource: {sourceRef: 'first', requirementCid: cid('8')},
  readTuple: {...scope, operation: 'read'},
  physicalBinding: {database: 'reference-db', schema: 'public', table: 'first'}});
const sourceOptions = (occurrence = readOccurrence()) => ({runId: 'source-scope',
  runDefinitionCid: cid('1'), unitId: 'source-unit', occurrence,
  declaredResults: ['answer'], beforeDefer: async () => {},
  continuation: async () => '{"requestId":"original"}'});
const delegatedSource = () => ({accountConfiguration: configuration('delegate'),
  context: {principal: 'owner', contextCid: cid('7')}});

test('Source review owns its occurrence and refuses changed installation context', async t => {
  const source = delegatedSource();
  const {open} = await fixture(t, {source});
  const installed = await open();
  const occurrence = readOccurrence();
  const original = structuredClone(occurrence);
  const gate = await installed.computationSourceAuthorization(sourceOptions(occurrence));
  occurrence.physicalBinding.table = 'changed-after-creation';
  occurrence.readTuple.resource = 'other';
  const waiting = await gate.authorize();
  assert.equal(waiting.action, 'waiting');
  const review = await installed.reviewCheckpoint({principalId: 'reviewer',
    checkpointCid: waiting.checkpoint.checkpointCid, maxBytes: 65536});
  assert.deepEqual(JSON.parse(Buffer.from(review.contentBase64, 'base64')).scope.occurrence,
    original);
  gate.close();
  source.context = {...source.context, contextCid: cid('9')};
  await assert.rejects(installed.computationSourceAuthorization(sourceOptions()),
    {code: 'SourceCheckpointConfigurationChanged'});
});

for (const exit of ['rejected', 'cancelled', 'expired']) {
  test(`Source ${exit} wait creates no resumable read`, async t => {
    const {open, clock, advance} = await fixture(t, {source: delegatedSource()});
    const installed = await open();
    const gate = await installed.computationSourceAuthorization(sourceOptions());
    const waiting = await gate.authorize();
    assert.equal(waiting.action, 'waiting');
    const [summary] = (await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10})).items;
    if (exit === 'rejected') {
      const answer = await signedAnswer(summary, 'rejected', {
        keyId: 'reviewer-key', reviewerId: 'reviewer',
        sign: bytes => sign(null, bytes, reviewer.privateKey)}, new Date(clock).toISOString());
      assert.equal((await installed.resolve({principalId: 'reviewer', items: [answer]}))
        .results[0].status, 'committed');
    } else if (exit === 'cancelled') {
      assert.equal(installed.journal.cancelCheckpoint(summary.checkpointCid).outcome, 'cancelled');
    } else {
      advance(24 * 60 * 60 * 1000 + 1);
      installed.journal.expire();
    }
    assert.equal(installed.journal.getRunState('source-scope').status, 'cancelled');
    assert.equal(installed.journal.currentResume(summary.checkpointCid), undefined);
    gate.close();
  });
}

test('revoked Source configuration invalidates durable approval before dispatch', async t => {
  const source = delegatedSource();
  const {open, close, clock} = await fixture(t, {source});
  let installed = await open();
  const gate = await installed.computationSourceAuthorization(sourceOptions());
  await gate.authorize(); gate.close();
  const [summary] = (await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10})).items;
  const answer = await signedAnswer(summary, 'approved', {keyId: 'reviewer-key',
    reviewerId: 'reviewer', sign: bytes => sign(null, bytes, reviewer.privateKey)},
  new Date(clock).toISOString());
  assert.equal((await installed.resolve({principalId: 'reviewer', items: [answer]})).results[0].status,
    'committed');
  await close(installed);
  source.accountConfiguration = configuration('deny');
  installed = await open();
  const claimed = installed.journal.claimResume('source-scope', {
    claimant: 'revoked', leaseMs: 60000, binding: installed.binding});
  assert.equal(claimed.action, 'invalidated');
  assert.equal(installed.journal.getRunState('source-scope').status, 'failed');
  assert.equal(claimed.terminalErrorCode, 'ACTQL_E_RESUME_REVALIDATION_FAILED');
});

test('failed Source continuation persistence retires only after confirmed custody close', async t => {
  const {open} = await fixture(t, {source: delegatedSource()});
  const installed = await open();
  let captureCid;
  const gate = await installed.computationSourceAuthorization({...sourceOptions(),
    beforeDefer: async () => {
      captureCid = await installed.retainComputationSource('source-scope', cid('1'),
        '{"fixture":"original captured rows"}');
    }, continuation: async () => { throw new Error('ContinuationWriteUnavailable'); }});
  assert.equal((await gate.authorize()).action, 'failure');
  const view = {kind: 'read_access', prepareAttemptId: null, runId: 'source-scope',
    runDefinitionCid: cid('1')};
  assert.ok((await installed.readComputationSource(view, captureCid, 4096)).length > 0);
  assert.equal(installed.journal.getRunState('source-scope'), undefined);
  // The physical acquisition owner invokes retirement only after its actual
  // close; failure to create a Checkpoint is not itself that confirmation.
  await installed.retireComputationSources('source-scope');
  await assert.rejects(installed.readComputationSource(view, captureCid, 4096),
    {code: 'ContinuationEvidenceRetired'});
  gate.close();
});

async function approveSource(installed, clock) {
  const gate = await installed.computationSourceAuthorization(sourceOptions());
  await gate.authorize(); gate.close();
  const [summary] = (await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10})).items;
  const answer = await signedAnswer(summary, 'approved', {keyId: 'reviewer-key',
    reviewerId: 'reviewer', sign: bytes => sign(null, bytes, reviewer.privateKey)},
  new Date(clock).toISOString());
  assert.equal((await installed.resolve({principalId: 'reviewer', items: [answer]})).results[0].status,
    'committed');
  return summary;
}

test('entered Source intents stay unresolved before changed-binding claim invalidation', async t => {
  const {open, clock, advance} = await fixture(t, {source: delegatedSource(), leaseMs: 1000});
  const installed = await open();
  const summary = await approveSource(installed, clock);
  assert.equal(installed.journal.hasStartedResume(summary.checkpointCid), false);
  assert.equal(installed.journal.claimResume('source-scope', {claimant: 'wrong-page',
    leaseMs: 1000, binding: installed.binding, preserveStarted: true,
    expectedCheckpointCid: cid('9')}).action, 'changed');
  const claimed = installed.journal.claimResume('source-scope', {claimant: 'first',
    leaseMs: 1000, binding: installed.binding, preserveStarted: true,
    expectedCheckpointCid: summary.checkpointCid});
  const gate = await installed.computationSourceAuthorization(sourceOptions());
  const decision = await gate.resume({resumption: {claim: {
    checkpointCid: summary.checkpointCid, claim: claimed.claim}}});
  decision.admission.enter();
  gate.close();
  assert.equal(installed.hasUnresolvedSourceStart('source-scope', cid('1')), true);
  advance(1001);
  const second = installed.journal.claimResume('source-scope', {claimant: 'second',
    leaseMs: 1000, preserveStarted: true, expectedCheckpointCid: summary.checkpointCid,
    binding: {...installed.binding, environmentBindingCid: cid('a')}});
  assert.equal(second.action, 'admitted');
  assert.equal(second.claim, undefined);
  assert.equal(installed.journal.getRunState('source-scope').status, 'resuming');
  assert.equal(installed.journal.currentResume(summary.checkpointCid).generation, claimed.claim.generation);
});

test('a stale Source failure cannot refuse the newer unstarted claimant', async t => {
  const {open, clock, advance} = await fixture(t, {source: delegatedSource(), leaseMs: 1000});
  const installed = await open();
  const summary = await approveSource(installed, clock);
  const first = installed.journal.claimResume('source-scope', {claimant: 'first',
    leaseMs: 1000, binding: installed.binding, preserveStarted: true});
  advance(1001);
  const second = installed.journal.claimResume('source-scope', {claimant: 'second',
    leaseMs: 1000, binding: installed.binding, preserveStarted: true});
  assert.equal(second.action, 'claimed');
  assert.throws(() => installed.journal.refuseUnsentSourceResume(summary.checkpointCid,
    cid('1'), first.claim), {code: 'ResumeClaimStale'});
  assert.equal(installed.journal.getRunState('source-scope').status, 'resuming');
  assert.equal(installed.journal.currentResume(summary.checkpointCid).generation,
    second.claim.generation);
  assert.equal(installed.journal.refuseUnsentSourceResume(summary.checkpointCid,
    cid('1'), second.claim).outcome, 'failed');
});

test('exact committed publication settles a lost Source resume completion without dispatch', async t => {
  const {open, clock, advance} = await fixture(t, {source: delegatedSource(), leaseMs: 1000});
  const installed = await open();
  const summary = await approveSource(installed, clock);
  const claimed = installed.journal.claimResume('source-scope', {claimant: 'first',
    leaseMs: 1000, binding: installed.binding, preserveStarted: true});
  const gate = await installed.computationSourceAuthorization(sourceOptions());
  const decision = await gate.resume({resumption: {claim: {
    checkpointCid: summary.checkpointCid, claim: claimed.claim}}});
  decision.admission.enter(); gate.close();
  advance(1001);
  // This port is called by the Host only after the exact Publication Store
  // index and its admitted state have been read. Availability remains the
  // Store's separate observation; the journal never invents available rows.
  const observed = {...installed.journal.getRunState('source-scope').runState, status: 'succeeded'};
  assert.throws(() => installed.journal.settleObservedEffectResume(summary.checkpointCid,
    cid('1'), JSON.stringify({...observed, status: 'failed'})), {code: 'InvalidRunState'});
  assert.throws(() => installed.journal.settleObservedEffectResume(summary.checkpointCid,
    cid('9'), JSON.stringify(observed)), {code: 'CheckpointRunMismatch'});
  assert.equal(installed.journal.settleObservedEffectResume(summary.checkpointCid,
    cid('1'), JSON.stringify(observed)).outcome, 'succeeded');
  assert.equal(installed.journal.hasStartedResume(summary.checkpointCid), false);
  assert.equal(installed.journal.getRunState('source-scope').status, 'succeeded');
  assert.equal(installed.journal.settleObservedEffectResume(summary.checkpointCid,
    cid('1'), JSON.stringify(observed)).outcome, 'not_resuming');
});

test('Effect review and signed answer survive installed service restart',
  async t => {
    const {open, close, clock} = await fixture(t);
    let installed = await open();
    let retained = 0;
    const gate = await installed.effectAuthorization(continuation(async () => {
      retained++;
    }));
    const waiting = await gate.authorize('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2')});
    assert.equal(waiting.action, 'waiting', JSON.stringify(waiting));
    // Only a dispatch carries its deciding gate's facts.
    assert.equal(authorizationDispatchFacts(waiting), undefined);
    assert.equal(retained, 1);
    const page = await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10});
    const summary = page.items[0];
    assert.equal(summary.subject.runId, 'run-a');
    assert.deepEqual(summary.requirements, ['effect_scope_approved']);
    assert.equal(installed.effectRunState('run-a', cid('1')).status,
      'waiting_checkpoint');
    assert.throws(() => installed.effectRunState('run-a', cid('9')),
      {code: 'EffectContinuationRunMismatch'});
    assert.equal(installed.effectRunState('other-run', cid('1')),
      undefined);
    await close(installed);
    installed = await open();
    const view = installed.journal.listRunCheckpoints()[0];
    assert.equal(view.checkpointCid, summary.checkpointCid);
    assert.deepEqual(await installed.effectContinuation(view),
      {requestId: 'request-a'});
    const review = await installed.reviewCheckpoint({principalId: 'reviewer',
      checkpointCid: summary.checkpointCid, maxBytes: 4096});
    assert.deepEqual(JSON.parse(Buffer.from(review.contentBase64, 'base64')),
      {message: 'Review the whole Effect Set'});
    const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
      authorityScopeCid: cid('3'),
      sign: bytes => sign(null, bytes, reviewer.privateKey)};
    const foreignScope = await signedAnswer(summary, 'approved',
      {...signer, authorityScopeCid: cid('9')},
      new Date(clock).toISOString());
    const refused = await installed.resolve({principalId: 'reviewer',
      items: [foreignScope]});
    assert.notEqual(refused.results[0].status, 'committed');
    assert.equal(installed.journal.getRunState('run-a').status,
      'waiting_checkpoint');
    const answer = await signedAnswer(summary, 'approved', signer,
      new Date(clock).toISOString());
    const resolved = await installed.resolve({principalId: 'reviewer',
      items: [answer]});
    assert.equal(resolved.results[0].status, 'committed',
      JSON.stringify(resolved));
    assert.equal(installed.effectRunState('run-a', cid('1')).status,
      'resuming');
    const duplicate = await installed.resolve({principalId: 'reviewer',
      items: [answer]});
    assert.equal(duplicate.results[0].status, 'duplicate');
    assert.equal(installed.journal.listRunCheckpoints().length, 1);
    const resumedGate = await installed.effectAuthorization(
      continuation(async () => { throw new Error('ResumeMustNotRecapture'); }));
    const claim = installed.journal.claimResume('run-a', {
      claimant: 'host-after-restart', leaseMs: 60_000,
      binding: installed.binding});
    const resumed = await resumedGate.resume('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2'),
        resumption: {claim}});
    assert.equal(resumed.action, 'dispatch', JSON.stringify(resumed));
    assert.equal(typeof resumed.admission?.enter, 'function');
    // The resumed commit dispatch carries its gate's principal and admitted
    // account configuration for an installed Site; a copy carries nothing.
    const facts = authorizationDispatchFacts(resumed);
    assert.equal(facts.principal, 'owner');
    assert.match(facts.configurationCid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(authorizationDispatchFacts({...resumed}), undefined);
    const foreign = await resumedGate.resume('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('9'),
        resumption: {claim}});
    assert.notEqual(foreign.action, 'dispatch');
    assert.equal(authorizationDispatchFacts(foreign), undefined);
    assert.equal(retained, 1);
    gate.close();
    resumedGate.close();
    await assert.rejects(gate.authorize('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2')}),
    {code: 'AuthorizationDecisionScopeClosed'});
  });

test('only explicit Host policy requests partial-application acceptance',
  async t => {
    const {open} = await fixture(t, {
      effectRequiredClaims: ['partial_application_accepted']});
    const installed = await open();
    const gate = await installed.effectAuthorization(continuation(async () => {}));
    const waiting = await gate.authorize('effect_commit',
      {...scope, operation: 'effect'}, {subjectCid: cid('2')});
    assert.equal(waiting.action, 'waiting');
    const page = await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10});
    assert.deepEqual(page.items[0].requirements,
      ['effect_scope_approved', 'partial_application_accepted']);
    gate.close();
  });

test('deferred target read is unsupported, not denied or checkpointed',
  async t => {
    const {open} = await fixture(t, {read: 'delegate'});
    const installed = await open();
    let retained = 0;
    const gate = await installed.effectAuthorization(continuation(async () => {
      retained++;
    }));
    const decision = await gate.authorize('acquisition',
      {...scope, operation: 'read'}, {subjectCid: cid('2')});
    assert.equal(decision.action, 'unsupported');
    assert.equal(authorizationDispatchFacts(decision), undefined);
    assert.equal(retained, 0);
    assert.deepEqual(installed.journal.listRunCheckpoints(), []);
    assert.deepEqual(installed.journal.listPending(), []);
    gate.close();
  });
