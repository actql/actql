// Public Client acceptance of the GitHub Issue source on the standard
// installed HTTPS Host, against an independent HTTPS fixture that answers
// as the GitHub REST API (2026-03-10). Expected rows are written by hand
// from the fixture's stored Issues; nothing is derived from product output.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {connect} from '../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from
  '../../../host-node/embedded-local.mjs';
import {publishInstalledSourceProfile} from
  '../../../host-node/installed-source.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {openHttpsExchangeFixture} from
  '../../../site-node/https-exchange-fixture.mjs';
import {graphqlRoute, issueReads} from './github-graphql.fixture.mjs';
import {INSTALLED_GITHUB_SITE_VERSION, INSTALLED_GITHUB_SOURCE_VERSION} from
  '../host/installed-github-source.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'github-standard-host');
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
const runtimeUrl = new URL('../../../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const secret = async () => 'test-only-token';
const tokens = new Map([['owner-token', owner]]);
const repositoryId = 1296269;
// Repository A's Issues as GitHub's GraphQL `Repository.issues` states them
// (pull requests are a separate connection and never appear here).
const storedA = [{number: 1, comments: 1},
  {number: 3, state: 'CLOSED', closedAt: '2026-10-03T00:00:00Z'},
  {number: 4, body: 'text'}, {number: 5}];
// Repository B, which may take A's name.
const storedB = [{number: 1, title: 'B-1'}, {number: 2, title: 'B-2'}];

const accountConfiguration = connection => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'github-source-account',
  entries: [{entry_id: 'issues-read', outcome: 'allow', exclusions: [],
    principal: {all: true}, connection: {any_of: [connection]},
    resource: {any_of: ['issues']}, operation: {any_of: ['read']}}]});

const program = JSON.stringify({version: 'actql/0.1', id: 'github-read',
  stages: [{id: 'acquire',
    inputs: {remote: {connector: 'gh-hello', resource: 'issues'}},
    steps: [{filter: "state = 'open'", as: 'open'},
      {select: ['number', 'title', 'author'], as: 'captured'}],
    results: {r: {from: 'captured', fields: ['number', 'title', 'author']}}},
  {id: 'compute',
    inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
    steps: [{select: ['number', 'title', 'author'], as: 'out'}],
    results: {r: {from: 'out', fields: ['number', 'title', 'author']}}}],
  results: {issues: {from: {stage: 'compute', result: 'r'}}}});

async function installation(t, {faults = []} = {}) {
  // The provider's current state; tests change it after publication while
  // the local Site profile stays fixed.
  const state = {
    repositories: new Map([['R_hello', {databaseId: repositoryId,
      nameWithOwner: 'octocat/hello', issues: storedA}]]),
    names: new Map([['octocat/hello', 'R_hello']]), pageSize: 2};
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
  const site = {version: INSTALLED_GITHUB_SITE_VERSION, apiOrigin: api.origin,
    owner: 'octocat', repo: 'hello', namespaceId: 'namespace-a',
    environment: 'test', siteKey: 'github-site', siteGeneration: 1,
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    journalRoot: join(root, 'credential-journal'),
    tokenEnvironment: 'ACTQL_TEST_GITHUB_TOKEN', caPath: api.caPath};
  const sitePath = join(root, 'github-site.json');
  await writeFile(sitePath, JSON.stringify(site));
  const connection = `github:${new URL(api.origin).host}/octocat/hello`;
  const profile = {version: INSTALLED_GITHUB_SOURCE_VERSION,
    siteProfilePath: sitePath,
    publicationPath: join(root, 'github-publication.json'),
    connectorId: 'gh-hello',
    accountConfigurationWire: accountConfiguration(connection)};
  const profilePath = join(root, 'source-profile.json');
  await writeFile(profilePath, JSON.stringify(profile));
  const hostRoot = join(root, 'state');
  const publish = () => publishInstalledSourceProfile(profilePath, {
    root: hostRoot, principalId: owner, moon: commonMoon, runtimeUrl,
    resolveSecret: secret});
  const open = async () => {
    const host = await openInstalledRemoteHttpHost({directory: hostRoot,
      authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
      sourceProfilePath: profilePath, resolveSourceSecret: secret});
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
    const client = await connect({mode: 'remote',
      endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'owner-token', durability: 'durable'});
    closers.push(() => client.close());
    return {client, close};
  };
  return {api, state, root, site, sitePath, profile, publish, open,
    connection};
}

