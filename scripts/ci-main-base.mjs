// Main applicability starts at a fully verified main ancestor, never push.before.
// A successful narrow run is deliberately not a checkpoint: this keeps the
// coverage argument local, with no cross-run ledger or recursive receipt chain.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync} from 'node:fs';
const sha = /^[0-9a-f]{40}$/u;
const workflowPath = '.github/workflows/ci.yml';
export const policyPaths = Object.freeze(['.github', 'scripts/ci-targets.mjs', 'scripts/ci-focused-tests.mjs', 'scripts/test-execution.mjs', 'scripts/packed-query-evidence.mjs', 'scripts/ci-main-base.mjs']);
const gitDefault = args => execFileSync('git', args, {encoding: 'utf8', maxBuffer: 1024 * 1024});
const positive = value => Number.isSafeInteger(value) && value > 0;

// Existing ephemeral workflow token only. The caller must have actions:read;
// no credentials are created, saved, or included in error messages/plan output.
export function actionsReader({repository, token, fetchImpl = fetch}) {
  assert(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(repository), 'Invalid repository');
  assert(typeof token === 'string' && token.length, 'Missing Actions read token');
  return async path => {
    assert(/^\/actions\/[A-Za-z0-9_./?=&%-]+$/u.test(path), 'Invalid Actions endpoint');
    const response = await fetchImpl(`https://api.github.com/repos/${repository}${path}`, {
      headers: {accept: 'application/vnd.github+json', authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28'},
      redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    assert(response.ok, `Actions history unavailable (HTTP ${response.status})`);
    return response.json();
  };
}

export function fullCheckpointJobs(gateJobs) {
  assert(Array.isArray(gateJobs) && gateJobs.includes('preflight') && gateJobs.includes('core'), 'Invalid gate policy');
  return ['check', ...gateJobs.flatMap(name => name === 'core' ? ['core (js)', 'core (wasm)', 'core (native)'] : [name])];
}

function validRun(run, {repository, repositoryId, workflowId, ancestors}) {
  return positive(run?.id) && positive(run.run_attempt) && run.workflow_id === workflowId
    && run.path === workflowPath && run.event === 'push' && run.head_branch === 'main'
    && run.repository?.id === repositoryId && run.repository?.full_name === repository
    && run.head_repository?.id === repositoryId && sha.test(run.head_sha ?? '') && ancestors.includes(run.head_sha)
    && run.status === 'completed' && run.conclusion === 'success';
}
function successfulJobs(data, run, requiredJobs) {
  if (!data || !Array.isArray(data.jobs) || data.total_count !== data.jobs.length || data.jobs.length > 100) return false;
  return requiredJobs.every(name => {
    const jobs = data.jobs.filter(job => job.name === name);
    return jobs.length === 1 && jobs[0].run_id === run.id && jobs[0].run_attempt === run.run_attempt
      && jobs[0].head_sha === run.head_sha && jobs[0].status === 'completed' && jobs[0].conclusion === 'success';
  });
}

export async function resolveMainBaseline({testedSha, repository, repositoryId, requiredJobs,
  git = gitDefault, request, maxAncestors = 100, maxRuns = 100, maxCandidates = 10}) {
  try {
    assert(sha.test(testedSha ?? '') && positive(repositoryId), 'Invalid tested revision/repository');
    assert(Array.isArray(requiredJobs) && requiredJobs.length > 3 && new Set(requiredJobs).size === requiredJobs.length, 'Invalid required jobs');
    assert([maxAncestors, maxRuns, maxCandidates].every(n => positive(n) && n <= 100), 'Invalid scan bound');
    assert.equal(git(['rev-parse', 'HEAD']).trim(), testedSha, 'Different tested checkout');
    assert.equal(git(['rev-parse', '--is-shallow-repository']).trim(), 'false', 'Incomplete history');
    assert.equal(git(['replace', '-l']).trim(), '', 'Replaced history');
    assert(!existsSync(git(['rev-parse', '--git-path', 'info/grafts']).trim()), 'Grafted history');
    const ancestors = git(['rev-list', '--first-parent', `--max-count=${maxAncestors + 1}`, testedSha]).trim().split('\n');
    assert(ancestors[0] === testedSha && ancestors.every(value => sha.test(value)), 'Invalid main ancestry');
    ancestors.shift(); // never let this run, or another run for this SHA, certify itself
    const policy = policyPaths.map(path => ({path, object: git(['rev-parse', `${testedSha}:${path}`]).trim()}));
    assert(policy.every(entry => sha.test(entry.object)), 'Missing policy identity');
    const workflow = await request('/actions/workflows/ci.yml');
    assert(positive(workflow?.id) && workflow.path === workflowPath && workflow.state === 'active', 'Unknown CI workflow');
    const runs = await request(`/actions/workflows/${workflow.id}/runs?branch=main&event=push&status=success&per_page=${maxRuns}`);
    assert(Array.isArray(runs?.workflow_runs) && runs.workflow_runs.length <= maxRuns, 'Invalid run inventory');
    const candidates = runs.workflow_runs.filter(run => validRun(run, {repository, repositoryId, workflowId: workflow.id, ancestors}))
      .sort((a, b) => ancestors.indexOf(a.head_sha) - ancestors.indexOf(b.head_sha));
    for (const run of candidates.slice(0, maxCandidates)) {
      if (!policy.every(entry => git(['rev-parse', `${run.head_sha}:${entry.path}`]).trim() === entry.object)) continue;
      // Attempt-specific endpoint prohibits combining successful jobs from retries.
      const jobs = await request(`/actions/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100`);
      if (!successfulJobs(jobs, run, requiredJobs)) continue;
      // Re-read after jobs to reject a run that was re-run while inspected.
      const current = await request(`/actions/runs/${run.id}`);
      if (!validRun(current, {repository, repositoryId, workflowId: workflow.id, ancestors})
        || current.id !== run.id || current.head_sha !== run.head_sha || current.run_attempt !== run.run_attempt) continue;
      return {baseSha: run.head_sha, testedSha, runId: run.id, runAttempt: run.run_attempt,
        workflowId: workflow.id, policy, reason: 'Cumulative changes since fully verified main ancestor'};
    }
    return {baseSha: null, reason: 'No trustworthy full main checkpoint within bounded history'};
  } catch (error) {
    // API payloads and tokens never enter diagnostic output.
    return {baseSha: null, reason: `Main checkpoint unavailable: ${error instanceof assert.AssertionError ? error.message.split('\n')[0] : 'history lookup failed'}`};
  }
}

export function validateMainBaseline(value) {
  assert.deepEqual(Object.keys(value ?? {}).sort(), ['baseSha', 'testedSha', 'runId', 'runAttempt', 'workflowId', 'policy', 'reason'].sort(), 'Invalid main checkpoint');
  assert(sha.test(value.baseSha) && sha.test(value.testedSha) && value.baseSha !== value.testedSha, 'Invalid main checkpoint boundary');
  assert([value.runId, value.runAttempt, value.workflowId].every(positive), 'Invalid main run identity');
  assert(typeof value.reason === 'string' && value.reason.length, 'Missing checkpoint reason');
  assert.deepEqual(value.policy?.map(entry => entry.path), policyPaths, 'Invalid checkpoint policy inventory');
  assert(value.policy.every(entry => Object.keys(entry).sort().join(',') === 'object,path' && sha.test(entry.object)), 'Invalid policy identity');
  return value;
}
