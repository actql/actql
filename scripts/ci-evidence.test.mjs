import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {delimiter, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {collectEvidence, formatHuman, parseArguments} from './ci-evidence.mjs';

const repository = 'example/project';
const prefix = `repos/${repository}`;
const head = '1111111111111111111111111111111111111111';
const stale = '2222222222222222222222222222222222222222';
const merge = '3333333333333333333333333333333333333333';
const base = '4444444444444444444444444444444444444444';
const headRuns = `${prefix}/actions/runs?head_sha=${head}&per_page=100`;
const branchRuns = `${prefix}/actions/runs?branch=feature%2Fone&per_page=100`;
const mergeRuns = `${prefix}/actions/runs?head_sha=${merge}&per_page=100`;
const protection = `${prefix}/branches/main/protection`;
const rules = `${prefix}/rules/branches/main?per_page=100`;
const attemptPath = (id, number) => `${prefix}/actions/runs/${id}/attempts/${number}`;
const jobsPath = (id, number) => `${attemptPath(id, number)}/jobs?per_page=100`;

// Hand-authored REST response fixtures. Expected values never come from the
// helper under test; the fixture only fills repeated API envelope fields.
function run(id, event, sha, attempt, conclusion) {
  return {id, name: 'CI', path: '.github/workflows/ci.yml', event,
    head_sha: sha, head_branch: 'feature/one', run_attempt: attempt,
    status: conclusion === null ? 'in_progress' : 'completed', conclusion,
    html_url: `https://github.com/example/project/actions/runs/${id}`,
    pull_requests: event === 'pull_request' ? [{number: 7, head: {sha}, base: {sha: base}}] : []};
}
function job(id, runId, attempt, sha, conclusion) {
  return {id, name: `job-${id}`, run_id: runId, run_attempt: attempt, head_sha: sha,
    status: conclusion === null ? 'queued' : 'completed', conclusion,
    html_url: `https://github.com/example/project/actions/runs/${runId}/job/${id}`};
}
function collection(key, rows) { return [{total_count: rows.length, [key]: rows}]; }
function fixture() {
  const push = run(10, 'push', head, 1, 'success');
  const prFailure = run(11, 'pull_request', head, 1, 'failure');
  const old = run(12, 'pull_request', stale, 1, 'success');
  const retry = run(13, 'pull_request', head, 2, 'success');
  const merged = run(14, 'pull_request', merge, 1, 'success');
  merged.pull_requests[0].head.sha = head;
  const data = {
    [prefix]: {default_branch: 'main'},
    [`${prefix}/branches/main`]: {name: 'main', commit: {sha: base}},
    [`${prefix}/pulls/7/reviews?per_page=100`]: [[]],
    [`${prefix}/git/commits/${base}`]: {sha: base, tree: {sha: base}, parents: []},
    [`${prefix}/git/commits/${head}`]: {sha: head, tree: {sha: head}, parents: [{sha: base}]},
    [`${prefix}/git/commits/${merge}`]: {sha: merge, tree: {sha: merge}, parents: [{sha: base}, {sha: head}]},
    [`${prefix}/compare/${head}...${base}`]: {status: 'behind', base_commit: {sha: head}, merge_base_commit: {sha: base}},
    [`${prefix}/pulls/7`]: {number: 7, state: 'open', draft: false, merged: false, mergeable: null, mergeable_state: 'unknown', head: {sha: head, ref: 'feature/one', repo: {full_name: repository}},
      base: {sha: base, ref: 'main'}, merge_commit_sha: merge, html_url: 'https://github.com/example/project/pull/7'},
    [`${prefix}/git/ref/pull/7/merge`]: {ref: 'refs/pull/7/merge', object: {sha: merge}},
    [protection]: {required_status_checks: {strict: true, contexts: ['build'], checks: [{context: 'build', app_id: 42}]}},
    [rules]: [[{type: 'required_status_checks', parameters: {
      required_status_checks: [{context: 'security', integration_id: 8}]}}]],
    [headRuns]: collection('workflow_runs', [push, prFailure, retry]),
    [branchRuns]: [
      {total_count: 5, workflow_runs: [push, prFailure]},
      {total_count: 5, workflow_runs: [old, retry, merged]},
    ],
    [mergeRuns]: collection('workflow_runs', [merged]),
  };
  for (const item of [push, prFailure, old, retry, merged]) {
    data[attemptPath(item.id, item.run_attempt)] = item;
    data[jobsPath(item.id, item.run_attempt)] = collection('jobs', [job(item.id * 10, item.id, item.run_attempt, item.head_sha, item.conclusion)]);
  }
  data[attemptPath(13, 1)] = run(13, 'pull_request', head, 1, 'failure');
  data[jobsPath(13, 1)] = collection('jobs', [job(129, 13, 1, head, 'failure')]);
  // These are different jobs/attempts, never a combined successful run.
  data[jobsPath(13, 2)] = [
    {total_count: 5, jobs: [job(130, 13, 2, head, 'success'), job(131, 13, 2, head, 'skipped')]},
    {total_count: 5, jobs: [job(132, 13, 2, head, 'cancelled'), job(133, 13, 2, head, null), job(134, 13, 2, head, 'neutral')]},
  ];
  for (const sha of [head, merge]) {
    data[`${prefix}/commits/${sha}/check-runs?filter=all&per_page=100`] = collection('check_runs', []);
    data[`${prefix}/commits/${sha}/statuses?per_page=100`] = [[]];
  }
  return data;
}
function reader(data, calls = []) {
  return async (endpoint, paginate) => {
    calls.push({endpoint, paginate});
    assert.ok(Object.hasOwn(data, endpoint), `Unexpected API call: ${endpoint}`);
    const value = data[endpoint];
    if (value?.error) throw new Error(value.error);
    return structuredClone(value);
  };
}
const collect = data => collectEvidence({repository, pr: 7}, reader(data));

test('green push and red PR remain separate with stale sources, merge ref and all retry attempts', async () => {
  const calls = [];
  const report = await collectEvidence({repository, pr: 7}, reader(fixture(), calls));
  assert.equal(report.complete, true);
  assert.equal(report.runs.length, 5);
  assert.equal(report.runs[0].attempts[0].event, 'push');
  assert.equal(report.runs[0].attempts[0].conclusion, 'success');
  assert.equal(report.runs[1].attempts[0].event, 'pull_request');
  assert.equal(report.runs[1].attempts[0].conclusion, 'failure');
  assert.equal(report.runs[2].attempts[0].sourceMatch, 'stale-pr-head');
  assert.deepEqual(report.runs[3].attempts.map(item => item.conclusion), ['failure', 'success']);
  assert.deepEqual(report.runs[3].attempts[1].jobs.map(item => item.conclusion), ['success', 'skipped', 'cancelled', null, 'neutral']);
  assert.equal(report.runs[4].attempts[0].sourceMatch, 'current-merge-test-ref');
  assert.equal(report.target.currentMergeTestSha, merge);
  assert.equal(report.target.headSha, head);
  assert.ok(report.runs.every(item => item.attempts.every(attempt => attempt.testedCheckoutSha === null)));
  assert.equal(report.requiredChecks.state, 'known');
  assert.deepEqual(report.requiredChecks.checks.map(item => [item.context, item.appId]), [['build', 42], ['security', 8]]);
  assert.ok(calls.filter(item => item.endpoint.includes('?')).every(item => item.paginate));
  assert.ok(calls.some(item => item.endpoint === jobsPath(13, 1)));
  assert.match(formatHuman(report), /pull_request \| SHA .*stale-pr-head/u);
  assert.match(formatHuman(report), /completed\/skipped/u);
  assert.match(formatHuman(report), /attempt 1\/2 \| completed\/failure/u);
  assert.deepEqual(JSON.parse(JSON.stringify(report)), report);
});

test('mismatched run metadata and unrelated same-named branches cannot become exact-head evidence', async () => {
  const data = fixture();
  data[attemptPath(12, 1)].pull_requests[0].head.sha = head;
  data[attemptPath(10, 1)].head_sha = stale;
  data[jobsPath(10, 1)][0].jobs[0].head_sha = stale;
  const report = await collect(data);
  assert.equal(report.runs[2].attempts[0].sourceMatch, 'mismatched-run-and-pr-head');
  assert.equal(report.runs[0].attempts[0].sourceMatch, 'stale-or-unrelated-branch-run');
});

test('same source SHA from another PR or unknown fork association is never target-PR evidence', async () => {
  const data = fixture();
  data[attemptPath(11, 1)].pull_requests[0].number = 8;
  data[attemptPath(13, 1)].pull_requests = [];
  data[attemptPath(14, 1)].pull_requests[0].base.sha = stale;
  const report = await collect(data);
  assert.equal(report.runs[1].attempts[0].sourceMatch, 'exact-head');
  assert.equal(report.runs[1].attempts[0].prAssociation, 'other-pr');
  assert.equal(report.runs[3].attempts[0].prAssociation, 'unknown');
  assert.equal(report.runs[4].attempts[0].prBaseMatch, 'different-base');
  assert.match(formatHuman(report), /PR association: other-pr/u);
  assert.match(formatHuman(report), /associated PR #8: head 111.*base 444/u);
  assert.match(formatHuman(report), /target PR base: different-base/u);
});

test('permissions, missing old attempts and incomplete pagination stay explicit without hiding available evidence', async () => {
  const data = fixture();
  data[protection] = {error: 'gh API HTTP 403'};
  data[attemptPath(13, 1)] = {error: 'gh API HTTP 404'};
  data[jobsPath(11, 1)][0].total_count = 2;
  const report = await collect(data);
  assert.equal(report.complete, false);
  assert.equal(report.requiredChecks.state, 'unknown');
  assert.equal(report.runs[3].attempts[0].available, false);
  assert.equal(report.runs[3].attempts[1].conclusion, 'success');
  assert.ok(report.errors.some(item => item.message.includes('not all results')));
  assert.ok(report.errors.some(item => item.message.includes('403')));
  assert.match(formatHuman(report), /attempt 1: unavailable/u);
});

test('required workflows and incomplete policy fields remain unknown; empty authoritative policy is known', async () => {
  for (const replacement of [undefined, {}, {contexts: []}]) {
    const data = fixture();
    data[protection].required_status_checks = replacement;
    assert.equal((await collect(data)).requiredChecks.state, 'unknown');
  }
  const data = fixture();
  data[protection].required_status_checks = null;
  data[rules] = [[{type: 'workflows', parameters: {workflows: []}}]];
  assert.equal((await collect(data)).requiredChecks.state, 'unknown');
  data[rules] = [[]];
  const result = await collect(data);
  assert.equal(result.requiredChecks.state, 'known');
  assert.deepEqual(result.requiredChecks.checks, []);
  for (const type of ['code_scanning', 'code_quality', 'required_deployments', 'future_check_rule']) {
    data[rules] = [[{type}]];
    const report = await collect(data);
    assert.equal(report.requiredChecks.state, 'unknown');
    assert.deepEqual(report.requiredChecks.unsupportedRules, [type]);
  }
});

test('missing merge/test ref is unknown; a closed PR merge commit is not a current test ref', async () => {
  const data = fixture();
  data[`${prefix}/git/ref/pull/7/merge`] = {error: 'gh API HTTP 404'};
  let report = await collect(data);
  assert.equal(report.target.currentMergeTestSha, null);
  assert.equal(report.complete, false);
  data[`${prefix}/pulls/7`].state = 'closed';
  report = await collect(data);
  assert.equal(report.target.currentMergeTestSha, null);
  assert.equal(report.target.mergeCommitSha, merge);
  assert.equal(report.complete, true);
});

test('job SHA, run and attempt identity cannot be silently combined; duplicate and incomplete jobs are flagged', async () => {
  const data = fixture();
  const jobs = data[jobsPath(13, 2)][1].jobs;
  jobs[0].head_sha = stale;
  jobs[1].run_attempt = 1;
  jobs[2].run_id = 12;
  const report = await collect(data);
  assert.equal(report.complete, false);
  assert.deepEqual(report.runs[3].attempts[1].jobs.map(item => item.identityMatches), [true, true, false, false, false]);
  assert.match(formatHuman(report), /IDENTITY MISMATCH/u);
});

test('cap and invalid collection shapes are incomplete, never empty-success evidence', async () => {
  const data = fixture();
  data[headRuns][0].total_count = 1000;
  data[jobsPath(10, 1)] = [{total_count: 1}];
  data[jobsPath(11, 1)][0].total_count = undefined;
  const report = await collect(data);
  assert.equal(report.complete, false);
  assert.ok(report.errors.some(item => item.message.includes('capped at 1,000')));
  assert.equal(report.runs[0].attempts[0].jobsAvailable, false);
  assert.ok(report.errors.some(item => item.message.includes('total_count')));
});

test('malformed PR associations and policy entries stay partial data instead of crashing JSON output', async () => {
  for (const associations of [{number: 7}, [null], [{number: 7}]]) {
    const data = fixture();
    data[attemptPath(12, 1)].pull_requests = associations;
    data[protection].required_status_checks.checks = [null];
    const report = await collect(data);
    assert.equal(report.complete, false);
    assert.equal(report.requiredChecks.state, 'unknown');
    assert.equal(report.runs.length, 5);
    assert.doesNotThrow(() => JSON.parse(JSON.stringify(report)));
  }
});

test('duplicate run IDs across pages and check-suite history cap cannot imply complete history', async () => {
  const data = fixture();
  data[branchRuns][1].workflow_runs[0] = data[branchRuns][0].workflow_runs[0];
  data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs',
    Array.from({length: 1000}, (_, id) => ({id: id + 1, name: 'build', head_sha: head,
      check_suite: {id: id + 1}, status: 'completed', conclusion: 'success'})));
  const report = await collect(data);
  assert.equal(report.complete, false);
  assert.ok(report.errors.some(item => item.message.includes('Duplicate collection IDs')));
  assert.ok(report.errors.some(item => item.message.includes('check-suite history cap')));
});

test('absent runs/checks and SHA-only policy uncertainty are stated without inventing a failure or readiness', async () => {
  const data = fixture();
  data[headRuns] = collection('workflow_runs', []);
  const report = await collectEvidence({repository, sha: head}, reader(data));
  assert.equal(report.complete, true);
  assert.deepEqual(report.runs, []);
  assert.equal(report.requiredChecks.state, 'unknown');
  assert.match(formatHuman(report), /Workflow runs: absent/u);
  assert.match(formatHuman(report), /check runs: absent/u);
  assert.match(formatHuman(report), /not .*readiness verdict/u);
});

test('external check runs and historical statuses remain separate by SHA with no event/attempt attribution', async () => {
  const data = fixture();
  data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs', [
    {id: 70, name: 'external', head_sha: head, status: 'completed', conclusion: 'failure', app: {id: 8}},
    {id: 71, name: 'external', head_sha: head, status: 'completed', conclusion: 'success', app: {id: 8}},
  ]);
  data[`${prefix}/commits/${head}/statuses?per_page=100`] = [[
    {id: 72, context: 'legacy', state: 'success'}, {id: 73, context: 'legacy', state: 'failure'},
  ]];
  const report = await collect(data);
  assert.deepEqual(report.commitChecks[0].checks.map(item => item.conclusion), ['failure', 'success']);
  assert.deepEqual(report.commitChecks[0].statuses.map(item => item.state), ['success', 'failure']);
  assert.deepEqual(report.commitChecks[1].checks, []);
  assert.match(formatHuman(report), /event\/attempt unattributed/u);
});

