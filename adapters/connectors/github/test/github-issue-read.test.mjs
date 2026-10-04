// Independent HTTPS fixture tests for GitHub's Issue listing driver. The
// expected rows, requests and stop reasons are written by hand from the
// GitHub REST documentation (API version 2026-03-10), not derived from output.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as moon from
  '../../../../_build/js/release/build/connectors/github/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {linkHeader, openHttpsExchangeFixture, pagedListing} from
  '../../../site-node/https-exchange-fixture.mjs';
import {openSqliteCredentialJournal} from
  '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  '../../../site-node/remote-credential-signature.mjs';
import {GITHUB_ISSUE_LIST_OPERATION, githubIssueListPath, readGitHubIssues}
  from '../site/github-issue-read.mjs';

const control = runtimeCore(commonMoon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const path = '/repos/octo/hello/issues';
const since = '2026-10-01T00:00:00Z';

const issue = (number, extra = {}) => ({number, node_id: `I_${number}`,
  title: `Issue ${number}`, state: 'open', body: null,
  user: {login: 'octo'}, comments: 0, created_at: '2026-10-02T00:00:00Z',
  updated_at: '2026-10-03T00:00:00Z', closed_at: null, labels: [], ...extra});
const row = number => ({number, node_id: `I_${number}`,
  title: `Issue ${number}`, state: 'open', body: null, author: 'octo',
  comments: 0, created_at: '2026-10-02T00:00:00Z',
  updated_at: '2026-10-03T00:00:00Z', closed_at: null});
const pull = number => issue(number,
  {pull_request: {url: `https://api.example/pulls/${number}`}});

async function setup(t, {routes = [], faults = []} = {}) {
  const fixture = await openHttpsExchangeFixture(t, {routes, faults});
  const root = await mkdtemp(join(tmpdir(), 'actql-github-read-'));
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['authority-a',
      new Map([['key-a', authority.publicKey]])]]),
  });
  t.after(async () => {
    journal.close();
    await rm(root, {recursive: true, force: true});
  });
  const scope = Object.freeze({
    issuerAuthority: 'authority-a', principal: 'principal-a',
    namespaceId: 'namespace-a', environment: 'production', siteKey: 'site-a',
    siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'github', connectorRevision: 'github/0.1',
    resourceOrigin: fixture.origin, operation: GITHUB_ISSUE_LIST_OPERATION,
    runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 16,
  });
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {keyId: 'key-a', privateKey: authority.privateKey}), control);
  const decisions = [];
  let reads = 0;
  const authorize = index => ({grant, scope, useId: `read-${reads}-${index}`});
  const read = (overrides = {}) => (reads++, readGitHubIssues({moon,
    origin: fixture.origin, owner: 'octo', repo: 'hello',
    credential: {control, journal, resolveSecret: async () => 'token-a',
      ca: fixture.ca, now: () => 1_999_999_999_999},
    authorizationFor: async index => {
      decisions.push(index);
      return authorize(index);
    },
    limits: {maxPages: 5, maxRows: 100, maxBytes: 100_000, maxNodes: 10_000,
      maxDepth: 16, maxLocatorUnits: 2048, perPage: 2},
    ...overrides}));
  return {fixture, journal, decisions, read, authorize};
}

const listing = (fixture, items, {query = {}, headers = () => ({})} = {}) => {
  const route = pagedListing({items, origin: fixture.origin, pathname: path,
    maxSize: 2, query});
  return {method: 'GET', pathname: path, handle: exchange => {
    const reply = route.handle(exchange);
    return {...reply, headers: {...reply.headers, ...headers(exchange)}};
  }};
};

test('the listing path is built only from plain owner and repository names', () => {
  assert.equal(githubIssueListPath('octo', 'hello.js'), '/repos/octo/hello.js/issues');
  for (const [owner, repo] of [['octo', '..'], ['o/x', 'r'], ['octo', 'r?x'],
    ['', 'r'], ['octo', 'r%2F']]) {
    assert.throws(() => githubIssueListPath(owner, repo),
      {code: 'InvalidGitHubRepository'});
  }
});

