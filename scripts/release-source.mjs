// Local Git and review-DATA inspection only. Neither a matching origin URL nor
// an author-written maintenance label proves protected review or publication.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {isAbsolute} from 'node:path';
import {admitReleasePolicy, admitReleaseRequest} from './release-policy.mjs';
import {compareReleaseVersions, releaseVersion} from './release-version.mjs';

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

export function inspectReleaseSource({repository, request, policy, branches, previousRelease}) {
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
  if (previousRelease !== undefined && previousRelease !== null) {
    exact(previousRelease, ['version', 'source']);
    const previous = releaseVersion(previousRelease.version);
    assert.equal(previous.line, selected.version.line, 'Previous release must belong to the same selected line');
    assert(compareReleaseVersions(previous.version, selected.version.version) < 0,
      'A new candidate must follow the complete previous version; same-byte resume is a separate operation');
    exact(previousRelease.source, ['repository', 'commit', 'branch']);
    assert.equal(previousRelease.source.repository, request.source.repository);
    commit(previousRelease.source.commit);
    assert(ancestor(previousRelease.source.commit, request.source.commit),
      'Fixed candidate does not descend from the selected previous release source');
  }
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
    ...(previousRelease === undefined ? {} : {previousRelease: structuredClone(previousRelease)}),
    execution: 'unavailable',
    pending: ['Protected source/policy revision and independent owner approval',
      ...(line.maintenanceCut ? ['Complete maintenance change/contract/regression/adaptation/forward-port review'] : [])],
    qualification: 'local Git-object/branch structure only; not remote repository authentication, semantic compatibility, artifact acceptance or release authority'};
}

// Connect the original byte and Git owners. All history inputs remain DATA:
// the protected executor must independently select/authenticate the actual
// previous release (or initial scope), policy revision and remote branch.
export async function inspectFixedReleaseSource({directory, expectedSha256, repository, policy, branches, history}) {
  assert(typeof expectedSha256 === 'string' && /^[a-f0-9]{64}$/u.test(expectedSha256));
  assert(history && ['initial', 'previous'].includes(history.kind),
    'Explicitly select initial history or the original previous fixed release');
  exact(history, history.kind === 'initial' ? ['kind'] : ['kind', 'directory', 'manifestSha256']);
  if (history.kind === 'previous') {
    assert(typeof history.directory === 'string' && isAbsolute(history.directory),
      'Previous fixed release directory must be absolute');
    assert(typeof history.manifestSha256 === 'string' && /^[a-f0-9]{64}$/u.test(history.manifestSha256));
  }
  // Retain this call's original inputs before byte I/O yields. These immutable
  // planning inputs are not cached permission or later current-state evidence.
  history = structuredClone(history);
  const selectedPolicy = admitReleasePolicy(policy);
  const selectedBranches = admitReleaseBranches(branches, selectedPolicy);
  const {verifyReleaseSet} = await import('./release-set.mjs');
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const previous = history.kind === 'previous'
    ? await verifyReleaseSet(history.directory, {expectedSha256: history.manifestSha256}) : null;
  const previousRelease = previous ? {version: previous.manifest.request.version,
    source: previous.manifest.request.source} : null;
  const source = inspectReleaseSource({repository, request: fixed.manifest.request,
    policy: selectedPolicy, branches: selectedBranches, previousRelease});
  await verifyReleaseSet(directory, {expectedSha256});
  if (previous) await verifyReleaseSet(history.directory, {expectedSha256: history.manifestSha256});
  return {schemaVersion: 'actql-fixed-release-source-plan/0.1', manifestSha256: fixed.sha256,
    history: {kind: history.kind, ...(previous ? {manifestSha256: previous.sha256} : {})}, source,
    execution: 'unavailable', pending: [...source.pending,
      'Independently authenticate the selected initial scope or actual previous published release',
      'Protected remote branch/policy/history and exact owner-approved candidate still required'],
    qualification: 'original fixed bytes plus local Git ancestry only; no publication history discovery, remote authentication, accepted artifact, approval or permission'};
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
