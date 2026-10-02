// Review/integration projections share ci-evidence's GET-only readers. They do
// not approve reviews, select a merge method, retarget a PR or mutate a ref.
const sha = value => typeof value === 'string' && /^[a-f0-9]{40}$/iu.test(value);
const text = value => typeof value === 'string' && value.length > 0;
const identity = pr => ({headSha: pr?.head?.sha ?? null, headRepository: pr?.head?.repo?.full_name ?? null,
  baseSha: pr?.base?.sha ?? null, baseBranch: pr?.base?.ref ?? null,
  state: pr?.state ?? null, merged: pr?.merged ?? null, draft: pr?.draft ?? null});
const validIdentity = value => sha(value.headSha) && sha(value.baseSha) && text(value.baseBranch);

export async function collectReviewContext(report, options, pr, {read, list, issue}) {
  const prefix = `repos/${report.repository}`;
  const repository = options.integration ? null : await read(prefix);
  const branch = options.integration ?? repository?.default_branch ?? null;
  const branchEndpoint = text(branch) ? `${prefix}/branches/${encodeURIComponent(branch)}` : null;
  const integration = branchEndpoint ? await read(branchEndpoint) : null;
  const integrationSha = sha(integration?.commit?.sha) ? integration.commit.sha : null;
  if (!integrationSha) issue(branchEndpoint ?? prefix, 'Intended integration branch SHA unavailable');
  const context = {branchEndpoint, initial: identity(pr), subjects: [{pr, role: 'selected-pr'}]};
  const result = report.integration = {branch, sha: integrationSha,
    scope: 'Selected PR, same-repository PRs whose head is its current base, and explicitly supplied dependency PRs; not a transitive dependency search.',
    dependencies: [], subjects: [], limits: [
      'Merged records a destination branch, not integration into the intended branch.',
      'Exact ancestry, exact whole-tree equality and merge-result ancestry are separate evidence; none proves semantic equivalence or that later changes were not reverted.',
      'Squash/cherry-pick content correspondence stays unverified unless exact tree evidence establishes it; titles and patch similarity are not used.',
    ]};
  const dependencies = new Set(options.dependencies ?? []);
  if (pr.base.ref !== branch) {
    const owner = report.repository.split('/')[0];
    const endpoint = `${prefix}/pulls?state=all&head=${encodeURIComponent(`${owner}:${pr.base.ref}`)}&per_page=100`;
    const candidates = await list(endpoint);
    for (const candidate of candidates ?? []) {
      // The server's query is not itself identity evidence (forks can reuse names).
      if (candidate.head?.ref === pr.base.ref && candidate.head?.repo?.full_name === report.repository &&
          Number.isSafeInteger(candidate.number) && candidate.number > 0) dependencies.add(candidate.number);
    }
    result.dependencies.push({endpoint, candidates: [...dependencies], available: candidates !== null});
  }
  dependencies.delete(options.pr);
  for (const number of [...dependencies].sort((a, b) => a - b)) {
    const dependency = await read(`${prefix}/pulls/${number}`);
    if (dependency?.number === number) context.subjects.push({pr: dependency, role: 'dependency'});
    else if (dependency) issue(`${prefix}/pulls/${number}`, 'Dependency PR identity mismatched');
  }
  const commits = new Map();
  const commit = async value => {
    if (!sha(value)) return null;
    if (!commits.has(value)) {
      const endpoint = `${prefix}/git/commits/${value}`;
      const found = await read(endpoint);
      if (found && (found.sha !== value || !sha(found.tree?.sha))) {
        issue(endpoint, 'Commit/tree identity missing or mismatched');
        commits.set(value, null);
      } else commits.set(value, found);
    }
    return commits.get(value);
  };
  const intended = await commit(integrationSha);
  const compare = async source => {
    const evidence = {sourceSha: source, targetSha: integrationSha, state: 'unknown', endpoint: null};
    if (!sha(source) || !integrationSha) return evidence;
    if (source === integrationSha) return {...evidence, state: 'reachable', reason: 'identical-commit'};
    const endpoint = `${prefix}/compare/${source}...${integrationSha}`;
    const comparison = await read(endpoint);
    evidence.endpoint = endpoint;
    if (!comparison) return evidence;
    evidence.status = comparison.status ?? null;
    evidence.mergeBaseSha = comparison.merge_base_commit?.sha ?? null;
    if (comparison.base_commit?.sha !== source || !sha(evidence.mergeBaseSha)) {
      issue(endpoint, 'Comparison identity or merge base unavailable');
    } else if (['ahead', 'identical'].includes(comparison.status) && evidence.mergeBaseSha === source) {
      evidence.state = 'reachable';
    } else if (['behind', 'diverged'].includes(comparison.status) && evidence.mergeBaseSha !== source) {
      evidence.state = 'not-reachable';
    } else issue(endpoint, 'Comparison ancestry metadata inconsistent');
    return evidence;
  };
  for (const subject of context.subjects) {
    const item = subject.pr;
    subject.initial = identity(item);
    const source = await commit(item.head?.sha);
    const merged = item.merged === true;
    const mergeResult = merged ? await commit(item.merge_commit_sha) : null;
    const headAncestry = await compare(item.head?.sha ?? null);
    const mergeResultAncestry = merged ? await compare(item.merge_commit_sha ?? null) : null;
    const treeEquality = (left, right) => !left || !right ? 'unknown' : left.tree.sha === right.tree.sha ? 'equal' : 'different';
    const headToIntegrationTree = treeEquality(source, intended);
    const headToMergeResultTree = treeEquality(source, mergeResult);
    const relation = headAncestry.state === 'reachable' ? 'exact-head-reachable' :
      headToIntegrationTree === 'equal' ? 'equivalent-tree-at-integration-tip' :
      mergeResultAncestry?.state === 'reachable' ?
        (headToMergeResultTree === 'equal' ? 'equivalent-tree-in-reachable-merge-result' : 'merge-result-reachable-content-unverified') :
        headAncestry.state === 'not-reachable' && (!merged || mergeResultAncestry?.state === 'not-reachable') ?
          'not-reachable-content-unverified' : 'unknown';
    result.subjects.push({number: item.number ?? null, role: subject.role, url: item.html_url ?? null,
      ...subject.initial, mergedAt: item.merged_at ?? null,
      mergeDestination: merged ? {repository: item.base?.repo?.full_name ?? report.repository, branch: item.base?.ref ?? null} : null,
      mergeResultSha: merged && sha(item.merge_commit_sha) ? item.merge_commit_sha : null,
      headTreeSha: source?.tree.sha ?? null, integrationTreeSha: intended?.tree.sha ?? null,
      mergeResultTreeSha: mergeResult?.tree.sha ?? null,
      headAncestry, mergeResultAncestry, headToIntegrationTree, headToMergeResultTree, relation,
      nextStep: relation === 'not-reachable-content-unverified' ?
        `Verify and integrate the ${merged ? `merge result from ${item.base?.ref ?? 'unknown destination'}` : 'PR changes'} into ${branch ?? 'the intended branch'}; squash/cherry-pick correspondence is unverified.` :
        relation === 'unknown' || relation === 'merge-result-reachable-content-unverified' ?
          'Obtain missing ancestry/content evidence before claiming the original changes are integrated.' : null});
  }
  const mergeCommit = await commit(report.target.currentMergeTestSha);
  report.target.currentMergeTestTreeSha = mergeCommit?.tree.sha ?? null;
  const parents = mergeCommit?.parents?.map(parent => parent.sha) ?? null;
  report.target.mergeTestParents = parents;
  report.target.mergeTestRelationship = parents?.length === 2 && parents[0] === report.target.currentBaseSha &&
    parents[1] === report.target.headSha ? 'current-base-and-head' : mergeCommit ? 'mismatched-or-unverified-parents' : 'unknown';
  const reviewsEndpoint = `${prefix}/pulls/${options.pr}/reviews?per_page=100`;
  const reviews = await list(reviewsEndpoint);
  report.reviews = {available: reviews !== null, endpoint: reviewsEndpoint,
    policy: 'unknown; observed reviews are not an approval or code-owner satisfaction decision',
    observations: (reviews ?? []).map(review => ({id: review.id ?? null, reviewer: review.user?.login ?? null,
      state: review.state ?? null, commitSha: review.commit_id ?? null, submittedAt: review.submitted_at ?? null,
      sourceMatch: !sha(review.commit_id) ? 'unknown' : review.commit_id === report.target.headSha ? 'exact-head' : 'stale-head',
      url: review.html_url ?? null}))};
  return context;
}