test('pages follow Link to completion, exclude pull requests and keep since',
  async t => {
    let items;
    const routes = [];
    const context = await setup(t, {routes});
    items = [issue(1), pull(2), issue(3), issue(4, {body: 'text',
      state: 'closed', closed_at: '2026-10-04T00:00:00Z', user: null})];
    routes.push(listing(context.fixture, items,
      {query: {state: 'all', since}}));
    const result = await context.read({filters: [['state', 'all'],
      ['since', since]]});
    assert.equal(result.complete, true);
    assert.deepEqual(result.rows, [row(1), row(3), {...row(4), body: 'text',
      state: 'closed', closed_at: '2026-10-04T00:00:00Z', author: null}]);
    assert.deepEqual(result.pages.map(page => [page.page, page.rows,
      page.excludedPullRequests, page.providerItems]), [[1, 1, 1, 2], [2, 2, 0, 2]]);
    const seen = context.fixture.seen();
    assert.deepEqual(seen.map(entry => entry.path), [
      `${path}?state=all&since=2026-10-01T00%3A00%3A00Z&per_page=2`,
      `${path}?state=all&since=2026-10-01T00%3A00%3A00Z&per_page=2&page=2`]);
    for (const entry of seen) {
      assert.equal(entry.query.since, since);
      assert.equal(entry.headers.accept, 'application/vnd.github+json');
      assert.equal(entry.headers['x-github-api-version'], '2026-03-10');
      assert.equal(entry.headers['user-agent'], 'actql-github-connector/0.1');
      assert.equal(entry.authorized, true);
    }
    // The current read decision is taken before every request.
    assert.deepEqual(context.decisions, [0, 1]);
  });

test('an empty listing is a complete read of one request', async t => {
  const routes = [];
  const context = await setup(t, {routes});
  routes.push(listing(context.fixture, []));
  const result = await context.read();
  assert.deepEqual([result.complete, result.rows, result.pages.length],
    [true, [], 1]);
  assert.equal(context.fixture.seen().length, 1);
});

test('a 200 with no remaining quota is accepted and the read stops before the next request',
  async t => {
    const routes = [];
    const context = await setup(t, {routes});
    routes.push(listing(context.fixture, [issue(1), issue(2), issue(3)], {
      headers: () => ({'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1790000000', 'x-ratelimit-resource': 'core'})}));
    const error = await context.read().then(() => undefined, value => value);
    assert.equal(error.code, 'GitHubRateLimited');
    assert.equal(error.stopped, true);
    assert.deepEqual(error.basis, {retryAfterSeconds: null,
      resetEpochSeconds: 1790000000, remaining: 0, resource: 'core'});
    assert.deepEqual(error.acceptedPages.map(page => page.rows), [2]);
    assert.deepEqual(error.unfetched, {path,
      query: [['per_page', '2'], ['page', '2']], page: 2});
    assert.equal(context.fixture.seen().length, 1);
  });

test('no remaining quota on the last page still completes', async t => {
  const routes = [];
  const context = await setup(t, {routes});
  routes.push(listing(context.fixture, [issue(1)], {
    headers: () => ({'x-ratelimit-remaining': '0'})}));
  const result = await context.read();
  assert.equal(result.complete, true);
  assert.deepEqual(result.rows, [row(1)]);
});

test('429 and header-evidenced 403 stop as rate limits; a plain 403 is a denial',
  async t => {
    for (const [reply, code, kind] of [
      [{status: 429, headers: {'retry-after': '30'}, body: {}}, 'GitHubRateLimited'],
      [{status: 403, headers: {'x-ratelimit-remaining': '0'}, body: {}},
        'GitHubRateLimited'],
      [{status: 403, body: {message: 'Resource not accessible'}},
        'GitHubReadRejected', 'PermissionDenied'],
      [{status: 404, body: {message: 'Not Found'}}, 'GitHubReadRejected',
        'NotFound'],
    ]) {
      const context = await setup(t, {routes: [{method: 'GET', pathname: path,
        handle: () => reply}]});
      const error = await context.read().then(() => undefined, value => value);
      assert.equal(error.code, code, JSON.stringify(reply));
      assert.equal(error.stopped, true);
      assert.deepEqual(error.acceptedPages, []);
      if (kind !== undefined) assert.equal(error.failure.kind, kind);
      assert.equal(context.fixture.seen().length, 1);
    }
  });

test('a foreign or non-advancing Link stops the read; it is never the last page',
  async t => {
    for (const [link, refusal] of [
      [linkHeader({next: `https://evil.example${path}?page=2`}), 'ForeignOrigin'],
      [linkHeader({next: 'PLACEHOLDER/repos/octo/other/issues?page=2'}),
        'ForeignResource'],
      [linkHeader({next: `PLACEHOLDER${path}?page=1`}), 'NonAdvancingPage'],
      ['<garbage', 'MalformedLink'],
    ]) {
      let origin;
      const context = await setup(t, {routes: [{method: 'GET', pathname: path,
        handle: () => ({headers: {link: link.replace('PLACEHOLDER', origin)},
          body: [issue(1)]})}]});
      origin = context.fixture.origin;
      const error = await context.read().then(() => undefined, value => value);
      assert.equal(error.code, 'GitHubLinkRefused');
      assert.equal(error.refusal, refusal);
      assert.deepEqual(error.acceptedPages.map(page => page.rows), [1]);
      assert.equal(context.fixture.seen().length, 1);
    }
  });

