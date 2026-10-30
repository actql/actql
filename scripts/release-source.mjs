// Local Git and review-DATA inspection only. Neither a matching origin URL nor
// an author-written maintenance label proves protected review or publication.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {admitReleasePolicy, admitReleaseRequest} from './release-policy.mjs';

const exact = (value, keys) => {
  assert(value && typeof value === 'object' && !Array.isArray(value));
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort());
};
const text = value => assert(typeof value === 'string' && value.length && value === value.trim() && !/[\u0000-\u001f\u007f]/u.test(value));
const sha = value => assert(typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value));

export function admitReleaseBranches(value, policy) {
  const selected = admitReleasePolicy(policy);
  exact(value, ['schemaVersion', 'lines']);
  assert.equal(value.schemaVersion, 'actql-release-branches/0.1');
  assert(Array.isArray(value.lines));
  assert.deepEqual(value.lines.map(item => item.line).sort(), [...selected.allowedLines].sort(),
    'Every allowed line needs exactly one explicit source-branch choice');
  for (const item of value.lines) {
    exact(item, ['line', 'sourceBranch', 'maintenanceCut']);
    if (item.maintenanceCut === null) assert.equal(item.sourceBranch, 'main');
    else {sha(item.maintenanceCut); assert.equal(item.sourceBranch, `release/${item.line}`);}
  }
  return structuredClone(value);
}

export function inspectReleaseSource({repository, request, policy, branches}) {
  const selected = admitReleaseRequest(request, policy);
  const configuration = admitReleaseBranches(branches, policy);
  const line = configuration.lines.find(value => value.line === selected.version.line);
  assert.equal(request.source.branch, line.sourceBranch, 'Candidate must name the selected development or maintenance source branch');
  const git = (...args) => execFileSync('git', ['--no-replace-objects', ...args],
    {cwd: repository, encoding: 'utf8', timeout: 15_000, maxBuffer: 16 * 1024 * 1024});
  const ancestor = (before, after) => {
    try {git('merge-base', '--is-ancestor', before, after); return true;}
    catch (failure) {if (failure.status === 1) return false; throw failure;}
  };
  const commit = value => {sha(value); assert.equal(git('rev-parse', '--verify', `${value}^{commit}`).trim(), value);};
  const ref = name => git('rev-parse', '--verify', `refs/heads/${name}`).trim();
  const branchTip = ref(line.sourceBranch), mainTip = ref('main');
  commit(request.source.commit);
  assert(ancestor(request.source.commit, branchTip), 'Fixed source is not on its named source branch');
  const findings = [], commits = [];
  if (line.maintenanceCut !== null) {
    commit(line.maintenanceCut);
    assert(ancestor(line.maintenanceCut, request.source.commit), 'Maintenance source predates or diverges from its fixed cut');
    const names = git('rev-list', '--reverse', `${line.maintenanceCut}..${request.source.commit}`).trim().split('\n').filter(Boolean);
    const development = new Set(git('rev-list', mainTip, '--not', line.maintenanceCut).trim().split('\n').filter(Boolean));
    const shared = names.filter(value => development.has(value));
    if (shared.length) findings.push({kind: 'development-history-crossed-cut', commits: shared,
      reason: 'Do not merge the whole development graph into maintenance; use isolated reviewed commit backports'});
    for (const name of names) {
      const parents = git('show', '-s', '--format=%P', name).trim().split(' ').filter(Boolean);
      const message = git('show', '-s', '--format=%B', name);
      const markers = [...message.matchAll(/^\(cherry picked from commit ([a-f0-9]{40})\)$/gmu)].map(value => value[1]);
      assert(markers.length <= 1, 'Ambiguous backport origin markers');
      let originCommit = markers[0] ?? null;
      if (originCommit !== null) {
        commit(originCommit);
        assert(ancestor(originCommit, mainTip), 'Backport origin is not in the observed development history');
      }
      const changedPaths = git('diff-tree', '--no-commit-id', '--name-only', '-r', '-m', '-z', name)
        .split('\0').filter(Boolean);
      commits.push({commit: name, parents, subject: message.split('\n')[0],
        changedPaths: [...new Set(changedPaths)].sort(), originCommit,
        origin: originCommit ? 'main-backport' : parents.length > 1 ? 'integration' : 'maintenance-only-or-unrecorded'});
    }
  }
  assert.equal(ref(line.sourceBranch), branchTip, 'Source branch changed during inspection');
  assert.equal(ref('main'), mainTip, 'Development branch changed during inspection');
  return {schemaVersion: 'actql-release-source-plan/0.1', source: structuredClone(request.source),
    version: selected.version.version, line: selected.version.line, sourceBranch: line.sourceBranch,
    branchTip, mainTip, maintenanceCut: line.maintenanceCut, findings, commits,
    execution: 'unavailable',
    pending: ['Protected source/policy revision and independent owner approval',
      ...(line.maintenanceCut ? ['Complete maintenance change/contract/regression/adaptation/forward-port review'] : [])],
    qualification: 'local Git-object/branch structure only; not remote repository authentication, semantic compatibility, artifact acceptance or release authority'};
}

