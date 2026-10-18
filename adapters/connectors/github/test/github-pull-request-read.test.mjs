// Actual Credential/SQLite/loopback HTTPS composition with independent native
// responses. Fixture authority and RowRun loans are not a normal Host supplier.
import assert from 'node:assert/strict';
import test from 'node:test';
import {callHttpsCredentialResource, withHttpsCredentialRunResponseOriginal} from
  '../../../site-node/https-credential-resource.mjs';
import {openGitHubReadFixture} from './github-read.fixture.mjs';
import {graphqlPullRequest, pullRequestReads} from './github-graphql.fixture.mjs';

const world = (pullRequests, extra = {}) => ({
  repositories: new Map([['R_A', {databaseId: 1296269,
    nameWithOwner: 'octo/hello', issues: [], pullRequests}]]),
  names: new Map([['octo/hello', 'R_A']]), pageSize: 1, ...extra});
const setup = (t, state, options) => openGitHubReadFixture(t, state,
  {...options, resource: 'pull_requests'});
const failed = promise => promise.then(() => assert.fail('read unexpectedly completed'), error => error);
const expected = (number, fields = {}) => ({number: String(number), node_id: `PR_${number}`,
  title: `Pull request ${number}`, state: 'open', state_reason: null,
  body: '', author: 'octocat', assignees: [], labels: [],
  url: `https://github.com/octo/hello/pull/${number}`, comments: '0', milestone: null,
  created_at: '2026-10-01T00:00:00.000Z', updated_at: '2026-10-02T00:00:00.000Z',
  closed_at: null, base: 'main', head: 'original/head', draft: false,
  mergeable: null, merged_at: null, merged_by: null, review_decision: null, ...fields});

test('original PullRequest pages complete through actual Credential uses and one accounted RowRun', async t => {
  const labels = Array.from({length: 101}, (_, i) => `label-${i}`);
  const assignees = Array.from({length: 101}, (_, i) => `user-${i}`);
  const context = await setup(t, world([
    {number: 1, state: 'OPEN', isDraft: true, mergeable: 'MERGEABLE', labels, assignees,
      milestone: {title: '2'}, comments: 2147483647, baseRefName: 'release/日本', headRefName: 'deleted/é'},
    {number: 2, state: 'CLOSED', mergeable: 'CONFLICTING', closedAt: '2026-10-03T00:00:00Z'},
    {number: 3, state: 'MERGED', mergeable: 'UNKNOWN', mergedBy: {login: 'bot[bot]'},
      mergedAt: '2026-10-04T00:00:00Z', closedAt: '2026-10-04T00:00:00Z', reviewDecision: 'APPROVED'},
  ]), {accounted: true});
  const bodies = [];
  const result = await context.read({callResource: async request => {
    const response = await callHttpsCredentialResource(request);
    bodies.push(response.body); return response;
  }});
  assert.equal(result.complete, true);
  assert.deepEqual(result.rows, [
    expected(1, {draft: true, mergeable: true, labels, assignees,
      milestone: '2', comments: '2147483647', base: 'release/日本', head: 'deleted/é'}),
    expected(2, {state: 'closed', mergeable: false, closed_at: '2026-10-03T00:00:00.000Z'}),
    expected(3, {state: 'merged', merged_at: '2026-10-04T00:00:00.000Z',
      closed_at: '2026-10-04T00:00:00.000Z', merged_by: 'bot[bot]', review_decision: 'approved'}),
  ]);
  assert.equal(bodies.length, 5);
  assert.equal(context.fixture.seen().length, 5);
  assert.equal(context.journal.recover().length, 5);
  assert.ok(context.journal.recover().every(use => use.outcome === 'succeeded'));
  assert.deepEqual(context.rowRun.counts(), {charges: 5, observations: 2});
  assert.equal(context.rowRun.transferredBytes(), BigInt(bodies.reduce((sum, body) => sum + body.byteLength, 0)));
  assert.equal(context.rowRun.finish(), 3);
  const outer = pullRequestReads(context.fixture);
  assert.equal(outer.length, 3);
  assert.deepEqual(outer.map(request => request.variables.id), ['R_A', 'R_A', 'R_A']);
  for (const request of outer) {
    assert.equal(request.variables.states, null);
    assert.ok(!request.query.includes('stateReason'));
  }
});

test('a same-name replacement cannot change the original PullRequest repository', async t => {
  const state = world([{number: 7}]);
  state.repositories.set('R_B', {databaseId: 42, nameWithOwner: 'octo/hello', pullRequests: [{number: 99}]});
  state.names.set('octo/hello', 'R_B');
  const context = await setup(t, state);
  assert.deepEqual((await context.read()).rows, [expected(7)]);
  assert.ok(pullRequestReads(context.fixture).every(request => request.variables.id === 'R_A'));
});

