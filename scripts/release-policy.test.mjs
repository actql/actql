import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, readFile, writeFile, rm, chmod} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {releaseVersion} from './release-version.mjs';
import {admitReleasePolicy, admitReleaseRequest, releasePlan} from './release-policy.mjs';
import {runReleasePlan} from './release.mjs';
import {admitCohort, preparePackageRelease, releasePackageMetadata} from './package-release.mjs';
import {admitNativeReleaseCohort, nativeReleaseMetadata, prepareNativeCliRelease} from './native-cli-release.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url), 'utf8'));
// Pure synthetic request; this number and source are not a real release choice.
const request = () => ({schemaVersion: 'actql-release-request/0.1', releaseId: 'synthetic-only',
  version: '0.0.7', source: {repository: 'https://github.com/actql/actql', commit: 'a'.repeat(40), branch: 'main'},
  targets: [{id: 'node', ecosystem: 'npm', packages: ['@actql/node'], platforms: ['linux-x64-gnu'],
    profiles: ['local'], destination: 'https://registry.npmjs.org/', channels: ['candidate-synthetic-only']}],
  notes: {summary: 'Synthetic fixture, not a product claim', breakingChanges: [], migration: [], knownLimitations: ['Unbuilt']}});

test('explicit versions map once to Python without selecting or incrementing a version', () => {
  for (const [input, python] of [['0.0.7', '0.0.7'], ['0.0.7-alpha.0', '0.0.7a0'],
    ['0.0.7-beta.2', '0.0.7b2'], ['0.0.7-rc.3', '0.0.7rc3']]) {
    assert.deepEqual(releaseVersion(input), {version: input, pythonVersion: python,
      line: '0.0', gitTag: `v${input}`, prerelease: input.includes('-')});
  }
});

test('relative versions, leading zeros and ambiguous normalization are refused', () => {
  for (const value of [undefined, 7, 'patch', 'minor', 'major', 'v0.0.7', ' 0.0.7', '0.0.7\n',
    '00.0.7', '0.00.7', '0.0.07', '0.0.7-alpha.01', '0.0.7-preview.1', '0.0.7+build.1', '0.0.7a1']) {
    assert.throws(() => releaseVersion(value), undefined, String(value));
  }
});

test('initial 0.0 policy rejects later lines including their prereleases', () => {
  assert.deepEqual(policy.allowedLines, ['0.0']);
  for (const version of ['0.1.0', '0.1.0-alpha.1', '0.2.0-rc.1', '1.0.0']) {
    assert.throws(() => admitReleaseRequest({...request(), version}, policy), /not allowed/u);
  }
  const parsed = admitReleaseRequest(request(), policy);
  assert.equal(parsed.request.version, '0.0.7');
  assert.equal(parsed.version.line, '0.0');
});

test('forged approval and actor fields cannot enter policy or request data', () => {
  for (const fields of [{approved: true}, {actor: 'owner'}, {approval: {approved: true}}, {publish: true}]) {
    assert.throws(() => admitReleaseRequest({...request(), ...fields}, policy));
    assert.throws(() => admitReleasePolicy({...policy, ...fields}));
  }
});

test('source and scope remain explicit and duplicate or redirected targets are refused', () => {
  assert.throws(() => admitReleaseRequest({...request(), source: {...request().source, commit: 'HEAD'}}, policy));
  assert.throws(() => admitReleaseRequest({...request(), targets: []}, policy));
  const target = request().targets[0];
  assert.throws(() => admitReleaseRequest({...request(), targets: [target, {...target}]}, policy));
  assert.throws(() => admitReleaseRequest({...request(), targets: [target, {...target, id: 'other'}]}, policy));
  assert.throws(() => admitReleaseRequest({...request(), targets: [{...target, destination: 'https://evil.invalid/'}]}, policy));
  assert.throws(() => admitReleaseRequest({...request(), targets: [{...target, channels: []}]}, policy));
});

test('Python has an explicit package/platform/profile selection and no npm-style channel', () => {
  const target = {id: 'python', ecosystem: 'pypi', packages: ['actql', 'actql-sdk', 'actql-local-runtime'],
    platforms: ['manylinux_2_28_x86_64'], profiles: ['local'], destination: 'https://upload.pypi.org/legacy/', channels: []};
  const selected = admitReleaseRequest({...request(), targets: [target]}, policy);
  assert.deepEqual(selected.request.targets, [target]);
  assert.throws(() => admitReleaseRequest({...request(), targets: [{...target, channels: ['latest']}]}, policy));
  // Request syntax does not certify platform readiness; plan states that gap.
  assert(releasePlan({...request(), targets: [target]}, policy).pending.some(value => value.includes('platform acceptance')));
});

test('breaking changes require migration text without bumping to another line', () => {
  const value = request(); value.notes.breakingChanges = ['Old option removed'];
  assert.throws(() => admitReleaseRequest(value, policy), /migration/u);
  value.notes.migration = ['Use the replacement option'];
  assert.equal(admitReleaseRequest(value, policy).version.version, '0.0.7');
});

test('read-only plan returns detached data and makes no artifact or approval claim', () => {
  const value = request(), before = structuredClone(value), result = releasePlan(value, policy);
  assert.deepEqual(value, before);
  assert(Object.values(result.effects).every(value => value === false));
  assert.match(result.qualification, /not build.*approval or publication/u);
  value.targets[0].packages.push('changed');
  assert.deepEqual(result.targets[0].packages, ['@actql/node']);
});