export function maintenanceReviewPlan(source, review) {
  assert.equal(source.schemaVersion, 'actql-release-source-plan/0.1');
  assert(source.maintenanceCut, 'Maintenance review needs a selected fixed branch cut');
  assert.equal(source.findings.length, 0, 'Development history must not be merged into maintenance');
  exact(review, ['schemaVersion', 'sourceCommit', 'line', 'commits']);
  assert.equal(review.schemaVersion, 'actql-maintenance-request/0.1');
  assert.equal(review.sourceCommit, source.source.commit); assert.equal(review.line, source.line);
  assert(Array.isArray(review.commits));
  assert.deepEqual(review.commits.map(value => value.commit).sort(), source.commits.map(value => value.commit).sort(),
    'Review must describe every actual change commit, including merge/conflict work');
  for (const item of review.commits) {
    exact(item, ['commit', 'category', 'originalPR', 'contracts', 'regressionEvidence', 'adaptation', 'forwardPort']);
    assert(['bugfix', 'distribution', 'dependency', 'regression', 'docs'].includes(item.category),
      'Features, new optimization projects and breaking changes do not belong in ordinary maintenance');
    const actual = source.commits.find(value => value.commit === item.commit);
    if (actual.originCommit !== null || item.originalPR !== null)
      assert(typeof item.originalPR === 'string' && /^https:\/\/github\.com\/actql\/actql\/pull\/[1-9][0-9]*$/u.test(item.originalPR));
    assert(Array.isArray(item.contracts) && item.contracts.length); item.contracts.forEach(text);
    assert(Array.isArray(item.regressionEvidence) && item.regressionEvidence.length);
    for (const evidence of item.regressionEvidence) {
      exact(evidence, ['description', 'sha256']); text(evidence.description);
      assert(typeof evidence.sha256 === 'string' && /^[a-f0-9]{64}$/u.test(evidence.sha256));
    }
    text(item.adaptation);
    exact(item.forwardPort, ['needed', 'reason']);
    assert.equal(typeof item.forwardPort.needed, 'boolean'); text(item.forwardPort.reason);
    if (actual.originCommit !== null) assert.equal(item.forwardPort.needed, false, 'Original backport already exists on main');
  }
  return {schemaVersion: 'actql-maintenance-review-plan/0.1', sourceCommit: source.source.commit,
    line: source.line, commits: structuredClone(review.commits), execution: 'unavailable',
    pending: ['Protected reviewer must inspect actual hunks and verify the claimed category, contracts and regression evidence',
      'Owner must decide any compatibility exception, support-window change or required forward-port'],
    qualification: 'complete review-DATA shape bound to actual local Git changes; labels and evidence hashes are not independent review or release approval'};
}
