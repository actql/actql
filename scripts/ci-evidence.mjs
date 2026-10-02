// Read-only GitHub Actions evidence. No aggregate green/merge-ready verdict.
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {addTimingEvidence, formatTiming} from './ci-timing.mjs';
import {collectArtifactEvidence, formatArtifactEvidence} from './ci-artifacts.mjs';

const usage = 'Usage: node scripts/ci-evidence.mjs OWNER/REPO ' +
  '(--pr NUMBER | --sha FULL_SHA | --runs ID,ID | --artifacts MANIFEST.json) [--branch BASE_BRANCH] ' +
  '[--compare RUN:ATTEMPT,RUN:ATTEMPT] [--json]';
const fullSha = value => typeof value === 'string' && /^[a-f0-9]{40}$/iu.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const string = value => typeof value === 'string' && value.length > 0;
const valueOrNull = value => value ?? null;

export function parseArguments(args) {
  if (args.length === 1 && args[0] === '--help') return {help: true};
  const [repository, ...rest] = args;
  if (!/^[\w.-]+\/[\w.-]+$/u.test(repository ?? '')) throw new Error(usage);
  const options = {repository, json: false};
  const seen = new Set();
  for (let index = 0; index < rest.length; index++) {
    const flag = rest[index];
    if (!['--pr', '--sha', '--runs', '--artifacts', '--compare', '--branch', '--json'].includes(flag) || seen.has(flag)) {
      throw new Error(usage);
    }
    seen.add(flag);
    if (flag === '--json') options.json = true;
    else {
      const value = rest[++index];
      if (!string(value) || value.startsWith('--')) throw new Error(usage);
      options[flag.slice(2)] = value;
    }
  }
  if ([options.pr, options.sha, options.runs, options.artifacts].filter(Boolean).length !== 1 ||
      (options.pr && (!/^[1-9][0-9]*$/u.test(options.pr) || !positive(Number(options.pr)))) ||
      (options.sha && !fullSha(options.sha)) || (options.pr && options.branch) || (options.artifacts && (options.branch || options.compare))) {
    throw new Error(usage);
  }
  if (options.pr) options.pr = Number(options.pr);
  if (options.sha) options.sha = options.sha.toLowerCase();
  for (const [key, pattern] of [['runs', /^[1-9][0-9]*$/u], ['compare', /^[1-9][0-9]*:[1-9][0-9]*$/u]]) {
    if (!options[key]) continue;
    const values = options[key].split(',');
    if (new Set(values).size !== values.length || values.some(value =>
      !pattern.test(value) || value.split(':').some(part => !positive(Number(part))))) throw new Error(usage);
    options[key] = key === 'runs' ? values.map(Number) : values;
  }
  return options;
}

// Never echo gh stderr, response bodies or environment: authentication errors
// and debug output can contain credentials. Only known diagnostic categories
// and the numeric HTTP status leave this boundary.
export function ghRequest(endpoint, paginate = false) {
  const args = ['api', '--hostname', 'github.com', '--method', 'GET',
    '-H', 'Accept: application/vnd.github+json',
    '-H', 'X-GitHub-Api-Version: 2022-11-28'];
  if (paginate) args.push('--paginate', '--slurp');
  args.push(endpoint);
  const result = spawnSync('gh', args, {
    encoding: 'utf8', timeout: 60_000, maxBuffer: 32 * 1024 * 1024,
    env: {...process.env, GH_DEBUG: '', DEBUG: '', GH_PROMPT_DISABLED: '1', GH_PAGER: 'cat'},
  });
  if (result.error || result.status !== 0) {
    const status = result.stderr?.match(/\bHTTP (\d{3})\b/u)?.[1];
    const reason = result.error?.code === 'ENOENT' ? 'gh CLI unavailable' :
      result.error?.code === 'ETIMEDOUT' ? 'gh API request timed out' :
        result.error?.code === 'ENOBUFS' ? 'gh API response exceeded buffer limit' :
          status ? `gh API HTTP ${status}` : 'gh API failed (check authentication, permissions and rate limits)';
    throw new Error(reason);
  }
  try { return JSON.parse(result.stdout); }
  catch { throw new Error('gh API returned invalid JSON'); }
}

