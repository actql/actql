// Actual Common/Credential/SQLite/loopback TLS composition. Authority and loans
// are explicit fixtures, not a normal installed Host or resource supplier.
import assert from 'node:assert/strict';
import test from 'node:test';
import {callHttpsCredentialResource, withHttpsCredentialRunResponseOriginal} from
  '../../../site-node/https-credential-resource.mjs';
import {openGitHubReadFixture} from './github-read.fixture.mjs';

const comment = (id, fields = {}) => ({id, nodeId: `IC_${id}`, author: null,
  body: '', createdAt: '2026-10-01T00:00:00Z', updatedAt: '2026-10-02T00:00:00Z', ...fields});
const world = () => ({repositories: new Map([['R_A', {databaseId: 1296269,
  nameWithOwner: 'octo/hello', issues: [{number: 7, id: 'I_original',
    commentRows: [comment('9007199254740993', {author: {login: ' é '}, body: '  é\n é  '}), comment('2')]}],
  pullRequests: [{number: 8, id: 'PR_original', commentRows: [comment('9223372036854775807')]}]}]]),
  names: new Map([['octo/hello', 'R_A']]), pageSize: 1, commentPageSize: 1});
const setup = (t, state, options) => openGitHubReadFixture(t, state,
  {...options, resource: 'issue_comments'});
const failed = promise => promise.then(() => assert.fail('read unexpectedly completed'), error => error);
const row = (id, subject, fields = {}) => ({id, subject_number: subject,
  author: null, body: '', created_at: '2026-10-01T00:00:00.000Z',
  updated_at: '2026-10-02T00:00:00.000Z', ...fields});

test('original Issue and PullRequest comments enter one accounted Source without replacing numeric identity', async t => {
  const context = await setup(t, world(), {accounted: true});
  const bodies = [];
  const result = await context.read({callResource: async request => {
    const response = await callHttpsCredentialResource(request);
    bodies.push(response.body); return response;
  }});
  assert.equal(result.complete, true);
  assert.deepEqual(result.rows, [row('9007199254740993', '7', {author: ' é ', body: '  é\n é  '}),
    row('2', '7'), row('9223372036854775807', '8')]);
  assert.equal(bodies.length, 5);
  assert.equal(context.fixture.seen().length, 5);
  assert.deepEqual(context.rowRun.counts(), {charges: 5, observations: 2});
  assert.equal(context.rowRun.transferredBytes(), BigInt(bodies.reduce((sum, body) => sum + body.byteLength, 0)));
  assert.equal(context.rowRun.finish(), 3);
  const requests = context.fixture.seen().map(entry => JSON.parse(entry.body));
  assert.deepEqual(requests.map(request => request.variables.id), ['R_A', 'I_original', 'I_original', 'R_A', 'PR_original']);
  assert.ok(requests.every(request => !request.query.includes('mutation')));
  const uses = context.journal.recover();
  assert.equal(uses.length, 5);
  assert.ok(uses.every(use => use.outcome === 'succeeded'));
  assert.equal(new Set(uses.map(use => use.useId)).size, 5);
});

test('comment read remains at the published repository after same-name replacement', async t => {
  const state = world();
  state.repositories.set('R_B', {databaseId: 42, nameWithOwner: 'octo/hello',
    issues: [{number: 99, id: 'I_replacement', commentRows: [comment('99')]}], pullRequests: []});
  state.names.set('octo/hello', 'R_B');
  const context = await setup(t, state);
  const result = await context.read();
  assert.deepEqual(result.rows.map(row => row.subject_number), ['7', '7', '8']);
  assert.ok(context.fixture.seen().every(entry => !entry.body.includes('I_replacement')));
});

test('comment read requires original observation accounting and finite subject bounds before I/O', async t => {
  const context = await setup(t, world());
  await assert.rejects(context.read({chargePage: () => ({}), consumePage: () => {}}),
    {code: 'GitHubObservationNotAdmitted'});
  await assert.rejects(context.read({limits: {maxPages: 10, maxRows: 100,
    maxBytes: 100000, maxNodes: 10000, maxDepth: 32, perPage: 100,
    maxRequestBytes: 16384, maxSubjects: 0}}), {code: 'InvalidGitHubReadLimits'});
  assert.equal(context.fixture.seen().length, 0);
  assert.equal(context.journal.recover().length, 0);
});

