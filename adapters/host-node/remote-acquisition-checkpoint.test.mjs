// D-next-2: a Program that reads the installed DuckDB source, through the
// public Client and a real Remote Host. The source's own account decides the
// Host-resolved read tuple before any Run or provider I/O; a delegated read
// is held, answered later and resumed by the Host to a Named Result.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, readdir, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {connect, RequestHeld} from '../../packages/sdk/index.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {machineCid} from '../../scripts/actql-spec-family.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const scratch = join(repository, '_build', 'remote-acquisition-checkpoint');
await mkdir(scratch, {recursive: true});
const program = await readFile(join(repository,
  'adapters/connectors/duckdb/node/examples/program.json'), 'utf8');
const owner = userInfo().username;
const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
const {DuckDBInstance} = createRequire(join(repository,
  'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');

// The installed source: a real DuckDB table and its checked Catalog view.
const sourceCatalog = await readFile(join(repository,
  'src/query_integration/query_amount_catalog_wbtest.mbt'), 'utf8');
const catalog = sourceCatalog.slice(sourceCatalog.indexOf(
  'fn query_amount_nullable_catalog')).match(
  /query_catalog_from_wire\(\s*("(?:[^"\\]|\\.)*")\s*,\s*expected="([^"]+)"/u);
const sourceEnvironment = JSON.parse(JSON.parse(catalog[1]));
const selector = {source_ref: 'connector://crm/main/r#v',
  source_contract_cid:
    'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
  source_view_contract_cid:
    'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
  read_mode: 'snapshot'};
sourceEnvironment.schema_snapshots = [{...selector,
  output_carrier: 'relation',
  carrier_schema_contract_cid:
    'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4',
  source_data_policy_cid:
    'sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf',
  data_classification: 'unknown'}];
sourceEnvironment.connector_capabilities = [{...selector,
  capability_contract_cids: [
    'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8'],
}];
delete sourceEnvironment.evidence_bundle_cid;
sourceEnvironment.evidence_bundle_cid = machineCid(sourceEnvironment);

const accountConfiguration = (outcome, operation, accountId) =>
  canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: accountId, entries: [{entry_id: `${accountId}-entry`,
      outcome, principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: [operation]},
      exclusions: []}]});

async function installedSource(root, readOutcome) {
  const database = join(root, 'records.duckdb');
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),' +
      '(2,20),(3,30)');
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
  const path = join(root, 'source-profile.json');
  const write = (outcome, target = {}) => writeFile(path, JSON.stringify({
    version: 'actql-installed-duckdb-source/0.1',
    database, schema: 'main', table: 'records', ...target,
    sourceRef: selector.source_ref,
    checkEnvironmentWire: canonicalText(sourceEnvironment),
    accountConfigurationWire: accountConfiguration(outcome, 'read',
      'source-account'),
  }));
  await write(readOutcome);
  return {path, write};
}

const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal'],
  ['reader-token', 'reader-principal']]);

async function acquiringHost(t, {readOutcome = 'delegate',
  runOutcome = 'allow', extra = {}, directory, profile} = {}) {
  const root = directory ?? await mkdtemp(join(scratch, 'host-'));
  const source = profile ?? await installedSource(root, readOutcome);
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd: root, stdio: 'ignore'});
  const certificate = await readFile(join(root, 'remote.crt'));
  const steps = [];
  const host = await openInstalledRemoteHttpHost({
    directory: join(root, 'state'),
    authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
    sourceProfilePath: source.path,
    authorization: {
      accountConfiguration: accountConfiguration(runOutcome, 'write',
        'host-account'),
      reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
        principalId: 'reviewer-principal',
        publicKey: pem(reviewerKeys.publicKey)}],
      reviewReaders: ['reader-principal'],
      hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)},
      // Well below the Host default (60 s) and long enough for one resume
      // step on a loaded machine; a test of a lapsed claim sets its own.
      leaseMs: 10_000,
      ...extra,
      observe: async (name, detail) => {
        steps.push(name);
        await extra.observe?.(name, detail);
      },
    },
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
  t.after(async () => {
    await close();
    if (directory === undefined) await rm(root, {recursive: true, force: true});
  });
  setDefaultCACertificates([...getCACertificates('default'),
    certificate.toString('utf8')]);
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  const as = token => connect({mode: 'remote', endpoint, token,
    durability: 'durable'});
  return {root, steps, close, source, as,
    diagnose: () => journalState(root, steps),
    count: name => steps.filter(item => item === name).length};
}

