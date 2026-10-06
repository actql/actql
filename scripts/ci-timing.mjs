// Timing projection of the existing attempt-bound evidence; no extra API calls.
// A timestamp is evidence only when it is a real, timezone-qualified instant.
function instant(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,3}))?(Z|[+-](\d\d):(\d\d))$/u.exec(value);
  if (!match || Number(match[4] ?? 0) > 23 || Number(match[5] ?? 0) > 59) return null;
  const local = `${match[1]}.${(match[2] ?? '').padEnd(3, '0')}Z`;
  const calendar = Date.parse(local), parsed = Date.parse(value);
  if (!Number.isFinite(calendar) || new Date(calendar).toISOString() !== local || !Number.isFinite(parsed)) return null;
  return parsed;
}
const boundary = (endpoint, field, value) => ({endpoint, field, value: value ?? null});
function interval(from, to, reason = null) {
  const start = instant(from.value), end = instant(to.value);
  reason ??= from.value == null || to.value == null ? 'missing-timestamp' :
    start === null || end === null ? 'invalid-timestamp' : end < start ? 'reversed-timestamps' : null;
  return {from, to, seconds: reason ? null : (end - start) / 1000, reason};
}
const executionReason = item => item.conclusion === 'skipped' ? 'skipped-not-executed' :
  item.status !== 'completed' ? 'not-completed' :
    typeof item.conclusion !== 'string' || !item.conclusion ? 'missing-outcome' : null;
const execution = (item, endpoint, prefix = '') => interval(
  boundary(endpoint, `${prefix}started_at`, item.startedAt),
  boundary(endpoint, `${prefix}completed_at`, item.completedAt), executionReason(item));
const precisionAllowance = value => 10 ** (3 - (value?.match(/\.(\d{1,3})(?:Z|[+-])/u)?.[1].length ?? 0)) - 1;
const knownNumber = value => Number.isSafeInteger(value) && value > 0;
const knownString = value => typeof value === 'string' && value.length > 0;
function stats(rows) {
  const values = rows.map(row => row.execution.seconds).filter(value => value !== null).sort((a, b) => a - b);
  const middle = Math.floor(values.length / 2);
  return {selectedCount: rows.length, sampleCount: values.length, omittedCount: rows.length - values.length,
    medianSeconds: values.length ? (values[middle] + values[Math.floor((values.length - 1) / 2)]) / 2 : null,
    maximumSeconds: values.length ? values.at(-1) : null};
}
function configuration(attempt) {
  const jobs = attempt.jobs;
  // These are observed dimensions, not a claim about resolved action refs,
  // dispatch inputs, runner image versions, historical checkout or cache hits.
  const known = knownString(attempt.workflowPath) && knownNumber(attempt.workflowId) && jobs.length > 0 &&
    new Set(jobs.map(job => job.name)).size === jobs.length &&
    jobs.every(job => job.conclusion === 'skipped' || job.runnerLabels?.length && job.steps?.length && job.steps.every(step =>
      knownNumber(step.number) && knownString(step.name))) &&
    (attempt.event !== 'pull_request' || attempt.pullRequests.length > 0 && attempt.pullRequests.every(pr => /^[a-f0-9]{40}$/iu.test(pr.baseSha ?? ''))) &&
    !['workflow_dispatch', 'repository_dispatch', 'workflow_call'].includes(attempt.event);
  return {known, observed: {
    workflowPath: attempt.workflowPath, workflowId: attempt.workflowId,
    prBases: attempt.pullRequests.map(pr => [pr.number, pr.baseSha]).sort(),
    jobs: jobs.map(job => ({name: job.name, status: job.status, conclusion: job.conclusion, labels: job.runnerLabels?.toSorted() ?? null,
      runnerGroupId: job.runnerGroupId, runnerGroupName: job.runnerGroupName,
      steps: job.steps?.map(step => [step.number, step.name, step.status, step.conclusion]) ?? null})).sort((a, b) => String(a.name).localeCompare(String(b.name))),
  }};
}