export async function collectEvidence(options, request = ghRequest) {
  const prefix = `repos/${options.repository}`;
  const report = {
    repository: options.repository,
    observedAt: new Date().toISOString(),
    target: {pr: options.pr ?? null, headSha: options.sha ?? null, baseBranch: options.branch ?? null},
    complete: true, errors: [], discovery: [], runs: [], commitChecks: [],
    requiredChecks: {state: 'unknown', branch: options.branch ?? null, sources: [], checks: [],
      reason: 'No target branch supplied; requirements are branch-specific.'},
    limits: [
      'This is an observation, not an atomic snapshot or a merge/deploy/Preview readiness verdict.',
      'Run head SHA and current PR merge SHA do not prove a job checkout; tested checkout SHA is unknown.',
      'No jobs are combined across events, runs, SHAs or attempts; skipped is not successful execution.',
      'Commit check-run history is limited by GitHub to the 1,000 most recent check suites per ref.',
    ],
  };
  const issue = (endpoint, message) => {
    report.complete = false;
    report.errors.push({endpoint, message});
  };
  const read = async endpoint => {
    try {
      const value = await request(endpoint, false);
      if (!object(value)) throw new Error('Expected an API object');
      return value;
    } catch (error) { issue(endpoint, error.message); return null; }
  };
  const list = async (endpoint, key, filteredRuns = false) => {
    try {
      const pages = await request(endpoint, true);
      if (!Array.isArray(pages) || pages.length === 0) throw new Error('Missing paginated API data');
      const items = [];
      const totals = [];
      for (const page of pages) {
        const rows = key ? page?.[key] : page;
        if (!Array.isArray(rows) || rows.some(row => !object(row))) {
          throw new Error('Incomplete paginated API response');
        }
        items.push(...rows);
        if (key) {
          if (!Number.isSafeInteger(page.total_count) || page.total_count < 0) {
            issue(endpoint, 'Missing collection total_count; completeness unknown');
          } else totals.push(page.total_count);
        }
      }
      if (totals.some(total => total !== items.length)) {
        issue(endpoint, 'Collection count changed or not all results were returned');
      }
      const ids = items.filter(item => item.id != null).map(item => item.id);
      if (new Set(ids).size !== ids.length) {
        issue(endpoint, 'Duplicate collection IDs; pagination may have omitted other results');
      }
      if (filteredRuns && (items.length >= 1000 || totals.some(total => total >= 1000))) {
        issue(endpoint, 'GitHub filtered workflow-run queries are capped at 1,000 results; older runs may be absent');
      }
      return items;
    } catch (error) { issue(endpoint, error.message); return null; }
  };

  let pr;
  if (options.pr) {
    const endpoint = `${prefix}/pulls/${options.pr}`;
    pr = await read(endpoint);
    if (!pr) return report;
    if (!fullSha(pr.head?.sha) || !string(pr.head?.ref) || !string(pr.base?.ref)) {
      issue(endpoint, 'PR source SHA or branch metadata is missing');
      return report;
    }
    report.target = {
      pr: options.pr, url: pr.html_url ?? null, state: pr.state ?? null,
      headSha: pr.head.sha, headBranch: pr.head.ref,
      headRepository: pr.head.repo?.full_name ?? null, baseBranch: pr.base.ref,
      currentBaseSha: fullSha(pr.base.sha) ? pr.base.sha : null,
      // For closed/merged PRs merge_commit_sha has different semantics. It is
      // not the live refs/pull/N/merge test candidate.
      mergeCommitSha: fullSha(pr.merge_commit_sha) ? pr.merge_commit_sha : null,
      currentMergeTestSha: null,
    };
    if (pr.state === 'open') {
      const endpoint = `${prefix}/git/ref/pull/${options.pr}/merge`;
      const merge = await read(endpoint);
      if (merge && fullSha(merge.object?.sha)) report.target.currentMergeTestSha = merge.object.sha;
      else if (merge) issue(endpoint, 'PR merge/test ref SHA missing');
    }
  }

  const branch = report.target.baseBranch;
  if (branch) {
    const protectionEndpoint = `${prefix}/branches/${encodeURIComponent(branch)}/protection`;
    const rulesEndpoint = `${prefix}/rules/branches/${encodeURIComponent(branch)}?per_page=100`;
    const protection = await read(protectionEndpoint);
    const rules = await list(rulesEndpoint);
    const policy = report.requiredChecks = {
      state: 'unknown', branch, sources: [protectionEndpoint, rulesEndpoint], checks: [], unsupportedRules: [],
      reason: 'Policy unavailable or ambiguous; visible checks alone do not define requirements.',
    };
    let valid = protection !== null && rules !== null;
    const addCheck = (check, appKey, source) => {
      if (!string(check?.context) || (check[appKey] != null && !Number.isInteger(check[appKey]))) {
        valid = false;
        return;
      }
      policy.checks.push({context: check.context, appId: check[appKey] ?? null, source});
    };
    if (protection) {
      const checks = protection.required_status_checks;
      if (checks === null) { /* authoritative absence of classic status requirements */ }
      else if (object(checks) && Array.isArray(checks.checks) && Array.isArray(checks.contexts)) {
        checks.checks.forEach(check => addCheck(check, 'app_id', protectionEndpoint));
        for (const context of checks.contexts) {
          if (!string(context)) valid = false;
          else if (!checks.checks.some(check => check?.context === context)) {
            addCheck({context}, 'app_id', protectionEndpoint);
          }
        }
      } else valid = false;
    }
    for (const rule of rules ?? []) {
      if (rule.type === 'required_status_checks') {
        const checks = rule.parameters?.required_status_checks;
        if (!Array.isArray(checks)) valid = false;
        else checks.forEach(check => addCheck(check, 'integration_id', rulesEndpoint));
      } else if (!['creation', 'update', 'deletion', 'non_fast_forward',
        'required_linear_history', 'required_signatures', 'pull_request',
        'commit_message_pattern', 'commit_author_email_pattern', 'committer_email_pattern',
        'branch_name_pattern', 'tag_name_pattern', 'file_path_restriction',
        'max_file_path_length', 'file_extension_restriction', 'max_file_size'].includes(rule.type)) {
        // Workflows, scanning/quality, deployment gates, merge queues and future
        // rule kinds cannot safely be reduced to named status-check contexts.
        valid = false;
        policy.unsupportedRules.push(rule.type ?? 'unknown');
      }
    }
    if (valid) {
      policy.state = 'known';
      policy.reason = 'Named status-check requirements read from classic protection and active branch rules; no satisfaction verdict.';
    }
  }

  const queries = options.runs ? [] : [`${prefix}/actions/runs?head_sha=${report.target.headSha}&per_page=100`];
  if (pr) queries.push(`${prefix}/actions/runs?branch=${encodeURIComponent(pr.head.ref)}&per_page=100`);
  if (report.target.currentMergeTestSha) {
    queries.push(`${prefix}/actions/runs?head_sha=${report.target.currentMergeTestSha}&per_page=100`);
  }
  const runs = new Map();
  for (const id of options.runs ?? []) {
    const endpoint = `${prefix}/actions/runs/${id}`;
    const run = await read(endpoint);
    report.discovery.push({endpoint, count: run ? 1 : null});
    if (run?.id === id) runs.set(id, run);
    else if (run) issue(endpoint, 'Selected run ID mismatched');
  }
  for (const endpoint of queries) {
    const found = await list(endpoint, 'workflow_runs', true);
    report.discovery.push({endpoint, count: found?.length ?? null});
    for (const run of found ?? []) {
      if (!positive(run.id)) { issue(endpoint, 'Run ID missing'); continue; }
      const previous = runs.get(run.id);
      if (previous && previous.run_attempt !== run.run_attempt) issue(endpoint, 'Run attempt changed during discovery');
      if (!previous || run.run_attempt > previous.run_attempt) runs.set(run.id, run);
    }
  }
  const sourceMatch = run => {
    if (!fullSha(run.head_sha)) return 'unknown';
    if (options.runs) return 'not-selected';
    if (run.head_sha === report.target.headSha) return 'exact-head';
    if (run.head_sha === report.target.currentMergeTestSha) return 'current-merge-test-ref';
    const associated = Array.isArray(run.pull_requests) ?
      run.pull_requests.find(item => object(item) && item.number === options.pr) : undefined;
    if (associated?.head?.sha === report.target.headSha) return 'mismatched-run-and-pr-head';
    return associated ? 'stale-pr-head' : pr ? 'stale-or-unrelated-branch-run' : 'mismatched-sha';
  };
  for (const run of [...runs.values()].sort((a, b) => a.id - b.id)) {
    if (!positive(run.run_attempt)) {
      issue(`${prefix}/actions/runs/${run.id}`, 'Run attempt count missing');
      continue;
    }
    const entry = {id: run.id, url: run.html_url ?? null, workflow: run.name ?? null,
      workflowPath: run.path ?? null, workflowUrl: run.workflow_url ?? null,
      latestAttempt: run.run_attempt, attempts: []};
    report.runs.push(entry);
    for (let number = 1; number <= run.run_attempt; number++) {
      const endpoint = `${prefix}/actions/runs/${run.id}/attempts/${number}`;
      const errorsBefore = report.errors.length;
      const attempt = await read(endpoint);
      const result = {number, available: attempt !== null, jobs: []};
      entry.attempts.push(result);
      if (!attempt) continue;
      Object.assign(result, {
        endpoint, workflow: attempt.name ?? null, workflowPath: attempt.path ?? null,
        workflowId: attempt.workflow_id ?? null,
        createdAt: attempt.created_at ?? null, startedAt: attempt.run_started_at ?? null,
        updatedAt: attempt.updated_at ?? null,
        event: attempt.event ?? null, headSha: attempt.head_sha ?? null,
        headBranch: attempt.head_branch ?? null, sourceMatch: sourceMatch(attempt),
        status: attempt.status ?? null, conclusion: valueOrNull(attempt.conclusion),
        url: attempt.html_url ?? entry.url, testedCheckoutSha: null,
        pullRequests: (Array.isArray(attempt.pull_requests) ? attempt.pull_requests : []).filter(object).map(item => ({
          number: item.number ?? null, headSha: item.head?.sha ?? null, baseSha: item.base?.sha ?? null,
        })),
      });
      const associated = result.pullRequests.find(item => item.number === options.pr);
      result.prAssociation = !options.pr ? 'not-selected' : associated ? 'target-pr' :
        result.pullRequests.length ? 'other-pr' : string(attempt.event) && attempt.event.startsWith('pull_request') ? 'unknown' : 'not-pr-event';
      result.prBaseMatch = !associated || !fullSha(associated.baseSha) || !report.target.currentBaseSha ? 'unknown' :
        associated.baseSha === report.target.currentBaseSha ? 'current-base' : 'different-base';
      if (attempt.id !== run.id || attempt.run_attempt !== number ||
          !fullSha(attempt.head_sha) || !string(attempt.event) || !string(attempt.status) ||
          !Object.hasOwn(attempt, 'conclusion') || !Array.isArray(attempt.pull_requests) ||
          attempt.pull_requests.some(item => !object(item) || !positive(item.number) || !fullSha(item.head?.sha)) ||
          !string(attempt.html_url) || (attempt.status === 'completed' && !string(attempt.conclusion))) {
        issue(endpoint, 'Run identity or required evidence missing/mismatched');
      }
      const jobsEndpoint = `${endpoint}/jobs?per_page=100`;
      const jobs = await list(jobsEndpoint, 'jobs');
      result.jobsAvailable = jobs !== null;
      const seen = new Set();
      for (const job of jobs ?? []) {
        const identityMatches = job.run_id === run.id && job.run_attempt === number && job.head_sha === attempt.head_sha;
        result.jobs.push({id: job.id ?? null, name: job.name ?? null, url: job.html_url ?? null,
          runId: job.run_id ?? null, attempt: job.run_attempt ?? null, headSha: job.head_sha ?? null,
          status: job.status ?? null, conclusion: valueOrNull(job.conclusion), identityMatches,
          endpoint: jobsEndpoint, createdAt: job.created_at ?? null,
          startedAt: job.started_at ?? null, completedAt: job.completed_at ?? null,
          runnerLabels: Array.isArray(job.labels) && job.labels.every(string) ? job.labels : null,
          runnerName: job.runner_name ?? null, runnerGroupId: job.runner_group_id ?? null,
          runnerGroupName: job.runner_group_name ?? null,
          steps: Array.isArray(job.steps) && job.steps.every(object) ? job.steps.map(step => ({
            number: step.number ?? null, name: step.name ?? null, status: step.status ?? null,
            conclusion: valueOrNull(step.conclusion), startedAt: step.started_at ?? null,
            completedAt: step.completed_at ?? null,
          })) : null});
        if (!identityMatches || !positive(job.id) || seen.has(job.id) || !string(job.name) ||
            !string(job.status) || !Object.hasOwn(job, 'conclusion')) {
          issue(jobsEndpoint, 'Job identity/status missing, duplicated or mismatched; do not combine this evidence');
        }
        seen.add(job.id);
      }
      result.evidenceComplete = report.errors.length === errorsBefore;
    }
  }

  for (const sha of [...new Set([report.target.headSha, report.target.currentMergeTestSha].filter(Boolean))]) {
    const checksEndpoint = `${prefix}/commits/${sha}/check-runs?filter=all&per_page=100`;
    const statusesEndpoint = `${prefix}/commits/${sha}/statuses?per_page=100`;
    const checks = await list(checksEndpoint, 'check_runs');
    const statuses = await list(statusesEndpoint);
    const suites = new Set((checks ?? []).map(check => check.check_suite?.id).filter(positive));
    if (suites.size >= 1000) issue(checksEndpoint, 'GitHub check-suite history cap reached; older checks may be absent');
    report.commitChecks.push({sha, checksAvailable: checks !== null, statusesAvailable: statuses !== null,
      // Commit check/status endpoints have no workflow event/attempt attribution.
      // Keep every observation separate from the run/attempt evidence above.
      checks: (checks ?? []).map(check => ({id: check.id ?? null, name: check.name ?? null,
        headSha: check.head_sha ?? null, status: check.status ?? null, conclusion: valueOrNull(check.conclusion),
        appId: check.app?.id ?? null, url: check.html_url ?? null})),
      statuses: (statuses ?? []).map(status => ({id: status.id ?? null, context: status.context ?? null,
        state: status.state ?? null, createdAt: status.created_at ?? null, url: status.target_url ?? null})),
    });
    if ((checks ?? []).some(check => !positive(check.id) || check.head_sha !== sha || !string(check.name) ||
        !string(check.status) || !Object.hasOwn(check, 'conclusion'))) {
      issue(checksEndpoint, 'Check-run identity/status missing or mismatched');
    }
    if ((statuses ?? []).some(status => !positive(status.id) || !string(status.context) || !string(status.state))) {
      issue(statusesEndpoint, 'Commit-status identity/state missing');
    }
  }
  addTimingEvidence(report, options.compare);
  return report;
}

