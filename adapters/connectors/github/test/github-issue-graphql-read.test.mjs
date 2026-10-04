// Independent HTTPS fixture tests for the node-bound GraphQL Issue read.
// Expectations are hand-written from the GitHub GraphQL documentation:
// `node(id:)` resolves the persisted global ID; `errors` (including
// RATE_LIMITED in an HTTP 200) is never a page.
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
import {openHttpsExchangeFixture} from
  '../../../site-node/https-exchange-fixture.mjs';
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';
import {openSqliteCredentialJournal} from
  '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  '../../../site-node/remote-credential-signature.mjs';
import {GITHUB_GRAPHQL_READ_OPERATION, readGitHubIssuesByNode} from
  '../site/github-issue-graphql-read.mjs';
import {graphqlRoute, issueReads} from './github-graphql.fixture.mjs';

const control = runtimeCore(commonMoon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const A = {nodeId: 'R_A', databaseId: 1296269, nameWithOwner: 'octo/hello'};
const issues = count => Array.from({length: count}, (_, index) =>
  ({number: index + 1}));
const row = number => ({number, node_id: `I_${number}`,
  // GitHub's GraphQL states no body as "", kept exactly as given.
  title: `Issue ${number}`, state: 'open', body: '', author: 'octocat',
  comments: 0, created_at: '2026-10-01T00:00:00.000Z',
  updated_at: '2026-10-02T00:00:00.000Z', closed_at: null});

async function setup(t, state, {faults = []} = {}) {
  const fixture = await openHttpsExchangeFixture(t, {faults,
    routes: [graphqlRoute(() => state)]});
  const root = await mkdtemp(join(tmpdir(), 'actql-github-graphql-'));
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
    resourceOrigin: fixture.origin, operation: GITHUB_GRAPHQL_READ_OPERATION,
    runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 32,
  });
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {keyId: 'key-a', privateKey: authority.privateKey}), control);
  let reads = 0;
  const read = (overrides = {}) => {
    const id = reads++;
    return readGitHubIssuesByNode({moon, repository: A,
      credential: {control, journal, resolveSecret: async () => 'token-a',
        ca: fixture.ca, now: () => 1_999_999_999_999},
      callResource: callHttpsCredentialResource,
      authorizationFor: async index => ({grant, scope,
        useId: `read-${id}-${index}`}),
      limits: {maxPages: 5, maxRows: 100, maxBytes: 100_000,
        maxNodes: 10_000, maxDepth: 32, perPage: 100,
        maxRequestBytes: 16_384},
      ...overrides});
  };
  return {fixture, journal, read};
}

const world = (extra = {}) => ({
  repositories: new Map([['R_A', {databaseId: 1296269,
    nameWithOwner: 'octo/hello', issues: issues(5)}]]),
  names: new Map([['octo/hello', 'R_A']]), pageSize: 2, ...extra});

const stopOf = promise => promise.then(() => undefined, error => error);

test('pages are read from the published node ID until the last cursor', async t => {
  const context = await setup(t, world());
  const result = await context.read();
  assert.equal(result.complete, true);
  assert.deepEqual(result.rows, [1, 2, 3, 4, 5].map(row));
  const reads = issueReads(context.fixture);
  assert.equal(reads.length, 3);
  // Every request names the published node ID; the cursor advances.
  assert.deepEqual(reads.map(request => request.variables.id),
    ['R_A', 'R_A', 'R_A']);
  assert.deepEqual(reads.map(request => request.variables.after),
    [null, Buffer.from('cursor:1').toString('base64'),
      Buffer.from('cursor:3').toString('base64')]);
  for (const entry of context.fixture.seen()) {
    assert.equal(entry.method, 'POST');
    assert.equal(entry.pathname, '/graphql');
    assert.equal(entry.headers['x-github-api-version'], '2026-03-10');
  }
});

test('a same-name repository B never changes the requested node', async t => {
  const state = world();
  const context = await setup(t, state);
  // B now owns the name; A keeps its node ID.
  state.repositories.set('R_B', {databaseId: 424242,
    nameWithOwner: 'octo/hello', issues: issues(9)});
  state.names.set('octo/hello', 'R_B');
  state.repositories.get('R_A').nameWithOwner = 'octo/hello';
  const result = await context.read();
  assert.deepEqual(result.rows.map(entry => entry.number), [1, 2, 3, 4, 5]);
  assert.ok(issueReads(context.fixture).every(request =>
    request.variables.id === 'R_A'));
});

test('a response for another repository, ID spelling or name is refused', async t => {
  for (const [change, code] of [
    [state => { state.repositories.get('R_A').databaseId = 424242; },
      'GitHubRepositoryIdentityChanged'],
    [state => { state.repositories.get('R_A').answerId = 'R_A_next'; },
      'GitHubRepositoryRepublishRequired'],
    [state => { state.repositories.get('R_A').nameWithOwner = 'octo/renamed'; },
      'GitHubRepositoryBindingChanged'],
  ]) {
    const state = world();
    change(state);
    const context = await setup(t, state);
    const error = await stopOf(context.read());
    assert.equal(error.code, code);
    assert.equal(error.stopped, true);
    assert.deepEqual(error.acceptedPages, []);
    assert.equal(issueReads(context.fixture).length, 1);
  }
});

