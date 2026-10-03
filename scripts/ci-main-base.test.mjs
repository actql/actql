import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {actionsReader, fullCheckpointJobs, policyPaths, resolveMainBaseline} from './ci-main-base.mjs';
const sha = char => char.repeat(40);
const head = sha('d'), previous = sha('c'), base = sha('b');
const requiredJobs = fullCheckpointJobs(['select-targets', 'preflight', 'lint', 'spec', 'core', 'native-macos', 'client', 'pipeline-evidence']);
function fixture() {
  const run = {id: 101, run_attempt: 1, workflow_id: 7, path: '.github/workflows/ci.yml', event: 'push', head_branch: 'main',
    repository: {id: 12, full_name: 'actql/actql'}, head_repository: {id: 12}, head_sha: base, status: 'completed', conclusion: 'success'};
  const jobs = {total_count: requiredJobs.length, jobs: requiredJobs.map(name => ({name, run_id: 101, run_attempt: 1, head_sha: base, status: 'completed', conclusion: 'success'}))};
  const calls = [];
  const state = {run, jobs, runs: [run], current: run, policyChanged: false};
  const git = args => {
    if (args[0] === 'replace') return '';
    if (args[0] === 'rev-list') return `${head}\n${previous}\n${base}\n`;
    if (args[1] === 'HEAD') return head;
    if (args[1] === '--is-shallow-repository') return 'false';
    if (args[1] === '--git-path') return '/tmp/actql-ci-no-grafts-fixture';
    return state.policyChanged && args[1].startsWith(base) ? sha('f') : sha('a');
  };
  const request = async path => {
    calls.push(path);
    if (path === '/actions/workflows/ci.yml') return {id: 7, path: '.github/workflows/ci.yml', state: 'active'};
    if (path.includes('/runs?')) return {workflow_runs: state.runs};
    if (path.includes('/jobs?')) return state.jobs;
    return state.current;
  };
  return {state, calls, options: {testedSha: head, repository: 'actql/actql', repositoryId: 12, requiredJobs, git, request}};
}
test('full checkpoint binds tested SHA, ancestry, policy and exact successful attempt', async () => {
  const {options, calls} = fixture();
  const result = await resolveMainBaseline(options);
  assert.equal(result.baseSha, base); assert.equal(result.testedSha, head);
  assert.equal(result.runId, 101); assert.equal(result.runAttempt, 1);
  assert.deepEqual(result.policy.map(p => p.path), policyPaths);
  assert(calls.includes('/actions/runs/101/attempts/1/jobs?per_page=100'));
});
for (const [key, value] of Object.entries({event: 'pull_request', head_branch: 'side', path: '.github/workflows/other.yml', workflow_id: 9,
  head_sha: sha('e'), conclusion: 'cancelled', status: 'in_progress', repository: {id: 99, full_name: 'actql/actql'}, head_repository: {id: 99}})) {
  test(`rejects wrong run ${key} regardless of display name`, async () => {
    const {options, state} = fixture(); state.run[key] = value; state.run.name = 'CI';
    assert.equal((await resolveMainBaseline(options)).baseSha, null);
  });
}
for (const conclusion of ['skipped', 'failure', 'cancelled', null]) {
  test(`narrow or incomplete ${conclusion} job cannot reset checkpoint`, async () => {
    const {options, state} = fixture(); state.jobs.jobs.find(j => j.name === 'core (wasm)').conclusion = conclusion;
    assert.equal((await resolveMainBaseline(options)).baseSha, null);
  });
}
test('missing, duplicate, truncated, wrong SHA and cross-attempt jobs are rejected', async () => {
  for (const change of [s => s.jobs.jobs.pop(), s => s.jobs.jobs.push(s.jobs.jobs[0]), s => s.jobs.total_count++,
    s => s.jobs.jobs[0].head_sha = head, s => s.jobs.jobs[0].run_attempt = 2, s => s.jobs.jobs[0].run_id = 102]) {
    const {options, state} = fixture(); change(state);
    assert.equal((await resolveMainBaseline(options)).baseSha, null);
  }
});
test('rerun during inspection, workflow policy drift and shallow history fall back full', async () => {
  const a = fixture(); a.state.current = {...a.state.run, run_attempt: 2};
  assert.equal((await resolveMainBaseline(a.options)).baseSha, null);
  const b = fixture(); b.state.policyChanged = true;
  assert.equal((await resolveMainBaseline(b.options)).baseSha, null);
  const c = fixture(); const original = c.options.git;
  c.options.git = args => args[1] === '--is-shallow-repository' ? 'true' : original(args);
  assert.equal((await resolveMainBaseline(c.options)).baseSha, null);
});
test('API failure and bounded history never silently use push.before', async () => {
  const f = fixture(); f.options.request = async () => {throw new Error('secret-token-must-not-leak');};
  const result = await resolveMainBaseline(f.options);
  assert.equal(result.baseSha, null); assert(!result.reason.includes('secret-token'));
  const g = fixture(); g.state.runs = []; assert.equal((await resolveMainBaseline(g.options)).baseSha, null);
});
test('private Actions requests use existing token only at fixed GitHub API origin', async () => {
  let captured;
  const request = actionsReader({repository: 'actql/actql', token: 'fixture-only', fetchImpl: async (url, options) => {
    captured = {url, options}; return {ok: true, json: async () => ({ok: true})};
  }});
  assert.deepEqual(await request('/actions/workflows/ci.yml'), {ok: true});
  assert.equal(captured.url, 'https://api.github.com/repos/actql/actql/actions/workflows/ci.yml');
  assert.equal(captured.options.headers.authorization, 'Bearer fixture-only');
  assert.equal(captured.options.redirect, 'error');
  await assert.rejects(request('https://other.example/actions/a'));
  assert.throws(() => actionsReader({repository: 'actql/actql', token: ''}));
});
test('A product change without successful CI followed by declaration B keeps product in cumulative diff', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'actql-ci-carryforward-'));
  const git = args => execFileSync('git', args, {cwd: dir, encoding: 'utf8'});
  try {
    git(['init', '-q']); git(['config', 'user.name', 'Fixture']); git(['config', 'user.email', 'fixture@example.invalid']);
    mkdirSync(join(dir, '.github'), {recursive: true}); mkdirSync(join(dir, 'scripts')); mkdirSync(join(dir, 'src'));
    writeFileSync(join(dir, '.github/policy'), 'policy');
    for (const path of policyPaths.slice(1)) writeFileSync(join(dir, path), 'policy');
    writeFileSync(join(dir, 'src/product.mbt'), 'original'); git(['add', '.']); git(['commit', '-qm', 'C verified']); const c = git(['rev-parse', 'HEAD']).trim();
    writeFileSync(join(dir, 'src/product.mbt'), 'changed'); git(['add', '.']); git(['commit', '-qm', 'A unverified']); const a = git(['rev-parse', 'HEAD']).trim();
    mkdirSync(join(dir, 'proofs/relation-pipeline/foundation-declarations'), {recursive: true});
    writeFileSync(join(dir, 'proofs/relation-pipeline/foundation-declarations/b.json'), '{}');
    git(['add', '.']); git(['commit', '-qm', 'B declaration']); const b = git(['rev-parse', 'HEAD']).trim();
    const f = fixture(); f.state.run.head_sha = c; for (const job of f.state.jobs.jobs) job.head_sha = c;
    // A cancelled run is not supplied by the successful-runs API. Even if supplied, it is rejected.
    f.state.runs.unshift({...f.state.run, id: 102, head_sha: a, conclusion: 'cancelled'});
    const result = await resolveMainBaseline({...f.options, testedSha: b, git});
    assert.equal(result.baseSha, c); assert.notEqual(result.baseSha, a);
    const paths = git(['diff', '--name-only', result.baseSha, b]).trim().split('\n');
    assert(paths.includes('src/product.mbt')); assert.equal(paths.length, 2);
  } finally {rmSync(dir, {recursive: true, force: true});}
});