test('a page or row ceiling stops with the unfetched locator kept', async t => {
  const routes = [];
  const context = await setup(t, {routes});
  routes.push(listing(context.fixture, [issue(1), issue(2), issue(3)]));
  const pages = await context.read({limits: {maxPages: 1, maxRows: 100,
    maxBytes: 100_000, maxNodes: 10_000, maxDepth: 16, maxLocatorUnits: 2048,
    perPage: 2}}).then(() => undefined, value => value);
  assert.equal(pages.code, 'GitHubReadPageLimit');
  assert.equal(pages.unfetched.page, 2);
  const rows = await context.read({limits: {maxPages: 5, maxRows: 2,
    maxBytes: 100_000, maxNodes: 10_000, maxDepth: 16, maxLocatorUnits: 2048,
    perPage: 2}}).then(() => undefined, value => value);
  assert.equal(rows.code, 'GitHubReadRowLimit');
  assert.deepEqual(rows.acceptedPages.map(page => page.page), [1]);
});

test('a revoked read decision stops before the next request', async t => {
  const routes = [];
  const context = await setup(t, {routes});
  routes.push(listing(context.fixture, [issue(1), issue(2), issue(3)]));
  const error = await context.read({authorizationFor: async index => {
    if (index > 0) {
      throw Object.assign(new Error('ExecutionAuthorizationDenied'),
        {code: 'ExecutionAuthorizationDenied'});
    }
    return context.authorize(index);
  }}).then(() => undefined, value => value);
  assert.equal(error.code, 'ExecutionAuthorizationDenied');
  assert.equal(error.stopped, true);
  assert.deepEqual(error.acceptedPages.map(page => page.rows), [2]);
  assert.equal(error.unfetched.page, 2);
  assert.equal(context.fixture.seen().length, 1);
});

test('a lost reply is an error with an unknown credential use, never a page',
  async t => {
    const context = await setup(t, {routes: [{method: 'GET', pathname: path,
      handle: () => ({body: []})}], faults: [{kind: 'lose-reply', method: 'GET',
      pathname: path}]});
    const error = await context.read().then(() => undefined, value => value);
    assert.equal(error.stopped, true);
    assert.deepEqual(error.acceptedPages, []);
    assert.equal(error.unfetched.page, 1);
    assert.equal(context.journal.recover().at(-1).outcome, 'unknown');
  });

test('a non-ASCII label filter continues on page two with the same value',
  async t => {
    // No space: the fixture spells a space as `+` (form encoding), which an
    // RFC 3986 query reads as a literal plus; that link is refused below.
    const label = '日本語ラベル';
    const routes = [];
    const context = await setup(t, {routes});
    routes.push(listing(context.fixture, [issue(1), issue(2), issue(3)],
      {query: {labels: label}}));
    const result = await context.read({filters: [['labels', label]]});
    assert.equal(result.complete, true);
    assert.deepEqual(result.rows.map(entry => entry.number), [1, 2, 3]);
    const seen = context.fixture.seen();
    assert.equal(seen.length, 2);
    // Both requests carry exactly the same label value, UTF-8 percent-encoded
    // once.
    assert.deepEqual(seen.map(entry => entry.query.labels), [label, label]);
    const encoded = '%E6%97%A5%E6%9C%AC%E8%AA%9E%E3%83%A9%E3%83%99%E3%83%AB';
    assert.equal(seen[0].path, `${path}?labels=${encoded}&per_page=2`);
    assert.equal(seen[1].path, `${path}?labels=${encoded}&per_page=2&page=2`);
  });

test('NFC and NFD label values stay distinct across pages', async t => {
  for (const label of ['café', 'café']) {
    const routes = [];
    const context = await setup(t, {routes});
    routes.push(listing(context.fixture, [issue(1), issue(2), issue(3)],
      {query: {labels: label}}));
    const result = await context.read({filters: [['labels', label]]});
    assert.equal(result.complete, true);
    assert.deepEqual(context.fixture.seen().map(entry => entry.query.labels),
      [label, label]);
  }
});

test('a continuation that spells a space as + is refused, not guessed', async t => {
  const routes = [];
  const context = await setup(t, {routes});
  routes.push(listing(context.fixture, [issue(1), issue(2), issue(3)],
    {query: {labels: 'a b'}}));
  const error = await context.read({filters: [['labels', 'a b']]})
    .then(() => undefined, value => value);
  assert.equal(error.code, 'GitHubLinkRefused');
  assert.equal(error.refusal, 'MalformedLink');
  assert.deepEqual(error.acceptedPages.map(page => page.rows), [2]);
  assert.equal(context.fixture.seen()[0].query.labels, 'a b');
});