// On a timeout, `describe` records what the Host had reached, so a slow or
// stuck resume can be told apart.
async function waitFor(check, describe) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  const detail = describe === undefined ? undefined : await describe();
  throw Object.assign(new Error(detail === undefined ? 'Timeout'
    : `Timeout ${JSON.stringify(detail)}`), {detail});
}

// The Checkpoint journal and Host progress of one Host directory.
function journalState(root, steps) {
  const database = new DatabaseSync(join(root, 'state', 'checkpoints',
    'journal', 'checkpoint-journal.sqlite3'), {readOnly: true});
  try {
    const rows = sql => database.prepare(sql).all().map(row => ({...row}));
    return {
      now: Date.now(),
      preparations: rows(`SELECT prepare_attempt_id, status, end_reason,
        cancel_requested, checkpoint_cid FROM preparations`),
      checkpoints: rows(`SELECT checkpoint_id, prepare_attempt_id,
        expires_at, closure, closed_at FROM checkpoints`),
      intents: rows(`SELECT prepare_attempt_id, state, generation,
        claimant, lease_expires_ms, outcome_status, completed_at
        FROM resume_intents`),
      steps: steps.slice(-30),
    };
  } finally { database.close(); }
}
const submit = (client, requestId) => client.aql(program, {format: 'json',
  requestId, parameters: {minimum: 1}});
async function held(client, requestId) {
  try { await submit(client, requestId); }
  catch (error) {
    assert.equal(error instanceof RequestHeld, true, String(error?.code));
    return error.held;
  }
  assert.fail('expected a held request');
}
// The independent expectation: rows of `records` with amount >= minimum
// (1): ids 3, 2, 3 for `b`, and those with id >= 3 for `c`.
async function assertResults(client, requestId, describe) {
  const found = await waitFor(async () => {
    const lookup = await client.lookupRequest(requestId);
    return lookup.kind === 'found' ? lookup : undefined;
  }, describe);
  const execution = await client.attach(found.ref);
  const state = await waitFor(async () => {
    const current = await execution.wait();
    return ['succeeded', 'failed', 'cancelled'].includes(current.status)
      ? current : undefined;
  }, describe);
  assert.equal(state.status, 'succeeded');
  assert.deepEqual((await execution.result('b').all()).map(row => row.id)
    .sort(), [2, 3, 3]);
  assert.deepEqual((await execution.result('c').all()).map(row => row.id)
    .sort(), [3, 3]);
}