const listings = api => issueReads(api);
// Every provider request is the GraphQL endpoint: no name-addressed REST.
const onlyGraphql = api => api.seen().every(entry =>
  entry.method === 'POST' && entry.pathname === '/graphql');

test('public Client reads published GitHub Issues to a Named Result', async t => {
  const setup = await installation(t);
  // A Host start without a publication refuses before any provider I/O.
  await assert.rejects(setup.open(), {code: 'GitHubPublicationMissing'});
  assert.equal(setup.api.seen().length, 0);
  const published = await setup.publish();
  // The publication stores the node ID in the form the reads compare.
  assert.deepEqual(published.repository, {id: repositoryId,
    node_id: 'R_hello'});
  assert.equal(setup.api.seen().length, 1);
  const {client} = await setup.open();
  // The Host start restored the publication without provider I/O.
  assert.equal(setup.api.seen().length, 1);
  const execution = await client.aql(program, {format: 'json',
    requestId: 'github-read-1'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await execution.result('issues').all();
  // A's open Issues.
  assert.deepEqual(rows.map(row => [row.number, row.title, row.author])
    .sort((a, b) => a[0] - b[0]),
  [[1, 'Issue 1', 'octocat'], [4, 'Issue 4', 'octocat'],
    [5, 'Issue 5', 'octocat']]);
  // Two pages of A (page size 2 of 4 Issues), each by A's node ID.
  const reads = listings(setup.api);
  assert.deepEqual(reads.map(request => request.variables.id),
    ['R_hello', 'R_hello']);
  assert.equal(reads[0].variables.after, null);
  assert.equal(typeof reads[1].variables.after, 'string');
  assert.ok(onlyGraphql(setup.api));
  for (const entry of setup.api.seen()) {
    assert.equal(entry.headers['x-github-api-version'], '2026-03-10');
    assert.equal(entry.authorized, true);
  }
});

test('a renamed repository binding is refused until it is published again',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    await writeFile(setup.sitePath, JSON.stringify({...setup.site,
      repo: 'hello-renamed'}));
    const seen = setup.api.seen().length;
    await assert.rejects(setup.open(), {code: 'GitHubRepositoryBindingChanged'});
    assert.equal(setup.api.seen().length, seen);
  });

test('a rate limit stated in an HTTP 200 stops the Run without a Result',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    setup.state.answer = () => ({
      headers: {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1790000000'},
      body: {data: null, errors: [{type: 'RATE_LIMITED',
        message: 'API rate limit exceeded'}]}});
    const {client} = await setup.open();
    const execution = await client.aql(program, {format: 'json',
      requestId: 'github-read-limited'});
    const state = await execution.wait();
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(state.result_available, false);
    assert.equal(listings(setup.api).length, 1);
  });

// The local Site profile stays fixed in every case below; only the
// provider's state changes after publication.
const failsWithoutResult = async (setup, requestId) => {
  const {client} = await setup.open();
  const execution = await client.aql(program, {format: 'json', requestId});
  const state = await execution.wait();
  assert.equal(state.status, 'failed', JSON.stringify(state));
  assert.equal(state.result_available, false);
  assert.equal(state.result_availability.issues.state, 'unavailable');
};

test('A, then a same-name B, then A again: every request stays on A', async t => {
  const setup = await installation(t);
  await setup.publish();
  // B takes the name while the read runs; A keeps its node ID.
  let pages = 0;
  const original = setup.state;
  setup.state.repositories.set('R_other', {databaseId: 424242,
    nameWithOwner: 'octocat/hello', issues: storedB});
  const route = graphqlRoute(() => original);
  setup.state.answer = variables => {
    pages += 1;
    original.names.set('octocat/hello', pages === 1 ? 'R_other' : 'R_hello');
    const {answer} = original;
    original.answer = undefined;
    try { return route.handle({body: JSON.stringify({
      query: 'query ActqlIssues(', variables})}); }
    finally { original.answer = answer; }
  };
  const {client} = await setup.open();
  const execution = await client.aql(program, {format: 'json',
    requestId: 'github-read-aba'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await execution.result('issues').all();
  // Only A's rows; none of B's titles.
  assert.deepEqual(rows.map(row => row.title).sort(),
    ['Issue 1', 'Issue 4', 'Issue 5']);
  assert.ok(listings(setup.api).every(request =>
    request.variables.id === 'R_hello'));
  assert.ok(onlyGraphql(setup.api));
});

test('a node answer for repository B is refused without a Result', async t => {
  const setup = await installation(t);
  await setup.publish();
  const a = setup.state.repositories.get('R_hello');
  setup.state.repositories.set('R_hello', {...a, databaseId: 424242,
    issues: storedB});
  await failsWithoutResult(setup, 'github-read-foreign');
  assert.equal(listings(setup.api).length, 1);
});

test('a vanished or unreadable A is never replaced by a name lookup', async t => {
  const setup = await installation(t);
  await setup.publish();
  setup.state.repositories.delete('R_hello');
  setup.state.repositories.set('R_other', {databaseId: 424242,
    nameWithOwner: 'octocat/hello', issues: storedB});
  setup.state.names.set('octocat/hello', 'R_other');
  await failsWithoutResult(setup, 'github-read-vanished');
  assert.ok(listings(setup.api).every(request =>
    request.variables.id === 'R_hello'));
  // Only the publication used a name.
  assert.equal(setup.api.seen().filter(entry => JSON.parse(entry.body).query
    .startsWith('query ActqlRepository(')).length, 1);
});

test('a changed node ID representation needs an explicit re-publication',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    setup.state.repositories.get('R_hello').answerId = 'R_hello_next';
    await failsWithoutResult(setup, 'github-read-id-spelling');
    // A new explicit publication would record the current spelling; a read
    // never rewrites the binding.
    const publication = JSON.parse(await readFile(
      setup.profile.publicationPath, 'utf8'));
    assert.equal(publication.repository.node_id, 'R_hello');
  });

// The body column is published exactly as GitHub stated it.
const bodyProgram = JSON.stringify({version: 'actql/0.1', id: 'github-body',
  stages: [{id: 'acquire',
    inputs: {remote: {connector: 'gh-hello', resource: 'issues'}},
    steps: [{filter: "state = 'open'", as: 'open'},
      {select: ['number', 'body'], as: 'captured'}],
    results: {r: {from: 'captured', fields: ['number', 'body']}}},
  {id: 'compute',
    inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
    steps: [{select: ['number', 'body'], as: 'out'}],
    results: {r: {from: 'out', fields: ['number', 'body']}}}],
  results: {issues: {from: {stage: 'compute', result: 'r'}}}});

test('an empty body is published as an empty string, not NULL', async t => {
  const setup = await installation(t);
  setup.state.repositories.get('R_hello').issues = [
    {number: 1, body: ''}, {number: 2, body: 'text'}];
  await setup.publish();
  const {client} = await setup.open();
  const execution = await client.aql(bodyProgram, {format: 'json',
    requestId: 'github-body-1'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await execution.result('issues').all();
  assert.deepEqual(rows.map(row => [row.number, row.body])
    .sort((a, b) => a[0] - b[0]), [[1, ''], [2, 'text']]);
});

test('a missing, null or invalid body fails the Run without a Result', async t => {
  for (const [requestId, mutate] of [
    ['github-body-missing', node => { delete node.body; }],
    ['github-body-null', node => { node.body = null; }],
    ['github-body-number', node => { node.body = 7; }],
  ]) {
    const setup = await installation(t);
    await setup.publish();
    const route = graphqlRoute(() => ({...setup.state, answer: undefined}));
    setup.state.answer = variables => {
      const reply = route.handle({body: JSON.stringify({
        query: 'query ActqlIssues(', variables})});
      for (const node of reply.body.data.node.issues.nodes) mutate(node);
      return reply;
    };
    await failsWithoutResult(setup, requestId);
  }
});