test('strict CLI selection accepts other repositories and full SHAs, rejects ambiguous inputs', () => {
  assert.deepEqual(parseArguments(['actql/actql-cloud', '--sha', head, '--json']), {
    repository: 'actql/actql-cloud', sha: head, json: true,
  });
  assert.equal(parseArguments([repository, '--sha', head, '--branch', 'release/one']).branch, 'release/one');
  for (const args of [[], [repository], [repository, '--sha', '123'], [repository, '--pr', '0'],
    [repository, '--pr', '7', '--sha', head], [repository, '--pr', '7', '--branch', 'main'],
    [repository, '--pr', '7', '--pr', '8'], [repository, '--pr', '7', '--rerun'],
    ['https://github.com/example/project', '--pr', '7']]) {
    assert.throws(() => parseArguments(args), /Usage/u);
  }
});

function fakeGh(t, data) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-ci-evidence-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const dataPath = join(directory, 'responses.json');
  const callsPath = join(directory, 'calls.jsonl');
  writeFileSync(dataPath, JSON.stringify(data));
  writeFileSync(join(directory, 'gh'), `#!/usr/bin/env node
import {appendFileSync, readFileSync} from 'node:fs';
const args = process.argv.slice(2);
appendFileSync(process.env.FIXTURE_CALLS, JSON.stringify(args) + '\\n');
const data = JSON.parse(readFileSync(process.env.FIXTURE_DATA, 'utf8'));
const reply = data[args.at(-1)];
if (reply?.error || reply === undefined) {
  console.error('gh: ' + (reply?.error ?? 'unexpected fixture endpoint') + ' secret-test-token');
  process.exit(1);
}
if (reply?.invalidJSON) process.stdout.write('{invalid');
else console.log(JSON.stringify(reply));
`, {mode: 0o755});
  const env = {...process.env, PATH: `${directory}${delimiter}${process.env.PATH}`,
    FIXTURE_DATA: dataPath, FIXTURE_CALLS: callsPath, GH_DEBUG: 'api'};
  const script = fileURLToPath(new URL('./ci-evidence.mjs', import.meta.url));
  return {invoke: args => spawnSync(process.execPath, [script, repository, ...args], {env, encoding: 'utf8'}),
    calls: () => readFileSync(callsPath, 'utf8').trim().split('\n').map(line => JSON.parse(line))};
}