function requiredObservations(report) {
  const dedup = new Map();
  for (const required of report.requiredChecks.checks) {
    const appId = required.appId === -1 ? null : required.appId;
    const key = JSON.stringify([required.context, appId]);
    if (!dedup.has(key)) dedup.set(key, {...required, appId, sources: []});
    dedup.get(key).sources.push(required.source);
  }
  const jobs = [];
  for (const run of report.runs) for (const attempt of run.attempts) for (const job of attempt.jobs) {
    jobs.push({runId: run.id, attempt: attempt.number, latestAttempt: run.latestAttempt,
      workflowPath: attempt.workflowPath ?? null, workflowId: attempt.workflowId ?? null,
      event: attempt.event ?? null, sourceSha: attempt.headSha ?? null, sourceMatch: attempt.sourceMatch ?? 'unknown',
      prAssociation: attempt.prAssociation ?? 'unknown', prBaseMatch: attempt.prBaseMatch ?? 'unknown',
      checkSuiteId: attempt.checkSuiteId ?? null, evidenceComplete: attempt.evidenceComplete ?? false,
      jobId: job.id, name: job.name, checkRunUrl: job.checkRunUrl, identityMatches: job.identityMatches,
      status: job.status, conclusion: job.conclusion, url: job.url});
  }
  return [...dedup.values()].map(required => ({...required,
    // Unknown policy remains unknown even if some readable source named checks.
    authoritative: report.requiredChecks.state === 'known',
    sourcesAtRevision: report.commitChecks.map(group => {
      const candidates = group.checks.filter(check => check.name === required.context &&
        (required.appId === null || check.appId === required.appId)).map(check => {
        const matches = jobs.filter(job => job.checkRunUrl === `https://api.github.com/repos/${report.repository}/check-runs/${check.id}` &&
          job.identityMatches && job.sourceSha === check.headSha &&
          job.checkSuiteId != null && job.checkSuiteId === check.checkSuiteId);
        const run = matches.length === 1 ? matches[0] : null;
        return {...check, attribution: run, attributionState: run ? 'exact-check-run-and-suite' : 'unknown',
          revisionMatch: check.headSha === group.sha ? (group.sha === report.target.headSha ? 'exact-head' : 'current-merge-test-ref') : 'mismatched-sha',
          attemptState: run ? run.attempt === run.latestAttempt ? 'latest-observed-attempt' : 'superseded-attempt' : 'unknown'};
      });
      const statuses = group.statuses.filter(status => status.context === required.context).map(status => ({...status,
        sourceSha: group.sha, appMatch: required.appId === null ? 'any-app' : 'unknown'}));
      const current = candidates.filter(check => check.attemptState !== 'superseded-attempt');
      const incomplete = !group.checksAvailable || !group.statusesAvailable || candidates.some(check => check.revisionMatch === 'mismatched-sha');
      const ambiguous = current.length > 1 || statuses.length > 1 || current.length > 0 && statuses.length > 0;
      const observed = current[0] ?? statuses[0];
      const state = incomplete ? 'unknown' : ambiguous ? 'multiple-observations' : !observed ? 'missing' :
        current.length ? observed.status === 'completed' ? `completed-${observed.conclusion ?? 'unknown'}` : 'running-or-pending' :
          observed.appMatch === 'unknown' ? 'unknown-app-source' :
            observed.state === 'pending' ? 'running-or-pending' : `status-${observed.state ?? 'unknown'}`;
      return {sourceSha: group.sha, sourceRelationship: group.sha === report.target.headSha ? 'head' : 'merge-test-ref',
        state, checks: candidates, statuses};
    }),
    relatedJobs: jobs.filter(job => job.name === required.context),
  }));
}

