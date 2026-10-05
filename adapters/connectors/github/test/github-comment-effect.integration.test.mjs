// Public Client acceptance of the GitHub Issue comment Effect on the standard
// installed HTTPS Host, against an independent HTTPS fixture that answers as
// the GitHub GraphQL API. Every expectation (subjects, bodies, comment count)
// is written by hand from the fixture's tables; nothing is derived from
// product output.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, readdir, readFile, rm, writeFile} from
  'node:fs/promises';
import {createServer} from 'node:https';
import {DatabaseSync} from 'node:sqlite';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {connect} from '../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost, publishInstalledEffect} from
  '../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {openHttpsExchangeFixture} from
  '../../../site-node/https-exchange-fixture.mjs';
import {commentSends, graphqlRoute} from './github-graphql.fixture.mjs';
import {INSTALLED_GITHUB_SITE_VERSION} from
  '../host/installed-github-source.mjs';
import {INSTALLED_GITHUB_EFFECT_VERSION} from
  '../host/installed-github-effect.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'github-comment-effect');
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'host.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'host.crt'));
setDefaultCACertificates([...getCACertificates('default'),
  tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));

const owner = userInfo().username;
const secret = async () => 'test-only-token';
const tokens = new Map([['owner-token', owner],
  ['reviewer-token', 'reviewer-principal']]);
const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};

// The published repository A with Issue 7 and pull request 8, and another
// repository B with Issue 1.
const providerState = () => ({
  repositories: new Map([
    ['R_hello', {databaseId: 1296269, nameWithOwner: 'octocat/hello',
      issues: []}],
    ['R_other', {databaseId: 424242, nameWithOwner: 'octocat/other',
      issues: []}]]),
  names: new Map([['octocat/hello', 'R_hello'],
    ['octocat/other', 'R_other']]),
  subjects: new Map([
    ['I_7', {type: 'Issue', repository: 'R_hello', number: 7}],
    ['PR_8', {type: 'PullRequest', repository: 'R_hello', number: 8}],
    ['I_B1', {type: 'Issue', repository: 'R_other', number: 1}]]),
  comments: []});

const entry = (entry_id, outcome, connection, resource, operation) => ({
  entry_id, outcome, exclusions: [], principal: {all: true},
  connection: {any_of: [connection]}, resource: {any_of: [resource]},
  operation: {any_of: [operation]}});
// The Effect installation's account: the common apply reads each member's
// Resource and the subject checks read Issues; the comment commit is
// delegated to the reviewer unless `commit` says otherwise.
const accountConfiguration = (connection, {commit = 'delegate'} = {}) =>
  canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'github-comment-host', entries: [
      entry('comment-commit', commit, connection, 'issue_comments', 'effect'),
      {entry_id: 'host-run', outcome: 'allow', exclusions: [],
        principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']}},
      {...entry('target-read', 'allow', connection, 'issues', 'read'),
        resource: {any_of: ['issue_comments', 'issues']}}]});

const checkpointAuthorization = accountConfiguration => ({
  accountConfiguration,
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
    principalId: 'reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}],
  reviewReaders: ['reviewer-principal'],
  hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)},
  leaseMs: 10_000, resumeAfterAnswer: false});

// A Values Program that comments `rows` ({node_id, comment}) through the
// installed Mapping.
const commentProgram = (mapping, rows) => JSON.stringify({version: 'actql/0.1',
  id: 'github-comment', stages: [{id: 'source', inputs: {},
    steps: [{values: {schema: {
      node_id: {type: 'string', nullable: false},
      comment: {type: 'string', nullable: false}}, rows}, as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['node_id', 'comment']}},
    effects: {comment: {create: {target: mapping.target,
      mapping: mapping.mappingRef, from: {result: 'rows'}}}}}],
  results: {answer: {from: {stage: 'source', result: 'rows'}}}});

