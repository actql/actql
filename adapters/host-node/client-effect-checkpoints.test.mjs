// Installed Checkpoint service with its real MoonBit gate, SQLite journal,
// encrypted evidence Store and public Client signature format. Full Program
// capture/apply/publication acceptance is a separate installed-Host test.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {readFileSync} from 'node:fs';
import fsPromises from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {compileFunction} from 'node:vm';
import {parseExpressionAt} from 'acorn';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import './effect-authorization-options.test.mjs';
import './client-effect-target-checkpoints.test.mjs';
import './client-two-source-checkpoints.test.mjs';
import './effect-target-read-continuation.test.mjs';
import './acquired-effect-source-authorization.test.mjs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {checkpointEffectReviewDouble} from './fixtures/checkpoint-effect-review.fixture.mjs';
import {authorizationDispatchFacts} from
  '../host-common/authorization-gate.mjs';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

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
  let preserved = false;
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
    if (!preserved) await rm(root, {recursive: true, force: true});
    else t.diagnostic('Retained failed Checkpoint fixture: ' + root);
  });
  return {open, close, clock, root, preserve() {preserved = true;}, advance(ms) { clock += ms; }};
}

test('Host first close joins the original pre-dispatch Effect resume Store reader', async t => {
  // Exercise the actual Host port expression, Checkpoint stop, Store FD and
  // shutdown. The resume callback and unused dispatch/journal ports are
  // explicit fixtures; this issues no business Run, send or physical-stop ACK.
  const latch = () => {let resolve; const promise = new Promise(done => {resolve = done;}); return {promise, resolve};};
  const allowRead = latch(), readEntered = latch(), drainEntered = latch();
  const originalOpen = fsPromises.open;
  let store, readFlight, closing, originalFd;
  t.after(async () => {
    allowRead.resolve();
    fsPromises.open = originalOpen; syncBuiltinESMExports();
    await readFlight?.catch(() => {});
    await closing?.catch(() => {});
    // Fixture hygiene after an original red, never a replacement first-close
    // positive. The same real FD must finish before this Store can release.
    if (store !== undefined && !store.status().closed) await store.close();
  });
  const f = await fixture(t), installed = await f.open();
  const directory = join(f.root, 'pending-publication');
  store = await openLocalPublicationStore({directory, storeAuthorityCid: cid('a'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 65536, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64}, createPublicationContractControlFixture());
  const wire = '{"answer":{"nullable":false,"type":"string"}}';
  const identity = 'sha256:' + createHash('sha256').update(wire).digest('hex');
  await store.putSemantic(wire, identity);
  const selected = join(directory, 'contracts', identity.slice(7) + '.json');
  fsPromises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (path === selected) {
      originalFd = handle;
      const stat = handle.stat;
      handle.stat = async function(...args) {
        readEntered.resolve(); await allowRead.promise;
        return Reflect.apply(stat, this, args);
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  const flights = new Map(), values = flights.values;
  flights.values = function() {drainEntered.resolve(); return Reflect.apply(values, this, []);};
  const sweep = async () => {
    if (readFlight !== undefined) return true;
    readFlight = store.readSemanticBytes(identity, false);
    flights.set('original-resume', readFlight);
    readFlight.finally(() => flights.delete('original-resume')).catch(() => {});
    return true;
  };
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const marker = 'await checkpoints.start(', start = source.indexOf(marker) + marker.length;
  assert(start >= marker.length && source.indexOf(marker, start) < 0);
  const expression = parseExpressionAt(source, start, {ecmaVersion: 'latest', sourceType: 'module'});
  const port = compileFunction('return (' + source.slice(expression.start, expression.end) + ');',
    ['inspectHeld', 'resumeHeld', 'abandonHeld', 'observeHeldRun', 'cancelHeldRun',
      'modelController', 'sweepModelRuns', 'modelResumeFlights', 'effectRun', 'sweepEffectRuns', 'effectResumeFlights', 'effectRetirementFlights'])(
    ...Array.from({length: 5}, () => () => assert.fail('No business continuation is issued')),
    undefined, undefined, new Map(), {}, sweep, flights, new Map());
  await installed.start(port);
  await readEntered.promise;
  assert(originalFd.fd >= 0, 'the same original semantic read really owns an open FD');
  let storeCloses = 0, fdAtStoreClose;
  const shutdown = installedHostShutdown({
    checkpoints: {stop: () => installed.stop(), close: () => f.close(installed)},
    dispatchOwner: {drain() {}}, retireTerminalEffects() {}, journal: {close() {}},
    store: {close() {storeCloses++; fdAtStoreClose = originalFd.fd; return store.close();}},
  });
  closing = shutdown.close();
  const boundary = await Promise.race([drainEntered.promise.then(() => ({kind: 'joined'})),
    closing.then(() => ({kind: 'closed'}), error => ({kind: 'failed', error}))]);
  if (boundary.kind === 'failed') {
    const original = boundary.error.cleanupErrors?.find(item => item.owner === 'store')?.error;
    t.diagnostic(JSON.stringify({code: boundary.error.code,
      storeCode: original?.code, semanticReaders: original?.cleanupDiagnostic?.resources?.semanticReaders}));
    throw boundary.error;
  }
  assert.equal(boundary.kind, 'joined');
  assert.equal(storeCloses, 0, 'stop must join this original before entering Store close');
  assert(originalFd.fd >= 0);
  allowRead.resolve();
  assert.equal((await readFlight).toString(), wire);
  await closing;
  assert.equal(storeCloses, 1, 'the first Host close succeeds without a retry');
  assert.equal(fdAtStoreClose, -1, 'only the original FD close supplied the physical observation');
  assert.equal(flights.size, 0);
  assert.equal(store.status().closed, true);
});

for (const boundary of ['preparation', 'acquisition']) {
  test(`epoch-bound ${boundary} does not enter an unsupported pre-Run wait`, async t => {
    const accountConfiguration = canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'local',
      entries: [{entry_id: 'accept', outcome: boundary === 'preparation' ? 'delegate' : 'allow',
        principal: {all: true}, connection: {any_of: ['local']},
        resource: {any_of: ['source-free-values']},
        operation: {any_of: ['write']}, exclusions: []}],
    });
    const {open, close} = await fixture(t, {accountConfiguration,
      source: boundary === 'acquisition' ? {
        accountConfiguration: configuration('delegate'),
        context: {principal: 'owner', contextCid: cid('7')},
      } : undefined});
    let installed = await open();
    const captured = {requestId: 'epoch-original', kind: 'aql',
      input: {format: 'sql', text: 'SELECT 1 AS n'}, parameters: {},
      resultNames: ['answer'], principalId: 'owner',
      submission: {epoch: {version: 'actql-submission-epoch/0.1',
        authorityScopeCid: cid('3'), epochNonce: 'b'.repeat(64),
        notBefore: 1800000000000, expiresAt: 1800000001000,
        authenticator: 'a'.repeat(64)}, nonce: 'original', intentCid: cid('6'),
      currentAuthorization: true},
      ...(boundary === 'acquisition' ? {
        acquisition: {
          checkedSource: {sourceRef: 'records', requirementCid: cid('8')},
          readTuple: {...scope, operation: 'read'},
          physicalBinding: {database: 'reference-db', schema: 'public', table: 'records'},
        },
      } : {}),
    };
    const request = {requested: {logicalRequestScopeCid: cid('5'),
      intentFingerprintCid: cid('6')}, captured};
    if (boundary === 'acquisition') {
      assert.deepEqual(await installed.acceptRun(request), {kind: 'dispatch'});
    }
    await assert.rejects(boundary === 'preparation'
      ? installed.acceptRun(request) : installed.acceptAcquisition(request),
    {code: 'ACTQL_E_DELEGATION_UNAVAILABLE'});
    assert.deepEqual((await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10})).items, []);
    await close(installed);
    installed = await open();
    assert.deepEqual((await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10})).items, []);
  });
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
  projectReview: checkpointEffectReviewDouble(runtimeCore(moon).publicationControl,cid('2')),
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
    const projected=JSON.parse(Buffer.from(review.contentBase64, 'base64'));
    assert.equal(projected.version,'actql-review-projection/0.1');
    assert.equal(projected.effect_preview_cid,cid('2'));
    assert.equal(projected.review_projection_cid,review.artifactCid);
    assert.equal(projected.displayed_rows[0].before.value.Name,'Before');
    assert.equal(projected.displayed_rows[0].after.value.Name,'After');
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


