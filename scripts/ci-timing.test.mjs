import assert from 'node:assert/strict';
import test from 'node:test';
import {collectEvidence, formatHuman, parseArguments} from './ci-evidence.mjs';

const repository = 'example/timing';
const prefix = `repos/${repository}/actions/runs`;
const sha = '1234567890123456789012345678901234567890';
const at = seconds => `2026-10-01T00:${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}Z`;
const path = (id, attempt = 1) => `${prefix}/${id}/attempts/${attempt}`;
function run(id, attempt = 1, conclusion = 'success') {
  return {id, run_attempt: attempt, name: 'CI', workflow_id: 12, path: '.github/workflows/ci.yml',
    head_sha: sha, head_branch: 'main', event: 'push', status: conclusion === null ? 'in_progress' : 'completed',
    conclusion, html_url: `https://github.com/${repository}/actions/runs/${id}`, pull_requests: [],
    created_at: at(0), run_started_at: at(10), updated_at: at(200)};
}
function job(id, runId, name, start, end, conclusion = 'success', attempt = 1) {
  return {id, run_id: runId, run_attempt: attempt, head_sha: sha, name,
    status: conclusion === null ? 'in_progress' : 'completed', conclusion,
    created_at: at(10), started_at: at(start), completed_at: end == null ? null : at(end),
    labels: ['ubuntu-24.04', 'x64'], runner_name: `runner-${id}`, runner_group_id: 1, runner_group_name: 'GitHub Actions',
    steps: [{number: 1, name: 'Test', status: conclusion === null ? 'in_progress' : 'completed', conclusion,
      started_at: at(start + 1), completed_at: end == null ? null : at(end - 1)}]};
}
const pages = jobs => [{total_count: jobs.length, jobs: jobs.slice(0, 1)}, {total_count: jobs.length, jobs: jobs.slice(1)}];
function fixture() {
  const data = {};
  for (const id of [10, 20, 30]) {
    data[`${prefix}/${id}`] = run(id);
    data[path(id)] = run(id);
    data[`${path(id)}/jobs?per_page=100`] = pages([
      job(id * 10, id, 'build', 20, id === 20 ? 70 : 60), job(id * 10 + 1, id, 'test', 30, 90),
    ]);
  }
  return data;
}
async function collect(data = fixture(), options = {runs: [10, 20, 30], compare: ['10:1', '20:1', '30:1']}) {
  return collectEvidence({repository, ...options}, async (endpoint, paginate) => {
    assert.ok(Object.hasOwn(data, endpoint), `Unexpected API call: ${endpoint}`);
    assert.equal(paginate, endpoint.includes('?'));
    if (data[endpoint] instanceof Error) throw data[endpoint];
    return structuredClone(data[endpoint]);
  });
}
const row = (report, kind, runId = 10, jobName = null, attempt = 1) => report.timing.measurements.find(item =>
  item.kind === kind && item.runId === runId && item.attempt === attempt && (jobName === null || item.jobName === jobName));

test('hand-authored intervals: overlapping jobs are wall spans, not sums, with paginated identities and endpoints', async () => {
  const report = await collect();
  assert.equal(report.complete, true);
  const attempt = row(report, 'attempt');
  assert.equal(attempt.execution.seconds, 70); // 00:00:20 -> 00:01:30, not 40 + 60.
  assert.equal(attempt.preStart.seconds, 10);
  assert.equal(row(report, 'job', 10, 'build').execution.seconds, 40);
  assert.equal(row(report, 'job', 10, 'build').preStart.seconds, 10);
  assert.equal(row(report, 'step', 10, 'build').execution.seconds, 38);
  assert.equal(attempt.execution.from.endpoint, `${path(10)}/jobs?per_page=100`);
  assert.equal(attempt.execution.from.field, 'jobs[id=100].started_at');
  assert.equal(attempt.execution.to.field, 'jobs[id=101].completed_at');
  assert.deepEqual(attempt.timestamps, {createdAt: at(0), startedAt: at(10), updatedAt: at(200)});
  for (const measurement of report.timing.measurements) {
    assert.equal(measurement.sourceSha, sha);
    assert.equal(measurement.sourceMatch, 'not-selected');
    assert.equal(measurement.event, 'push');
    assert.equal(measurement.workflowId, 12);
    assert.equal(measurement.cacheState, 'unknown');
    assert.ok(measurement.runnerLabels);
  }
  assert.equal(report.timing.longestJobs[0].execution.seconds, 60);
  assert.equal(report.timing.longestSteps[0].execution.seconds, 58);
  const build = report.timing.comparison.groups.find(group => group.dimensions.kind === 'job' && group.dimensions.jobName === 'build');
  assert.equal(build.selectedCount, 3); assert.equal(build.sampleCount, 3);
  assert.equal(build.medianSeconds, 40); assert.equal(build.maximumSeconds, 50);
  assert.match(formatHuman(report), /not proven runner queue/u);
  assert.match(formatHuman(report), /not a job-duration sum/u);
  assert.doesNotThrow(() => JSON.parse(JSON.stringify(report)));
});