function runnerConsumption(attempt, jobs, common, wallSpan, steps) {
  const observations = jobs.map((row, index) => {
    const job = attempt.jobs[index];
    const skipped = job.conclusion === 'skipped';
    const startedStep = steps.some(step => step.jobId === row.jobId && step.identityValid && step.execution.seconds !== null);
    const reason = skipped ? 'skipped-not-executed' : row.execution.reason ??
      (!knownString(job.runnerName) || !job.runnerLabels?.length ? 'missing-runner-observation' :
        !startedStep ? 'no-observed-step-execution' :
          job.steps.some(step => step.status !== 'completed') ? 'incomplete-step-execution' : null);
    return {jobId: row.jobId, jobName: row.jobName, runnerName: job.runnerName,
      execution: {...row.execution, seconds: reason ? null : row.execution.seconds, reason}, skipped};
  });
  const executed = observations.filter(row => !row.skipped);
  const measured = executed.filter(row => row.execution.seconds !== null);
  // Count distinct jobs once, never steps or nested phase measurements.
  // Millisecond timestamps avoid fractional addition drift; overflow is unknown.
  const milliseconds = measured.map(row => Math.round(row.execution.seconds * 1000));
  const total = milliseconds.reduce((sum, value) => sum + value, 0);
  const safe = milliseconds.every(Number.isSafeInteger) && Number.isSafeInteger(total);
  const reason = !attempt.evidenceComplete || !attempt.jobsAvailable ? 'incomplete-or-mismatched-evidence' :
    executionReason(attempt) ?? (!executed.length ? 'no-executed-job' :
      measured.length !== executed.length ? 'incomplete-job-execution' : !safe ? 'duration-overflow' : null);
  return {...common, status: attempt.status, conclusion: attempt.conclusion,
    boundary: 'sum of distinct observed job started_at -> completed_at intervals',
    successfulSample: reason === null && attempt.conclusion === 'success' && executed.every(row =>
      attempt.jobs.find(job => job.id === row.jobId).conclusion === 'success'),
    knownJobSeconds: safe ? total / 1000 : null,
    totalJobSeconds: reason === null ? total / 1000 : null,
    reason, measuredJobCount: measured.length, unknownJobCount: executed.length - measured.length,
    skippedJobCount: observations.length - executed.length,
    observedJobWallSpan: wallSpan, jobs: observations};
}