export async function finishReviewEvidence(report, options, context, {read, issue}) {
  const prefix = `repos/${report.repository}`;
  report.requiredChecks.observations = requiredObservations(report);
  const changes = [];
  // Recheck each dependency and the intended branch, then the merge ref, and
  // read the selected PR last. A changed boundary invalidates stable evidence.
  for (const subject of context.subjects.filter(subject => subject.role === 'dependency')) {
    const current = await read(`${prefix}/pulls/${subject.pr.number}`);
    if (!current || JSON.stringify(identity(current)) !== JSON.stringify(subject.initial) ||
        current.merge_commit_sha !== subject.pr.merge_commit_sha) changes.push(`dependency-pr-${subject.pr.number}`);
  }
  if (context.branchEndpoint) {
    const current = await read(context.branchEndpoint);
    if (current?.commit?.sha !== report.integration.sha) changes.push('integration-branch');
  }
  if (report.target.currentMergeTestSha) {
    const current = await read(`${prefix}/git/ref/pull/${options.pr}/merge`);
    if (current?.object?.sha !== report.target.currentMergeTestSha) changes.push('merge-test-ref');
  }
  const endpoint = `${prefix}/pulls/${options.pr}`;
  const current = await read(endpoint);
  const final = identity(current);
  const known = current && validIdentity(context.initial) && validIdentity(final);
  if (known && JSON.stringify(final) !== JSON.stringify(context.initial)) changes.push('selected-pr-revision-or-state');
  const state = !known ? 'unknown' : changes.length ? 'changed' : 'stable-observed';
  report.revision = {state, initial: context.initial, final, changedBoundaries: changes,
    finalReadAt: new Date().toISOString(), endpoint,
    reason: 'Sequential boundary rereads detect observed movement; they cannot guarantee an atomic snapshot or future stability.'};
  if (state !== 'stable-observed') issue(endpoint, 'Revision changed or unavailable at final reread; recollect before using this evidence');
  report.reviewEvidence = {revision: state, requirements: report.requiredChecks.state,
    draft: report.target.draft, mergeable: report.target.mergeable, mergeabilityState: report.target.mergeabilityState,
    finalDraft: typeof current?.draft === 'boolean' ? current.draft : null,
    finalMergeable: typeof current?.mergeable === 'boolean' ? current.mergeable : null,
    finalMergeabilityState: current?.mergeable_state ?? 'unknown',
    verdict: 'not-issued',
    limits: ['Named check observations are not GitHub requirement satisfaction; merge-ref precedence, app identity, duplicate names, event eligibility and historical status ordering remain explicit.',
      'Skipped/neutral checks may satisfy GitHub policy but are not successful execution evidence. Cancelled is not success.',
      'Review observations retain their commit binding; stale approvals never become current-head approval evidence. Code-owner/review policy is not inferred.',
      'No review-ready, merge-ready, deployment or semantic integration decision is made.']};
}