test('A1: an allowed read runs; a denied read acquires nothing', async t => {
  const allowed = await acquiringHost(t, {readOutcome: 'allow'});
  const client = await allowed.as('owner-token');
  const execution = await submit(client, 'allow-a');
  assert.equal((await execution.wait()).status, 'succeeded');
  await assertResults(client, 'allow-a');
  assert.equal(allowed.count('acquisition_started'), 1);
  assert.deepEqual((await (await allowed.as('reviewer-token')).checkpoints())
    .items, []);
  const denied = await acquiringHost(t, {readOutcome: 'deny'});
  const deniedClient = await denied.as('owner-token');
  await assert.rejects(submit(deniedClient, 'deny-a'),
    {code: 'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(denied.count('dispatch_reserved'), 0);
  assert.equal(denied.count('acquisition_started'), 0);
  assert.deepEqual(await deniedClient.lookupRequest('deny-a'),
    {kind: 'not_found'});
});

test('A2: a delegated read is permitted or rejected at once by the Host',
  async t => {
    let answer = 'permit';
    const host = await acquiringHost(t, {extra: {
      decide: view => ({decision: answer, subject: view.subject,
        authority: 'host-policy'}),
      answeringAuthorities: ['host-policy']}});
    const client = await host.as('owner-token');
    const execution = await submit(client, 'permit-a');
    assert.equal((await execution.wait()).status, 'succeeded');
    answer = 'reject';
    await assert.rejects(submit(client, 'reject-a'),
      {code: 'ACTQL_E_DELEGATION_REJECTED'});
    assert.equal(host.count('acquisition_started'), 1);
  });

test('A3: a held read is reviewed, answered and resumed to its Results',
  async t => {
    const host = await acquiringHost(t);
    const client = await host.as('owner-token');
    const reviewer = await host.as('reviewer-token');
    const reader = await host.as('reader-token');
    const hold = await held(client, 'held-a');
    assert.equal(hold.checkpoint.kind, 'read_access');
    assert.equal(host.count('dispatch_reserved'), 0);
    assert.equal(host.count('acquisition_started'), 0);
    const {items: [summary]} = await reviewer.checkpoints();
    assert.equal(summary.kind, 'read_access');
    assert.equal(summary.requiredArtifact.type, 'read_scope');
    const review = JSON.parse(new TextDecoder().decode(
      (await reader.reviewCheckpoint(summary)).bytes));
    assert.deepEqual(review.displayed_scope.read_tuple,
      {connection: 'local-database', operation: 'read',
        resource: join(host.root, 'records.duckdb')});
    assert.equal(review.displayed_scope.source.sourceRef,
      'connector://crm/main/r#v');
    await reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    await assertResults(client, 'held-a');
    assert.equal(host.count('acquisition_started'), 1);
    assert.equal(host.count('acquisition_completed'), 1);
  });

test('A3: a held read survives a Host restart and resumes by itself',
  async t => {
    const directory = await mkdtemp(join(scratch, 'restart-'));
    const first = await acquiringHost(t, {directory,
      extra: {resumeAfterAnswer: false}});
    const client = await first.as('owner-token');
    const reviewer = await first.as('reviewer-token');
    await held(client, 'restart-a');
    const {items: [summary]} = await reviewer.checkpoints();
    await reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    assert.equal(first.count('acquisition_started'), 0);
    await first.close();
    const second = await acquiringHost(t, {directory,
      profile: first.source});
    t.after(() => rm(directory, {recursive: true, force: true}));
    await assertResults(await second.as('owner-token'), 'restart-a');
    assert.equal(second.count('acquisition_started'), 1);
  });

test('A5: an expired read approval or a changed source account acquires nothing',
  async t => {
    const expired = await acquiringHost(t, {extra: {
      checkpointTtlMs: 8000, resumeAfterAnswer: false}});
    const client = await expired.as('owner-token');
    const reviewer = await expired.as('reviewer-token');
    await held(client, 'expired-a');
    const {items: [summary]} = await reviewer.checkpoints();
    await reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    await new Promise(resolve => setTimeout(resolve,
      Math.max(0, Date.parse(summary.expiresAt) + 300 - Date.now())));
    const directory = expired.root;
    await expired.close();
    const restarted = await acquiringHost(t, {directory,
      profile: expired.source});
    const owner2 = await restarted.as('owner-token');
    await waitFor(async () => (await owner2.lookupRequest('expired-a'))
      .state === 'ended');
    assert.equal(restarted.count('acquisition_started'), 0);
    // The source account changed to deny while a read waited: the held
    // request ends at revalidation and nothing is acquired.
    const changing = await acquiringHost(t, {extra: {
      resumeAfterAnswer: false}});
    const owner3 = await changing.as('owner-token');
    const reviewer3 = await changing.as('reviewer-token');
    await held(owner3, 'changed-a');
    const {items: [changedSummary]} = await reviewer3.checkpoints();
    await reviewer3.resolveCheckpoints([{checkpoint: changedSummary,
      decision: 'approved'}], {signer});
    const changedDirectory = changing.root;
    await changing.close();
    await changing.source.write('deny');
    const after = await acquiringHost(t, {directory: changedDirectory,
      profile: changing.source});
    const owner4 = await after.as('owner-token');
    const ended = await waitFor(async () => {
      const lookup = await owner4.lookupRequest('changed-a');
      return lookup.state === 'ended' ? lookup : undefined;
    });
    assert.equal(ended.endReason, 'revalidation_failed');
    assert.equal(after.count('acquisition_started'), 0);
  });

test('A3: Run acceptance and the read are held and answered in turn',
  async t => {
    const host = await acquiringHost(t, {runOutcome: 'delegate'});
    const client = await host.as('owner-token');
    const reviewer = await host.as('reviewer-token');
    const first = await held(client, 'both-a');
    assert.equal(first.checkpoint.kind, 'run_scope');
    const {items: [acceptance]} = await reviewer.checkpoints();
    await reviewer.resolveCheckpoints([{checkpoint: acceptance,
      decision: 'approved'}], {signer});
    // After Run acceptance the read is decided and held next.
    const read = await waitFor(async () => {
      const {items} = await reviewer.checkpoints();
      return items.find(item => item.kind === 'read_access');
    }, host.diagnose);
    assert.equal(host.count('acquisition_started'), 0);
    await reviewer.resolveCheckpoints([{checkpoint: read,
      decision: 'approved'}], {signer});
    await assertResults(client, 'both-a', host.diagnose);
    assert.equal(host.count('acquisition_started'), 1);
  });

test('A3: an approved read never reads a different physical target',
  async t => {
    for (const [name, change, setup] of [
      ['table', {table: 'other_records'},
        'CREATE TABLE other_records(id DOUBLE, amount DOUBLE); ' +
        'INSERT INTO other_records VALUES (99,30)'],
      ['schema', {schema: 'other'},
        'CREATE SCHEMA other; ' +
        'CREATE TABLE other.records(id DOUBLE, amount DOUBLE); ' +
        'INSERT INTO other.records VALUES (99,30)'],
    ]) {
      const directory = await mkdtemp(join(scratch, `target-${name}-`));
      t.after(() => rm(directory, {recursive: true, force: true}));
      const first = await acquiringHost(t, {directory,
        extra: {resumeAfterAnswer: false}});
      const client = await first.as('owner-token');
      const reviewer = await first.as('reviewer-token');
      await held(client, `target-${name}`);
      const {items: [summary]} = await reviewer.checkpoints();
      const review = JSON.parse(new TextDecoder().decode((await (await first
        .as('reader-token')).reviewCheckpoint(summary)).bytes));
      const database = join(directory, 'records.duckdb');
      const hex = name => Buffer.from(name, 'utf8').toString('hex');
      assert.deepEqual(review.displayed_scope.physical_binding, {
        version: 'actql-installed-duckdb-target/0.1',
        database, schema: 'main', table: 'records',
        utf8_hex: {database: hex(database), schema: hex('main'),
          table: hex('records')}});
      await reviewer.resolveCheckpoints([{checkpoint: summary,
        decision: 'approved'}], {signer});
      await first.close();
      // The Host's source profile now resolves the same checked source to
      // another schema or table holding other rows.
      const instance = await DuckDBInstance.create(join(directory,
        'records.duckdb'));
      const connection = await instance.connect();
      try { await connection.run(setup); }
      finally {
        connection.closeSync();
        instance.closeSync();
      }
      await first.source.write('delegate', change);
      const second = await acquiringHost(t, {directory,
        profile: first.source});
      const owner2 = await second.as('owner-token');
      const ended = await waitFor(async () => {
        const lookup = await owner2.lookupRequest(`target-${name}`);
        return lookup.state === 'ended' ? lookup : undefined;
      });
      assert.equal(ended.kind, 'held', name);
      assert.equal(second.count('dispatch_reserved'), 0, name);
      assert.equal(second.count('acquisition_started'), 0, name);
    }
  });

// Run acceptance and the read, each answered at once by the Host or later
// by a reviewer. `permit` reaches the Results with one read; `reject`
// ends with no protected read.
test('A2: Run acceptance and the read combine immediate and later answers',
  async t => {
    for (const [name, preparation, acquisition, expected] of [
      ['run-later-read-permit', 'defer', 'permit', 'result'],
      ['run-later-read-reject', 'defer', 'reject', 'ended'],
      ['run-permit-read-later', 'permit', 'defer', 'result'],
      ['run-later-read-later', 'defer', 'defer', 'result'],
    ]) {
      const host = await acquiringHost(t, {runOutcome: 'delegate', extra: {
        decide: view => ({decision: view.boundary === 'acquisition'
          ? acquisition : preparation, subject: view.subject,
        authority: 'host-policy'}),
        answeringAuthorities: ['host-policy', 'reviewer']}});
      const client = await host.as('owner-token');
      const reviewer = await host.as('reviewer-token');
      const approve = async kind => {
        const checkpoint = await waitFor(async () => {
          const {items} = await reviewer.checkpoints();
          return items.find(item => item.kind === kind);
        }, host.diagnose);
        assert.equal(host.count('acquisition_started'), 0, name);
        await reviewer.resolveCheckpoints([{checkpoint,
          decision: 'approved'}], {signer});
      };
      const first = await held(client, name);
      assert.equal(first.checkpoint.kind,
        preparation === 'defer' ? 'run_scope' : 'read_access', name);
      if (preparation === 'defer') await approve('run_scope');
      if (acquisition === 'defer') await approve('read_access');
      if (expected === 'result') {
        await assertResults(client, name, host.diagnose);
        assert.equal(host.count('acquisition_started'), 1, name);
      } else {
        await waitFor(async () =>
          (await client.lookupRequest(name)).state === 'ended',
        host.diagnose);
        assert.equal(host.count('dispatch_reserved'), 0, name);
        assert.equal(host.count('acquisition_started'), 0, name);
      }
    }
  });

// The private evidence states of every held attempt of one Host directory.
async function holdingStates(root) {
  const ledgers = join(root, 'state', 'checkpoints', 'attempts');
  const states = [];
  for (const file of (await readdir(ledgers)).filter(name =>
    name.endsWith('.json'))) {
    const ledger = JSON.parse(await readFile(join(ledgers, file), 'utf8'));
    states.push(...ledger.holdings.filter(item =>
      item.name !== 'invocation_request').map(item => item.state));
  }
  return [...new Set(states)];
}

test('A4/A7: a held read keeps separate review rights and one answer',
  async t => {
    const host = await acquiringHost(t);
    const client = await host.as('owner-token');
    const reviewer = await host.as('reviewer-token');
    const reader = await host.as('reader-token');
    await held(client, 'answers-a');
    const {items: [summary]} = await reviewer.checkpoints();
    assert.equal(summary.kind, 'read_access');
    // A7: only review readers read the body, within its bound; an aborted
    // read is not a cancellation; a reader cannot answer.
    for (const [who, target, options, code] of [
      [reviewer, summary, {}, 'CheckpointReviewDenied'],
      [client, summary, {}, 'CheckpointReviewDenied'],
      [reader, `sha256:${'0'.repeat(64)}`, {}, 'CheckpointReviewDenied'],
      [reader, summary, {maxBytes: 16}, 'CheckpointReviewTooLarge'],
    ]) {
      await assert.rejects(who.reviewCheckpoint(target, options), {code});
    }
    const controller = new AbortController();
    controller.abort();
    await assert.rejects(reader.reviewCheckpoint(summary,
      {signal: controller.signal}));
    assert.equal((await client.lookupRequest('answers-a')).state,
      'waiting_checkpoint');
    await assert.rejects(reader.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer}), {code: 'CheckpointAnswerDenied'});
    assert.equal(host.count('acquisition_started'), 0);
    // A4: the first reply is lost; the identical signed answer is resent
    // and matched; a contradicting answer cannot replace it.
    const real = globalThis.fetch;
    let dropped = false;
    globalThis.fetch = async (url, init) => {
      const response = await real(url, init);
      if (!dropped && String(url).endsWith('/resolve')) {
        dropped = true;
        await response.body?.cancel();
        throw new TypeError('reply lost');
      }
      return response;
    };
    let lost;
    try {
      await reviewer.resolveCheckpoints([{checkpoint: summary,
        decision: 'approved'}], {signer});
    } catch (error) { lost = error; }
    finally { globalThis.fetch = real; }
    assert.equal(lost?.code, 'ResolutionUnknown');
    const resent = await reviewer.resolveCheckpoints(lost.signed);
    assert.deepEqual(resent.results.map(item => item.status), ['duplicate']);
    const contradicted = await reviewer.resolveCheckpoints([{
      checkpoint: summary, decision: 'rejected'}], {signer});
    assert.deepEqual(contradicted.results.map(item => item.status),
      ['conflicting']);
    await assertResults(client, 'answers-a');
    assert.equal(host.count('acquisition_started'), 1);
  });

