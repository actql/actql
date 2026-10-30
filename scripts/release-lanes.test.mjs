// Synthetic planning DATA and real, temporary Git histories only. No remote
// branch, registry mutation, publisher credential, product artifact or approval.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {compareReleaseVersions, releaseVersion} from './release-version.mjs';
import {promotionPlan} from './release-channels.mjs';
import {observeReleaseChannels} from './release-registry.mjs';
import {admitReleaseBranches, inspectReleaseSource, maintenanceReviewPlan} from './release-source.mjs';
import {runRelease} from './release.mjs';

const sha = body => createHash('sha256').update(body).digest('hex');
const policy = {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0', '0.1', '0.2'],
  publicationAuthority: 'external-owner-approval-required'};
function fixed(version = '0.1.1', channels = ['latest', 'release-0.1']) {
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'synthetic-review-only', version,
    source: {repository: 'https://github.com/actql/actql', commit: 'a'.repeat(40), branch: 'main'},
    targets: [{id: 'node', ecosystem: 'npm', packages: ['@actql/node'], platforms: ['darwin-arm64'],
      profiles: ['local'], destination: 'https://registry.npmjs.org/', channels}],
    notes: {summary: 'Planning fixture only', breakingChanges: [], migration: [], knownLimitations: ['No product or approval']}};
  const bytes = Buffer.from('Independent planning transport bytes\n');
  return {sha256: 'b'.repeat(64), payload: bytes, manifest: {schemaVersion: 'actql-release-set/0.1',
    release: releaseVersion(version), request, policy, acceptance: 'unaccepted', qualification: 'Independent cold-byte planning fixture',
    cohorts: [], artifacts: [{targetId: 'node', ecosystem: 'npm', name: '@actql/node', version,
      file: `actql-node-${version}.tgz`, bytes: bytes.length, sha256: sha(bytes),
      integrity: `sha512-${createHash('sha512').update(bytes).digest('base64')}`, path: `node/actql-node-${version}.tgz`}]}};
}
function report(f, version = '0.1.0') {
  return {schemaVersion: 'actql-release-channels/0.1', manifestSha256: f.sha256,
    startedAt: '2000-01-01T00:00:00Z', endedAt: '2000-01-01T00:00:01Z',
    observations: f.manifest.request.targets[0].channels.map(channel => ({targetId: 'node', name: '@actql/node',
      channel, state: version === null ? 'absent' : 'present', ...(version === null ? {} : {version})})),
    issues: [], requests: [], qualification: 'Synthetic historical DATA only'};
}
const move = (channel = 'latest', expectedVersion = '0.1.0') => [{targetId: 'node', name: '@actql/node', channel, expectedVersion}];
const plan = (f, moves, observed) => promotionPlan(f, moves, observed, sha(JSON.stringify(observed)));

async function directory(t, prefix) {
  const path = await mkdtemp(join(tmpdir(), prefix));
  t.after(() => rm(path, {recursive: true, force: true}));
  return path;
}

async function coldFixture(t) {
  const f = fixed('0.0.7', ['latest', 'release-0.0']), path = await directory(t, 'actql-channel-bytes-');
  const artifact = f.manifest.artifacts[0];
  await mkdir(join(path, 'node'));
  await writeFile(join(path, artifact.path), f.payload);
  const child = Buffer.from(JSON.stringify({version: 'actql-package-release/0.1', sourceSha: f.manifest.request.source.commit,
    cohort: {packageVersion: artifact.version, registry: 'https://registry.npmjs.org/', tag: 'latest'},
    packages: [{name: artifact.name, version: artifact.version, file: artifact.file,
      bytes: artifact.bytes, sha256: artifact.sha256, integrity: artifact.integrity}]}));
  await writeFile(join(path, 'node/release.json'), child);
  f.manifest.cohorts = [{targetId: 'node', kind: 'node-npm', path: 'node/release.json', bytes: child.length,
    sha256: sha(child), verification: 'Independent cold-byte fixture; no full producer qualification'}];
  const body = Buffer.from(JSON.stringify(f.manifest)); f.sha256 = sha(body);
  await writeFile(join(path, 'release-set.json'), body);
  await writeFile(join(path, 'release-set.sha256'), `${f.sha256}  release-set.json\n`);
  return {...f, path};
}