test('plan CLI is read-only and every external operation refuses before opening a request', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'actql-release-plan-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const path = join(dir, 'request.json'); await writeFile(path, JSON.stringify(request()));
  const result = await runReleasePlan(['plan', path]);
  assert.equal(result.version.version, '0.0.7');
  for (const command of ['prepare', 'stage', 'publish', 'promote', 'resume', '--publish']) {
    await assert.rejects(runReleasePlan([command, join(dir, 'absent.json')]), /Only read-only plan/u);
  }
  await assert.rejects(runReleasePlan(['plan', path, '--yes']), /usage/u);
});

test('real legacy CLI publication refuses before credential or upload subprocesses', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'actql-release-denied-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const marker = join(dir, 'credential-or-upload-called');
  const npm = join(dir, 'npm');
  await writeFile(npm, '#!/bin/sh\nprintf called >> "$ACTQL_RELEASE_TEST_MARKER"\nexit 77\n');
  await chmod(npm, 0o755);
  for (const script of ['publish-package-release.mjs', 'native-cli-release.mjs']) {
    const child = spawnSync(process.execPath, [resolve(root, 'scripts', script), '--publish', join(dir, 'missing-release')],
      {cwd: root, env: {...process.env, PATH: dir, ACTQL_RELEASE_TEST_MARKER: marker}, encoding: 'utf8', timeout: 20_000});
    assert.equal(child.error, undefined);
    assert.notEqual(child.status, 0);
    assert.match(child.stderr, /Direct publication is disabled/u);
  }
  await assert.rejects(readFile(marker), {code: 'ENOENT'});
});

test('release preparation: Node and Native consume the same explicit version grammar', async () => {
  const node = JSON.parse(await readFile(new URL('../release/client-cohort.json', import.meta.url)));
  const native = {registry: node.registry, access: node.access, tag: 'candidate-synthetic-only'};
  for (const version of ['0.0.7', '0.0.7-alpha.0', '0.0.7-beta.2', '0.0.7-rc.3']) {
    assert.equal(admitCohort({...node, packageVersion: version}).packageVersion, version);
    assert.equal(admitNativeReleaseCohort({...native, packageVersion: version}).packageVersion, version);
  }
  for (const packageVersion of [undefined, 'patch', '0.0.7-preview.1', '0.0.7-rc.01', '0.0.7+build.1', '0.0.7\n']) {
    assert.throws(() => admitCohort({...node, packageVersion}));
    assert.throws(() => admitNativeReleaseCohort({...native, packageVersion}));
  }
  assert.throws(() => admitNativeReleaseCohort({...native, packageVersion: '0.0.1'}), /placeholder/u);
  for (const tag of [undefined, '', 'latest\n']) {
    assert.throws(() => admitNativeReleaseCohort({...native, tag, packageVersion: '0.0.7'}));
  }
});

test('release preparation: isolated Node and Native metadata preserves explicit RC and original source', async () => {
  const original = JSON.parse(await readFile(new URL('../packages/native-cli/package.json', import.meta.url)));
  const before = structuredClone(original);
  const native = {packageVersion: '0.0.7-rc.3', registry: 'https://registry.npmjs.org/',
    access: 'public', tag: 'candidate-synthetic-only'};
  const cli = nativeReleaseMetadata(original, native);
  assert.equal(cli.version, '0.0.7-rc.3');
  assert.deepEqual(cli.bin, original.bin);
  assert.deepEqual(cli.exports, original.exports);
  assert.deepEqual(cli.publishConfig, {registry: native.registry, access: native.access});
  assert.deepEqual(original, before);
  cli.files.push('not-an-original');
  assert.deepEqual(original, before);
  const base = JSON.parse(await readFile(new URL('../release/client-cohort.json', import.meta.url)));
  const node = admitCohort({...base, packageVersion: native.packageVersion, tag: native.tag});
  const sdk = {name: '@actql/node', version: '0.0.0-development', dependencies: {'@actql/sdk': '0.0.0-development'}};
  const staged = releasePackageMetadata(sdk, 'node', node);
  assert.equal(staged.version, native.packageVersion);
  assert.equal(staged.dependencies['@actql/sdk'], native.packageVersion);
  assert.equal(sdk.version, '0.0.0-development');
  assert.equal(sdk.dependencies['@actql/sdk'], '0.0.0-development');
  assert.equal(releaseVersion(staged.version).pythonVersion, '0.0.7rc3');
});

test('release preparation: omitted selections refuse before source, artifact or output work', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'actql-release-no-default-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const destination = join(dir, 'must-not-exist');
  await assert.rejects(preparePackageRelease({repository: join(dir, 'absent-source'), destination}), /explicit cohort/u);
  await assert.rejects(prepareNativeCliRelease(destination, [join(dir, 'absent-artifact')]), /explicit Native/u);
  await assert.rejects(readFile(join(destination, 'release.json')), {code: 'ENOENT'});
});

test('release preparation: real Node and Native CLI cannot silently use source version or latest', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'actql-release-cli-no-default-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const marker = join(dir, 'subprocess-called');
  for (const command of ['npm', 'moon', 'git']) {
    const path = join(dir, command);
    await writeFile(path, '#!/bin/sh\nprintf called >> "$ACTQL_RELEASE_TEST_MARKER"\nexit 77\n');
    await chmod(path, 0o755);
  }
  for (const script of ['package-release.mjs', 'native-cli-release.mjs']) {
    const destination = join(dir, script);
    const child = spawnSync(process.execPath, [resolve(root, 'scripts', script), 'prepare', destination],
      {cwd: root, env: {...process.env, PATH: dir, ACTQL_RELEASE_TEST_MARKER: marker}, encoding: 'utf8', timeout: 20_000});
    assert.equal(child.error, undefined);
    assert.notEqual(child.status, 0);
    assert.match(child.stderr, /explicit cohort/u);
    await assert.rejects(readFile(join(destination, 'release.json')), {code: 'ENOENT'});
  }
  await assert.rejects(readFile(marker), {code: 'ENOENT'});
});