test('A8: held read evidence is kept while needed and released after',
  async t => {
    // Run acceptance and then the read are held: the evidence stays held
    // through both answers and is released once the Run is terminal.
    const chain = await acquiringHost(t, {runOutcome: 'delegate'});
    const client = await chain.as('owner-token');
    const reviewer = await chain.as('reviewer-token');
    await held(client, 'retain-a');
    const answer = async kind => {
      const checkpoint = await waitFor(async () => {
        const {items} = await reviewer.checkpoints();
        return items.find(item => item.kind === kind);
      }, chain.diagnose);
      assert.deepEqual(await holdingStates(chain.root), ['held'], kind);
      await reviewer.resolveCheckpoints([{checkpoint,
        decision: 'approved'}], {signer});
    };
    await answer('run_scope');
    await answer('read_access');
    await assertResults(client, 'retain-a', chain.diagnose);
    await waitFor(async () => {
      const states = await holdingStates(chain.root);
      return states.length === 1 && states[0] === 'retired';
    }, chain.diagnose);
    // A read hold cancelled by its owner releases its evidence and never
    // reads.
    const cancelled = await acquiringHost(t);
    const owner2 = await cancelled.as('owner-token');
    await held(owner2, 'retain-b');
    assert.deepEqual(await holdingStates(cancelled.root), ['held']);
    assert.equal((await owner2.cancelRequest('retain-b')).kind, 'accepted');
    await waitFor(async () =>
      (await owner2.lookupRequest('retain-b')).state === 'ended');
    await waitFor(async () => {
      const states = await holdingStates(cancelled.root);
      return states.length === 1 && states[0] === 'retired';
    });
    assert.equal(cancelled.count('acquisition_started'), 0);
  });

