// Independent HTTPS fixture tests for GitHub comment creation through the
// common Effect owner's durable claim. Expectations are hand-written from the
// GitHub REST documentation (2026-03-10): 201 with the created comment is
// success; documented refusals create nothing; anything else is unknown.
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
import {GITHUB_COMMENT_CREATE_OPERATION, prepareGitHubCommentRequest,
  projectGitHubCommentObservation, sendGitHubIssueComment} from
  '../site/github-comment-create.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(commonMoon);
const control = runtime.remoteCredentialControl;
const effects = runtime.effectApplicationControl;
const path = '/repos/octo/hello/issues/7/comments';
const created = {id: 42, node_id: 'IC_42', body: 'hello',
  user: {login: 'octo'}, created_at: '2026-10-04T00:00:00Z'};
const limits = {maxRequestBytes: 65_536, maxResponseBytes: 100_000};

async function setup(t, {reply = () => ({status: 201, body: created}),
  faults = []} = {}) {
  const fixture = await openHttpsExchangeFixture(t, {faults,
    routes: [{method: 'POST', pathname: path, handle: reply}]});
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
  const scope = Object.freeze({
    issuerAuthority: 'authority-a', principal: 'principal-a',
    namespaceId: 'namespace-a', environment: 'production', siteKey: 'site-a',
    siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'github', connectorRevision: 'github/0.1',
    resourceOrigin: fixture.origin, operation: GITHUB_COMMENT_CREATE_OPERATION,
    runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 1,
  });
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {keyId: 'key-a', privateKey: authority.privateKey}), control);
  const request = prepareGitHubCommentRequest({origin: fixture.origin,
    owner: 'octo', repo: 'hello', issueNumber: 7, body: 'hello'});
  const logical = effects.logicalRequestScope(cid('9'), 'request-1', 32);
  const key = effects.dispatchKey(logical, cid('b'), '"row-1"', 32, 8, 3);
  const locator = effects.logicalItemLocator(logical, 'program-1', 'node-1',
    'CommentOne', '{"issue":7}', 64, 128, 8, 3);
  const claim = {scope: logical, locator, key,
    basis: effects.ledgerBasis(logical, locator, key, cid('c'), cid('d'),
      cid('e'), request.requestCid, cid('0'), 'unavailable', cid('1'),
      cid('2')),
    intentFingerprintCid: cid('e'), canonicalRequestCid: request.requestCid};
  const openLedger = () => {
    const ledger = openEffectLedger({moon: commonMoon, root,
      authorityScopeCid: cid('9'), callerRequestId: 'request-1',
      maxEntryBytes: 4096});
    ledgers.push(ledger);
    return ledger;
  };
  let live;
  const dispatch = ledger => captureClaimedEffectResponse({ledger, claim,
    requestCid: request.requestCid,
    execute: async () => {
      const sent = await sendGitHubIssueComment({moon, request,
        authorization: {grant, scope, useId: 'comment-1'},
        credential: {control, journal, resolveSecret: async () => 'token-a',
          ca: fixture.ca, now: () => 1_999_999_999_999}, limits});
      live = sent.headers;
      return sent;
    }});
  const project = (observation, headers) => projectGitHubCommentObservation({
    moon, observation, headers, maxResponseBytes: limits.maxResponseBytes});
  return {fixture, journal, request, openLedger, dispatch, project,
    live: () => live};
}

const posts = fixture => fixture.seen().filter(entry => entry.method === 'POST');

test('the request identity is exact and changes with the comment body', () => {
  const base = {origin: 'https://api.github.com', owner: 'octo',
    repo: 'hello', issueNumber: 7, body: 'hello'};
  const first = prepareGitHubCommentRequest(base);
  assert.equal(first.path, '/repos/octo/hello/issues/7/comments');
  assert.equal(first.body, '{"body":"hello"}');
  assert.equal(prepareGitHubCommentRequest(base).requestCid, first.requestCid);
  assert.notEqual(prepareGitHubCommentRequest({...base, body: 'hello!'})
    .requestCid, first.requestCid);
  for (const invalid of [{issueNumber: 0}, {body: ''}, {owner: '..'},
    {origin: 'http://api.github.com'}]) {
    assert.throws(() => prepareGitHubCommentRequest({...base, ...invalid}));
  }
});

test('a created comment is sent once and a retry of the claim does not send again',
  async t => {
    const context = await setup(t);
    const first = await context.dispatch(context.openLedger());
    assert.equal(first.claimed, true);
    const projected = context.project(first.physical.observation,
      context.live());
    assert.equal(projected.kind, 'typed-success-response');
    assert.deepEqual(projected.result, {commentId: 42, nodeId: 'IC_42'});
    const seen = posts(context.fixture);
    assert.equal(seen.length, 1);
    assert.equal(seen[0].body, '{"body":"hello"}');
    assert.equal(seen[0].headers['x-github-api-version'], '2026-03-10');
    assert.equal(seen[0].headers['user-agent'], 'actql-github-connector/0.1');
    const retry = await context.dispatch(context.openLedger());
    assert.equal(retry.claimed, false);
    assert.equal(posts(context.fixture).length, 1);
  });

test('a lost reply leaves a possible dispatch that is never resent', async t => {
  const context = await setup(t, {faults: [{kind: 'lose-reply',
    method: 'POST', pathname: path}]});
  await assert.rejects(context.dispatch(context.openLedger()));
  assert.equal(context.journal.recover().at(-1).outcome, 'unknown');
  const retry = await context.dispatch(context.openLedger());
  assert.equal(retry.claimed, false);
  assert.equal(posts(context.fixture).length, 1);
});

test('only documented refusals settle a failure; rate limits stay unknown',
  async t => {
    for (const [reply, kind] of [
      [{status: 422, body: {message: 'Validation Failed'}},
        'typed-failure-response'],
      [{status: 404, body: {message: 'Not Found'}}, 'typed-failure-response'],
      [{status: 403, body: {message: 'Resource not accessible'}},
        'typed-failure-response'],
      [{status: 403, headers: {'retry-after': '60'}, body: {}},
        'provider-response'],
      [{status: 429, body: {}}, 'provider-response'],
      [{status: 502, body: ''}, 'provider-response'],
      [{status: 201, body: {id: 42}}, 'unclassified-response'],
    ]) {
      const context = await setup(t, {reply: () => reply});
      const sent = await context.dispatch(context.openLedger());
      assert.equal(context.project(sent.physical.observation, context.live())
        .kind, kind, JSON.stringify(reply));
      assert.equal(posts(context.fixture).length, 1);
    }
  });

test('a recovered 403 without its headers stays unknown', async t => {
  const context = await setup(t, {reply: () => ({status: 403,
    body: {message: 'Resource not accessible'}})});
  const sent = await context.dispatch(context.openLedger());
  assert.equal(context.project(sent.physical.observation, undefined).kind,
    'provider-response');
  assert.equal(context.project({...sent.physical.observation,
    statusCode: 201, body: Buffer.from(JSON.stringify(created))}, undefined)
    .kind, 'typed-success-response');
});