test('subprocess CLI only invokes gh GET, follows pagination, emits valid JSON and treats red CI as data', t => {
  const fake = fakeGh(t, fixture());
  const result = fake.invoke(['--pr', '7', '--json']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).runs[1].attempts[0].conclusion, 'failure');
  for (const args of fake.calls()) {
    assert.equal(args[0], 'api');
    assert.equal(args[args.indexOf('--method') + 1], 'GET');
    assert.equal(args[args.indexOf('--hostname') + 1], 'github.com');
    if (args.at(-1).includes('?')) {
      assert.ok(args.includes('--paginate'));
      assert.ok(args.includes('--slurp'));
    }
  }
});

test('subprocess API failures preserve partial JSON, numeric HTTP errors and never echo credential/debug stderr', t => {
  const data = fixture();
  data[protection] = {error: 'HTTP 403'};
  data[jobsPath(10, 1)] = {invalidJSON: true};
  const result = fakeGh(t, data).invoke(['--pr', '7', '--json']);
  assert.equal(result.status, 1);
  const report = JSON.parse(result.stdout);
  assert.equal(report.requiredChecks.state, 'unknown');
  assert.ok(report.errors.some(item => item.message === 'gh API HTTP 403'));
  assert.ok(report.errors.some(item => item.message === 'gh API returned invalid JSON'));
  assert.doesNotMatch(result.stdout + result.stderr, /secret-test-token/u);
});