// Physical names are compared exactly: a table named with a combining
// accent and one with the precomposed letter are different tables for the
// database, though ActQL's logical text treats them as the same.
test('A3: an approved read binds the exact physical name, not its NFC form',
  async t => {
    const decomposed = 'rec_e\u0301';
    const composed = 'rec_\u00e9';
    assert.equal(decomposed.normalize('NFC'), composed);
    for (const [name, target, expected] of [
      ['same', decomposed, 'result'],
      ['composed', composed, 'ended'],
    ]) {
      const directory = await mkdtemp(join(scratch, `unicode-${name}-`));
      t.after(() => rm(directory, {recursive: true, force: true}));
      const source = await installedSource(directory, 'delegate');
      const instance = await DuckDBInstance.create(join(directory,
        'records.duckdb'));
      const connection = await instance.connect();
      try {
        await connection.run(`CREATE TABLE "${decomposed}" AS ` +
          'SELECT * FROM records');
        await connection.run(`CREATE TABLE "${composed}"` +
          '(id DOUBLE, amount DOUBLE)');
        await connection.run(`INSERT INTO "${composed}" VALUES (99,30)`);
      } finally {
        connection.closeSync();
        instance.closeSync();
      }
      await source.write('delegate', {table: decomposed});
      const first = await acquiringHost(t, {directory, profile: source,
        extra: {resumeAfterAnswer: false}});
      const client = await first.as('owner-token');
      const reviewer = await first.as('reviewer-token');
      await held(client, `unicode-${name}`);
      const {items: [summary]} = await reviewer.checkpoints();
      await reviewer.resolveCheckpoints([{checkpoint: summary,
        decision: 'approved'}], {signer});
      await first.close();
      await source.write('delegate', {table: target});
      const second = await acquiringHost(t, {directory, profile: source});
      const owner2 = await second.as('owner-token');
      if (expected === 'result') {
        await assertResults(owner2, `unicode-${name}`);
        assert.equal(second.count('acquisition_started'), 1, name);
      } else {
        await waitFor(async () =>
          (await owner2.lookupRequest(`unicode-${name}`)).state === 'ended');
        assert.equal(second.count('dispatch_reserved'), 0, name);
        assert.equal(second.count('acquisition_started'), 0, name);
      }
    }
  });