export function addTimingEvidence(report, selection = []) {
  const timing = report.timing = {observedAt: report.observedAt, configurations: [], measurements: [], runnerConsumption: [], longestJobs: [], longestSteps: [],
    comparison: {selection, groups: [], unavailable: []}, limits: [
      'Timing is not successful test evidence and does not change check conclusions or readiness uncertainty.',
      'Execution uses reported started_at -> completed_at. Running/skipped durations are unknown, not zero or completed samples.',
      'Observed pre-start delay is not proven runner queue time: dependency-ready and scheduling timestamps are unavailable.',
      'Attempt execution is the observed job wall span (earliest job start -> latest job completion), not a job-duration sum or dependency critical path.',
      'Run updated_at is retained but is not a completion timestamp; no run-start -> updated_at duration is inferred.',
      'Comparisons separate reported SHA, workflow, event, attempt, outcomes, completeness and observed configuration; missing configuration is isolated by run.',
      'Matching observed configuration does not prove matching checkout, runner image, action/dependency refs or cache state. Cache state stays unknown; dispatch inputs are unavailable.',
      'Runner consumption sums distinct completed job intervals once, including setup/transfer/check work inside each job; steps and Session phase sums are not added to it.',
      'Jobs without an observed runner or started step leave runner totals unknown. Failed/cancelled attempts retain measured consumption but are not successful comparison samples.',
      'Job-duration totals are observed runner time, not billed minutes or causal savings. Cross-revision savings still require authenticated equal-input/obligation evidence and comparable execution conditions.',
    ]};
  const attempts = new Map(), configurations = new Map();
  for (const run of report.runs) for (const attempt of run.attempts) {
    const key = `${run.id}:${attempt.number}`;
    if (!attempt.available) { attempts.set(key, []); continue; }
    const config = configuration(attempt), configKey = JSON.stringify(config);
    if (!configurations.has(configKey)) {
      const id = `configuration-${configurations.size + 1}`;
      configurations.set(configKey, id);
      timing.configurations.push({id, ...config});
    }
    const configurationId = configurations.get(configKey);
    const common = {repository: report.repository, runId: run.id, attempt: attempt.number,
      workflow: attempt.workflow, workflowPath: attempt.workflowPath, workflowId: attempt.workflowId,
      event: attempt.event, sourceSha: attempt.headSha, sourceMatch: attempt.sourceMatch,
      attemptStatus: attempt.status, attemptConclusion: attempt.conclusion,
      evidenceComplete: attempt.evidenceComplete, configurationId, configurationKnown: config.known, cacheState: 'unknown'};
    const rows = [];
    const jobs = attempt.jobs.map(job => {
      const identityValid = attempt.evidenceComplete && job.identityMatches;
      const row = {...common, kind: 'job', jobId: job.id, jobName: job.name, stepNumber: null, stepName: null,
        runnerLabels: job.runnerLabels, runnerName: job.runnerName, runnerGroupId: job.runnerGroupId,
        status: job.status, conclusion: job.conclusion, identityValid,
        stepsState: job.steps === null ? 'unknown' : job.steps.length ? 'available' : 'absent',
        timestamps: {createdAt: job.createdAt, startedAt: job.startedAt, completedAt: job.completedAt},
        execution: execution(job, job.endpoint, `jobs[id=${job.id}].`),
        preStart: interval(boundary(job.endpoint, `jobs[id=${job.id}].created_at`, job.createdAt),
          boundary(job.endpoint, `jobs[id=${job.id}].started_at`, job.startedAt), job.conclusion === 'skipped' ? 'skipped-not-executed' : null),
        sinceAttemptStart: interval(boundary(attempt.endpoint, 'run_started_at', attempt.startedAt),
          boundary(job.endpoint, `jobs[id=${job.id}].started_at`, job.startedAt), job.conclusion === 'skipped' ? 'skipped-not-executed' : null),
      };
      if (!identityValid) for (const name of ['execution', 'preStart', 'sinceAttemptStart']) {
        row[name] = {...row[name], seconds: null, reason: 'incomplete-or-mismatched-evidence'};
      }
      rows.push(row);
      const numbers = (job.steps ?? []).map(step => step.number);
      for (const step of job.steps ?? []) {
        const valid = identityValid && knownNumber(step.number) && knownString(step.name) &&
          numbers.filter(number => number === step.number).length === 1;
        const measured = execution(step, job.endpoint, `jobs[id=${job.id}].steps[number=${step.number}].`);
        const parentStart = instant(job.startedAt), parentEnd = instant(job.completedAt);
        // Whole-second parent timestamps have up to one second less precision
        // than fractional step timestamps. Do not invent a parent bound.
        const outside = measured.seconds !== null && (
          parentStart !== null && instant(step.startedAt) < parentStart - precisionAllowance(job.startedAt) ||
          parentEnd !== null && instant(step.completedAt) > parentEnd + precisionAllowance(job.completedAt));
        if (job.conclusion === 'skipped' || outside) {
          measured.seconds = null;
          measured.reason = 'inconsistent-parent-job';
        }
        rows.push({...common, kind: 'step', jobId: job.id, jobName: job.name,
          stepNumber: step.number, stepName: step.name, runnerLabels: job.runnerLabels,
          runnerName: job.runnerName, runnerGroupId: job.runnerGroupId, status: step.status, conclusion: step.conclusion,
          identityValid: valid, timestamps: {startedAt: step.startedAt, completedAt: step.completedAt},
          execution: valid ? measured : {...measured, seconds: null, reason: 'incomplete-or-mismatched-evidence'},
        });
      }
      return row;
    });
    const executed = jobs.filter(job => job.conclusion !== 'skipped');
    const complete = attempt.evidenceComplete && attempt.jobsAvailable && !executionReason(attempt) &&
      executed.length > 0 && executed.every(job => job.execution.seconds !== null);
    const first = complete ? executed.reduce((a, b) => instant(a.execution.from.value) < instant(b.execution.from.value) ? a : b) : null;
    const last = complete ? executed.reduce((a, b) => instant(a.execution.to.value) > instant(b.execution.to.value) ? a : b) : null;
    rows.unshift({...common, kind: 'attempt', jobId: null, jobName: null, stepNumber: null, stepName: null,
      runnerLabels: jobs.map(job => ({jobId: job.jobId, labels: job.runnerLabels})),
      status: attempt.status, conclusion: attempt.conclusion, identityValid: attempt.evidenceComplete,
      timestamps: {createdAt: attempt.createdAt, startedAt: attempt.startedAt, updatedAt: attempt.updatedAt},
      execution: interval(first?.execution.from ?? boundary(attempt.endpoint, 'earliest jobs.started_at', null),
        last?.execution.to ?? boundary(attempt.endpoint, 'latest jobs.completed_at', null), complete ? null : 'incomplete-job-wall-span'),
      preStart: interval(boundary(attempt.endpoint, 'created_at', attempt.createdAt),
        boundary(attempt.endpoint, 'run_started_at', attempt.startedAt), !attempt.evidenceComplete ? 'incomplete-or-mismatched-evidence' :
          attempt.number === 1 ? null : 'creation-is-not-retry-admission'),
    });
    timing.runnerConsumption.push(runnerConsumption(attempt, jobs, common, rows[0].execution, rows.filter(row => row.kind === 'step')));
    attempts.set(key, rows);
    timing.measurements.push(...rows);
  }
  // Rankings retain the complete measurement, including every identity and
  // boundary. Parallel jobs are ranked individually and are never summed.
  for (const [kind, key] of [['job', 'longestJobs'], ['step', 'longestSteps']]) {
    timing[key] = timing.measurements.filter(row => row.kind === kind && row.execution.seconds !== null)
      .sort((a, b) => b.execution.seconds - a.execution.seconds).slice(0, 10);
  }
  const groups = new Map();
  for (const key of selection) {
    const rows = attempts.get(key);
    if (!rows?.length) { timing.comparison.unavailable.push(key); continue; }
    for (const row of rows) {
      const dimensions = {kind: row.kind, workflow: row.workflow, sourceSha: row.sourceSha,
        sourceMatch: row.sourceMatch, event: row.event, attempt: row.attempt,
        attemptStatus: row.attemptStatus, attemptConclusion: row.attemptConclusion,
        status: row.status, conclusion: row.conclusion, evidenceComplete: row.evidenceComplete,
        identityValid: row.identityValid, timingState: row.execution.reason ?? 'completed', configurationId: row.configurationId,
        jobName: row.jobName, stepNumber: row.stepNumber, stepName: row.stepName,
        // Unknown configuration cannot silently create a homogeneous sample.
        isolatedRun: row.configurationKnown ? null : row.runId,
        isolatedJob: row.configurationKnown ? null : row.jobId};
      const groupKey = JSON.stringify(dimensions);
      if (!groups.has(groupKey)) groups.set(groupKey, {dimensions, rows: []});
      groups.get(groupKey).rows.push(row);
    }
  }
  timing.comparison.groups = [...groups.values()].map(({dimensions, rows}) => ({dimensions,
    members: rows.map(row => ({runId: row.runId, attempt: row.attempt, jobId: row.jobId,
      stepNumber: row.stepNumber, omittedReason: row.execution.reason})), ...stats(rows)}));
}