test('fixed-run CLI remains GET-only and keeps all attempts outside the selected comparison', t => {
  const data = fixture();
  data[`${prefix}/actions/runs/13`] = data[attemptPath(13, 2)];
  const fake = fakeGh(t, data);
  const result = fake.invoke(['--runs', '13', '--compare', '13:2', '--json']);
  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.deepEqual(report.runs[0].attempts.map(attempt => attempt.conclusion), ['failure', 'success']);
  assert.deepEqual(report.timing.comparison.selection, ['13:2']);
  for (const args of fake.calls()) assert.equal(args[args.indexOf('--method') + 1], 'GET');
});

// Independent timing fixtures share the existing read-only tooling gate.
{
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
}


// #196 and #198 use the same collector and existing lint test entrypoint.
const comparePath = (from, to = base) => `${prefix}/compare/${from}...${to}`;
const commitPath = value => `${prefix}/git/commits/${value}`;
function mergedPR(data, destination = 'main') {
  const pr = data[`${prefix}/pulls/7`];
  Object.assign(pr, {state: 'closed', merged: true, merged_at: '2026-10-02T12:00:00Z'});
  pr.base.ref = destination;
  if (destination !== 'main') {
    data[`${prefix}/pulls?state=all&head=example%3A${encodeURIComponent(destination)}&per_page=100`] = [[]];
    data[`${prefix}/branches/${encodeURIComponent(destination)}/protection`] = data[protection];
    data[`${prefix}/rules/branches/${encodeURIComponent(destination)}?per_page=100`] = data[rules];
  }
  data[comparePath(merge)] = {status: 'diverged', base_commit: {sha: merge}, merge_base_commit: {sha: stale}};
  return pr;
}
function requiredBuild(data) {
  data[rules] = [[]];
  for (const id of [10, 11, 12, 13, 14]) {
    for (let attempt = 1; attempt <= (id === 13 ? 2 : 1); attempt++) {
      const run = data[attemptPath(id, attempt)];
      run.check_suite_id = id * 100;
      run.workflow_id = id === 10 ? 1 : 2;
      for (const page of data[jobsPath(id, attempt)]) for (const job of page.jobs) {
        job.check_run_url = `https://api.github.com/repos/${repository}/check-runs/${job.id}`;
        job.name = 'build';
      }
    }
  }
}
function check(id, suiteId, source, status = 'completed', conclusion = 'success', appId = 42) {
  return {id, name: 'build', head_sha: source, status, conclusion,
    check_suite: {id: suiteId}, app: {id: appId}};
}

