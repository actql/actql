// Independent original GitHub Issue boundary cases; expected rows stay local.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import * as moon from '../../../../_build/js/release/build/connectors/github/host_node/host_node.js';
import {callHttpsCredentialResource, withHttpsCredentialRunResponseOriginal} from '../../../site-node/https-credential-resource.mjs';
import {issueReads} from './github-graphql.fixture.mjs';
import {openGitHubReadFixture as setup, accountedGitHubRows as accountedIssueRows} from './github-read.fixture.mjs';

const A = {nodeId: 'R_A', databaseId: 1296269, nameWithOwner: 'octo/hello'};
const issues = count => Array.from({length: count}, (_, index) =>
  ({number: index + 1}));
const row = number => ({number: String(number), node_id: `I_${number}`,
  // GitHub's GraphQL states no body as "", kept exactly as given.
  title: `Issue ${number}`, state: 'open', body: '', author: 'octocat',
  comments: '0', state_reason: null, assignees: [], labels: [],
  url: `https://github.com/octo/hello/issues/${number}`, milestone: null, created_at: '2026-10-01T00:00:00.000Z',
  updated_at: '2026-10-02T00:00:00.000Z', closed_at: null});


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

test('page callbacks reuse the original prefix check across pure codec getters', async t => {
  const context = await setup(t, world());
  const bodies = new Set();
  const prototype = Object.getPrototypeOf(createHash('sha256'));
  const update = prototype.update;
  let checks = 0, bytes = 0, pages = 0;
  const hashes = t.mock.method(prototype, 'update', function (data, ...args) {
    if (bodies.has(data)) { checks++; bytes += data.byteLength; }
    return Reflect.apply(update, this, [data, ...args]);
  });
  const cpu = process.cpuUsage(), started = performance.now();
  let result;
  try {
    result = await context.read({
      callResource: async request => {
        const response = await callHttpsCredentialResource(request);
        bodies.add(response.body);
        return response;
      },
      chargePage: body => Object.freeze({body}),
      consumePage: () => { pages++; },
    });
  } finally { hashes.mock.restore(); }
  const used = process.cpuUsage(cpu);
  t.diagnostic(JSON.stringify({responsePrefixChecks: checks, hashedResponseBytes: bytes,
    elapsedMs: performance.now() - started, cpuUserMs: used.user / 1000,
    cpuSystemMs: used.system / 1000, physicalRequests: context.fixture.seen().length,
    qualification: 'one actual Credential/SQLite/loopback TLS diagnostic; not an ordinary latency distribution'}));
  assert.equal(result.complete, true);
  assert.deepEqual(result.rows, [1, 2, 3, 4, 5].map(row));
  assert.equal(context.fixture.seen().length, 3);
  assert.equal(pages, 3);
  // Count only hashes after the physical response returns to this driver;
  // the Credential Owner already hashed its original receipt before that.
  // Functional and mutation/refusal controls cover admission independently.
  assert.equal(checks, 0, `unchanged original response checks must not rehash bodies: ${checks}`);
  assert.ok(context.journal.recover().every(record => record.outcome === 'succeeded'));
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
  assert.deepEqual(result.rows.map(entry => entry.number), ['1', '2', '3', '4', '5']);
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
        closedAt: null, milestone: null, stateReason: null,
        assignees: {totalCount: 0, pageInfo: {hasNextPage: false, endCursor: null}, nodes: []},
        labels: {totalCount: 0, pageInfo: {hasNextPage: false, endCursor: null}, nodes: []},
        url: 'https://github.com/octo/hello/issues/1'}]}}}}});
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


test('milestone titles survive authorized pages without an API selector', async t => {
  const titles = ['2', '*', 'none', 'null', '', '  release β / 日本語  '];
  const state = world();
  state.repositories.get('R_A').issues = [...titles.map((title, index) => ({
    number: index + 1, milestone: {title, number: 71, databaseId: 805, id: 'M_X'},
  })), {number: 7, milestone: null}];
  const context = await setup(t, state);
  const result = await context.read();
  assert.deepEqual(result.rows.map(row => row.milestone), [...titles, null]);
  const reads = issueReads(context.fixture);
  assert.equal(reads.length, 4);
  for (const request of reads) {
    assert.match(request.query, /milestone \{ title \}/u);
    assert.doesNotMatch(request.query, /\$milestone|milestone\s*:/u);
    assert.equal(Object.hasOwn(request.variables, 'milestone'), false);
  }
});

