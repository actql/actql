import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from '../../scripts/actql-spec-family.mjs';
import {prepareClientHostRequest, validClientBody, validNamedSubmissionAttempt,
  validSubmissionAttempt, validSubmissionName} from './index.mjs';

// Literal wire vectors are DATA, not authenticated Journal observations.
const cid = digit => `sha256:${digit.repeat(64)}`;
const connection = {mode: 'remote', owner: 'remote', durability: 'durable', consentRefs: [], runners: []};
const epoch = {version: 'actql-submission-epoch/0.1', authorityScopeCid: cid('a'),
  epochNonce: 'b'.repeat(64), authenticator: 'c'.repeat(64), notBefore: 1000, expiresAt: 2000};
const original = {epoch, nonce: 'original'};
const candidate = {epoch: {...epoch, epochNonce: 'd'.repeat(64),
  notBefore: 2000, expiresAt: 3000}, nonce: 'new-connection-candidate'};
const attemptRef = {operation: 'submit', attemptId: 'this-attempt'};
const intentCid = cid('e');
const requestName = 'same-public-name';
const request = {connection, requestName, submissionRef: candidate, intentCid,
  kind: 'aql', input: {text: 'SELECT 1', format: 'sql'}, parameters: null, attemptRef};
const outcome = {kind: 'ready', submissionRef: original, intentCid,
  admission: {ref: {namespaceId: 'workspace', authorityScopeCid: cid('a'),
    runDefinitionCid: cid('f')}, durability: 'durable', revision: 0}};
const observed = {kind: 'observed', requestName, intentCid, attemptRef, outcome};
const valid = value => validNamedSubmissionAttempt(value, connection, requestName,
  candidate, intentCid, attemptRef);

test('named packet identities pin new projections without changing old submission bodies', () => {
  const registry = JSON.parse(readFileSync(new URL('../../spec/contracts/actql-client-host.json', import.meta.url), 'utf8'));
  for (const [name, digest] of Object.entries({
    submission_name: '2c70e3f78e693a207550d3d6c57cf1a2cb26a5b0f7bcf89fea0044f666a26c4b',
    named_submission_attempt: 'ce219bc256b0f466cef1245d078fdc056d45aaef1293517c3fd58812bb51e5e8',
    submission_ref: '02c0c7d0ab9cd0430cf40a81099389710dd234b4dad33b8d0ae8c1048099bc50',
    submission_outcome: '597313f48866b0c35cce6ff669d0183baa4dc992f8a2d5b3b4f3f42997fea2ff',
    submission_attempt: 'c6a7b7cadbee3d8f8f49bcc56bccbcbd3124f7062cef71100fd35238962b22b2',
    submission_lookup: '0fb021b461a0bf3d0a273d3b3a4bc56747162f88344e770d1f07ab0ee88b2bc5',
  })) assert.equal(machineCid(registry.schemas[name]), `sha256:${digest}`, name);
});

test('named request names retain the bounded original caller-ID string domain', () => {
  for (const value of ['name', 'é'.repeat(128), 'a'.repeat(256), 'with,commas']) {
    assert.equal(validSubmissionName(value), true);
  }
  for (const value of ['', null, false, 1, {}, 'é'.repeat(129), 'a'.repeat(257),
    'e\u0301', '\ud800', 'line\nfeed', '\u0080', '\u007f']) {
    assert.equal(validSubmissionName(value), false);
  }
});

test('named request packets are closed and do not reinterpret old submissions', () => {
  assert.equal(validClientBody('submit-named-intent', request), true);
  for (const options of [{}, {readOnly: true}, {stopBefore: 'commit'},
    {readOnly: true, stopBefore: 'commit'}]) {
    const packet = {...request, ...options};
    assert.deepEqual(prepareClientHostRequest('submit-named-intent', packet).body, packet);
  }
  for (const options of [{readOnly: false}, {readOnly: null}, {stopBefore: null},
    {unresolvedHistory: {}}, {requestId: requestName}, {name: requestName}, {extra: 1}]) {
    assert.equal(prepareClientHostRequest('submit-named-intent', {...request, ...options}), undefined);
  }
  const {requestName: _name, ...old} = request;
  assert.equal(validClientBody('submit-intent', old), true);
  assert.equal(validClientBody('submit-intent', request), false);
  assert.equal(validClientBody('submit-named-intent', old), false);
  const prepared = prepareClientHostRequest('submit-named-intent', request);
  assert.notEqual(prepared.body, request);
  assert.notEqual(prepared.body.submissionRef, request.submissionRef);
  assert.equal(Object.isFrozen(prepared.body.submissionRef), true);
});

test('named observations correlate the original reference without weakening explicit epochs', () => {
  assert.equal(valid(observed), true);
  assert.equal(validSubmissionAttempt({kind: 'recorded', attemptRef, outcome},
    connection, candidate, intentCid, attemptRef), false);
  assert.equal(validSubmissionAttempt({kind: 'recorded', attemptRef, outcome},
    connection, original, intentCid, attemptRef), true);
  for (const changed of [
    {...observed, requestName: 'other'}, {...observed, intentCid: cid('0')},
    {...observed, attemptRef: {...attemptRef, attemptId: 'other'}},
    {...observed, outcome: {...outcome, intentCid: cid('0')}},
    {...observed, outcome: {...outcome, admission: {...outcome.admission,
      ref: {...outcome.admission.ref, authorityScopeCid: cid('0')}}}},
    {...observed, outcome: {...outcome, submissionRef: {...original,
      epoch: {...epoch, authorityScopeCid: cid('0')}}}},
    {...observed, outcome: {...outcome, submissionRef: {...original, extra: true}}},
    {...observed, extra: true},
  ]) assert.equal(valid(changed), false);
});

test('named initial replies validate original check observations rather than dropping them', () => {
  const checkObservation = JSON.parse(readFileSync(new URL('./fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  assert.equal(valid({...observed, outcome: {...outcome, checkObservation}}), true);
  assert.equal(valid({...observed, outcome: {...outcome, checkObservation: {}}}), false);
  assert.equal(valid({...observed, outcome: {...outcome, checkObservation: {
    ...checkObservation, outcome_schema_cid: cid('0')}}}), false);
});

test('named unresolved and refused replies remain distinct from committed original admission', () => {
  const unresolved = {...observed, outcome: {kind: 'unresolvable',
    submissionRef: original, problem: {code: 'OriginalCustodyUnavailable'}}};
  assert.equal(valid(unresolved), true);
  assert.equal(valid({...unresolved, outcome: {...unresolved.outcome, admission: outcome.admission}}), false);
  for (const response of [
    {kind: 'conflict', requestName, intentCid, attemptRef, reason: 'intent'},
    {kind: 'refused', requestName, intentCid, attemptRef,
      guarantee: 'attempt_uncommitted_unconsumed', reason: 'authorization'},
  ]) {
    assert.equal(valid(response), true);
    assert.equal(valid({...response, admission: outcome.admission}), false);
    assert.equal(valid({...response, attemptRef: {...attemptRef, attemptId: 'foreign'}}), false);
  }
  assert.equal(valid({kind: 'refused', requestName, intentCid, attemptRef,
    guarantee: 'never_executed', reason: 'authorization'}), false);
});
