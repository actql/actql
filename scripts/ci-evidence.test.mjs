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
    [`${prefix}/pulls/7`]: {number: 7, state: 'open', head: {sha: head, ref: 'feature/one', repo: {full_name: repository}},
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
