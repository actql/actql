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
import {openHttpsExchangeFixture, pagedListing} from
  '../../../site-node/https-exchange-fixture.mjs';
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
const issue = (number, extra = {}) => ({number, node_id: `I_${number}`,
  title: `Issue ${number}`, state: 'open', body: null,
  user: {login: 'octocat'}, comments: number, labels: [],
  created_at: '2026-10-01T00:00:00Z', updated_at: '2026-10-02T00:00:00Z',
  closed_at: null, ...extra});
const stored = [issue(1), issue(2, {pull_request: {url: 'x'}}),
  issue(3, {state: 'closed', closed_at: '2026-10-03T00:00:00Z'}),
  issue(4, {body: 'text'}), issue(5)];

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

async function installation(t, {routes: extraRoutes = [], faults = [],
  repositoryAt = () => ({id: repositoryId, node_id: 'R_hello'})} = {}) {
  let api;
  const routes = [...extraRoutes];
  api = await openHttpsExchangeFixture(t, {routes, faults});
  // The provider's answer for the access name, per observation (0 is the
  // explicit publication); the Site profile never changes.
  let repositoryReads = 0;
  routes.push({method: 'GET', pathname: '/repos/octocat/hello',
    handle: () => ({body: {...repositoryAt(repositoryReads++),
      name: 'hello', full_name: 'octocat/hello',
      owner: {login: 'octocat', id: 1}}})});
  routes.push(pagedListing({items: stored, origin: api.origin,
    pathname: '/repos/octocat/hello/issues', maxSize: 2,
    query: {state: 'all'}}));
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
  return {api, root, site, sitePath, profile, publish, open, connection};
}

const listings = api => api.seen().filter(entry =>
  entry.pathname === '/repos/octocat/hello/issues');

test('public Client reads published GitHub Issues to a Named Result', async t => {
  const setup = await installation(t);
  // A Host start without a publication refuses before any provider I/O.
  await assert.rejects(setup.open(), {code: 'GitHubPublicationMissing'});
  assert.equal(setup.api.seen().length, 0);
  const published = await setup.publish();
  assert.deepEqual(published.repository, {id: repositoryId,
    node_id: 'R_hello'});
  assert.equal(setup.api.seen().length, 1);
  const {client} = await setup.open();
  // The Host start restored the publication without provider I/O.
  assert.equal(setup.api.seen().length, 1);
  const repositoryChecks = () => setup.api.seen().filter(entry =>
    entry.pathname === '/repos/octocat/hello').length;
  const execution = await client.aql(program, {format: 'json',
    requestId: 'github-read-1'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await execution.result('issues').all();
  // Open Issues only; the pull request (#2) is not an Issue row.
  assert.deepEqual(rows.map(row => [row.number, row.title, row.author])
    .sort((a, b) => a[0] - b[0]),
  [[1, 'Issue 1', 'octocat'], [4, 'Issue 4', 'octocat'],
    [5, 'Issue 5', 'octocat']]);
  // Three listing pages (page size 2 of 5 provider items), each with the
  // declared headers, and the date-free state filter kept on every page.
  const pages = listings(setup.api);
  assert.deepEqual(pages.map(entry => entry.query.page ?? '1'), ['1', '2', '3']);
  // The read was bracketed by two identity checks of the published
  // repository (plus the publication's own observation).
  assert.equal(repositoryChecks(), 3);
  const order = setup.api.seen().slice(1).map(entry => entry.pathname);
  assert.equal(order[0], '/repos/octocat/hello');
  assert.equal(order.at(-1), '/repos/octocat/hello');
  for (const entry of pages) {
    assert.equal(entry.query.state, 'all');
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

test('a rate-limited page stops the Run without a partial Result', async t => {
  const setup = await installation(t, {faults: [{kind: 'reply',
    method: 'GET', pathname: '/repos/octocat/hello/issues',
    reply: {status: 403, headers: {'x-ratelimit-remaining': '0',
      'x-ratelimit-reset': '1790000000'}, body: {message: 'rate limited'}}}]});
  await setup.publish();
  const {client} = await setup.open();
  const execution = await client.aql(program, {format: 'json',
    requestId: 'github-read-limited'});
  const state = await execution.wait();
  assert.equal(state.status, 'failed', JSON.stringify(state));
  assert.equal(listings(setup.api).length, 1);
});

const replaced = {id: 424242, node_id: 'R_other'};

test('another repository under the same name before the read issues nothing',
  async t => {
    // The local Site profile stays fixed; only the provider's repository
    // behind owner/repo is replaced after publication.
    const setup = await installation(t, {repositoryAt: read => read === 0
      ? {id: repositoryId, node_id: 'R_hello'} : replaced});
    await setup.publish();
    const {client} = await setup.open();
    const execution = await client.aql(program, {format: 'json',
      requestId: 'github-read-replaced-before'});
    const state = await execution.wait();
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(state.result_available, false);
    assert.equal(state.result_availability.issues.state, 'unavailable');
    // Nothing was listed under the old binding.
    assert.equal(listings(setup.api).length, 0);
  });

test('a repository replaced during the read issues no Result', async t => {
  const setup = await installation(t, {repositoryAt: read => read <= 1
    ? {id: repositoryId, node_id: 'R_hello'} : replaced});
  await setup.publish();
  const {client} = await setup.open();
  const execution = await client.aql(program, {format: 'json',
    requestId: 'github-read-replaced-during'});
  const state = await execution.wait();
  assert.equal(state.status, 'failed', JSON.stringify(state));
  assert.equal(state.result_available, false);
  assert.equal(state.result_availability.issues.state, 'unavailable');
  // The pages were read, but the closing check found another repository.
  assert.equal(listings(setup.api).length, 3);
});