async function history(t, line = '0.1') {
  const repository = await directory(t, 'actql-maintenance-git-');
  const git = (...args) => execFileSync('git', args, {cwd: repository, encoding: 'utf8', stdio: 'pipe'}).trim();
  git('init', '--initial-branch=main'); git('config', 'user.name', 'ActQL Test');
  git('config', 'user.email', 'test@example.invalid'); git('config', 'commit.gpgsign', 'false');
  await writeFile(join(repository, 'program.txt'), 'original\n');
  git('add', '.'); git('commit', '-m', 'test: independent original');
  const cut = git('rev-parse', 'HEAD'); git('branch', `release/${line}`);
  const branches = {schemaVersion: 'actql-release-branches/0.1', lines: [{line, sourceBranch: `release/${line}`, maintenanceCut: cut}]};
  const selectedPolicy = {...policy, allowedLines: [line]};
  const request = fixed(`${line}.1`, [`release-${line}`]).manifest.request;
  request.source.branch = `release/${line}`;
  const inspect = () => {
    request.source.commit = git('rev-parse', `refs/heads/release/${line}`);
    return inspectReleaseSource({repository, request, policy: selectedPolicy, branches});
  };
  return {repository, git, cut, branches, request, policy: selectedPolicy, inspect};
}
function review(source) {
  return {schemaVersion: 'actql-maintenance-request/0.1', sourceCommit: source.source.commit, line: source.line,
    commits: source.commits.map(item => ({commit: item.commit, category: 'bugfix',
      originalPR: item.originCommit ? 'https://github.com/actql/actql/pull/1' : null,
      contracts: ['Existing behavior is restored; this label still needs protected hunk review'],
      regressionEvidence: [{description: 'Synthetic evidence reference; not an executed product test', sha256: 'c'.repeat(64)}],
      adaptation: 'Describe the actual maintenance difference for owner review',
      forwardPort: {needed: !item.originCommit, reason: item.originCommit ? 'Original already exists on main' : 'Forward-port decision is still pending'}}))};
}

test('release lanes: one version owner orders numeric prereleases and large segments without precision loss', () => {
  const values = ['0.1.0-alpha.2', '0.1.0-alpha.10', '0.1.0-beta.0', '0.1.0-rc.1', '0.1.0', '0.1.1', '0.2.0'];
  for (let i = 1; i < values.length; i++) {
    assert.equal(compareReleaseVersions(values[i - 1], values[i]), -1);
    assert.equal(compareReleaseVersions(values[i], values[i - 1]), 1);
  }
  assert.equal(compareReleaseVersions('0.0.9007199254740993', '0.0.9007199254740992'), 1);
  assert.equal(compareReleaseVersions('0.1.0-rc.1', '0.1.0-rc.1'), 0);
  assert.throws(() => compareReleaseVersions('0.1.0-preview.1', '0.1.0'));
});

test('release lanes: newer latest cannot be rolled back by a maintenance release', () => {
  const f = fixed();
  assert.throws(() => plan(f, move('latest', '0.2.0'), report(f, '0.2.0')), /roll.*backward/u);
  const result = plan(f, move('release-0.1'), report(f));
  assert.equal(result.transitions[0].toVersion, '0.1.1');
  assert.equal(result.execution, 'unavailable'); assert(result.pending.length);
});

test('release lanes: RC cannot become a stable alias and maintenance tags retain their exact line', () => {
  for (const channel of ['latest', 'release-0.1']) {
    const f = fixed('0.1.0-rc.1');
    assert.throws(() => plan(f, move(channel, null), report(f, null)), /stable channel/u);
  }
  const f = fixed('0.1.1', ['release-0.2']);
  assert.throws(() => plan(f, move('release-0.2', null), report(f, null)), /another line/u);
});