test('retries preserve failures, cancellations, skipped and running rows; original creation is not retry queue time', async () => {
  const data = fixture();
  data[`${prefix}/10`] = run(10, 2);
  data[path(10)] = run(10, 1, 'failure');
  data[path(10, 2)] = run(10, 2);
  data[`${path(10)}/jobs?per_page=100`] = pages([
    job(100, 10, 'build', 20, 60, 'failure'), job(101, 10, 'test', 30, 50, 'cancelled'),
    job(102, 10, 'skip', 0, 0, 'skipped'), job(103, 10, 'running', 40, null, null),
  ]);
  data[`${path(10, 2)}/jobs?per_page=100`] = pages([job(110, 10, 'build', 100, 140, 'success', 2)]);
  const report = await collect(data, {runs: [10], compare: ['10:1', '10:2']});
  assert.deepEqual(report.runs[0].attempts.map(item => item.conclusion), ['failure', 'success']);
  assert.equal(row(report, 'job', 10, 'build').execution.seconds, 40);
  assert.equal(row(report, 'job', 10, 'test').execution.seconds, 20);
  assert.equal(row(report, 'job', 10, 'skip').execution.reason, 'skipped-not-executed');
  assert.equal(row(report, 'job', 10, 'running').execution.reason, 'not-completed');
  assert.equal(row(report, 'attempt').execution.seconds, null);
  assert.equal(row(report, 'attempt', 10, null, 2).preStart.reason, 'creation-is-not-retry-admission');
  assert.equal(row(report, 'attempt', 10, null, 2).execution.seconds, 40);
  assert.ok(report.timing.comparison.groups.every(group => group.sampleCount <= 1));
  assert.ok(report.timing.comparison.groups.some(group => group.dimensions.conclusion === 'failure'));
  assert.ok(report.timing.comparison.groups.some(group => group.dimensions.conclusion === 'cancelled'));
  assert.ok(report.timing.comparison.groups.some(group => group.dimensions.conclusion === 'skipped' && group.sampleCount === 0));
});

test('missing, invalid, impossible, timezone-less and reversed timestamps stay unknown; valid fractions work', async () => {
  for (const [value, reason] of [[null, 'missing-timestamp'], ['2026-02-30T00:00:00Z', 'invalid-timestamp'],
    ['2026-10-01', 'invalid-timestamp'], ['2026-10-01T00:00:20', 'invalid-timestamp'], ['bogus', 'invalid-timestamp'],
    [at(70), 'reversed-timestamps']]) {
    const data = fixture(); data[`${path(10)}/jobs?per_page=100`][0].jobs[0].started_at = value;
    const report = await collect(data);
    assert.equal(row(report, 'job', 10, 'build').execution.reason, reason);
    assert.equal(row(report, 'attempt').execution.seconds, null);
  }
  const data = fixture(); const job = data[`${path(10)}/jobs?per_page=100`][0].jobs[0];
  job.started_at = '2026-10-01T00:00:20.1Z'; job.completed_at = '2026-10-01T00:01:00.25Z';
  assert.equal(row(await collect(data), 'job', 10, 'build').execution.seconds, 40.15);
});

test('comparisons are opt-in and split event, attempt, source, configuration, outcomes and incomplete evidence', async () => {
  assert.deepEqual((await collect(fixture(), {runs: [10]})).timing.comparison.groups, []);
  for (const change of [
    data => { data[path(20)].event = 'pull_request'; },
    data => { data[path(20)].head_sha = 'a'.repeat(40); },
    data => { data[path(20)].conclusion = 'failure'; },
    data => { data[`${path(20)}/jobs?per_page=100`][0].jobs[0].labels = ['windows']; },
    data => { data[`${path(20)}/jobs?per_page=100`][0].jobs[0].steps[0].conclusion = 'cancelled'; },
    data => { data[`${path(20)}/jobs?per_page=100`][0].total_count = 3; },
    data => { delete data[`${path(20)}/jobs?per_page=100`][0].jobs[0].steps; },
  ]) {
    const data = fixture(); change(data);
    const report = await collect(data, {runs: [10, 20], compare: ['10:1', '20:1']});
    assert.ok(report.timing.comparison.groups.every(group => group.selectedCount === 1));
  }
});