test('comment read rechecks current authorization between original enumeration and dependent acquisition', async t => {
  const context = await setup(t, world(), {beforeAuthorize: index => {
    if (index === 1) throw Object.assign(new Error('ExecutionAuthorizationDenied'), {code: 'ExecutionAuthorizationDenied'});
  }});
  let disclosed = 0;
  const error = await failed(context.read({consumePage: () => { disclosed++; }}));
  assert.equal(error.code, 'ExecutionAuthorizationDenied');
  assert.deepEqual(error.acceptedPages, []);
  assert.equal(disclosed, 0);
  assert.equal(context.fixture.seen().length, 1);
  assert.equal(context.journal.recover().length, 1);
});

test('comment read retains the original dependent Unknown use without resend or fabricated completion', async t => {
  const context = await setup(t, world(), {faults: [{kind: 'lose-reply', method: 'POST',
    pathname: '/graphql', bodyIncludes: 'query ActqlIssueComments('}]});
  let disclosed = 0;
  const error = await failed(context.read({consumePage: () => { disclosed++; }}));
  assert.equal(error.stopped, true);
  assert.deepEqual(error.acceptedPages, []);
  assert.equal(disclosed, 0);
  assert.equal(context.fixture.seen().length, 2);
  const uses = context.journal.recover();
  assert.equal(uses.length, 2);
  assert.equal(uses.find(use => use.useId === 'read-0-1').outcome, 'unknown');
});

test('comment read cannot disclose after a prior enumeration body changes during the next physical response', async t => {
  const context = await setup(t, world());
  const responses = [];
  let disclosed = 0;
  const error = await failed(context.read({callResource: async request => {
    const response = await callHttpsCredentialResource(request);
    responses.push(response);
    if (responses.length === 2) responses[0].body[0] ^= 1;
    return response;
  }, consumePage: () => { disclosed++; }}));
  assert.equal(error.code, 'RemoteCredentialRunResponseChanged');
  assert.equal(disclosed, 0);
  assert.equal(context.fixture.seen().length, 2);
  responses[0].body[0] ^= 1;
  assert.throws(() => withHttpsCredentialRunResponseOriginal(responses[0],
    context.credential.control, context.journal, () => {}), {code: 'RemoteCredentialRunResponseChanged'});
});


test('comment consumer refusal preserves the accepted original page stop envelope', async t => {
  const context = await setup(t, world(), {accounted: true});
  const cause = new Error('original page consumer refusal');
  const acceptedRows = [];
  const error = await failed(context.read({consumePage: async (rows, page, charge) => {
    if (page === 2) throw cause;
    context.rowRun.page(rows, page, charge);
    acceptedRows.push(...rows);
  }}));
  assert.equal(context.fixture.seen().length, 3);
  assert.deepEqual(acceptedRows, [row('9007199254740993', '7', {author: ' é ', body: '  é\n é  '})]);
  assert.deepEqual(context.rowRun.counts(), {charges: 3, observations: 1});
  assert.equal(context.journal.recover().length, 3);
  assert.ok(context.journal.recover().every(use => use.outcome === 'succeeded'));
  assert.equal(error.stopped, true);
  assert.equal(error.code, 'GitHubPageNotAdmitted');
  assert.equal(error.cause, cause);
  assert.equal(error.complete, undefined);
  assert.deepEqual(error.acceptedPages, [{page: 1,
    useCid: context.journal.recover().find(use => use.useId === 'read-0-1').useCid, rows: 1}]);
  assert.deepEqual(error.unfetched, {after: undefined, page: 2});
});

test('comment enumeration consumer refusal preserves the original stop envelope before dependent send', async t => {
  const context = await setup(t, world(), {accounted: true});
  const cause = new Error('original enumeration consumer refusal');
  let pages = 0;
  const error = await failed(context.read({consumeObservation: async () => { throw cause; },
    consumePage: () => { pages++; }}));
  assert.equal(context.fixture.seen().length, 1);
  assert.equal(pages, 0);
  assert.deepEqual(context.rowRun.counts(), {charges: 1, observations: 0});
  assert.equal(context.journal.recover().length, 1);
  assert.equal(context.journal.recover()[0].outcome, 'succeeded');
  assert.equal(error.stopped, true);
  assert.equal(error.code, 'GitHubObservationNotAdmitted');
  assert.equal(error.cause, cause);
  assert.equal(error.complete, undefined);
  assert.deepEqual(error.acceptedPages, []);
  assert.deepEqual(error.unfetched, {after: undefined, page: 1});
});
