// Independent HTTPS fixture tests for GitHub Issue comment creation by node
// ID through the common Effect owner's durable claim. Expectations are
// hand-written from GitHub's GraphQL documentation and the GraphQL
// specification: a reply naming the created comment on exactly the requested
// Issue is success; errors without `data` were raised before execution and
// applied nothing; anything else is unknown and never resent.
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
import {openEffectLedger} from '../../../host-node/effect-ledger.mjs';
import {captureClaimedEffectResponse} from
  '../../../host-node/effect-physical-dispatch.mjs';
import {openHttpsExchangeFixture} from
  '../../../site-node/https-exchange-fixture.mjs';
import {openSqliteCredentialJournal} from
  '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  '../../../site-node/remote-credential-signature.mjs';
import {GITHUB_COMMENT_CREATE_OPERATION, checkGitHubCommentSubject,
  prepareGitHubCommentRequest, projectGitHubCommentObservation,
  sendGitHubIssueComment} from '../site/github-comment-create.mjs';
import {GITHUB_GRAPHQL_READ_OPERATION} from
  '../site/github-issue-graphql-read.mjs';
import {commentSends, graphqlRoute} from './github-graphql.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(commonMoon);
const control = runtime.remoteCredentialControl;
const effects = runtime.effectApplicationControl;
const limits = {maxRequestBytes: 300_000, maxResponseBytes: 100_000,
  maxNodes: 10_000, maxDepth: 32};
const published = {nodeId: 'R_A', databaseId: 1296269,
  nameWithOwner: 'octo/hello'};

// Repository A (published) and B, with an Issue and a pull request in A and
// an Issue in B.
const newWorld = () => ({
  repositories: new Map([
    ['R_A', {databaseId: 1296269, nameWithOwner: 'octo/hello', issues: []}],
    ['R_B', {databaseId: 424242, nameWithOwner: 'octo/other', issues: []}]]),
  names: new Map([['octo/hello', 'R_A'], ['octo/other', 'R_B']]),
  subjects: new Map([
    ['I_A7', {type: 'Issue', repository: 'R_A', number: 7}],
    ['PR_A8', {type: 'PullRequest', repository: 'R_A', number: 8}],
    ['I_B1', {type: 'Issue', repository: 'R_B', number: 1}]]),
  comments: []});

async function setup(t, {world = newWorld(), faults = [], body = 'hello',
  subjectId = 'I_A7'} = {}) {
  const fixture = await openHttpsExchangeFixture(t, {faults,
    routes: [graphqlRoute(() => world)]});
  const root = await mkdtemp(join(tmpdir(), 'actql-github-comment-'));
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['authority-a',
      new Map([['key-a', authority.publicKey]])]]),
  });
  const ledgers = [];
  t.after(async () => {
    for (const ledger of ledgers) ledger.close?.();
    journal.close();
    await rm(root, {recursive: true, force: true});
  });
  let grants = 0;
  // One single-use grant for one operation.
  const authorize = operation => {
    const scope = Object.freeze({
      issuerAuthority: 'authority-a', principal: 'principal-a',
      namespaceId: 'namespace-a', environment: 'production',
      siteKey: 'site-a', siteGeneration: 1, runtimeBundleCid: cid('a'),
      connectorRegistration: 'github', connectorRevision: 'github/0.1',
      resourceOrigin: fixture.origin, operation,
      runInvocationCid: cid('b'), taskAttempt: 1,
      dispatchRequestCid: `sha256:${String(grants++).padStart(64, '0')}`,
      expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 1,
    });
    const grant = control.prepare(scope);
    journal.acceptGrant(signRemoteCredentialGrant(grant, control,
      {keyId: 'key-a', privateKey: authority.privateKey}), control);
    return {grant, scope, useId: `use-${grants}`};
  };
  const credential = {control, journal, resolveSecret: async () => 'token-a',
    ca: fixture.ca, now: () => 1_999_999_999_999};
  const prepare = (text, subject = subjectId) => prepareGitHubCommentRequest(
    {moon, origin: fixture.origin, subjectId: subject, body: text});
  const request = prepare(body);
  const logical = effects.logicalRequestScope(cid('9'), 'request-1', 32);
  const key = effects.dispatchKey(logical, cid('b'), '"row-1"', 32, 8, 3);
  const locator = effects.logicalItemLocator(logical, 'program-1', 'node-1',
    'CommentOne', '{"issue":"I_A7"}', 64, 128, 8, 3);
  // The claim of one row for one exact request.
  const claimFor = requestCid => ({scope: logical, locator, key,
    basis: effects.ledgerBasis(logical, locator, key, cid('c'), cid('d'),
      cid('e'), requestCid, cid('0'), 'unavailable', cid('1'), cid('2')),
    intentFingerprintCid: cid('e'), canonicalRequestCid: requestCid});
  const claim = claimFor(request.requestCid);
  const openLedger = () => {
    const ledger = openEffectLedger({moon: commonMoon, root,
      authorityScopeCid: cid('9'), callerRequestId: 'request-1',
      maxEntryBytes: 4096});
    ledgers.push(ledger);
    return ledger;
  };
  const check = (subject = subjectId) => checkGitHubCommentSubject({moon,
    subjectId: subject, repository: published,
    authorization: authorize(GITHUB_GRAPHQL_READ_OPERATION), credential,
    limits});
  let live;
  const dispatch = (ledger, {sending = request, claimed = claim} = {}) =>
    captureClaimedEffectResponse({ledger, claim: claimed,
      requestCid: sending.requestCid,
      execute: async () => {
        const sent = await sendGitHubIssueComment({moon, request: sending,
          authorization: authorize(GITHUB_COMMENT_CREATE_OPERATION),
          credential, limits});
        live = sent.headers;
        return sent;
      }});
  const project = (observation, headers, subject = subjectId) =>
    projectGitHubCommentObservation({moon, observation, headers, limits,
      subjectId: subject});
  return {fixture, world, journal, request, prepare, claimFor, openLedger,
    check, dispatch, project, live: () => live};
}

