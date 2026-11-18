import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {checkedRequestProgramPreparation, requestProgramPreparationProblemCode,
  requestProgramPreparationRefusalCode} from './client-program-preparation.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';

const problemCode = 'ClientProgramTimestampPatternInvalid';
// An explicit audience-bound report port isolates disclosure from the original
// typed cause. The actual Request/parser test owns that cause qualification.
const invalid = JSON.parse(await readFile(new URL(
  '../../packages/client-wire/fixtures/check-default-type.invalid.json', import.meta.url), 'utf8'));
function originalRefusal(category = problemCode) {
  const issue = {}, result = {$tag: 0, _0: issue};
  let calls = 0;
  try {
    checkedRequestProgramPreparation({clientProgramRequestPreparationIssueCode(actual) {
      assert.strictEqual(actual, result); calls++; return category;
    }}, result);
    assert.fail('The original typed refusal must throw');
  } catch (error) {return {error, issue, calls};}
}

test('timestamp pattern cause uses one original projection and cannot be copied or changed', () => {
  const {error, issue, calls} = originalRefusal();
  assert.equal(calls, 1); assert.equal(error.code, 'ClientProgramInvalidInput');
  assert.strictEqual(error.cause, issue);
  error.code = 'ClientProgramRejected'; error.problemCode = 'forged';
  assert.equal(requestProgramPreparationProblemCode(error), problemCode);
  assert.equal(requestProgramPreparationRefusalCode(error), 'ClientProgramInvalidInput');
  for (const foreign of [null, undefined, {}, {...error}, structuredClone(error),
    Object.assign(Error('untyped Host failure'), {code: problemCode, cause: issue})]) {
    assert.equal(requestProgramPreparationProblemCode(foreign), undefined);
    assert.equal(requestProgramPreparationRefusalCode(foreign), undefined);
  }
});

function serviceFixture({phase = 'not_accepted', available = true, changeAudience = false,
  category = problemCode, source: suppliedSource} = {}) {
  const {error} = originalRefusal(category);
  error.code = 'ClientProgramRejected'; // The nominal refusal remains invalid input.
  const scope = {authorityScopeCid: 'sha256:' + 'a'.repeat(64), namespaceId: 'timestamp'};
  const submissionRef = {epoch: {version: 'actql-submission-epoch/0.1',
    authorityScopeCid: scope.authorityScopeCid, epochNonce: 'b'.repeat(64),
    notBefore: 1, expiresAt: 2, authenticator: 'c'.repeat(64)}, nonce: 'original'};
  const intentCid = 'sha256:' + 'd'.repeat(64), input = Object.freeze({original: 'typed intent'});
  const source = suppliedSource ?? {kind: 'aql', input: {format: 'sql',
    text: "SELECT PARSE_TIMESTAMP('%Y', '2026') AS x"}, parameters: null};
  const body = {principalId: 'original', connection: {}, submissionRef, intentCid, ...source};
  const wire = JSON.stringify(source), events = [];
  let retained, authorized = true, preparations = 0, submissions = 0, observations = 0, checks = 0, writes = 0;
  const sameRef = actual => assert.deepEqual(actual, submissionRef);
  const service = installNodeClientSubmission({
    authorizedScope() {
      if (!authorized) return undefined;
      return changeAudience && observations > 0 ? {...scope, namespaceId: 'changed'} : scope;
    },
    prepareSubmit() {preparations++; if (phase === 'not_accepted') throw error; return {};},
    submit() {submissions++; throw error;},
    lookupRequest() {return {kind: 'not_found'};},
    observeOriginalPreparationFailure(actual) {
      assert.strictEqual(actual, error); observations++; events.push('original');
      return available ? invalid : undefined;
    },
    checkSubmissionInput() {checks++; return available ? invalid : undefined;},
    moon: {
      clientSubmittedIntent(actual) {assert.deepEqual(JSON.parse(actual), source); return input;},
      clientSubmittedIntentCid(actual) {assert.strictEqual(actual, input); return intentCid;},
      clientSubmittedIntentWire(actual) {assert.strictEqual(actual, input); return wire;},
    },
    journal: {
      checkSubmittedIntent(ref, actual) {sameRef(ref); assert.strictEqual(actual, input);},
      lookupSubmittedIntent(ref) {sameRef(ref); return retained;},
      verifySubmissionEpoch() {return {validity: 'admissible'};},
      submissionIdentity() {return {requestId: 'original-request'};},
      recordSubmittedIntent(ref, actual, fields) {
        sameRef(ref); assert.strictEqual(actual, input); writes++; events.push('record');
        retained = {submissionRef: ref, intentCid, intentWire: wire, phase: fields.phase ?? 'preparing',
          requestId: 'original-request', revision: 1, outcome: fields.outcome};
        assert.equal(retained.outcome?.checkObservation, undefined);
        return retained;
      },
      completeSubmittedIntent(ref, outcome) {
        sameRef(ref); assert.equal(outcome.checkObservation, undefined); writes++;
        retained = {...retained, phase: outcome.kind, revision: retained.revision + 1, outcome};
        return retained;
      },
    },
  });
  return {events, submit: () => service.submitIntent(body),
    lookup: () => service.lookupSubmission({principalId: body.principalId, connection: body.connection, submissionRef}),
    deny() {authorized = false;}, counts: () => ({preparations, submissions, observations, checks, writes})};
}