async function installation(t, {faults = [], commit} = {}) {
  const state = providerState();
  const api = await openHttpsExchangeFixture(t, {faults,
    routes: [graphqlRoute(() => state)]});
  const root = await mkdtemp(join(scratch, 'host-'));
  const closers = [];
  t.after(async () => {
    for (const close of closers.reverse()) await close();
    await rm(root, {recursive: true, force: true});
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  const sitePath = join(root, 'github-site.json');
  await writeFile(sitePath, JSON.stringify({
    version: INSTALLED_GITHUB_SITE_VERSION, apiOrigin: api.origin,
    owner: 'octocat', repo: 'hello', namespaceId: 'namespace-a',
    environment: 'test', siteKey: 'github-site', siteGeneration: 1,
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    journalRoot: join(root, 'credential-journal'),
    tokenEnvironment: 'ACTQL_TEST_GITHUB_TOKEN', caPath: api.caPath}));
  const connection = `github:${new URL(api.origin).host}/octocat/hello`;
  const configuration = accountConfiguration(connection, {commit});
  const effectProfilePath = join(root, 'effect-profile.json');
  await writeFile(effectProfilePath, JSON.stringify({
    version: INSTALLED_GITHUB_EFFECT_VERSION, siteProfilePath: sitePath,
    publicationPath: join(root, 'github-publication.json'),
    connectorId: 'gh-hello', accountConfigurationWire: configuration,
    writes: [{resource: 'issue_comments', sources: [
      {target: 'subject_id', field: 'node_id', null_behavior: 'reject'},
      {target: 'body', field: 'comment', null_behavior: 'reject'}]}]}));
  const hostRoot = join(root, 'state');
  const published = await publishInstalledEffect({effectProfilePath,
    directory: hostRoot, resolveEffectSecret: secret});
  const [mapping] = published.mappings;
  const openHost = async () => {
    const host = await openInstalledRemoteHttpHost({directory: hostRoot,
      authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
      effectProfilePath, resolveEffectSecret: secret,
      authorization: checkpointAuthorization(configuration)});
    const server = createServer({key: tlsKey, cert: tlsCertificate},
      host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    let closed = false;
    const close = async () => {
      if (closed) return;
      closed = true;
      server.closeAllConnections?.();
      await new Promise(resolve => server.close(resolve));
      await host.close();
    };
    closers.push(close);
    const endpoint = `https://127.0.0.1:${server.address().port}/`;
    const as = async token => {
      const client = await connect({mode: 'remote', endpoint, token,
        durability: 'durable'});
      closers.push(() => client.close());
      return client;
    };
    return {as, close};
  };
  // Alter the one durable Effect input body (named by the Store's
  // `effect-source` holding manifest) while the Host is stopped.
  const alterEffectInput = async () => {
    const objects = [];
    const walk = async directory => {
      for (const item of await readdir(directory, {withFileTypes: true})) {
        const path = join(directory, item.name);
        if (item.isDirectory()) await walk(path);
        else if (item.name.endsWith('.json') &&
            directory.includes('physical-holdings')) {
          const holding = JSON.parse(await readFile(path, 'utf8'));
          const store = directory.slice(0,
            directory.indexOf('physical-holdings'));
          if (holding.namespace === 'effect-source') {
            objects.push(...holding.objects.map(object =>
              join(store, 'objects', object.cid.slice(7))));
          }
        }
      }
    };
    await walk(hostRoot);
    assert.equal(objects.length, 1, 'one durable Effect input');
    const bytes = await readFile(objects[0]);
    bytes[bytes.length - 1] ^= 0x01;
    await writeFile(objects[0], bytes);
  };
  return {api, state, mapping, openHost, alterEffectInput,
    program: rows => commentProgram(mapping, rows)};
}

async function waitFor(check, {attempts = 400} = {}) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('WaitForTimeout');
}

const terminal = ['succeeded', 'failed', 'needs_reconciliation', 'cancelled'];

// Submit and wait until the Run is held for approval or has ended.
async function submitted(setup, host, requestId, rows) {
  const client = await host.as('owner-token');
  const execution = await client.aql(setup.program(rows), {format: 'json',
    requestId});
  const state = await waitFor(async () => {
    const current = await execution.status();
    return current.status === 'waiting_checkpoint' ||
      terminal.includes(current.status) ? current : undefined;
  });
  return {execution, state};
}

async function approve(host, execution) {
  const reviewer = await host.as('reviewer-token');
  const [checkpoint] = (await reviewer.checkpoints()).items;
  assert.equal(checkpoint?.kind, 'effect_set');
  const answer = await reviewer.resolveCheckpoints([
    {checkpoint, decision: 'approved'}], {signer: {...signer,
    authorityScopeCid: execution.ref.authorityScopeCid}});
  assert.deepEqual(answer.results.map(item => item.status), ['committed']);
}

// Approve the held Set from a separate Host process and close it, so no Host
// is running when a test then changes the input or the provider; nothing
// has been sent at that point.
async function approvedAndStopped(setup, first, execution) {
  await first.close();
  const reviewer = await setup.openHost();
  await approve(reviewer, execution);
  await reviewer.close();
  assert.equal(commentSends(setup.api).length, 0,
    'nothing is sent before the approved Set is resumed');
}

// Resume the Run in a new Host process and wait for its end.
async function resumed(setup, execution) {
  const host = await setup.openHost();
  const attached = await (await host.as('owner-token')).attach(execution.ref);
  const state = await waitFor(async () => {
    const current = await attached.status();
    return terminal.includes(current.status) ? current : undefined;
  });
  return {host, attached, state};
}

const subjectChecks = api => api.seen()
  .filter(entry => entry.pathname === '/graphql')
  .map(entry => JSON.parse(entry.body))
  .filter(request => request.query.startsWith('query ActqlCommentSubject('));

test('a comment waits for approval across a restart, is sent once and never again',
  async t => {
    const setup = await installation(t);
    const first = await setup.openHost();
    const {execution, state} = await submitted(setup, first, 'comment-once',
      [{node_id: 'I_7', comment: 'hello from actql'}]);
    assert.equal(state.status, 'waiting_checkpoint', JSON.stringify(state));
    // Held: the subject was checked for the Preview and again by the apply
    // attempt that reached the commit decision; nothing was sent.
    assert.equal(subjectChecks(setup.api).length, 2);
    assert.equal(commentSends(setup.api).length, 0);
    await first.close();
    const second = await setup.openHost();
    await approve(second, execution);
    await second.close();
    const {host: third, state: done} = await resumed(setup, execution);
    assert.equal(done.status, 'succeeded', JSON.stringify(done));
    // Exactly one comment, on Issue 7, with the exact body.
    assert.deepEqual(setup.state.comments, [{subjectId: 'I_7',
      body: 'hello from actql', databaseId: 1000}]);
    assert.deepEqual(commentSends(setup.api).map(request =>
      request.variables), [{subjectId: 'I_7', body: 'hello from actql'}]);
    // The subject was checked again before the approved send.
    assert.equal(subjectChecks(setup.api).length, 3);
    await third.close();
    // A further restart sends nothing more.
    const fourth = await setup.openHost();
    const again = await (await fourth.as('owner-token')).attach(execution.ref);
    assert.equal((await again.status()).status, 'succeeded');
    assert.equal(commentSends(setup.api).length, 1);
    assert.equal(setup.state.comments.length, 1);
  });

test('a recovered Ledger whose first close fails is retried by its Host owner, once',
  async t => {
    const setup = await installation(t);
    const first = await setup.openHost();
    const {execution} = await submitted(setup, first, 'comment-close-retry',
      [{node_id: 'I_7', comment: 'hello from actql'}]);
    await approvedAndStopped(setup, first, execution);
    // The resumed Host's first Effect Ledger close fails.
    const original = DatabaseSync.prototype.close;
    const counts = {attempts: 0, closes: 0};
    let failures = 1;
    DatabaseSync.prototype.close = function () {
      if (!new Error().stack.includes('effect-ledger.mjs')) {
        return original.call(this);
      }
      counts.attempts++;
      if (failures > 0) {
        failures--;
        throw new Error('InjectedLedgerCloseFailure');
      }
      const closed = original.call(this);
      counts.closes++;
      return closed;
    };
    t.after(() => { DatabaseSync.prototype.close = original; });
    const {host, state} = await resumed(setup, execution);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    await waitFor(async () => counts.closes === 1);
    await host.close();
    // Sent once; the handle was closed once, by a retry of the failed close.
    assert.equal(commentSends(setup.api).length, 1);
    assert.deepEqual(counts, {attempts: 2, closes: 1});
  });

test('a pull request or another repository\'s Issue is refused before any approval or send',
  async t => {
    for (const subject of ['PR_8', 'I_B1', 'I_GONE']) {
      const setup = await installation(t);
      const host = await setup.openHost();
      const {state} = await submitted(setup, host, `comment-${subject}`,
        [{node_id: subject, comment: 'hello'}]);
      assert.equal(state.status, 'failed', `${subject}: ${state.status}`);
      assert.equal(commentSends(setup.api).length, 0, subject);
      assert.equal(setup.state.comments.length, 0, subject);
    }
  });

test('a subject that stops being an Issue after approval is refused before the send',
  async t => {
    const setup = await installation(t);
    const first = await setup.openHost();
    const {execution} = await submitted(setup, first, 'comment-moved',
      [{node_id: 'I_7', comment: 'hello'}]);
    await approvedAndStopped(setup, first, execution);
    // After approval, the node now resolves into another repository.
    setup.state.subjects.set('I_7', {type: 'Issue', repository: 'R_other',
      number: 7});
    const {state} = await resumed(setup, execution);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(commentSends(setup.api).length, 0);
    assert.equal(setup.state.comments.length, 0);
  });

test('a reply lost after the comment was created stays unknown and is never resent',
  async t => {
    const setup = await installation(t, {faults: [{
      kind: 'apply-then-lose-reply', method: 'POST', pathname: '/graphql',
      bodyIncludes: 'mutation ActqlAddComment('}]});
    const first = await setup.openHost();
    const {execution} = await submitted(setup, first, 'comment-lost',
      [{node_id: 'I_7', comment: 'hello'}]);
    await approvedAndStopped(setup, first, execution);
    const {host: second, state} = await resumed(setup, execution);
    assert.equal(state.status, 'needs_reconciliation', JSON.stringify(state));
    assert.deepEqual(state.next_action, {effects: ['comment'],
      kind: 'reconcile'});
    // The comment exists at the provider, and was sent exactly once.
    assert.equal(setup.state.comments.length, 1);
    assert.equal(commentSends(setup.api).length, 1);
    await second.close();
    // A restart does not resend it.
    const third = await setup.openHost();
    const again = await (await third.as('owner-token')).attach(execution.ref);
    assert.equal((await waitFor(async () => {
      const current = await again.status();
      return terminal.includes(current.status) ? current : undefined;
    })).status, 'needs_reconciliation');
    assert.equal(commentSends(setup.api).length, 1);
    assert.equal(setup.state.comments.length, 1);
  });

test('an account allow without approval sends nothing: the Mapping requires approval',
  async t => {
    const setup = await installation(t, {commit: 'allow'});
    const host = await setup.openHost();
    const {state} = await submitted(setup, host, 'comment-allow',
      [{node_id: 'I_7', comment: 'hello'}]);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(commentSends(setup.api).length, 0);
    assert.equal(setup.state.comments.length, 0);
  });

test('an Effect input altered after approval is refused before any send',
  async t => {
    const setup = await installation(t);
    const first = await setup.openHost();
    const {execution} = await submitted(setup, first, 'comment-altered',
      [{node_id: 'I_7', comment: 'hello'}]);
    await approvedAndStopped(setup, first, execution);
    await setup.alterEffectInput();
    const {state} = await resumed(setup, execution);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(commentSends(setup.api).length, 0);
    assert.equal(setup.state.comments.length, 0);
  });

// Several rows of one member: their canonical order may differ from the
// input order, and equal rows stay separate operations.
for (const [name, rows, bodies] of [
  ['two rows whose canonical order reverses the input',
    [{node_id: 'I_7', comment: 'first'}, {node_id: 'I_7', comment: 'second'}],
    ['first', 'second']],
  ['two equal rows',
    [{node_id: 'I_7', comment: 'same'}, {node_id: 'I_7', comment: 'same'}],
    ['same', 'same']],
]) {
  test(`${name}: held, restarted, approved, sent exactly once each`,
    async t => {
      const setup = await installation(t);
      const first = await setup.openHost();
      const {execution, state} = await submitted(setup, first,
        `comment-rows-${bodies.join('-')}`, rows);
      assert.equal(state.status, 'waiting_checkpoint', JSON.stringify(state));
      assert.equal(commentSends(setup.api).length, 0);
      await first.close();
      const second = await setup.openHost();
      await approve(second, execution);
      await second.close();
      const {host: third, state: done} = await resumed(setup, execution);
      assert.equal(done.status, 'succeeded', JSON.stringify(done));
      const sent = () => commentSends(setup.api).map(request =>
        request.variables.body).sort();
      assert.deepEqual(sent(), bodies);
      assert.deepEqual(setup.state.comments.map(comment =>
        [comment.subjectId, comment.body]).sort(),
      bodies.map(body => ['I_7', body]));
      await third.close();
      // A further restart sends nothing more.
      const fourth = await setup.openHost();
      const again = await (await fourth.as('owner-token'))
        .attach(execution.ref);
      assert.equal((await again.status()).status, 'succeeded');
      assert.deepEqual(sent(), bodies);
    });
}