function show(interval) {
  return `${interval.seconds === null ? `unknown (${interval.reason})` : `${interval.seconds}s`} ` +
    `[${interval.from.endpoint} ${interval.from.field}=${interval.from.value ?? 'unknown'} -> ` +
    `${interval.to.endpoint} ${interval.to.field}=${interval.to.value ?? 'unknown'}]`;
}
const identity = row => `${row.workflow} [${row.workflowPath}] | ${row.event} | SHA ${row.sourceSha} | ${row.sourceMatch} | run ${row.runId} attempt ${row.attempt} | ${row.status}/${row.conclusion ?? 'unknown'}`;
const subject = row => row.kind === 'attempt' ? 'observed job wall span' :
  `${row.jobName}${row.kind === 'step' ? ` / step ${row.stepNumber} ${row.stepName}` : ''}`;
export function formatTiming(timing) {
  const lines = [`\nTiming observed at ${timing.observedAt}:`];
  for (const config of timing.configurations) lines.push(`  ${config.id}: ${JSON.stringify(config)}`);
  for (const row of timing.measurements) {
    lines.push(`  ${identity(row)} | ${subject(row)} | labels ${JSON.stringify(row.runnerLabels)}`);
    lines.push(`    execution: ${show(row.execution)}`);
    lines.push(`    timestamps: ${JSON.stringify(row.timestamps)}`);
    if (row.kind === 'job') lines.push(`    steps: ${row.stepsState}`);
    if (row.preStart) lines.push(`    observed pre-start delay: ${show(row.preStart)}`);
    if (row.sinceAttemptStart) lines.push(`    observed since attempt start: ${show(row.sinceAttemptStart)}`);
  }
  for (const [label, rows] of [['Longest jobs', timing.longestJobs], ['Longest steps', timing.longestSteps]]) {
    lines.push(`${label} (individual execution intervals):`);
    for (const row of rows) lines.push(`  ${row.execution.seconds}s | ${subject(row)} | ${identity(row)} | labels ${JSON.stringify(row.runnerLabels)}`);
  }
  for (const total of timing.runnerConsumption) {
    lines.push(`Runner consumption: ${identity(total)} | total ${total.totalJobSeconds === null ? `unknown (${total.reason})` : `${total.totalJobSeconds}s`} | known partial ${total.knownJobSeconds ?? 'unknown'}s | measured jobs ${total.measuredJobCount}, unknown ${total.unknownJobCount}, skipped ${total.skippedJobCount} | successful sample ${total.successfulSample}`);
    lines.push(`  observed job wall span: ${show(total.observedJobWallSpan)}`);
    for (const job of total.jobs) lines.push(`  job ${job.jobId} ${job.jobName}: ${show(job.execution)}`);
  }
  lines.push(`Timing comparison selection: ${timing.comparison.selection.join(', ') || 'none (use --compare RUN:ATTEMPT,...)'}`);
  for (const group of timing.comparison.groups) {
    lines.push(`  group ${JSON.stringify(group.dimensions)}`);
    lines.push(`    selected ${group.selectedCount}; completed samples ${group.sampleCount}; omitted ${group.omittedCount}; median ${group.medianSeconds === null ? 'unknown' : `${group.medianSeconds}s`}; maximum ${group.maximumSeconds === null ? 'unknown' : `${group.maximumSeconds}s`}`);
    lines.push(`    members ${JSON.stringify(group.members)}`);
  }
  if (timing.comparison.unavailable.length) lines.push(`  unavailable selections: ${timing.comparison.unavailable.join(', ')}`);
  return [...lines, ...timing.limits];
}