const base = {moon, origin: 'https://api.github.com', subjectId: 'I_A7'};

test('the request is the fixed mutation and its identity is the exact bytes',
  () => {
    const first = prepareGitHubCommentRequest({...base, body: 'hello'});
    assert.equal(first.path, '/graphql');
    const sent = JSON.parse(first.body);
    assert.match(sent.query, /^mutation ActqlAddComment\(/u);
    assert.deepEqual(sent.variables, {subjectId: 'I_A7', body: 'hello'});
    assert.equal(prepareGitHubCommentRequest({...base, body: 'hello'})
      .requestCid, first.requestCid);
    assert.notEqual(prepareGitHubCommentRequest({...base, body: 'hello!'})
      .requestCid, first.requestCid);
    assert.notEqual(prepareGitHubCommentRequest({...base, subjectId: 'I_A8',
      body: 'hello'}).requestCid, first.requestCid);
    for (const [left, right] of [['café', 'café'],
      ['line\r\nnext', 'line\nnext'], ['a b', 'a b']]) {
      const a = prepareGitHubCommentRequest({...base, body: left});
      const b = prepareGitHubCommentRequest({...base, body: right});
      assert.notEqual(a.body, b.body);
      assert.notEqual(a.requestCid, b.requestCid, JSON.stringify([left, right]));
      assert.equal(JSON.parse(a.body).variables.body, left);
    }
    for (const invalid of [{body: ''}, {subjectId: ''},
      {origin: 'http://api.github.com'}, {body: 'x'.repeat(65_537)}]) {
      assert.throws(() => prepareGitHubCommentRequest({...base,
        body: 'hello', ...invalid}));
    }
  });

test('only an Issue of the published repository passes the subject check',
  async t => {
    const context = await setup(t);
    assert.deepEqual(await context.check('I_A7'), {nodeId: 'I_A7', number: 7});
    for (const [subject, code] of [
      ['PR_A8', 'GitHubCommentSubjectNotIssue'],
      ['I_B1', 'GitHubCommentForeignRepository'],
      ['I_GONE', 'GitHubCommentSubjectUnavailable'],
    ]) {
      await assert.rejects(context.check(subject), {code}, subject);
    }
    assert.equal(commentSends(context.fixture).length, 0);
  });

test('a created comment is sent once and a retry of the claim does not send again',
  async t => {
    const context = await setup(t);
    await context.check();
    const first = await context.dispatch(context.openLedger());
    assert.equal(first.claimed, true);
    const projected = context.project(first.physical.observation,
      context.live());
    assert.equal(projected.kind, 'typed-success-response');
    assert.deepEqual(projected.result, {commentId: 1000, nodeId: 'IC_1000'});
    assert.deepEqual(context.world.comments, [{subjectId: 'I_A7',
      body: 'hello', databaseId: 1000}]);
    const seen = context.fixture.seen().filter(entry =>
      entry.pathname === '/graphql' &&
      JSON.parse(entry.body).query.startsWith('mutation'));
    assert.equal(seen.length, 1);
    assert.equal(seen[0].headers['x-github-api-version'], '2026-03-10');
    assert.equal(seen[0].headers['user-agent'], 'actql-github-connector/0.1');
    const retry = await context.dispatch(context.openLedger());
    assert.equal(retry.claimed, false);
    assert.equal(commentSends(context.fixture).length, 1);
  });

test('a lost reply leaves a possible dispatch that is never resent', async t => {
  const context = await setup(t, {faults: [{kind: 'lose-reply',
    method: 'POST', pathname: '/graphql'}]});
  await assert.rejects(context.dispatch(context.openLedger()));
  assert.equal(context.journal.recover().at(-1).outcome, 'unknown');
  const retry = await context.dispatch(context.openLedger());
  assert.equal(retry.claimed, false);
  assert.equal(commentSends(context.fixture).length, 1);
});

test('only documented outcomes settle a comment; the rest stay unknown',
  async t => {
    for (const [reply, kind, extra] of [
      [{body: {errors: [{type: 'NOT_FOUND', message: 'x'}]}},
        'typed-failure-response', {errorType: 'NOT_FOUND'}],
      [{body: {data: {addComment: null},
        errors: [{type: 'FORBIDDEN', message: 'x'}]}},
      'unclassified-response'],
      [{body: {errors: [{type: 'RATE_LIMITED', message: 'x'}]}},
        'unclassified-response'],
      // Malformed request errors are not evidence that nothing ran.
      [{body: {errors: [{}]}}, 'unclassified-response'],
      [{body: {errors: [{message: 42}]}}, 'unclassified-response'],
      [{body: {errors: []}}, 'unclassified-response'],
      [{body: {data: null, errors: [{type: 'NOT_FOUND', message: 'x'}]}},
        'unclassified-response'],
      [{body: {data: {addComment: {commentEdge: {node: {id: 'IC_9',
        databaseId: 9}}, subject: {__typename: 'PullRequest',
        id: 'I_A7'}}}}}, 'unclassified-response'],
      [{body: {data: {addComment: {commentEdge: {node: {id: 'IC_9',
        databaseId: 9}}, subject: {__typename: 'Issue', id: 'I_B1'}}}}},
      'unclassified-response'],
      [{status: 403, body: {message: 'Resource not accessible'}},
        'typed-failure-response', {status: 403}],
      [{status: 403, headers: {'retry-after': '60'}, body: {}},
        'provider-response'],
      [{status: 429, body: {}}, 'provider-response'],
      [{status: 502, body: ''}, 'provider-response'],
    ]) {
      const world = {...newWorld(), commentReply: () => reply};
      const context = await setup(t, {world});
      const sent = await context.dispatch(context.openLedger());
      const projected = context.project(sent.physical.observation,
        context.live());
      assert.equal(projected.kind, kind, JSON.stringify(reply));
      for (const [name, value] of Object.entries(extra ?? {})) {
        assert.equal(projected[name], value, JSON.stringify(reply));
      }
      assert.equal(commentSends(context.fixture).length, 1);
    }
  });

test('a recovered 403 without its headers stays unknown', async t => {
  const world = {...newWorld(), commentReply: () => ({status: 403,
    body: {message: 'Resource not accessible'}})};
  const context = await setup(t, {world});
  const sent = await context.dispatch(context.openLedger());
  assert.equal(context.project(sent.physical.observation, undefined).kind,
    'provider-response');
  const created = {data: {addComment: {commentEdge: {node: {id: 'IC_5',
    databaseId: 5}}, subject: {__typename: 'Issue', id: 'I_A7'}}}};
  assert.equal(context.project({...sent.physical.observation,
    statusCode: 200, body: Buffer.from(JSON.stringify(created))}, undefined)
    .kind, 'typed-success-response');
  // The same reply is not a success for another row's subject.
  assert.equal(context.project({...sent.physical.observation,
    statusCode: 200, body: Buffer.from(JSON.stringify(created))}, undefined,
  'I_B1').kind, 'unclassified-response');
});

test('a different body is refused for an existing claim and nothing is sent',
  async t => {
    const context = await setup(t, {body: 'café'});
    const other = context.prepare('café');
    // Presenting another body under this row's claim is refused before any
    // credential use or request.
    await assert.rejects(context.dispatch(context.openLedger(),
      {sending: other}), {code: 'InvalidEffectPhysicalDispatch'});
    assert.equal(commentSends(context.fixture).length, 0);
    // The row's own body is sent once.
    const sent = await context.dispatch(context.openLedger());
    assert.equal(sent.claimed, true);
    assert.deepEqual(commentSends(context.fixture).map(entry =>
      entry.variables), [{subjectId: 'I_A7', body: 'café'}]);
    // A claim of the same row for the other body cannot take its place in
    // the Ledger, and sends nothing.
    await assert.rejects(context.dispatch(context.openLedger(),
      {sending: other, claimed: context.claimFor(other.requestCid)}),
    {code: 'EffectLedgerIntentConflict'});
    assert.equal(commentSends(context.fixture).length, 1);
    // Re-presenting the same body is the same request: no second send.
    const again = await context.dispatch(context.openLedger());
    assert.equal(again.claimed, false);
    assert.equal(commentSends(context.fixture).length, 1);
  });

test('a recovered reply keeps its classification without headers', async t => {
  for (const [body, kind] of [
    [{errors: [{type: 'NOT_FOUND', message: 'x'}]}, 'typed-failure-response'],
    [{errors: [{}]}, 'unclassified-response'],
    [{errors: [{message: 42}]}, 'unclassified-response'],
  ]) {
    const world = {...newWorld(), commentReply: () => ({body})};
    const context = await setup(t, {world});
    const sent = await context.dispatch(context.openLedger());
    const stored = sent.response;
    assert.equal(context.project({useCid: stored.credentialUseCid,
      statusCode: stored.statusCode, body: stored.responseBytes}, undefined)
      .kind, kind, JSON.stringify(body));
  }
});