// Same-stage inputs keep distinct read permissions even when they use the
// same installation, tuple and physical backing. Resume uses a new process;
// only sealed Journal/evidence and public signed answers cross that boundary.
test('same-stage Source waits have distinct bounded identities and cold original answer matching', async t => {
  const source = delegatedSource();
  const f = await fixture(t, {source});
  try {
    const installed = await f.open();
    const occurrences = [0, 1].map(input => ({...readOccurrence(), stage: 0, input, task: input, computeTask: 0}));
    const options = occurrences.map((occurrence, input) => ({...sourceOptions(occurrence),
      unitId: 'source-unit', continuation: async () => JSON.stringify({original: input})}));
    let gate = await installed.computationSourceAuthorization(options[0]);
    const first = await gate.authorize();
    assert.equal(first.action, 'waiting'); gate.close();
    const [summary] = (await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10})).items;
    const answer = await signedAnswer(summary, 'approved', {keyId: 'reviewer-key', reviewerId: 'reviewer',
      sign: bytes => sign(null, bytes, reviewer.privateKey)}, new Date(f.clock).toISOString());
    assert.equal((await installed.resolve({principalId: 'reviewer', items: [answer]})).results[0].status, 'committed');
    const firstClaim = installed.journal.claimResume('source-scope', {claimant: 'first-source', leaseMs: 60000,
      binding: installed.binding, expectedCheckpointCid: summary.checkpointCid});
    assert.equal(firstClaim.action, 'claimed');
    gate = await installed.computationSourceAuthorization(options[0]);
    const firstRead = await gate.resume({resumption: {claim: {checkpointCid: summary.checkpointCid, claim: firstClaim.claim}}});
    assert.equal(firstRead.action, 'dispatch'); firstRead.admission.enter(); gate.close();
    const nextJournal = {...installed.journal, persistCheckpoint: checkpoint =>
      installed.journal.completeResume(firstClaim.claim, {checkpoint})};
    gate = await installed.computationSourceAuthorization({...options[1], journalPort: nextJournal});
    const second = await gate.authorize();
    assert.equal(second.action, 'waiting', JSON.stringify(second)); gate.close();
    assert.notEqual(second.checkpoint.checkpointId, first.checkpoint.checkpointId);
    for (const id of [first.checkpoint.checkpointId, second.checkpoint.checkpointId]) {
      assert.match(id, /^[A-Za-z0-9._:-]{1,128}$/u);
    }
    await f.close(installed);
    const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
      import assert from 'node:assert/strict';
      import {readFileSync} from 'node:fs';
      import {sign,createPrivateKey} from 'node:crypto';
      import {installRemoteCheckpoints} from './adapters/host-node/client-checkpoints.mjs';
      import {runtimeCore} from './adapters/host-common/runtime-core.mjs';
      import {signedAnswer} from './packages/sdk/checkpoints.mjs';
      import * as moon from './_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
      const input=JSON.parse(readFileSync(0,'utf8'));
      const privateKey=createPrivateKey(input.reviewerPrivate);
      const installed=await installRemoteCheckpoints({...input.install,
        now:()=>input.clock,contractControl:runtimeCore(moon).publicationControl});
      try {
        const [summary]=(await installed.listCheckpoints({principalId:'reviewer',after:'',limit:10})).items;
        assert.equal(summary.checkpointCid,input.secondCid);
        const wrong={...input.firstAnswer,checkpointCid:summary.checkpointCid};
        assert.notEqual((await installed.resolve({principalId:'reviewer',items:[wrong]})).results[0].status,'committed');
        assert.equal(installed.journal.activeRunCheckpoint('source-scope').checkpointCid,input.secondCid);
        const view=installed.journal.inspect(input.secondCid);
        assert.deepEqual(await installed.computationContinuation(view),{original:1});
        const answer=await signedAnswer(summary,'approved',{keyId:'reviewer-key',reviewerId:'reviewer',
          sign:bytes=>sign(null,bytes,privateKey)},new Date(input.clock).toISOString());
        assert.equal((await installed.resolve({principalId:'reviewer',items:[answer]})).results[0].status,'committed');
        const claim=installed.journal.claimResume('source-scope',{claimant:'cold-second-source',leaseMs:60000,
          binding:installed.binding,expectedCheckpointCid:summary.checkpointCid});
        assert.equal(claim.action,'claimed');
        const gate=await installed.computationSourceAuthorization({...input.options,
          beforeDefer:async()=>assert.fail('cold resume must not issue another Checkpoint'),
          continuation:async()=>assert.fail('cold resume must use the original sealed continuation')});
        try {
          const read=await gate.resume({resumption:{claim:{checkpointCid:summary.checkpointCid,claim:claim.claim}}});
          assert.equal(read.action,'dispatch'); read.admission.enter();
          assert.throws(()=>read.admission.enter(),{code:'ResumeAdmissionConsumed'});
          assert.equal(installed.hasUnresolvedSourceStart('source-scope',input.options.runDefinitionCid),true);
        } finally {gate.close();}
      } finally {await installed.close();}
      console.log(JSON.stringify({coldOriginal:true,wrongAnswerRefused:true,firstClose:true}));
    `], {cwd: new URL('../../', import.meta.url), encoding: 'utf8', timeout: 30000,
      input: JSON.stringify({clock: f.clock, secondCid: second.checkpoint.checkpointCid, firstAnswer: answer,
        reviewerPrivate: pem(reviewer.privateKey), options: {...options[1], beforeDefer: undefined, continuation: undefined},
        install: {root: f.root, namespaceId: 'local', authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
          realizationKey: 'source-free-values', environmentCid: cid('4'), source,
          authorization: {accountConfiguration: configuration('allow'), leaseMs: 60000,
            effectRequiredClaims: [], resumeAfterAnswer: false,
            reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer', principalId: 'reviewer', publicKey: pem(reviewer.publicKey)}],
            reviewReaders: ['reviewer'], hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}}}})});
    assert.equal(child.status, 0, child.stdout + child.stderr);
    assert.deepEqual(JSON.parse(child.stdout.trim()), {coldOriginal: true, wrongAnswerRefused: true, firstClose: true});
  } catch (error) {f.preserve(); throw error;}
});


test('Source Checkpoint identifiers remain bounded for long original Run identifiers', async t => {
  const f = await fixture(t, {source: delegatedSource()});
  try {
    const installed = await f.open();
    const ids = [];
    for (const suffix of ['a', 'b']) {
      // The current continuation evidence owner prefixes this original with
      // `effect-`; exercise its full admitted 128-character storage identity.
      const runId = 'r'.repeat(120) + suffix;
      const gate = await installed.computationSourceAuthorization({...sourceOptions(), runId});
      try {
        const waiting = await gate.authorize();
        assert.equal(waiting.action, 'waiting', JSON.stringify(waiting));
        assert.equal(waiting.checkpoint.runId, runId);
        assert.match(waiting.checkpoint.checkpointId, /^[A-Za-z0-9._:-]{1,128}$/u);
        ids.push(waiting.checkpoint.checkpointId);
      } finally {gate.close();}
    }
    assert.notEqual(ids[0], ids[1], 'the same read scope on different original Runs remains distinct');
  } catch (error) {f.preserve(); throw error;}
});

for (const [name, checkpointId, unresolved] of [
  ['sealed legacy Source identity remains recognized after original entry', 'source-scope-source-0', true],
  ['arbitrary Source-like identity is not an original read-scope identity', 'source-' + 'f'.repeat(64), false],
]) {
  test(name, async t => {
    const f = await fixture(t, {source: delegatedSource()});
    try {
      const installed = await f.open();
      // Model an already sealed record using the original Journal admission;
      // only the historical identifier recipe differs, not its signed scope.
      const journalPort = {...installed.journal, persistCheckpoint: checkpoint =>
        installed.journal.persistCheckpoint({...checkpoint,
          body: {...checkpoint.body, checkpoint_id: checkpointId}})};
      const gate = await installed.computationSourceAuthorization({...sourceOptions(), journalPort});
      try {
        assert.equal((await gate.authorize()).action, 'waiting');
        const [summary] = (await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10})).items;
        const answer = await signedAnswer(summary, 'approved', {keyId: 'reviewer-key', reviewerId: 'reviewer',
          sign: bytes => sign(null, bytes, reviewer.privateKey)}, new Date(f.clock).toISOString());
        assert.equal((await installed.resolve({principalId: 'reviewer', items: [answer]})).results[0].status, 'committed');
        const claim = installed.journal.claimResume('source-scope', {claimant: 'original-source', leaseMs: 60000,
          binding: installed.binding, expectedCheckpointCid: summary.checkpointCid});
        const decision = await gate.resume({resumption: {claim: {checkpointCid: summary.checkpointCid, claim: claim.claim}}});
        assert.equal(decision.action, 'dispatch'); decision.admission.enter();
        assert.equal(installed.hasUnresolvedSourceStart('source-scope', cid('1')), unresolved);
        assert.equal(installed.hasUnresolvedSourceStart('other-run', cid('1')), false);
        assert.equal(installed.hasUnresolvedSourceStart('source-scope', cid('9')), false);
      } finally {gate.close();}
    } catch (error) {f.preserve(); throw error;}
  });
}