test('API failures, missing selections and duplicate identities stay explicit and do not become completed samples', async () => {
  const data = fixture();
  data[path(20)] = new Error('gh API HTTP 404');
  data[`${path(30)}/jobs?per_page=100`] = new Error('gh API HTTP 403');
  const report = await collect(data, {runs: [10, 20, 30], compare: ['10:1', '20:1', '30:1', '99:1']});
  assert.equal(report.complete, false);
  assert.deepEqual(report.timing.comparison.unavailable, ['20:1', '99:1']);
  assert.equal(row(report, 'attempt', 30).execution.seconds, null);
  assert.equal(report.errors.length, 2);
  const duplicate = fixture();
  duplicate[`${path(10)}/jobs?per_page=100`][1].jobs[0].id = 100;
  assert.ok((await collect(duplicate)).timing.measurements.filter(item => item.runId === 10).every(item => item.execution.seconds === null));
});

test('strict fixed-run and comparison CLI selection retains existing PR/SHA selection rules', () => {
  assert.deepEqual(parseArguments([repository, '--runs', '10,20', '--compare', '10:1,20:2', '--json']),
    {repository, runs: [10, 20], compare: ['10:1', '20:2'], json: true});
  for (const suffix of [['--runs', '10,10'], ['--runs', '10,'], ['--runs', '0'], ['--runs', '1e3'],
    ['--runs', '9007199254740992'], ['--runs', '10', '--sha', sha], ['--runs', '10', '--pr', '2'],
    ['--runs', '10', '--compare', '10'], ['--runs', '10', '--compare', '10:1,10:1'],
    ['--runs', '10', '--compare', '10:0']]) assert.throws(() => parseArguments([repository, ...suffix]), /Usage/u);
});


test('zoned timestamp offsets represent equivalent instants without normalizing impossible dates', async () => {
  const data = fixture(), item = data[`${path(10)}/jobs?per_page=100`][0].jobs[0];
  item.started_at = '2026-09-30T16:00:20.000-08:00';
  item.completed_at = '2026-10-01T09:01:00+09:00';
  assert.equal(row(await collect(data), 'job', 10, 'build').execution.seconds, 40);
  item.started_at = '2026-02-30T16:00:20.000-08:00';
  assert.equal(row(await collect(data), 'job', 10, 'build').execution.reason, 'invalid-timestamp');
});

test('mismatched attempt identities suppress pre-start arithmetic and retain their raw boundaries', async () => {
  const data = fixture(); data[`${path(10)}/jobs?per_page=100`][0].jobs[0].run_attempt = 2;
  const report = await collect(data), measured = row(report, 'job', 10, 'build');
  for (const name of ['execution', 'preStart', 'sinceAttemptStart']) {
    assert.equal(measured[name].seconds, null);
    assert.equal(measured[name].reason, 'incomplete-or-mismatched-evidence');
  }
  assert.equal(measured.preStart.from.value, at(10));
  assert.equal(row(report, 'attempt').preStart.seconds, null);
});


test('step intervals outside known parent bounds or inside a skipped job stay unknown', async () => {
  const data = fixture(), item = data[`${path(10)}/jobs?per_page=100`][0].jobs[0];
  item.steps[0].completed_at = at(80);
  assert.equal(row(await collect(data), 'step', 10, 'build').execution.reason, 'inconsistent-parent-job');
  item.steps[0].completed_at = at(59); item.conclusion = 'skipped';
  assert.equal(row(await collect(data), 'step', 10, 'build').execution.reason, 'inconsistent-parent-job');
  item.conclusion = null; item.status = 'in_progress'; item.completed_at = null;
  assert.equal(row(await collect(data), 'step', 10, 'build').execution.seconds, 38);
});


test('even-sized comparison median uses both central hand-authored durations', async () => {
  const report = await collect(fixture(), {runs: [10, 20], compare: ['10:1', '20:1']});
  const group = report.timing.comparison.groups.find(item => item.dimensions.kind === 'job' && item.dimensions.jobName === 'build');
  assert.equal(group.sampleCount, 2);
  assert.equal(group.medianSeconds, 45); // (40 + 50) / 2.
  assert.equal(group.maximumSeconds, 50);
});
