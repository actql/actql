// Independent HTTPS fixture tests for the node-bound GraphQL Issue read.
// Expectations are hand-written from the GitHub GraphQL documentation:
// `node(id:)` resolves the persisted global ID; `errors` (including
// RATE_LIMITED in an HTTP 200) is never a page.
import assert from 'node:assert/strict';
import {generateKeyPairSync, randomUUID} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
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
import {checked} from '../../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {callHttpsCredentialResource, openHttpsCredentialBinding, closeHttpsCredentialBinding} from
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
const row = number => ({number: String(number), node_id: `I_${number}`,
  // GitHub's GraphQL states no body as "", kept exactly as given.
  title: `Issue ${number}`, state: 'open', body: '', author: 'octocat',
  comments: '0', state_reason: null, assignees: [], labels: [],
  url: `https://github.com/octo/hello/issues/${number}`, milestone: null, created_at: '2026-10-01T00:00:00.000Z',
  updated_at: '2026-10-02T00:00:00.000Z', closed_at: null});

async function setup(t, state, {faults = [], beforeAuthorize, accounted = false} = {}) {
  const fixture = await openHttpsExchangeFixture(t, {faults,
    routes: [graphqlRoute(() => state)]});
  const root = await mkdtemp(join(tmpdir(), 'actql-github-graphql-'));
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['authority-a',
      new Map([['key-a', authority.publicKey]])]]),
  });
  let binding;
  let rowRun;
  t.after(async () => {
    if (binding !== undefined) assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    if (rowRun !== undefined) rowRun.close();
    journal.close();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      t.diagnostic(`Retained GitHub GraphQL credential fixture: ${root}`);
    } else await rm(root, {recursive: true, force: true});
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
  const credential = {control, journal, resolveSecret: async () => 'token-a',
    ca: fixture.ca, now: () => 1_999_999_999_999};
  if (accounted) {
    binding = openHttpsCredentialBinding({...credential, scope, maxSecretBytes: 128});
    credential.binding = binding;
    rowRun = await accountedIssueRows(() => closeHttpsCredentialBinding(binding) === 'closed');
  }
  let reads = 0;
  const read = (overrides = {}) => {
    const id = reads++;
    return readGitHubIssuesByNode({moon, repository: A,
      credential,
      callResource: callHttpsCredentialResource,
      authorizationFor: async index => {
        await beforeAuthorize?.(index);
        return {grant, scope, useId: `read-${id}-${index}`};
      },
      limits: {maxPages: 5, maxRows: 100, maxBytes: 100_000,
        maxNodes: 10_000, maxDepth: 32, perPage: 100,
        maxRequestBytes: 16_384},
      ...(rowRun === undefined ? {} : {chargePage: rowRun.charge,
        consumeObservation: rowRun.observe, consumePage: rowRun.page}),
      ...overrides});
  };
  return {fixture, journal, read, rowRun};
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
      assert.notEqual(original, charged[0]); observed.push(original);
    },
    consumePage: (rows, page, {charge}) => {
      assert.equal(charge, charged[0]); assert.equal(page, 1);
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
async function accountedIssueRows(verifyTransport) {
  const read = name => readFile(new URL('../../../../' + name, import.meta.url), 'utf8');
  const declaration = checked(commonMoon.clientProgramRowSourceRestoreRelationDeclaration(
    'gh', 'github', 'github/0.1', await read('src/connectors/github/source-views.json'), undefined));
  const declared = JSON.parse(commonMoon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const check = commonMoon.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  const view = declared.views[0];
  const publication = JSON.stringify({environmentCid: environment.evidenceCid, aliases: [{name: 'gh.issues',
    sourceRef: view.source_ref, sourceViewContractCid: view.view_cid, schemaContractCid: view.carrier_schema_cid}]});
  const preparation = commonMoon.clientProgramPrepareSourceWithParameters(
    'SELECT number, comments, state_reason, assignees, labels, url FROM gh.issues ORDER BY number',
    'sql', check, publication, undefined, undefined);
  const program = commonMoon.clientProgramPreparationReady(preparation);
  assert.ok(program, commonMoon.clientProgramPreparationIssueCode(preparation));
  const aoa = JSON.parse(await read('spec/contracts/actql-aoa.json'));
  const requirement = checked(commonMoon.clientProgramPrepareLocalQueryRequirement(program, 0, 0,
    await read('spec/dependencies/aoa-pipeline-registry.json'), JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  const acquisition = checked(commonMoon.clientProgramRowSourcePrepareAcquisition(declaration, requirement,
    await read('spec/contracts/actql-query-acquisition.json'), await read('spec/contracts/actql-query-process-evidence.json')));
  const ledger = checked(commonMoon.clientProgramAcquisitionLedger(1, 1, 100000n, 100000000n, 100000000n, 0));
  const run = checked(commonMoon.clientProgramRowSourceStartAccounted(acquisition, randomUUID(), verifyTransport,
    ledger, 100000n, 100000n));
  checked(commonMoon.clientProgramRowSourceBegin(run, 100000, 5, 100, undefined));
  let charges = 0;
  let observations = 0;
  return {
    charge: body => { charges++; return checked(commonMoon.clientProgramRowSourceChargePage(run, body)); },
    observe: charge => { observations++; return checked(commonMoon.clientProgramRowSourceConsumeObservationCharge(run, charge)); },
    page: (rows, _page, {charge}) => checked(commonMoon.clientProgramRowSourceAcceptChargedPage(run, charge, Buffer.from(JSON.stringify(rows)))),
    finish() {
      checked(commonMoon.clientProgramRowSourceFinish(run));
      const capture = checked(commonMoon.clientProgramRowSourceCapture(run));
      const source = checked(commonMoon.clientProgramRowSourceCaptureSource(capture));
      const relation = checked(commonMoon.clientProgramIdentifyCapturedSourceRelation(source));
      return commonMoon.clientProgramCapturedSourceRowCount(relation);
    },
    counts: () => ({charges, observations}),
    close() {
      checked(commonMoon.clientProgramRowSourceCloseAccounted(run));
      assert.deepEqual(commonMoon.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
    },
  };
}

test('the same actual accounted RowRun admits child observations then captures exact array and int64 contracts', async t => {
  const state = world();
  const labels = Array.from({length: 101}, (_, index) => `label-${index}`);
  state.repositories.get('R_A').issues = [{number: 7, comments: 2147483647, labels}];
  const context = await setup(t, state, {accounted: true});
  const result = await context.read();
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
      assert.equal(charge, originals[1]);
      await Promise.resolve(); current = false;
    },
    consumePage: () => { published++; },
  }));
  assert.equal(failure.code, 'ExecutionAuthorizationDenied');
  assert.deepEqual(checks, [0, 1, 2]);
  assert.equal(context.fixture.seen().length, 2);
  assert.equal(published, 0);
});