test('all Issue columns and both child connections complete through separately authorized physical uses', async t => {
  const state = world();
  const assignees = Array.from({length: 101}, (_, index) => index === 100 ? 'user-0' : `user-${index}`);
  const labels = Array.from({length: 101}, (_, index) => index === 100 ? ' é ' : `label-${index}`);
  state.repositories.get('R_A').issues = [{number: 7, stateReason: 'NOT_PLANNED',
    assignees, labels, url: 'https://github.com/octo/hello/issues/7'}];
  const context = await setup(t, state);
  const charged = [];
  const observed = [];
  let published = 0;
  const result = await context.read({
    chargePage: body => {
      const original = Object.freeze({body}); charged.push(original); return original;
    },
    consumeObservation: original => {
      assert.equal(charged.includes(original), true);
      assert.equal(original, charged[observed.length]); observed.push(original);
    },
    consumePage: (rows, page, {charge}) => {
      assert.equal(charge, charged[2]); assert.equal(page, 1);
      assert.deepEqual(rows[0].assignees, assignees);
      assert.deepEqual(rows[0].labels, labels);
      assert.equal(observed.length, 2); published++;
    },
  });
  assert.equal(result.complete, true);
  assert.equal(published, 1);
  assert.equal(charged.length, 3);
  assert.equal(context.fixture.seen().length, 3);
  assert.deepEqual(result.rows, [{...row(7), state_reason: 'not_planned', assignees, labels}]);
  const requests = context.fixture.seen().map(entry => JSON.parse(entry.body));
  assert.deepEqual(requests.map(value => value.variables.id), ['R_A', 'R_A', 'R_A']);
  assert.deepEqual(requests.slice(1).map(value => value.variables.number), [7, 7]);
  assert.match(requests[1].query, /^query ActqlIssueAssignees\(/u);
  assert.match(requests[2].query, /^query ActqlIssueLabels\(/u);
  const records = context.journal.recover();
  assert.equal(records.length, 3);
  assert.deepEqual(records.map(value => value.useId), ['read-0-0', 'read-0-1', 'read-0-2']);
});

test('a child page cannot cross repository Issue update or cursor identity and no partial row is published', async t => {
  for (const change of ['repository', 'issue', 'updated', 'count', 'cursor']) {
    const state = world();
    state.repositories.get('R_A').issues = [{number: 7,
      labels: Array.from({length: 101}, (_, index) => `label-${index}`)}];
    state.childAnswer = (_field, variables) => ({body: {data: {node: {
      __typename: 'Repository', id: 'R_A', databaseId: change === 'repository' ? 424242 : 1296269,
      nameWithOwner: 'octo/hello', issue: {
        id: change === 'issue' ? 'I_foreign' : 'I_7', number: 7,
        updatedAt: change === 'updated' ? '2026-10-03T00:00:00Z' : '2026-10-02T00:00:00Z',
        labels: {totalCount: change === 'count' ? 102 : 101,
          pageInfo: {hasNextPage: change === 'cursor',
            endCursor: change === 'cursor' ? variables.after : null},
          nodes: [{name: 'label-100'}]}}}}}});
    const context = await setup(t, state);
    let published = 0;
    const failure = await stopOf(context.read({consumePage: () => { published++; }}));
    assert.equal(failure.stopped, true, change);
    assert.equal(published, 0, change);
    assert.deepEqual(failure.acceptedPages, [], change);
    assert.equal(context.fixture.seen().length, 2, change);
  }
});

test('nested pages spend the existing request ceiling and current authorization is checked again before send', async t => {
  const state = world();
  state.repositories.get('R_A').issues = [{number: 7,
    labels: Array.from({length: 101}, (_, index) => `label-${index}`)}];
  const bounded = await setup(t, state);
  const failure = await stopOf(bounded.read({limits: {maxPages: 1,
    maxRows: 100, maxBytes: 100_000, maxNodes: 10_000, maxDepth: 32,
    perPage: 100, maxRequestBytes: 16_384}}));
  assert.equal(failure.code, 'GitHubReadPageLimit');
  assert.deepEqual(failure.acceptedPages, []);
  assert.equal(bounded.fixture.seen().length, 1);
  const checks = [];
  const revoked = await setup(t, state, {beforeAuthorize: index => {
    checks.push(index);
    if (index === 1) throw Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied'});
  }});
  const denied = await stopOf(revoked.read());
  assert.equal(denied.code, 'ExecutionAuthorizationDenied');
  assert.deepEqual(checks, [0, 1]);
  assert.equal(revoked.fixture.seen().length, 1);
  assert.equal(revoked.journal.recover().length, 1);
});


// Explicit component reservations exercise the original accounted RowRun;
// they are not the installed Host's normal resource supplier.

test('the same actual accounted RowRun admits child observations then captures exact array and int64 contracts', async t => {
  const state = world();
  const labels = Array.from({length: 101}, (_, index) => `label-${index}`);
  state.repositories.get('R_A').issues = [{number: 7, comments: 2147483647, labels}];
  const context = await setup(t, state, {accounted: true});
  const actualBodies = [];
  const result = await context.read({callResource: async request => {
    const response = await callHttpsCredentialResource(request);
    actualBodies.push(response.body);
    return response;
  }});
  assert.equal(context.rowRun.receivedBytes(), actualBodies.reduce((sum, body) => sum + body.byteLength, 0));
  assert.equal(context.rowRun.transferredBytes(), BigInt(context.rowRun.receivedBytes()));
  assert.equal(actualBodies.length, 2);
  assert.equal(result.rows[0].number, '7');
  assert.equal(result.rows[0].comments, '2147483647');
  assert.deepEqual(result.rows[0].labels, labels);
  assert.deepEqual(context.rowRun.counts(), {charges: 2, observations: 1});
  assert.equal(context.rowRun.finish(), 1);
  assert.equal(context.fixture.seen().length, 2);
});

test('a lost nested reply remains the original unknown use and no complete row or resend is produced', async t => {
  const state = world();
  state.repositories.get('R_A').issues = [{number: 7,
    labels: Array.from({length: 101}, (_, index) => `label-${index}`)}];
  const context = await setup(t, state, {faults: [{kind: 'lose-reply',
    method: 'POST', pathname: '/graphql', bodyIncludes: 'query ActqlIssueLabels('}]});
  let published = 0;
  const failure = await stopOf(context.read({consumePage: () => { published++; }}));
  assert.equal(failure.stopped, true);
  assert.deepEqual(failure.acceptedPages, []);
  assert.equal(published, 0);
  assert.equal(context.fixture.seen().length, 2);
  const records = context.journal.recover();
  assert.equal(records.length, 2);
  assert.equal(records[1].useId, 'read-0-1');
  assert.equal(records[1].outcome, 'unknown');
});

test('current authorization after awaited child consumption still fences the next physical field request', async t => {
  const state = world();
  state.repositories.get('R_A').issues = [{number: 7,
    assignees: Array.from({length: 101}, (_, index) => `user-${index}`),
    labels: Array.from({length: 101}, (_, index) => `label-${index}`)}];
  let current = true;
  const checks = [];
  const context = await setup(t, state, {beforeAuthorize: index => {
    checks.push(index);
    if (!current) throw Object.assign(new Error('ExecutionAuthorizationDenied'),
      {code: 'ExecutionAuthorizationDenied'});
  }});
  const originals = [];
  let published = 0;
  const failure = await stopOf(context.read({
    chargePage: body => { const charge = Object.freeze({body}); originals.push(charge); return charge; },
    consumeObservation: async charge => {
      assert.equal(originals.includes(charge), true);
      if (charge === originals[1]) { await Promise.resolve(); current = false; }
    },
    consumePage: () => { published++; },
  }));
  assert.equal(failure.code, 'ExecutionAuthorizationDenied');
  assert.deepEqual(checks, [0, 1, 2]);
  assert.equal(context.fixture.seen().length, 2);
  assert.equal(published, 0);
});


test('original prefix mutation during awaited accounting or final consumption is sticky and never publishes completion', async t => {
  for (const phase of ['charge', 'observation', 'page']) {
    const state = world();
    state.repositories.get('R_A').issues = [{number: 7,
      labels: Array.from({length: 101}, (_, index) => `label-${index}`)}];
    const context = await setup(t, state);
    const responses = [];
    let published = 0;
    const corrupt = async () => {
      await Promise.resolve();
      responses[0].body[0] ^= 1;
    };
    const failure = await stopOf(context.read({
      callResource: async request => {
        const response = await callHttpsCredentialResource(request);
        responses.push(response); return response;
      },
      chargePage: async body => {
        if (phase === 'charge') await corrupt();
        return Object.freeze({body});
      },
      consumeObservation: async () => { if (phase === 'observation') await corrupt(); },
      consumePage: async () => {
        published++;
        if (phase === 'page') await corrupt();
      },
    }));
    assert.equal(failure.code, 'RemoteCredentialRunResponseChanged', phase);
    assert.equal(failure.stopped, true, phase);
    assert.deepEqual(failure.acceptedPages, [], phase);
    assert.equal(published, phase === 'page' ? 1 : 0, phase);
    assert.equal(context.fixture.seen().length, phase === 'page' ? 2 : 1, phase);
    responses[0].body[0] ^= 1;
    assert.throws(() => withHttpsCredentialRunResponseOriginal(responses[0],
      context.credential.control, context.journal, () => {}),
    {code: 'RemoteCredentialRunResponseChanged'}, phase);
    assert.ok(context.journal.recover().every(record => record.outcome === 'succeeded'), phase);
  }
});

test('copied and another read original responses cannot substitute for this request use before charge', async t => {
  for (const kind of ['copy', 'foreign-read']) {
    const context = await setup(t, world());
    let previous;
    if (kind === 'foreign-read') {
      await context.read({callResource: async request => {
        const response = await callHttpsCredentialResource(request);
        previous ??= response; return response;
      }});
    }
    const sends = context.fixture.seen().length;
    let charged = 0;
    const failure = await stopOf(context.read({
      callResource: async request => {
        const response = await callHttpsCredentialResource(request);
        return kind === 'copy' ? Object.freeze({...response}) : previous;
      },
      chargePage: () => { charged++; },
    }));
    assert.equal(failure.code, kind === 'copy' ?
      'RemoteCredentialRunResponseOriginalUnavailable' : 'GitHubResponseOriginalChanged', kind);
    assert.equal(charged, 0, kind);
    assert.equal(context.fixture.seen().length, sends + 1, kind);
    assert.deepEqual(failure.acceptedPages, [], kind);
  }
});

for (const boundary of ['transport', 'accounting']) {
  test(`queued exchange fulfillment mutation refuses before row disclosure: ${boundary}`, async t => {
    const state = world();
    state.repositories.get('R_A').issues = [{number: 7, title: 'original'}];
    const context = await setup(t, state);
    let original, offset, disclosed = 0;
    const mutate = () => Buffer.from('modified').copy(original.body, offset);
    const failure = await stopOf(context.read({
      callResource: request => ({then(resolve, reject) {
        callHttpsCredentialResource(request).then(response => {
          original = response;
          const at = response.body.indexOf(Buffer.from('"title":"original"'));
          assert(at >= 0);
          offset = at + Buffer.byteLength('"title":"');
          resolve(response);
          // Resolve first: the exchange continuation checks the original,
          // then this queued callback runs before its caller resumes.
          if (boundary === 'transport') queueMicrotask(mutate);
        }).catch(reject);
      }}),
      ...(boundary !== 'accounting' ? {} : {chargePage: () => ({then(resolve) {
        resolve(undefined);
        queueMicrotask(mutate);
      }})}),
      consumePage: () => { disclosed++; },
    }));
    assert.equal(failure?.code, 'RemoteCredentialRunResponseChanged');
    assert.equal(failure.stopped, true);
    assert.equal(disclosed, 0, 'Do not disclose a row parsed from changed original bytes');
    assert.deepEqual(failure.acceptedPages, []);
    assert.equal(context.fixture.seen().length, 1);
    assert.equal(context.journal.recover()[0].outcome, 'succeeded');
    Buffer.from('original').copy(original.body, offset);
    assert.throws(() => withHttpsCredentialRunResponseOriginal(original,
      context.credential.control, context.journal, () => {}),
    {code: 'RemoteCredentialRunResponseChanged'});
  });
}

test('actual RowRun refuses copied foreign reused and observed-only tickets without releasing a row prefix', async t => {
  const first = await accountedIssueRows(() => true);
  const foreign = await accountedIssueRows(() => true);
  t.after(() => { first.close(); foreign.close(); });
  const body = Buffer.from('[]');
  const ticket = first.charge(body);
  assert.throws(() => foreign.page([], 1, {charge: ticket}));
  assert.throws(() => first.page([], 1, {charge: {...ticket}}));
  // Each refusal aborts only its original attempt; fresh attempts cover reuse.
  const observed = await accountedIssueRows(() => true);
  t.after(() => observed.close());
  const observation = observed.charge(body);
  observed.observe(observation);
  assert.throws(() => observed.page([], 1, {charge: observation}));
});


test('cancellation after an actual response retains the original pending or consumed ticket without another send', async t => {
  for (const phase of ['charge', 'observation']) {
    const state = world();
    state.repositories.get('R_A').issues = [{number: 7,
      labels: Array.from({length: 101}, (_, index) => `label-${index}`)}];
    const context = await setup(t, state, {accounted: true});
    const controller = new AbortController();
    const stop = Object.assign(new Error('OriginalReadStopped'), {code: 'OriginalReadStopped'});
    let response;
    let published = 0;
    const failure = await stopOf(context.read({signal: controller.signal,
      callResource: async request => {
        response = await callHttpsCredentialResource(request); return response;
      },
      chargePage: async body => {
        const ticket = context.rowRun.charge(body);
        if (phase === 'charge') { await Promise.resolve(); controller.abort(stop); }
        return ticket;
      },
      consumeObservation: async ticket => {
        context.rowRun.observe(ticket);
        if (phase === 'observation') { await Promise.resolve(); controller.abort(stop); }
      },
      consumePage: () => { published++; },
    }));
    assert.equal(failure.code, stop.code, phase);
    assert.equal(failure.cause, stop, phase);
    assert.deepEqual(failure.acceptedPages, [], phase);
    assert.equal(published, 0, phase);
    assert.equal(context.fixture.seen().length, 1, phase);
    assert.equal(context.journal.recover()[0].outcome, 'succeeded', phase);
    assert.deepEqual(context.rowRun.counts(), {charges: 1,
      observations: phase === 'observation' ? 1 : 0}, phase);
    assert.equal(context.rowRun.transferredBytes(), BigInt(response.body.byteLength), phase);
    withHttpsCredentialRunResponseOriginal(response, context.credential.control,
      context.journal, facts => { assert.equal(facts.response, response); });
  }
});


test('original filter capture refuses non-array labels before I/O and keeps the admitted array snapshot', async t => {
  const context = await setup(t, world());
  for (const labels of ['x', new Set(['x']), {0: 'x', length: 1}, [7]]) {
    await assert.rejects(context.read({filters: {state: 'all', labels}}),
      {code: 'InvalidGitHubReadFilters'});
  }
  assert.equal(context.fixture.seen().length, 0);
  assert.deepEqual(context.journal.recover(), []);
  const labels = [' a ', 'β', ' a '];
  const filters = {state: 'all', labels};
  let captured = false;
  const result = await context.read({filters,
    chargePage: () => {
      if (!captured) { labels.push('changed'); filters.state = 'draft'; captured = true; }
    },
  });
  assert.equal(result.complete, true);
  const requests = issueReads(context.fixture);
  assert.equal(requests.length, 3);
  for (const request of requests) {
    assert.deepEqual(request.variables.labels, [' a ', 'β', ' a ']);
    assert.equal(request.variables.states, null);
  }
});

test('native label snapshot ignores an own slice payload supplier', async t => {
  const context = await setup(t, world());
  const labels = [' original ', 'β', ' original '];
  let sliceCalls = 0;
  labels.slice = () => { sliceCalls += 1; return ['replacement']; };
  const result = await context.read({filters: {state: 'all', labels}});
  assert.equal(result.complete, true);
  assert.equal(sliceCalls, 0);
  const requests = issueReads(context.fixture);
  assert.equal(requests.length, 3);
  for (const request of requests) {
    assert.deepEqual(request.variables.labels, [' original ', 'β', ' original ']);
  }
});

test('native label snapshot cannot hide an invalid member with an own some method', async t => {
  const context = await setup(t, world());
  const labels = ['original', 7];
  let someCalls = 0;
  labels.some = () => { someCalls += 1; return false; };
  await assert.rejects(context.read({filters: {state: 'all', labels}}),
    {code: 'InvalidGitHubReadFilters'});
  assert.equal(someCalls, 0);
  assert.equal(context.fixture.seen().length, 0);
  assert.deepEqual(context.journal.recover(), []);
});

test('native label snapshot validates the single captured value of a changing index getter', async t => {
  const context = await setup(t, world());
  const labels = [];
  let indexReads = 0;
  Object.defineProperty(labels, '0', {get() {
    indexReads += 1;
    return indexReads === 1 ? 'original' : 'replacement';
  }});
  const result = await context.read({filters: {state: 'all', labels}});
  assert.equal(result.complete, true);
  assert.equal(indexReads, 1);
  const requests = issueReads(context.fixture);
  assert.equal(requests.length, 3);
  for (const request of requests) assert.deepEqual(request.variables.labels, ['original']);
});