const clean = value => String(value ?? 'unknown').replace(/[\u0000-\u001f\u007f-\u009f]/gu, ' ');
export function formatHuman(report) {
  const lines = [`${report.repository}${report.target.pr ? ` PR #${report.target.pr}` : ''}`,
    `Source HEAD: ${report.target.headSha ?? 'unknown'}`];
  if (report.target.pr) {
    lines.push(`Current base: ${report.target.baseBranch} at ${report.target.currentBaseSha ?? 'unknown'}`);
    lines.push(`Current PR merge/test ref: ${report.target.currentMergeTestSha ?? 'unknown'} (not historical checkout proof)`);
    lines.push(`PR merge_commit_sha: ${report.target.mergeCommitSha ?? 'unknown'}; state: ${report.target.state ?? 'unknown'}`);
  }
  lines.push(`Evidence: ${report.complete ? 'retrieved' : 'INCOMPLETE'}; required checks: ${report.requiredChecks.state}`);
  lines.push(report.requiredChecks.reason);
  for (const check of report.requiredChecks.checks) {
    lines.push(`  required: ${check.context} (app ${check.appId ?? 'any'})`);
  }
  if (report.requiredChecks.unsupportedRules?.length) {
    lines.push(`  unsupported policy rules: ${report.requiredChecks.unsupportedRules.join(', ')}`);
  }
  for (const run of report.runs) {
    lines.push(`\nWorkflow ${run.workflow ?? 'unknown'} [${run.workflowPath ?? 'unknown'}] run ${run.id}: ${run.url ?? 'unknown'}`);
    for (const attempt of run.attempts) {
      if (!attempt.available) { lines.push(`  attempt ${attempt.number}: unavailable`); continue; }
      lines.push(`  ${attempt.event} | SHA ${attempt.headSha} | ${attempt.sourceMatch} | attempt ${attempt.number}/${run.latestAttempt} | ${attempt.status}/${attempt.conclusion ?? 'pending-or-unknown'}`);
      if (report.target.pr) lines.push(`    PR association: ${attempt.prAssociation}; target PR base: ${attempt.prBaseMatch}`);
      for (const pr of attempt.pullRequests) lines.push(`    associated PR #${pr.number}: head ${pr.headSha ?? 'unknown'}; base ${pr.baseSha ?? 'unknown'}`);
      lines.push(`    tested checkout SHA: unknown; ${attempt.url}`);
      if (!attempt.jobs.length) lines.push(`    jobs: ${attempt.jobsAvailable ? 'absent' : 'unavailable'}`);
      for (const job of attempt.jobs) {
        lines.push(`    ${job.name}: ${job.status}/${job.conclusion ?? 'pending-or-unknown'}${job.identityMatches ? '' : ' [IDENTITY MISMATCH/UNKNOWN]'} | ${job.url ?? 'URL unknown'}`);
        if (!job.identityMatches) lines.push(`      reported job ${job.id}: run ${job.runId}, attempt ${job.attempt}, SHA ${job.headSha}`);
      }
    }
  }
  if (!report.runs.length) lines.push('\nWorkflow runs: absent or unavailable (see discovery/errors)');
  for (const group of report.commitChecks) {
    lines.push(`\nCommit checks at ${group.sha} (event/attempt unattributed):`);
    if (!group.checks.length) lines.push(`  check runs: ${group.checksAvailable ? 'absent' : 'unavailable'}`);
    for (const check of group.checks) lines.push(`  ${check.name}: ${check.status}/${check.conclusion ?? 'pending-or-unknown'} (app ${check.appId ?? 'unknown'}) | ${check.url ?? 'URL unknown'}`);
    if (!group.statuses.length) lines.push(`  statuses: ${group.statusesAvailable ? 'absent' : 'unavailable'}`);
    for (const status of group.statuses) lines.push(`  ${status.context}: ${status.state} at ${status.createdAt ?? 'unknown'} | ${status.url ?? 'URL unknown'}`);
  }
  if (report.timing) lines.push(...formatTiming(report.timing));
  for (const error of report.errors) lines.push(`ERROR ${error.endpoint}: ${error.message}`);
  lines.push('', ...report.limits);
  return lines.map(clean).join('\n');
}

async function main() {
  let options;
  try { options = parseArguments(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 2; return; }
  if (options.help) { console.log(usage); return; }
  let report;
  try { report = await (options.artifacts ? collectArtifactEvidence(options) : collectEvidence(options)); }
  catch { console.error('Selected evidence could not be read or validated'); process.exitCode = 1; return; }
  console.log(options.json ? JSON.stringify(report, null, 2) : options.artifacts ? formatArtifactEvidence(report) : formatHuman(report));
  // Exit status measures retrieval, not CI success. Failed/skipped CI is data.
  process.exitCode = report.complete ? 0 : 1;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