test('a vanished or unreadable repository is never looked up by name', async t => {
  const state = world();
  state.repositories.delete('R_A');
  state.repositories.set('R_B', {databaseId: 424242,
    nameWithOwner: 'octo/hello', issues: issues(3)});
  state.names.set('octo/hello', 'R_B');
  const context = await setup(t, state);
  const error = await stopOf(context.read());
  // NOT_FOUND arrives as GraphQL errors with a null node.
  assert.equal(error.code, 'GitHubGraphQLRefused');
  assert.equal(error.refusal.kind, 'Errors');
  const seen = context.fixture.seen();
  assert.equal(seen.length, 1);
  assert.equal(JSON.parse(seen[0].body).variables.id, 'R_A');
  // A null node without errors is refused as unavailable too.
  const silent = await setup(t, {...world(),
    answer: () => ({body: {data: {node: null}}})});
  assert.equal((await stopOf(silent.read())).code,
    'GitHubRepositoryUnavailable');
  // Permission loss is a rejection, never a fallback.
  const denied = await setup(t, {...world(),
    answer: () => ({status: 401, body: {message: 'Bad credentials'}})});
  const refusal = await stopOf(denied.read());
  assert.equal(refusal.code, 'GitHubReadRejected');
  assert.equal(denied.fixture.seen().length, 1);
});

test('HTTP 200 errors and partial data are never a page', async t => {
  const limited = await setup(t, {...world(), answer: () => ({
    headers: {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1790000000'},
    body: {data: null, errors: [{type: 'RATE_LIMITED',
      message: 'API rate limit exceeded'}]}})});
  const stop = await stopOf(limited.read());
  assert.equal(stop.code, 'GitHubRateLimited');
  assert.equal(stop.basis.remaining, 0);
  assert.equal(issueReads(limited.fixture).length, 1);
  const partial = await setup(t, {...world(), answer: () => ({body: {
    errors: [{type: 'FORBIDDEN', message: 'Resource not accessible'}],
    data: {node: {__typename: 'Repository', id: 'R_A',
      databaseId: 1296269, nameWithOwner: 'octo/hello',
      issues: {pageInfo: {hasNextPage: false, endCursor: null},
        nodes: []}}}}})});
  const refused = await stopOf(partial.read());
  assert.equal(refused.code, 'GitHubGraphQLRefused');
  assert.deepEqual(refused.refusal, {kind: 'Errors', type: 'FORBIDDEN'});
});

test('a missing, repeated or non-advancing cursor stops the read', async t => {
  const page = (endCursor, hasNextPage = true) => () => ({body: {data: {node: {
    __typename: 'Repository', id: 'R_A', databaseId: 1296269,
    nameWithOwner: 'octo/hello', issues: {pageInfo: {hasNextPage, endCursor},
      nodes: [{number: 1, id: 'I_1', title: 'Issue 1', state: 'OPEN',
        body: '', author: {login: 'octocat'}, comments: {totalCount: 0},
        createdAt: '2026-10-01T00:00:00Z', updatedAt: '2026-10-02T00:00:00Z',
        closedAt: null}]}}}}});
  const missing = await setup(t, {...world(), answer: page(null)});
  assert.equal((await stopOf(missing.read())).refusal.kind, 'MissingCursor');
  const repeated = await setup(t, {...world(), answer: page('same')});
  const cycle = await stopOf(repeated.read());
  assert.equal(cycle.code, 'GitHubCursorCycle');
  assert.deepEqual(cycle.acceptedPages.map(entry => entry.rows), [1, 1]);
  assert.equal(issueReads(repeated.fixture).length, 2);
});

test('page and row ceilings, revocation and a lost reply keep the stop', async t => {
  const pages = await setup(t, world());
  const ceiling = await stopOf(pages.read({limits: {maxPages: 1,
    maxRows: 100, maxBytes: 100_000, maxNodes: 10_000, maxDepth: 32,
    perPage: 100, maxRequestBytes: 16_384}}));
  assert.equal(ceiling.code, 'GitHubReadPageLimit');
  assert.equal(ceiling.unfetched.page, 2);
  const rows = await setup(t, world());
  assert.equal((await stopOf(rows.read({limits: {maxPages: 5, maxRows: 3,
    maxBytes: 100_000, maxNodes: 10_000, maxDepth: 32, perPage: 100,
    maxRequestBytes: 16_384}}))).code, 'GitHubReadRowLimit');
  const revoked = await setup(t, world());
  let calls = 0;
  const denied = await stopOf(revoked.read({authorizationFor: async () => {
    calls++;
    throw Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied'});
  }}));
  assert.equal(denied.code, 'ExecutionAuthorizationDenied');
  assert.equal(calls, 1);
  assert.equal(revoked.fixture.seen().length, 0);
  const lost = await setup(t, world(), {faults: [{kind: 'lose-reply',
    method: 'POST', pathname: '/graphql'}]});
  const loss = await stopOf(lost.read());
  assert.equal(loss.stopped, true);
  assert.equal(lost.journal.recover().at(-1).outcome, 'unknown');
});

test('filters reach the fixed query only as typed variables', async t => {
  const context = await setup(t, world());
  await context.read({filters: {state: 'open', labels: ['日本語ラベル'],
    since: '2026-10-01T00:00:00Z'}});
  const [first] = issueReads(context.fixture);
  assert.deepEqual(first.variables, {id: 'R_A', first: 100, after: null,
    states: ['OPEN'], labels: ['日本語ラベル'],
    since: '2026-10-01T00:00:00Z'});
  assert.equal(first.query, JSON.parse(moon.githubIssuesRequestJson('R_A',
    1, false, '', 'all', [], false, '')).body &&
    JSON.parse(JSON.parse(moon.githubIssuesRequestJson('R_A', 1, false, '',
      'all', [], false, '')).body).query);
  assert.ok(!first.query.includes('mutation'));
  await assert.rejects(context.read({filters: {state: 'draft', labels: []}}),
    {code: 'InvalidGitHubReadFilters'});
});