test('release lanes: stale unknown duplicate or redirected channel scope refuses before a plan exists', () => {
  const f = fixed();
  assert.throws(() => plan(f, move('latest', '0.0.9'), report(f)), /changed/u);
  const unknown = report(f); delete unknown.observations[0].version; unknown.observations[0].state = 'unknown';
  assert.throws(() => plan(f, move(), unknown), /unknown/u);
  assert.throws(() => plan(f, [...move(), ...move()], report(f)), /Duplicate/u);
  assert.throws(() => plan(f, move('unselected'), report(f)), /outside/u);
  assert.throws(() => plan(f, [{...move()[0], toVersion: '0.2.0'}], report(f)));
  assert.throws(() => plan(f, move(), {...report(f), approved: true}));
  const wrong = report(f); wrong.manifestSha256 = 'd'.repeat(64);
  assert.throws(() => plan(f, move(), wrong), /another fixed/u);
});

test('release lanes: equal channel is recorded as identical while unknown version spelling is not overwritten', () => {
  const f = fixed();
  assert.equal(plan(f, move('latest', '0.1.1'), report(f, '0.1.1')).transitions[0].action, 'already-identical');
  assert.throws(() => plan(f, move('latest', '0.0.0-development'), report(f, '0.0.0-development')));
});

test('release lanes: public channel GET and promotion-plan CLI bind fixed bytes and exact historical report', async t => {
  const f = await coldFixture(t), calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push({url, options}); assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit');
    assert.equal(options.redirect, 'error'); assert.equal(Object.hasOwn(options, 'body'), false);
    return Response.json({latest: '0.0.6'});
  });
  const observed = await runRelease(['channels', f.path, f.sha256]);
  assert.deepEqual(observed.observations.map(value => value.state), ['present', 'absent']);
  assert.equal(calls[0].url, 'https://registry.npmjs.org/-/package/%40actql%2Fnode/dist-tags');
  const raw = Buffer.from(JSON.stringify(observed)), observedPath = join(f.path, 'channel-report.json');
  await writeFile(observedPath, raw);
  const moves = join(f.path, 'moves.json'); await writeFile(moves, JSON.stringify(move('latest', '0.0.6')));
  const result = await runRelease(['promotion-plan', f.path, f.sha256, moves, observedPath]);
  assert.equal(result.channelObservationSha256, sha(raw)); assert.equal(result.manifestSha256, f.sha256);
  assert.equal(result.execution, 'unavailable'); assert.equal(calls.length, 1);
});

test('release lanes: unavailable channel map is unknown while only a successful map can show an absent tag', async t => {
  const f = await coldFixture(t);
  for (const status of [404, 503]) {
    const result = await observeReleaseChannels(f.path, f.sha256, {fetchResponse: async () => new Response('', {status})});
    assert(result.observations.every(value => value.state === 'unknown'));
  }
  const result = await observeReleaseChannels(f.path, f.sha256, {fetchResponse: async () => Response.json({})});
  assert(result.observations.every(value => value.state === 'absent'));
});

test('release lanes: checked-in initial branch choice never grants another line or an arbitrary feature source', async () => {
  const p = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url)));
  const b = JSON.parse(await readFile(new URL('../release/branches.json', import.meta.url)));
  assert.deepEqual(p.allowedLines, ['0.0']); assert.deepEqual(admitReleaseBranches(b, p).lines,
    [{line: '0.0', sourceBranch: 'main', maintenanceCut: null}]);
  assert.throws(() => admitReleaseBranches(b, {...p, allowedLines: ['0.0', '0.1']}));
  assert.throws(() => admitReleaseBranches({...b, lines: [{...b.lines[0], sourceBranch: 'feature/arbitrary'}]}, p));
});

test('release lanes: real Git source must be on its literal selected branch', async t => {
  const h = await history(t), request = fixed('0.0.7', ['latest']).manifest.request;
  const branches = {schemaVersion: 'actql-release-branches/0.1', lines: [{line: '0.0', sourceBranch: 'main', maintenanceCut: null}]};
  request.source.commit = h.cut;
  const p = {...policy, allowedLines: ['0.0']};
  assert.equal(inspectReleaseSource({repository: h.repository, request, policy: p, branches}).source.commit, h.cut);
  request.source.branch = 'feature/unreleased';
  assert.throws(() => inspectReleaseSource({repository: h.repository, request, policy: p, branches}), /selected.*source branch/u);
  h.git('checkout', '-b', 'feature/unreleased');
  await writeFile(join(h.repository, 'feature.txt'), 'Unmerged feature\n'); h.git('add', '.'); h.git('commit', '-m', 'feat: unmerged');
  request.source.branch = 'main'; request.source.commit = h.git('rev-parse', 'HEAD');
  assert.throws(() => inspectReleaseSource({repository: h.repository, request, policy: p, branches}), /not on its named/u);
});