test('#196 normal merge proves exact original ancestry and records the merge destination', async () => {
  const data = fixture();
  mergedPR(data);
  data[comparePath(head)] = {status: 'ahead', base_commit: {sha: head}, merge_base_commit: {sha: head}};
  data[comparePath(merge)] = {status: 'ahead', base_commit: {sha: merge}, merge_base_commit: {sha: merge}};
  const report = await collect(data), subject = report.integration.subjects[0];
  assert.equal(report.complete, true);
  assert.equal(subject.relation, 'exact-head-reachable');
  assert.deepEqual(subject.mergeDestination, {repository, branch: 'main'});
  assert.equal(subject.mergeResultAncestry.state, 'reachable');
  assert.equal(report.target.currentMergeTestSha, null);
});

test('#196 merged into a feature branch is not main integration and identifies the missing step', async () => {
  const data = fixture();
  mergedPR(data, 'feature/parent');
  const report = await collect(data), subject = report.integration.subjects[0];
  assert.equal(report.complete, true);
  assert.equal(subject.mergeDestination.branch, 'feature/parent');
  assert.equal(subject.relation, 'not-reachable-content-unverified');
  assert.match(subject.nextStep, /merge result from feature\/parent.*into main/u);
  assert.match(formatHuman(report), /merge destination: example\/project:feature\/parent/u);
  assert.equal(report.reviewEvidence.verdict, 'not-issued');
});