export function formatReview(report) {
  if (!report.revision) return [];
  const lines = [`\nRevision: ${report.revision.state}; final HEAD: ${report.revision.final.headSha ?? 'unknown'}; final base: ${report.revision.final.baseBranch ?? 'unknown'} at ${report.revision.final.baseSha ?? 'unknown'}`,
    `Draft: ${report.reviewEvidence.finalDraft ?? 'unknown'}; mergeable: ${report.reviewEvidence.finalMergeable ?? 'unknown'}; mergeability: ${report.reviewEvidence.finalMergeabilityState}`,
    `Merge/test tree: ${report.target.currentMergeTestTreeSha ?? 'unknown'}; parents: ${report.target.mergeTestRelationship}`,
    `Intended integration: ${report.integration.branch ?? 'unknown'} at ${report.integration.sha ?? 'unknown'}`,
    report.integration.scope];
  for (const item of report.integration.subjects) {
    lines.push(`  ${item.role} #${item.number}: HEAD ${item.headSha}; base ${item.baseBranch} at ${item.baseSha}; merged ${item.merged ?? 'unknown'}`,
      `    merge destination: ${item.mergeDestination ? `${item.mergeDestination.repository}:${item.mergeDestination.branch}` : 'not merged/unknown'}; merge result ${item.mergeResultSha ?? 'unknown'}`,
      `    integration relationship: ${item.relation}; head ancestry ${item.headAncestry.state}; merge-result ancestry ${item.mergeResultAncestry?.state ?? 'not-applicable'}`,
      `    trees: HEAD ${item.headTreeSha ?? 'unknown'}; merge result ${item.mergeResultTreeSha ?? 'unknown'}; integration ${item.integrationTreeSha ?? 'unknown'}`);
    if (item.nextStep) lines.push(`    next step: ${item.nextStep}`);
  }
  for (const required of report.requiredChecks.observations) {
    lines.push(`\nRequirement observation: ${required.context} (app ${required.appId ?? 'any'}; policy ${required.authoritative ? 'known' : 'unknown'})`);
    for (const source of required.sourcesAtRevision) {
      lines.push(`  ${source.sourceRelationship} ${source.sourceSha}: ${source.state}`);
      for (const check of source.checks) lines.push(`    check ${check.id}: ${check.status}/${check.conclusion ?? 'unknown'}; SHA ${check.headSha}; ${check.attemptState}; ${check.attribution ? `run ${check.attribution.runId} attempt ${check.attribution.attempt} ${check.attribution.event} [${check.attribution.workflowPath}] PR association ${check.attribution.prAssociation}, base ${check.attribution.prBaseMatch}` : 'event/attempt unattributed'}`);
      for (const status of source.statuses) lines.push(`    status ${status.id}: ${status.state}; app match ${status.appMatch}`);
    }
    for (const job of required.relatedJobs) lines.push(`  same-named job (not matched by name alone): run ${job.runId} attempt ${job.attempt}/${job.latestAttempt} ${job.event} [${job.workflowPath}] SHA ${job.sourceSha} ${job.sourceMatch} ${job.status}/${job.conclusion ?? 'unknown'}`);
  }
  lines.push(`\nReviews: ${report.reviews.available ? 'observed' : 'unavailable'}; ${report.reviews.policy}`);
  for (const review of report.reviews.observations) lines.push(`  ${review.reviewer ?? 'unknown'}: ${review.state ?? 'unknown'} on ${review.commitSha ?? 'unknown'} (${review.sourceMatch})`);
  if (report.revision.changedBoundaries.length) lines.push(`CHANGED: ${report.revision.changedBoundaries.join(', ')}`);
  return [...lines, ...report.integration.limits, ...report.reviewEvidence.limits];
}