test('foreign repository and malformed native PullRequest fields refuse before row disclosure', async t => {
  for (const kind of ['repository', 'type', 'mergeable', 'draft', 'state', 'missing-ref']) {
    const state = world([{number: 7}]);
    state.pullAnswer = () => {
      const row = graphqlPullRequest({number: 7});
      if (kind === 'type') row.__typename = 'Issue';
      if (kind === 'mergeable') row.mergeable = 'FUTURE';
      if (kind === 'draft') row.isDraft = 'false';
      if (kind === 'state') row.state = 'FUTURE';
      if (kind === 'missing-ref') delete row.headRefName;
      return {body: {data: {node: {__typename: 'Repository',
        id: kind === 'repository' ? 'R_B' : 'R_A', databaseId: 1296269, nameWithOwner: 'octo/hello',
        pullRequests: {pageInfo: {hasNextPage: false, endCursor: null}, nodes: [row]}}}}};
    };
    const context = await setup(t, state);
    let disclosed = 0;
    const failure = await failed(context.read({consumePage: () => { disclosed++; }}));
    assert.equal(failure.code, kind === 'repository' ? 'GitHubRepositoryRepublishRequired' : 'GitHubGraphQLRefused', kind);
    assert.equal(failure.stopped, true, kind);
    assert.equal(disclosed, 0, kind);
    assert.deepEqual(failure.acceptedPages, [], kind);
    assert.equal(context.fixture.seen().length, 1, kind);
    assert.equal(context.journal.recover()[0].outcome, 'succeeded', kind);
  }
});

test('current loss after a PullRequest response prevents its dependent physical request', async t => {
  const labels = Array.from({length: 101}, (_, i) => `label-${i}`);
  let current = true;
  const context = await setup(t, world([{number: 7, labels}]), {beforeAuthorize: () => {
    if (!current) throw Object.assign(new Error('ExecutionAuthorizationDenied'), {code: 'ExecutionAuthorizationDenied'});
  }});
  let disclosed = 0;
  const failure = await failed(context.read({chargePage: body => Object.freeze({body}),
    consumeObservation: async () => { await Promise.resolve(); current = false; },
    consumePage: () => { disclosed++; }}));
  assert.equal(failure.code, 'ExecutionAuthorizationDenied');
  assert.deepEqual(failure.acceptedPages, []);
  assert.equal(disclosed, 0);
  assert.equal(context.fixture.seen().length, 1);
});

test('a lost PullRequest nested reply retains its original Unknown use without resend', async t => {
  const labels = Array.from({length: 101}, (_, i) => `label-${i}`);
  const context = await setup(t, world([{number: 7, labels}]), {faults: [{kind: 'lose-reply',
    method: 'POST', pathname: '/graphql', bodyIncludes: 'query ActqlPullRequestLabels('}]});
  let disclosed = 0;
  const failure = await failed(context.read({consumePage: () => { disclosed++; }}));
  assert.equal(failure.stopped, true);
  assert.deepEqual(failure.acceptedPages, []);
  assert.equal(disclosed, 0);
  assert.equal(context.fixture.seen().length, 2);
  const records = context.journal.recover();
  assert.equal(records.length, 2);
  assert.equal(records[1].useId, 'read-0-1');
  assert.equal(records[1].outcome, 'unknown');
});

test('PullRequest original response mutation during accounting is sticky after restored bytes', async t => {
  const context = await setup(t, world([{number: 7}]));
  let response;
  let disclosed = 0;
  const failure = await failed(context.read({callResource: async request => {
    response = await callHttpsCredentialResource(request); return response;
  }, chargePage: async () => {
    await Promise.resolve(); response.body[0] ^= 1;
  }, consumePage: () => { disclosed++; }}));
  assert.equal(failure.code, 'RemoteCredentialRunResponseChanged');
  assert.equal(disclosed, 0);
  assert.equal(context.fixture.seen().length, 1);
  response.body[0] ^= 1;
  assert.throws(() => withHttpsCredentialRunResponseOriginal(response,
    context.credential.control, context.journal, () => {}), {code: 'RemoteCredentialRunResponseChanged'});
});

test('PullRequest filters keep native state distinct and refuse an unsupported since before I/O', async t => {
  const context = await setup(t, world([{number: 1, state: 'CLOSED'}, {number: 2, state: 'MERGED', labels: ['2', 'none']}]));
  await assert.rejects(context.read({filters: {state: 'all', labels: [], since: '2026-10-01T00:00:00Z'}}),
    {code: 'InvalidGitHubReadFilters'});
  assert.equal(context.fixture.seen().length, 0);
  const result = await context.read({filters: {state: 'merged', labels: ['2', 'none']}});
  assert.deepEqual(result.rows, [expected(2, {state: 'merged', labels: ['2', 'none']})]);
  const request = pullRequestReads(context.fixture)[0];
  assert.deepEqual(request.variables.states, ['MERGED']);
  assert.deepEqual(request.variables.labels, ['2', 'none']);
  assert.equal(Object.hasOwn(request.variables, 'since'), false);
});