test('#196 squash correspondence distinguishes exact trees from original ancestry and unknown content', async () => {
  const data = fixture();
  mergedPR(data);
  data[comparePath(merge)] = {status: 'ahead', base_commit: {sha: merge}, merge_base_commit: {sha: merge}};
  data[commitPath(merge)].tree.sha = head;
  let subject = (await collect(data)).integration.subjects[0];
  assert.equal(subject.headAncestry.state, 'not-reachable');
  assert.equal(subject.headToMergeResultTree, 'equal');
  assert.equal(subject.relation, 'equivalent-tree-in-reachable-merge-result');
  data[commitPath(merge)].tree.sha = merge;
  subject = (await collect(data)).integration.subjects[0];
  assert.equal(subject.relation, 'merge-result-reachable-content-unverified');
  assert.match(subject.nextStep, /before claiming/u);
  data[commitPath(base)].tree.sha = head;
  assert.equal((await collect(data)).integration.subjects[0].relation, 'equivalent-tree-at-integration-tip');
});

test('#196 missing history and wrong comparison/tree identity never establish integration', async () => {
  for (const replacement of [{error: 'gh API HTTP 404'}, {status: 'ahead', base_commit: {sha: stale}, merge_base_commit: {sha: head}},
    {status: 'ahead', base_commit: {sha: head}, merge_base_commit: {sha: stale}}]) {
    const data = fixture();
    data[comparePath(head)] = replacement;
    const report = await collect(data);
    assert.equal(report.integration.subjects[0].relation, 'unknown');
    assert.equal(report.complete, false);
  }
  const data = fixture();
  data[commitPath(head)] = {sha: stale, tree: {sha: base}};
  assert.equal((await collect(data)).integration.subjects[0].headToIntegrationTree, 'unknown');
});

