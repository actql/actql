import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {sourcefreeFixtureAuthorization} from './fixtures/release-sourcefree-authorization.mjs';
import {auditSequenceTransport} from '../reviews/2026-10-14-sequence-release-matrix/public-audit.mjs';
import {selectReleaseSequenceQueryCases, releaseSequenceSuccessNames,
  releaseSequenceRefusalNames} from './release-sequence-query-cases.mjs';
import {sequenceSourceSuccesses, sequenceSourceRefusals}
  from './fixtures/sequence-source-input.mjs';

test('Sequence retains exact synthetic authorization for its second process', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-sequence-auth-unit-'));
  try {
    for (const mode of ['local', 'https']) {
      const original = await sourcefreeFixtureAuthorization(mode, 'sequence', {directory});
      assert.equal((await stat(join(directory, `sourcefree-sequence-authorization-${mode}.json`))).mode & 0o777, 0o600);
      assert.deepEqual(await sourcefreeFixtureAuthorization(mode, 'sequence', {directory, reopen: true}), original);
      const runner = 'import {createHash} from "node:crypto";' +
        'const {sourcefreeFixtureAuthorization}=await import(process.argv[3]);' +
        'const value=await sourcefreeFixtureAuthorization(process.argv[2],"sequence",' +
        '{directory:process.argv[1],reopen:true});' +
        'console.log(createHash("sha256").update(JSON.stringify(value)).digest("hex"));';
      const observed = execFileSync(process.execPath, ['--input-type=module', '-e', runner,
        directory, mode, new URL('./fixtures/release-sourcefree-authorization.mjs', import.meta.url).href],
      {encoding: 'utf8', timeout: 10000}).trim();
      assert.equal(observed, createHash('sha256').update(JSON.stringify(original)).digest('hex'));
      await assert.rejects(sourcefreeFixtureAuthorization(mode, 'sequence', {directory}), {code: 'EEXIST'});
      await assert.rejects(sourcefreeFixtureAuthorization(mode, 'time-series', {directory, reopen: true}), {code: 'ENOENT'});
    }
  } finally {await rm(directory, {recursive: true});}
});

test('Sequence audit refuses missing rereads and altered original references values schemas or counters', () => {
  // Synthetic reports check the audit, not installed product execution.
  const quiet = {forbiddenProcesses: 0, forbiddenFetches: 0, sourceSecrets: 0};
  const count = acceptedRuns => ({acceptedRuns, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0});
  const completed = sequenceSourceSuccesses.map((item, index) => ({name: item.name,
    ref: {run: index}, submissionRef: {submission: index}, observedResults: structuredClone(item.results),
    beforeSubmit: count(index), beforeRead: count(index + 1), afterReplay: count(index + 1)}));
  const completedRefusals = sequenceSourceRefusals.map((item, index) => ({name: item.name,
    submissionRef: {refusal: index}, outcome: {kind: 'not_accepted', problem: {code: item.expectedCode},
      submissionRef: {refusal: index}}, beforeSubmit: count(18), afterRefusal: count(18)}));
  const report = {mode: 'local', suite: 'sequence', complete: true, actualNormal: 18, actualRefusal: 9,
    expectedSuccessNames: completed.map(item => item.name), successNames: completed.map(item => item.name),
    expectedRefusalNames: completedRefusals.map(item => item.name), refusalNames: completedRefusals.map(item => item.name),
    completed, completedRefusals, providerObservation: quiet,
    freshProcessReread: {mode: 'local', suite: 'sequence', phase: 'fresh-process-reread', complete: true,
      providerObservation: quiet, completed: completed.map(item => ({...item,
        beforeAcceptedRuns: 18, afterAcceptedRuns: 18}))}};
  const audit = auditSequenceTransport(report);
  assert.equal(audit.actualNormal, 18); assert.equal(audit.actualRefusal, 9);
  assert.equal(audit.freshRereadNamedResults, 18);
  for (const change of [r => {delete r.freshProcessReread;},
    r => {r.freshProcessReread.complete = false;},
    r => {r.freshProcessReread.completed.pop();},
    r => {r.freshProcessReread.completed[0].ref = {run: 'new'};},
    r => {r.freshProcessReread.completed[0].submissionRef = {submission: 'new'};},
    r => {r.freshProcessReread.completed[0].afterAcceptedRuns++;},
    r => {r.freshProcessReread.completed[0].observedResults.answer.columns.reverse();},
    r => {r.freshProcessReread.completed[0].observedResults.answer.rows.pop();},
    r => {r.completed[0].afterReplay.acceptedRuns++;},
    r => {r.completedRefusals[0].outcome.problem.code = 'Other';},
    r => {r.providerObservation.sourceSecrets++;}]) {
    const altered = structuredClone(report); change(altered);
    assert.throws(() => auditSequenceTransport(altered));
  }
});

test('release Sequence selects all original 18 normal and 9 refusal inputs without rewriting them', () => {
  const selected = selectReleaseSequenceQueryCases();
  assert.equal(selected.successes.length, 18);
  assert.equal(selected.refusals.length, 9);
  assert.deepEqual(selected.successes.map(value => value.name), releaseSequenceSuccessNames);
  assert.deepEqual(selected.refusals.map(value => value.name), releaseSequenceRefusalNames);
  for (const [kind, original] of [['successes', sequenceSourceSuccesses],
    ['refusals', sequenceSourceRefusals]]) {
    assert.equal(Object.isFrozen(selected[kind]), true);
    for (let index = 0; index < original.length; index++) {
      assert.equal(selected[kind][index], original[index]);
    }
  }
  const nullable = selected.successes.find(value => value.name === 'sequence-json-nullable-case');
  assert.deepEqual(JSON.parse(nullable.text).stages[0].steps[1].sequence.pattern[0].where,
    {case: {when: [{when: {eq: [{field: 'kind'}, {literal: 1}]}, then: {literal: true}}],
      else: {literal: null}}});
  const parameters = selected.successes.find(value => value.name === 'sequence-sql-parameters');
  assert.deepEqual(parameters.parameters, {tag: 1, span: 20, cap: 2});
  assert.deepEqual(parameters.parameterDeclarations, {
    tag: {type: 'number', nullable: false}, span: {type: 'number', nullable: false},
    cap: {type: 'number', nullable: false}});
});

test('release Sequence refuses missing duplicate reordered or extra original cases', () => {
  const alternatives = [sequenceSourceSuccesses.slice(1),
    [sequenceSourceSuccesses[0], ...sequenceSourceSuccesses],
    [...sequenceSourceSuccesses].reverse()];
  for (const successes of alternatives) {
    assert.throws(() => selectReleaseSequenceQueryCases({successes}), {code: 'ERR_ASSERTION'});
  }
  for (const refusals of [sequenceSourceRefusals.slice(1),
    [...sequenceSourceRefusals, {name: 'unrelated-case'}]]) {
    assert.throws(() => selectReleaseSequenceQueryCases({refusals}), {code: 'ERR_ASSERTION'});
  }
});

test('release Sequence cannot quietly substitute a Source-backed acquisition', () => {
  for (const field of ['sourceReadCount', 'sourceReadSessionCount']) {
    const successes = sequenceSourceSuccesses.map((value, index) => index === 0
      ? {...value, [field]: 1} : value);
    assert.throws(() => selectReleaseSequenceQueryCases({successes}), {code: 'ERR_ASSERTION'});
  }
});
