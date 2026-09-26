// The installed Remote Host with Run-acceptance protection, driven through
// the public Client over HTTPS: allow, deny and missing configuration,
// immediate Host answers, and a held request that is reviewed, answered and
// resumed by the Host. The packed, multi-process acceptance is
// scripts/test-packed-client-checkpoint.mjs.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from
  'node:fs/promises';
import {createServer} from 'node:https';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connect, RequestHeld} from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const scratch = join(repository, '_build', 'remote-checkpoint-host');
await mkdir(scratch, {recursive: true});
const document = await readFile(join(repository,
  'packages/sdk/fixtures/values.json'), 'utf8');
const owner = userInfo().username;
const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});

export function runAcceptanceConfiguration(outcome, {siteKey =
  'actql-remote-host'} = {}) {
  return canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'remote-account',
    entries: [{entry_id: 'run-acceptance', outcome,
      principal: {all: true}, connection: {any_of: [siteKey]},
      resource: {any_of: ['source-free-values']},
      operation: {any_of: ['write']}, exclusions: []}],
  });
}

const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal'],
  ['reader-token', 'reader-principal'],
  ['stranger-token', 'stranger-principal']]);

async function remoteHost(t, authorization, {directory} = {}) {
  const root = directory ?? await mkdtemp(join(scratch, 'host-'));
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd: root, stdio: 'ignore'});
  const certificate = await readFile(join(root, 'remote.crt'));
  let dispatches = 0;
  const host = await openInstalledRemoteHttpHost({
    directory: join(root, 'state'),
    authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
    beforeDispatch: async () => { dispatches++; },
    authorization,
  });
  const server = createServer({key: await readFile(join(root, 'remote.key')),
    cert: certificate}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    server.closeAllConnections?.();
    await new Promise(resolve => server.close(resolve));
    await host.close();
  };
  // Close the Host (and its Store owner) before removing its state.
  t.after(async () => {
    await close();
    if (directory === undefined) {
      await rm(root, {recursive: true, force: true});
    }
  });
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  // Trust this test certificate for the process's fetch.
  setDefaultCACertificates([...getCACertificates('default'),
    certificate.toString('utf8')]);
  const as = token => connect({mode: 'remote', endpoint, token,
    durability: 'durable'});
  return {as, dispatches: () => dispatches, close};
}