test('release lanes: actual cherry-pick -x retains original main commit and complete review DATA without authorizing release', async t => {
  const h = await history(t);
  await writeFile(join(h.repository, 'program.txt'), 'Existing behavior fixed\n'); h.git('add', '.'); h.git('commit', '-m', 'fix: main regression');
  const original = h.git('rev-parse', 'HEAD'); h.git('checkout', 'release/0.1'); h.git('cherry-pick', '-x', original);
  const head = h.git('rev-parse', 'HEAD'), source = h.inspect();
  assert.equal(source.findings.length, 0); assert.equal(source.commits.length, 1);
  assert.equal(source.commits[0].originCommit, original); assert.notEqual(head, original);
  const result = maintenanceReviewPlan(source, review(source));
  assert.equal(result.execution, 'unavailable'); assert(result.pending.length);
  assert.equal(h.git('rev-parse', 'HEAD'), head);
});

test('release lanes: whole development merge into maintenance is detected from real history even with bugfix labels', async t => {
  const h = await history(t);
  await writeFile(join(h.repository, 'new-syntax.txt'), 'Unrelated new feature\n'); h.git('add', '.'); h.git('commit', '-m', 'feat: new syntax');
  h.git('checkout', 'release/0.1');
  await writeFile(join(h.repository, 'maintenance.txt'), 'Separate maintenance work\n'); h.git('add', '.'); h.git('commit', '-m', 'fix: maintenance');
  h.git('merge', '--no-ff', 'main', '-m', 'merge: broad main');
  const source = h.inspect(); assert.equal(source.findings[0].kind, 'development-history-crossed-cut');
  assert.throws(() => maintenanceReviewPlan(source, review(source)), /must not be merged/u);
});

test('release lanes: maintenance-only work must record forward-port and regression scope while incompatible categories refuse', async t => {
  const h = await history(t); h.git('checkout', 'release/0.1');
  await writeFile(join(h.repository, 'program.txt'), 'Line-specific correction\n'); h.git('add', '.'); h.git('commit', '-m', 'fix: line-only');
  const source = h.inspect(), valid = review(source);
  assert.equal(maintenanceReviewPlan(source, valid).commits[0].forwardPort.needed, true);
  for (const category of ['feature', 'breaking', 'optimization-project']) {
    const invalid = structuredClone(valid); invalid.commits[0].category = category;
    assert.throws(() => maintenanceReviewPlan(source, invalid), /ordinary maintenance/u);
  }
  for (const mutate of [value => delete value.commits[0].forwardPort, value => value.commits[0].regressionEvidence = [],
    value => value.commits = [], value => value.sourceCommit = 'd'.repeat(40), value => value.approved = true]) {
    const invalid = structuredClone(valid); mutate(invalid); assert.throws(() => maintenanceReviewPlan(source, invalid));
  }
});

test('release lanes: source and maintenance CLI read actual Git with no checkout or publication action', async t => {
  const h = await history(t, '0.0'); h.git('checkout', 'release/0.0');
  await writeFile(join(h.repository, 'program.txt'), 'Independent branch patch\n'); h.git('add', '.'); h.git('commit', '-m', 'fix: patch');
  const source = h.inspect(), requestPath = join(h.repository, 'request.json'), reviewPath = join(h.repository, 'review.json');
  const branchPath = join(h.repository, 'branches.json');
  await writeFile(requestPath, JSON.stringify(h.request)); await writeFile(reviewPath, JSON.stringify(review(source)));
  await writeFile(branchPath, JSON.stringify(h.branches)); const head = h.git('rev-parse', 'HEAD');
  const result = await runRelease(['source-plan', requestPath, h.repository, branchPath]);
  assert.equal(result.source.commit, head); assert.equal(result.execution, 'unavailable');
  const maintenance = await runRelease(['maintenance-plan', requestPath, h.repository, reviewPath, branchPath]);
  assert.equal(maintenance.execution, 'unavailable'); assert.equal(h.git('rev-parse', 'HEAD'), head);
});