test('#196 explicit dependencies and current-base candidates are repository-scoped and report each destination', async () => {
  const data = fixture();
  data[`${prefix}/pulls/7`].base.ref = 'feature/parent';
  data[`${prefix}/branches/feature%2Fparent/protection`] = data[protection];
  data[`${prefix}/rules/branches/feature%2Fparent?per_page=100`] = data[rules];
  data[`${prefix}/pulls?state=all&head=example%3Afeature%2Fparent&per_page=100`] = [[
    {number: 8, head: {ref: 'feature/parent', repo: {full_name: repository}}},
    {number: 9, head: {ref: 'feature/parent', repo: {full_name: 'other/project'}}},
  ]];
  data[`${prefix}/pulls/8`] = {...structuredClone(data[`${prefix}/pulls/7`]), number: 8, merged: true,
    state: 'closed', base: {ref: 'feature/grandparent', sha: stale}, merge_commit_sha: merge};
  data[comparePath(merge)] = {status: 'diverged', base_commit: {sha: merge}, merge_base_commit: {sha: stale}};
  const calls = [];
  const report = await collectEvidence({repository, pr: 7, integration: 'main', dependencies: [8]}, reader(data, calls));
  assert.deepEqual(report.integration.subjects.map(item => item.number), [7, 8]);
  assert.equal(report.integration.subjects[1].mergeDestination.branch, 'feature/grandparent');
  assert.equal(report.integration.subjects[1].relation, 'not-reachable-content-unverified');
  assert.equal(calls.filter(item => item.endpoint === `${prefix}/pulls/8`).length, 2);
  assert.ok(!calls.some(item => item.endpoint === `${prefix}/pulls/9`));
});

test('#198 final HEAD/base reread detects movement and unavailable boundaries', async () => {
  for (const change of ['head', 'base', 'base-ref', 'draft', 'unavailable']) {
    const data = fixture(), calls = [];
    let reads = 0;
    const request = reader(data, calls);
    const report = await collectEvidence({repository, pr: 7}, async (endpoint, paginate) => {
      if (endpoint === `${prefix}/pulls/7` && ++reads === 2) {
        if (change === 'unavailable') throw new Error('gh API HTTP 403');
        if (change === 'head') data[endpoint].head.sha = stale;
        if (change === 'base') data[endpoint].base.sha = stale;
        if (change === 'base-ref') data[endpoint].base.ref = 'other';
        if (change === 'draft') data[endpoint].draft = true;
      }
      return request(endpoint, paginate);
    });
    assert.equal(report.complete, false);
    assert.equal(report.revision.state, change === 'unavailable' ? 'unknown' : 'changed');
    assert.equal(calls.at(-1).endpoint, change === 'unavailable' ? `${prefix}/git/ref/pull/7/merge` : `${prefix}/pulls/7`);
    assert.equal(report.reviewEvidence.verdict, 'not-issued');
  }
});

test('#196/#198 integration branch or merge-ref movement invalidates the observed boundary', async () => {
  for (const endpoint of [`${prefix}/branches/main`, `${prefix}/git/ref/pull/7/merge`]) {
    const data = fixture(); let reads = 0;
    const request = reader(data);
    const report = await collectEvidence({repository, pr: 7}, async (path, paginate) => {
      if (path === endpoint && ++reads === 2) {
        if (path.includes('/branches/')) data[path].commit.sha = stale;
        else data[path].object.sha = stale;
      }
      return request(path, paginate);
    });
    assert.equal(report.revision.state, 'changed');
    assert.equal(report.complete, false);
  }
});

test('#198 current requirements retain actual run/attempt/event and never use stale green jobs', async () => {
  const data = fixture(); requiredBuild(data);
  data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs', [check(130, 1300, head)]);
  const report = await collect(data), required = report.requiredChecks.observations[0];
  const current = required.sourcesAtRevision[0];
  assert.equal(current.state, 'completed-success');
  assert.deepEqual([current.checks[0].attribution.runId, current.checks[0].attribution.attempt,
    current.checks[0].attribution.event], [13, 2, 'pull_request']);
  assert.equal(required.sourcesAtRevision[1].state, 'missing');
  assert.equal(required.relatedJobs.find(item => item.runId === 12).sourceMatch, 'stale-pr-head');
  data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs', []);
  assert.equal((await collect(data)).requiredChecks.observations[0].sourcesAtRevision[0].state, 'missing');
});