for (const phase of ['not_accepted', 'preparation_failed']) {
  test(`timestamp pattern ${phase} preserves original identity and current disclosure without resubmission`, async () => {
    const f = serviceFixture({phase}), first = await f.submit();
    assert.equal(first.kind, phase);
    assert.deepEqual(first.problem, {code: problemCode, classification: 'invalid_input'});
    if (phase === 'not_accepted') {
      assert.strictEqual(first.checkObservation, invalid);
      assert.ok(f.events.indexOf('original') < f.events.indexOf('record'));
      assert.ok(f.events.lastIndexOf('original') > f.events.indexOf('record'));
      assert.deepEqual(f.counts(), {preparations: 1, submissions: 0, observations: 2, checks: 0, writes: 1});
    }
    const before = f.counts(), saved = await f.lookup();
    const {checkObservation, ...facts} = first; void checkObservation;
    assert.deepEqual(saved, facts); assert.equal(saved.checkObservation, undefined);
    assert.deepEqual(f.counts(), {...before, checks: before.checks + 1});
    f.deny(); await assert.rejects(f.lookup(), {code: 'ClientRequestLookupDenied'});
  });
}

test('timestamp pattern unavailable original disclosure stays coarse without a semantic recheck', async () => {
  const f = serviceFixture({available: false}), first = await f.submit();
  assert.deepEqual(first.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'});
  assert.equal(first.checkObservation, undefined);
  assert.deepEqual(f.counts(), {preparations: 1, submissions: 0, observations: 2, checks: 0, writes: 1});
  assert.deepEqual(await f.lookup(), first);
});

test('timestamp pattern audience change refuses before the first durable outcome', async () => {
  const f = serviceFixture({changeAudience: true});
  await assert.rejects(f.submit(), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts(), {preparations: 1, submissions: 0, observations: 1, checks: 0, writes: 0});
});


const collectionCauses = [
  ['ClientProgramAggregateOrderRequired', 'ClientProgramInvalidInput', 'invalid_input',
    "SELECT STRING_AGG(s, ',') AS x FROM t"],
  ['ClientProgramOrderUnresolved', 'ClientProgramRejected', 'operation_failed',
    'SELECT ARRAY_AGG(n ORDER BY n) AS x FROM t'],
];
const collectionInput = text => ({kind: 'aql', input: {format: 'sql', text:
  "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) " + text}, parameters: null});

test('collection causes retain their distinct original refusal categories without copied authority', () => {
  for (const [category, outer] of collectionCauses) {
    const {error, issue, calls} = originalRefusal(category);
    assert.equal(calls, 1); assert.equal(error.code, outer); assert.strictEqual(error.cause, issue);
    error.code = 'ClientProgramNeedsInputs'; error.problemCode = 'forged';
    assert.equal(requestProgramPreparationProblemCode(error), category);
    assert.equal(requestProgramPreparationRefusalCode(error), outer);
    for (const foreign of [{...error}, structuredClone(error), Object.assign(Error(category), {code: category})]) {
      assert.equal(requestProgramPreparationProblemCode(foreign), undefined);
      assert.equal(requestProgramPreparationRefusalCode(foreign), undefined);
    }
  }
});

for (const [category, , classification, sql] of collectionCauses) {
  for (const phase of ['not_accepted', 'preparation_failed']) {
    test(`collection original ${category} preserves ${phase}, current disclosure and retained identity`, async () => {
      const f = serviceFixture({category, phase, source: collectionInput(sql)}), first = await f.submit();
      assert.equal(first.kind, phase);
      assert.deepEqual(first.problem, {code: category, classification});
      if (phase === 'not_accepted') {
        assert.deepEqual(f.counts(), {preparations: 1, submissions: 0, observations: 2, checks: 0, writes: 1});
        assert.ok(f.events.indexOf('original') < f.events.indexOf('record'));
        assert.ok(f.events.lastIndexOf('original') > f.events.indexOf('record'));
      }
      const before = f.counts(), saved = await f.lookup();
      const {checkObservation, ...facts} = first; void checkObservation;
      assert.deepEqual(saved, facts); assert.equal(saved.checkObservation, undefined);
      assert.deepEqual(f.counts(), {...before, checks: before.checks + 1});
      f.deny(); await assert.rejects(f.lookup(), {code: 'ClientRequestLookupDenied'});
    });
  }
}

test('collection unavailable original disclosure cannot reveal either specific order cause', async () => {
  for (const [category, , , sql] of collectionCauses) {
    const f = serviceFixture({category, available: false, source: collectionInput(sql)}), first = await f.submit();
    assert.deepEqual(first.problem, {code: 'ClientProgramRejected', classification: 'operation_failed'});
    assert.equal(first.checkObservation, undefined);
    assert.deepEqual(f.counts(), {preparations: 1, submissions: 0, observations: 2, checks: 0, writes: 1});
    assert.deepEqual(await f.lookup(), first);
  }
});
