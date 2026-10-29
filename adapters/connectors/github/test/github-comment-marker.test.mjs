// Actual pure provider helpers with an explicit physical encoder port. Tags
// below are fixture DATA, not Core DispatchKey/approval/claim or send evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {GITHUB_COMMENT_STAMP_RECIPE, prepareGitHubCommentLogicalRequest,
  finalizeGitHubCommentRequest, prepareGitHubCommentRequest} from '../site/github-comment-create.mjs';

const origin = 'https://api.github.test', subjectId = 'I_original';
const tag = 'sha256:' + 'a'.repeat(64);
function providerPort(encode) {
  const calls = [];
  const moon = {githubAddCommentRequestJson(subject, body) {
    assert.equal(this, moon); calls.push({subject, body});
    return encode ? encode(subject, body) : JSON.stringify({body: JSON.stringify({
      query: 'fixture addComment', variables: {subjectId: subject, body}})});
  }};
  return {moon, calls};
}

test('Comment logical preparation stays separate and finalizes exact body and original tag DATA', () => {
  const f = providerPort();
  for (const [body, expectedCid] of [
    ['cafe\u0301\r\n東京', 'sha256:a46018b4e159a81fe7ede2dac60002c11a8c52ca8934bafef1942098f37b1508'],
    ['', 'sha256:7808fc3a9dfd5ab825eca4f467ee0418b7aa6caf000b2c4728a107b633fd383f'],
  ]) {
    const before = f.calls.length;
    const logical = prepareGitHubCommentLogicalRequest({origin, subjectId, body});
    assert(Object.isFrozen(logical));
    assert.equal(f.calls.length, before);
    assert.equal(Object.hasOwn(logical, 'body'), false);
    assert.equal(Object.hasOwn(logical, 'requestCid'), false);
    const final = finalizeGitHubCommentRequest({moon: f.moon, request: logical, requestTag: tag});
    assert.equal(f.calls.length, before + 1);
    assert.equal(f.calls.at(-1).body, body + '\n\n<!-- actql:effect:' + tag + ' -->');
    assert.equal(final.logicalBody, body); assert.equal(final.requestTag, tag);
    assert.equal(final.requestCid, expectedCid); assert(Object.isFrozen(final));
    for (const key of Object.keys(logical)) assert.equal(final[key], logical[key]);
    assert.equal(JSON.parse(final.body).variables.body, f.calls.at(-1).body);
    assert.equal(JSON.parse(final.body).variables.subjectId, subjectId);
  }
  assert.deepEqual(GITHUB_COMMENT_STAMP_RECIPE,
    {separator: '\n\n', prefix: '<!-- actql:effect:', suffix: ' -->'});
  assert(Object.isFrozen(GITHUB_COMMENT_STAMP_RECIPE));
});

test('Comment final transport uses the existing provider CID domain for changed bytes', () => {
  const f = providerPort();
  const old = prepareGitHubCommentRequest({moon: f.moon, origin, subjectId, body: 'original'});
  const logical = prepareGitHubCommentLogicalRequest({origin, subjectId, body: 'original'});
  const a = finalizeGitHubCommentRequest({moon: f.moon, request: logical, requestTag: tag});
  const b = finalizeGitHubCommentRequest({moon: f.moon, request: logical,
    requestTag: 'sha256:' + 'b'.repeat(64)});
  assert.notEqual(a.body, old.body); assert.notEqual(a.requestCid, old.requestCid);
  assert.notEqual(a.requestCid, b.requestCid);
  assert.equal(a.logicalBody, b.logicalBody); assert.equal(a.logicalBody, 'original');
  assert.equal(logical.logicalBody, 'original');
  assert.equal(f.calls.length, 3); // One historical physical call, two distinct final bodies.
});

test('Comment marker refuses malformed or missing DATA without invoking an encoder or accessor', () => {
  const f = providerPort();
  const logical = prepareGitHubCommentLogicalRequest({origin, subjectId, body: 'original'});
  for (const requestTag of [undefined, '', 'original', {scope: tag}, 'SHA256:' + 'a'.repeat(64)]) {
    assert.throws(() => finalizeGitHubCommentRequest({moon: f.moon, request: logical, requestTag}),
      {code: 'InvalidGitHubCommentRequest'});
  }
  for (const body of [undefined, null, '\ud800']) {
    assert.throws(() => prepareGitHubCommentLogicalRequest({origin, subjectId, body}),
      {code: 'InvalidGitHubCommentRequest'});
  }
  for (const changed of [{...logical, method: 'PUT'}, {...logical, path: '/other'},
    {...logical, requestCid: tag}, {...logical, version: 'foreign'}]) {
    assert.throws(() => finalizeGitHubCommentRequest({moon: f.moon, request: changed, requestTag: tag}),
      {code: 'InvalidGitHubCommentRequest'});
  }
  let getters = 0;
  const changed = {...logical};
  Object.defineProperty(changed, 'logicalBody', {enumerable: true, get() {getters++; return 'foreign';}});
  assert.throws(() => finalizeGitHubCommentRequest({moon: f.moon, request: changed, requestTag: tag}),
    {code: 'InvalidGitHubCommentRequest'});
  assert.equal(getters, 0); assert.equal(f.calls.length, 0);
});

test('Comment physical admission failure remains failure and final data cannot be treated as logical input', () => {
  const logical = prepareGitHubCommentLogicalRequest({origin, subjectId, body: 'original'});
  const cause = new Error('same original physical encoder failure');
  const throwing = providerPort(() => {throw cause;});
  assert.throws(() => finalizeGitHubCommentRequest({moon: throwing.moon, request: logical, requestTag: tag}),
    error => error === cause);
  const refusing = providerPort(() => JSON.stringify({refused: 'InvalidBody'}));
  assert.throws(() => finalizeGitHubCommentRequest({moon: refusing.moon, request: logical, requestTag: tag}),
    error => error.code === 'InvalidGitHubCommentRequest' && error.refusal === 'InvalidBody');
  const f = providerPort(), final = finalizeGitHubCommentRequest({moon: f.moon, request: logical, requestTag: tag});
  assert.throws(() => finalizeGitHubCommentRequest({moon: f.moon, request: final, requestTag: tag}),
    {code: 'InvalidGitHubCommentRequest'});
  assert.equal(f.calls.length, 1);
  assert.equal(Object.hasOwn(final, 'outcome'), false);
});