test('#198 duplicate names across workflows stay separate, mismatched sources and apps cannot become current', async () => {
  const data = fixture(); requiredBuild(data);
  data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs', [check(100, 1000, head), check(110, 1100, head)]);
  let current = (await collect(data)).requiredChecks.observations[0].sourcesAtRevision[0];
  assert.equal(current.state, 'multiple-observations');
  assert.deepEqual(current.checks.map(item => item.attribution.workflowId), [1, 2]);
  data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs', [check(120, 1200, stale)]);
  current = (await collect(data)).requiredChecks.observations[0].sourcesAtRevision[0];
  assert.equal(current.state, 'unknown');
  assert.equal(current.checks[0].revisionMatch, 'mismatched-sha');
  data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs', [check(100, 1000, head, 'completed', 'success', 99)]);
  assert.equal((await collect(data)).requiredChecks.observations[0].sourcesAtRevision[0].state, 'missing');
});

test('#198 retries supersede old success without hiding cancelled, skipped or running outcomes', async () => {
  const data = fixture(); requiredBuild(data);
  for (const [status, conclusion, state] of [['in_progress', null, 'running-or-pending'],
    ['completed', 'cancelled', 'completed-cancelled'], ['completed', 'skipped', 'completed-skipped'],
    ['completed', 'neutral', 'completed-neutral']]) {
    data[`${prefix}/commits/${head}/check-runs?filter=all&per_page=100`] = collection('check_runs', [
      check(129, 1300, head), check(130, 1300, head, status, conclusion)]);
    const current = (await collect(data)).requiredChecks.observations[0].sourcesAtRevision[0];
    assert.equal(current.state, state);
    assert.equal(current.checks[0].attemptState, 'superseded-attempt');
    assert.equal(current.checks[1].attemptState, 'latest-observed-attempt');
  }
});

test('#198 unavailable policy stays unknown, merge tree and reviews preserve exact revision bindings', async () => {
  const data = fixture(); requiredBuild(data);
  data[protection] = {error: 'gh API HTTP 403'};
  data[rules] = [[{type: 'required_status_checks', parameters: {required_status_checks: [{context: 'build', integration_id: 42}]}}]];
  data[`${prefix}/pulls/7`].draft = true;
  data[`${prefix}/pulls/7/reviews?per_page=100`] = [[
    {id: 1, user: {login: 'reviewer'}, state: 'APPROVED', commit_id: stale},
    {id: 2, user: {login: 'reviewer'}, state: 'CHANGES_REQUESTED', commit_id: head},
  ]];
  let report = await collect(data);
  assert.equal(report.requiredChecks.state, 'unknown');
  assert.equal(report.requiredChecks.observations[0].authoritative, false);
  assert.equal(report.reviewEvidence.draft, true);
  assert.equal(report.reviewEvidence.finalMergeabilityState, 'unknown');
  assert.equal(report.target.mergeTestRelationship, 'current-base-and-head');
  assert.deepEqual(report.target.mergeTestParents, [base, head]);
  assert.deepEqual(report.reviews.observations.map(review => review.sourceMatch), ['stale-head', 'exact-head']);
  data[commitPath(merge)].parents[0].sha = stale;
  report = await collect(data);
  assert.equal(report.target.mergeTestRelationship, 'mismatched-or-unverified-parents');
  assert.equal(report.reviewEvidence.verdict, 'not-issued');
});

test('#196 strict integration/dependency CLI options are explicit PR-only GET selection', () => {
  assert.deepEqual(parseArguments([repository, '--pr', '7', '--integration', 'release/one', '--dependencies', '8,9']),
    {repository, pr: 7, integration: 'release/one', dependencies: [8, 9], json: false});
  for (const args of [['--sha', head, '--integration', 'main'], ['--runs', '10', '--dependencies', '7'],
    ['--pr', '7', '--dependencies', '8,8'], ['--pr', '7', '--dependencies', '0']]) {
    assert.throws(() => parseArguments([repository, ...args]), /Usage/u);
  }
});

test('#198 an app-pinned requirement cannot attribute a legacy status to the required app', async () => {
  const data = fixture(); requiredBuild(data);
  data[`${prefix}/commits/${head}/statuses?per_page=100`] = [[{id: 91, context: 'build', state: 'success'}]];
  let required = (await collect(data)).requiredChecks.observations[0];
  assert.equal(required.sourcesAtRevision[0].state, 'unknown-app-source');
  data[protection].required_status_checks.checks[0].app_id = -1;
  required = (await collect(data)).requiredChecks.observations[0];
  assert.equal(required.appId, null);
  assert.equal(required.sourcesAtRevision[0].state, 'status-success');
});

// Read-only scheduling diagnostics share the existing CI reporting fixture gate.
import './verification-actions.test.mjs';