const reviewers = [{keyId: 'reviewer-key', reviewerId: 'reviewer',
  principalId: 'reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}];
const hostKey = {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)};
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
const protectedHost = (outcome, extra = {}) => ({
  ...(outcome === undefined ? {} :
    {accountConfiguration: runAcceptanceConfiguration(outcome)}),
  reviewers, reviewReaders: ['reader-principal'], hostKey, ...extra,
});

async function waitFor(check) {
  for (let attempt = 0; attempt < 200; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('Timeout');
}

test('allow runs without a Checkpoint; deny and missing configuration start nothing',
  async t => {
    const allowed = await remoteHost(t, protectedHost('allow'));
    const client = await allowed.as('owner-token');
    const execution = await client.aql(document, {format: 'json',
      requestId: 'allow-a'});
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.deepEqual((await (await allowed.as('reviewer-token'))
      .checkpoints()).items, []);
    for (const [label, authorization, code] of [
      ['deny', protectedHost('deny'), 'ACTQL_E_ACCOUNT_DENIED'],
      ['missing', protectedHost(undefined), 'ACTQL_E_ACCOUNT_CONFIG_INVALID'],
    ]) {
      const host = await remoteHost(t, authorization);
      const denied = await host.as('owner-token');
      await assert.rejects(denied.aql(document, {format: 'json',
        requestId: `${label}-a`}), {code}, label);
      assert.equal(host.dispatches(), 0, label);
      assert.deepEqual(await denied.lookupRequest(`${label}-a`),
        {kind: 'not_found'}, label);
    }
  });

test('delegate immediate permit runs and immediate reject records nothing',
  async t => {
    const decide = view => ({decision: view.subject.subject_cid ===
      undefined ? 'reject' : 'permit', subject: view.subject,
    authority: 'host-policy'});
    let answer = 'permit';
    const host = await remoteHost(t, protectedHost('delegate', {
      decide: view => ({...decide(view), decision: answer}),
      answeringAuthorities: ['host-policy']}));
    const client = await host.as('owner-token');
    const permitted = await client.aql(document, {format: 'json',
      requestId: 'permit-a'});
    assert.equal((await permitted.wait()).status, 'succeeded');
    answer = 'reject';
    await assert.rejects(client.aql(document, {format: 'json',
      requestId: 'reject-a'}), {code: 'ACTQL_E_DELEGATION_REJECTED'});
    assert.deepEqual(await client.lookupRequest('reject-a'),
      {kind: 'not_found'});
    assert.deepEqual((await (await host.as('reviewer-token'))
      .checkpoints()).items, []);
  });

test('a held request is reviewed, answered and resumed by the Host',
  async t => {
    const host = await remoteHost(t, protectedHost('delegate'));
    const client = await host.as('owner-token');
    let held;
    try {
      await client.aql(document, {format: 'json', requestId: 'held-a'});
    } catch (error) { held = error; }
    assert.equal(held instanceof RequestHeld, true);
    assert.equal(held.held.state, 'waiting_checkpoint');
    assert.equal(host.dispatches(), 0);
    // The same request again is the same held request, not a new one.
    await assert.rejects(client.aql(document, {format: 'json',
      requestId: 'held-a'}), error => error instanceof RequestHeld &&
      error.held.checkpoint.checkpointCid ===
        held.held.checkpoint.checkpointCid);
    // The same request ID with another intent conflicts.
    const changed = JSON.parse(document);
    changed.stages[0].steps[0].values.rows = [{id: 9}];
    await assert.rejects(client.aql(JSON.stringify(changed),
      {format: 'json', requestId: 'held-a'}),
    {code: 'ClientRequestIntentConflict'});
    assert.equal((await client.lookupRequest('held-a')).state,
      'waiting_checkpoint');

    const reviewer = await host.as('reviewer-token');
    const reader = await host.as('reader-token');
    const {items: [summary]} = await reviewer.checkpoints();
    assert.equal(summary.checkpointCid, held.held.checkpoint.checkpointCid);
    assert.equal(summary.subject.requestId, 'held-a');
    assert.equal(JSON.stringify(summary).includes('"rows"'), false);
    // Status, review and answer permissions are separate.
    await assert.rejects(host.as('stranger-token'), {code:
      'ClientConnectionDenied'});
    // A reviewer is not the request owner: no Run operation.
    await assert.rejects(reviewer.aql(document, {format: 'json',
      requestId: 'reviewer-own'}), {code: 'ClientConnectionDenied'});
    await assert.rejects(reviewer.lookupRequest('held-a'),
      {code: 'ClientConnectionDenied'});
    await assert.rejects(reviewer.reviewCheckpoint(summary),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(client.reviewCheckpoint(summary),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(reader.reviewCheckpoint(`sha256:${'0'.repeat(64)}`),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(reader.reviewCheckpoint(summary, {maxBytes: 16}),
      {code: 'CheckpointReviewTooLarge'});
    const review = await reader.reviewCheckpoint(summary);
    const projection = JSON.parse(new TextDecoder().decode(review.bytes));
    assert.equal(projection.version, 'actql-run-review-projection/0.1');
    assert.equal(projection.displayed_scope.request_id, 'held-a');
    assert.equal(projection.displayed_scope.site_key, 'actql-remote-host');
    await assert.rejects(reader.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer}), {code: 'CheckpointAnswerDenied'});
    // Still nothing ran.
    assert.equal(host.dispatches(), 0);

    const answered = await reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed']);
    // A resend of the identical signed answer is a duplicate.
    const again = await reviewer.resolveCheckpoints(answered.signed);
    assert.deepEqual(again.results.map(item => item.status), ['duplicate']);
    const found = await waitFor(async () => {
      const lookup = await client.lookupRequest('held-a');
      return lookup.kind === 'found' ? lookup : undefined;
    });
    const execution = await client.attach(found.ref);
    // wait() returns the current state; a Client waits again until the Run
    // is terminal.
    assert.equal((await waitFor(async () => {
      const state = await execution.wait();
      return ['succeeded', 'failed', 'cancelled'].includes(state.status)
        ? state : undefined;
    })).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    assert.equal(host.dispatches(), 1);
    // The submit is now the existing Run.
    assert.deepEqual((await client.aql(document, {format: 'json',
      requestId: 'held-a'})).ref, found.ref);
    assert.deepEqual((await reviewer.checkpoints()).items, []);
  });

test('rejected answers end the request without a Run; answers are per item',
  async t => {
    const host = await remoteHost(t, protectedHost('delegate'));
    const client = await host.as('owner-token');
    for (const requestId of ['batch-a', 'batch-b']) {
      const changed = JSON.parse(document);
      changed.id = requestId;
      await assert.rejects(client.aql(JSON.stringify(changed),
        {format: 'json', requestId}), error => error instanceof RequestHeld);
    }
    const reviewer = await host.as('reviewer-token');
    const {items} = await reviewer.checkpoints({limit: 1});
    assert.equal(items.length, 1);
    const page = await reviewer.checkpoints({limit: 1});
    const rest = await reviewer.checkpoints({after: page.next, limit: 5});
    const [first, second] = [...page.items, ...rest.items];
    assert.notEqual(first.checkpointCid, second.checkpointCid);
    const rejected = await reviewer.resolveCheckpoints([
      {checkpoint: first, decision: 'rejected'}], {signer});
    assert.deepEqual(rejected.results.map(item => item.status),
      ['committed']);
    // A contradicting answer for the same Checkpoint, and a new one for the
    // second, in one batch: each result stands on its own.
    const mixed = await reviewer.resolveCheckpoints([
      {checkpoint: first, decision: 'approved'},
      {checkpoint: second, decision: 'rejected'}], {signer});
    assert.deepEqual(mixed.results.map(item => item.status),
      ['conflicting', 'committed']);
    for (const summary of [first, second]) {
      const lookup = await client.lookupRequest(summary.subject.requestId);
      assert.equal(lookup.state, 'ended');
      assert.equal(lookup.endReason, 'rejected');
    }
    assert.equal(host.dispatches(), 0);
  });

async function heldRequests(client, ids) {
  for (const requestId of ids) {
    const changed = JSON.parse(document);
    changed.id = requestId;
    await assert.rejects(client.aql(JSON.stringify(changed),
      {format: 'json', requestId}), error => error instanceof RequestHeld);
  }
}
async function allCheckpoints(reviewer) {
  const items = [];
  let after;
  do {
    const page = await reviewer.checkpoints({after, limit: 100});
    items.push(...page.items);
    after = page.next;
  } while (after !== undefined);
  return items;
}
async function approveAll(reviewer, items) {
  for (let index = 0; index < items.length; index += 16) {
    const answered = await reviewer.resolveCheckpoints(items.slice(index,
      index + 16).map(checkpoint => ({checkpoint, decision: 'approved'})),
    {signer});
    assert.ok(answered.results.every(item => item.status === 'committed'));
  }
}
async function succeeded(client, requestId) {
  const found = await waitFor(async () => {
    const lookup = await client.lookupRequest(requestId);
    return lookup.kind === 'found' ? lookup : undefined;
  });
  const execution = await client.attach(found.ref);
  return waitFor(async () => (await execution.wait()).status === 'succeeded');
}

// The first claim stalls while a second request is approved; nothing else
// (no submit, answer, lease retry or restart) wakes the Host afterwards.
async function stalledSweep(t, {leaseMs, stallMs}) {
  const steps = [];
  let stall = true;
  let released;
  const stalled = new Promise(resolve => { released = resolve; });
  const host = await remoteHost(t, protectedHost('delegate', {
    leaseMs,
    async observe(name) {
      steps.push(name);
      if (name === 'resume_claimed' && stall) {
        stall = false;
        await stalled;
      }
    }}));
  const client = await host.as('owner-token');
  const reviewer = await host.as('reviewer-token');
  await heldRequests(client, ['race-a', 'race-b']);
  const [first, second] = await allCheckpoints(reviewer);
  await approveAll(reviewer, [first]);
  await waitFor(() => steps.includes('resume_claimed'));
  await approveAll(reviewer, [second]);
  await new Promise(resolve => setTimeout(resolve, stallMs));
  released();
  for (const requestId of ['race-a', 'race-b']) {
    assert.equal(await succeeded(client, requestId), true, requestId);
  }
  assert.equal(host.dispatches(), 2);
  assert.equal(steps.filter(name => name === 'computed').length, 2);
}

test('an answer committed during a resume is not lost', async t => {
  // The lease stays live: only the recorded wake continues the second one.
  await stalledSweep(t, {leaseMs: 60_000, stallMs: 100});
});

test('a claim whose lease lapsed sends nothing and is retried by the Host',
  async t => {
    await stalledSweep(t, {leaseMs: 1000, stallMs: 1200});
  });

test('more than one page of approved requests resumes at Host start',
  async t => {
    // Pages of 5 over 12 requests: the same continuation as 101 requests
    // over the default page of 100.
    const count = 12;
    const ids = Array.from({length: count}, (_, index) =>
      `start-${String(index).padStart(3, '0')}`);
    const directory = await mkdtemp(join(scratch, 'restart-'));
    const answering = await remoteHost(t, protectedHost('delegate',
      {resumeAfterAnswer: false, sweepPage: 5}), {directory});
    const client = await answering.as('owner-token');
    const reviewer = await answering.as('reviewer-token');
    await heldRequests(client, ids);
    const items = await allCheckpoints(reviewer);
    assert.equal(items.length, count);
    await approveAll(reviewer, items);
    assert.equal(answering.dispatches(), 0);
    await answering.close();
    const restarted = await remoteHost(t, protectedHost('delegate',
      {sweepPage: 5}), {directory});
    const owner = await restarted.as('owner-token');
    for (const requestId of ids) {
      assert.equal(await succeeded(owner, requestId), true, requestId);
    }
    assert.equal(restarted.dispatches(), count);
    await restarted.close();
    await rm(directory, {recursive: true, force: true});
  });

test('a lost or corrupt request index is rebuilt from the held evidence',
  async t => {
    const directory = await mkdtemp(join(scratch, 'index-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const first = await remoteHost(t, protectedHost('delegate'),
      {directory});
    const client = await first.as('owner-token');
    await heldRequests(client, ['index-a', 'index-b']);
    await first.close();
    const index = join(directory, 'state', 'checkpoints', 'held');
    const files = (await readdir(index)).filter(name =>
      name.endsWith('.json')).sort();
    assert.equal(files.length, 2);
    await rm(join(index, files[0]));
    await writeFile(join(index, files[1]), '{not json');
    const second = await remoteHost(t, protectedHost('delegate'),
      {directory});
    const reviewer = await second.as('reviewer-token');
    const items = await allCheckpoints(reviewer);
    assert.deepEqual(items.map(item => item.subject.requestId).sort(),
      ['index-a', 'index-b']);
    // The rebuilt entries are durable again.
    assert.deepEqual((await readdir(index)).filter(name =>
      name.endsWith('.json')).sort(), files);
    await approveAll(reviewer, items);
    const owner = await second.as('owner-token');
    for (const requestId of ['index-a', 'index-b']) {
      assert.equal(await succeeded(owner, requestId), true, requestId);
    }
    await second.close();
  });

test('closing during a resumed dispatch records its end before releasing',
  async t => {
    const directory = await mkdtemp(join(scratch, 'close-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const steps = [];
    let released;
    const stalled = new Promise(resolve => { released = resolve; });
    const host = await remoteHost(t, protectedHost('delegate', {
      async observe(name) {
        steps.push(name);
        if (name === 'physical_start_reserved') await stalled;
      }}), {directory});
    const client = await host.as('owner-token');
    const reviewer = await host.as('reviewer-token');
    await heldRequests(client, ['close-a']);
    await approveAll(reviewer, await allCheckpoints(reviewer));
    await waitFor(() => steps.includes('physical_start_reserved'));
    const closing = host.close();
    released();
    await closing;
    assert.ok(steps.includes('computed'));
    // The journal Run ended with the dispatch; no later start is needed.
    const database = new DatabaseSync(join(directory, 'state',
      'checkpoints', 'journal', 'checkpoint-journal.sqlite3'),
    {readOnly: true});
    try {
      assert.deepEqual(database.prepare('SELECT status FROM runs').all()
        .map(row => row.status), ['succeeded']);
    } finally { database.close(); }
    const ledgers = join(directory, 'state', 'checkpoints', 'attempts');
    for (const file of await readdir(ledgers)) {
      const ledger = JSON.parse(await readFile(join(ledgers, file), 'utf8'));
      assert.ok(ledger.holdings.filter(item =>
        item.name !== 'invocation_request').every(item =>
        item.state === 'retired'), file);
    }
  });

// DCI-R7: submitting a held request again never starts it outside the
// resumed authorization. The Host's resume is stalled after the Run
// Definition exists and before its physical start; meanwhile the owner
// submits the same request.
async function resubmittedWhileStalled(t, {leaseMs = 60_000,
  checkpointTtlMs, wait = 0}) {
  const steps = [];
  let stall = true;
  let released;
  const stalled = new Promise(resolve => { released = resolve; });
  const host = await remoteHost(t, protectedHost('delegate', {
    leaseMs, ...(checkpointTtlMs === undefined ? {} : {checkpointTtlMs}),
    async observe(name) {
      steps.push(name);
      if (name === 'definition_admitted' && stall) {
        stall = false;
        await stalled;
      }
    }}));
  const client = await host.as('owner-token');
  const reviewer = await host.as('reviewer-token');
  await heldRequests(client, ['again-a']);
  await approveAll(reviewer, await allCheckpoints(reviewer));
  await waitFor(() => steps.includes('definition_admitted'));
  await new Promise(resolve => setTimeout(resolve, wait));
  const changed = JSON.parse(document);
  changed.id = 'again-a';
  const again = await client.aql(JSON.stringify(changed), {format: 'json',
    requestId: 'again-a'});
  // The resubmit returns the existing Run and starts nothing by itself.
  await new Promise(resolve => setTimeout(resolve, 200));
  assert.equal(steps.filter(name => name === 'physical_start_reserved')
    .length, 0);
  assert.equal(host.dispatches(), 0);
  released();
  const state = await waitFor(async () => {
    const current = await again.wait();
    return ['succeeded', 'failed', 'cancelled'].includes(current.status)
      ? current : undefined;
  });
  return {state, starts: steps.filter(name =>
    name === 'physical_start_reserved').length, steps};
}

test('a resubmit of a held request after its approval expired starts nothing',
  async t => {
    const {state, starts} = await resubmittedWhileStalled(t,
      {checkpointTtlMs: 2000, wait: 2300});
    assert.equal(starts, 0);
    assert.equal(state.status, 'failed');
  });

test('a resubmit during a valid resume starts the Run at most once',
  async t => {
    const {state, starts} = await resubmittedWhileStalled(t, {});
    assert.equal(starts, 1);
    assert.equal(state.status, 'succeeded');
  });

test('a resubmit while the resuming claim lapses starts the Run once',
  async t => {
    const {state, starts, steps} = await resubmittedWhileStalled(t,
      {leaseMs: 1000, wait: 1300});
    assert.equal(starts, 1);
    assert.equal(state.status, 'succeeded');
    // The lapsed claim started nothing; a later claim did.
    assert.ok(steps.filter(name => name === 'resume_claimed').length >= 2);
  });