// The read decision after Run acceptance outlives the resume lease: its
// Checkpoint is not persisted by the lapsed claim, and the next claim
// decides and holds the read, which then resumes to the Results.
test('A3: a read decided past its resume lease is held by the next claim',
  async t => {
    let slowReads = 1;
    const host = await acquiringHost(t, {runOutcome: 'delegate', extra: {
      leaseMs: 1000,
      decide: async view => {
        if (view.boundary === 'acquisition' && slowReads-- > 0) {
          await new Promise(resolve => setTimeout(resolve, 2500));
        }
        return {decision: 'defer', subject: view.subject,
          authority: 'host-policy'};
      },
      answeringAuthorities: ['host-policy', 'reviewer']}});
    const client = await host.as('owner-token');
    const reviewer = await host.as('reviewer-token');
    await held(client, 'lapsed-a');
    const approve = async kind => {
      const checkpoint = await waitFor(async () => {
        const {items} = await reviewer.checkpoints();
        return items.find(item => item.kind === kind);
      }, host.diagnose);
      await reviewer.resolveCheckpoints([{checkpoint,
        decision: 'approved'}], {signer});
    };
    await approve('run_scope');
    await approve('read_access');
    await assertResults(client, 'lapsed-a', host.diagnose);
    assert.equal(host.count('acquisition_started'), 1);
    assert.equal(slowReads, -1);
  });
