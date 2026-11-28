import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import {mkdtemp, mkdir, readFile, writeFile, rm, cp, rename, symlink} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import test, {before, after} from 'node:test';
import {writeInertPairedPythonReleaseCohort, writeInertPythonReleaseCohort} from './fixtures/release-python-wheels.mjs';
import {admitCohort, stagePackage} from './package-release.mjs';
import {freezeReleaseSet, verifyReleaseSet, resumeReleaseSet, releaseSetSummary} from './release-set.mjs';
import {runRelease} from './release.mjs';

const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url)));
const source = 'a'.repeat(40), version = '0.0.7'; // Synthetic, not a selected product release.
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
let scratch, nodeDirectory, pythonDirectory;
const request = (python = false) => ({schemaVersion: 'actql-release-request/0.1',
  releaseId: 'synthetic-fixed-bytes', version: python ? '0.0.7-rc.1' : version,
  source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'},
  targets: [python ? {id: 'python', ecosystem: 'pypi', packages: ['actql-sdk', 'actql-local-runtime', 'actql'],
    platforms: ['darwin-arm64'], profiles: ['local'], destination: 'https://upload.pypi.org/legacy/', channels: []}
    : {id: 'node', ecosystem: 'npm', packages: ['@actql/client-wire', '@actql/sdk', '@actql/local-node', '@actql/node'],
      platforms: ['linux-x64-gnu'], profiles: ['local'], destination: 'https://registry.npmjs.org/', channels: ['candidate-synthetic']}],
  notes: {summary: 'Synthetic archive metadata only', breakingChanges: [], migration: [],
    knownLimitations: ['No engine, Source, normal install, platform or public acceptance']}});
const descriptor = python => ({targetId: python ? 'python' : 'node',
  kind: python ? 'python-wheels' : 'node-npm', directory: python ? pythonDirectory : nodeDirectory});

before(async () => {
  scratch = await mkdtemp(join(tmpdir(), 'actql-release-set-'));
  nodeDirectory = join(scratch, 'original-node'); await mkdir(nodeDirectory);
  const development = join(nodeDirectory, 'development'); await mkdir(development);
  const cohort = admitCohort({version: 'actql-package-release-cohort/0.1', packageVersion: version,
    registry: 'https://registry.npmjs.org/', access: 'public', tag: 'candidate-synthetic',
    packages: ['client-wire', 'sdk', 'local-node', 'node']});
  const license = join(scratch, 'LICENSE'); await writeFile(license, 'Synthetic fixture only\n');
  const packages = [], tarballs = {};
  for (const [index, name] of cohort.packages.entries()) {
    const directory = join(scratch, `package-${name}`); await mkdir(directory);
    await writeFile(join(directory, 'package.json'), JSON.stringify({name: `@actql/${name}`,
      version: '0.0.0-development', private: true, type: 'module', files: ['index.mjs', 'index.d.ts'],
      exports: {'.': {types: './index.d.ts', default: './index.mjs'}},
      dependencies: index ? {[`@actql/${cohort.packages[index - 1]}`]: '0.0.0-development'} : {}}));
    await writeFile(join(directory, 'index.mjs'), 'export const fixture = 19;\n');
    await writeFile(join(directory, 'index.d.ts'), 'export declare const fixture: number;\n');
    execFileSync('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination', development,
      '--cache', join(scratch, 'cache')], {cwd: directory, encoding: 'utf8', stdio: 'pipe'});
    const item = await stagePackage({archive: join(development, `actql-${name}-0.0.0-development.tgz`),
      destination: nodeDirectory, name, cohort, license});
    packages.push(item); tarballs[name] = item.originalSha256;
  }
  await writeFile(join(development, 'packed-client-packages.json'), JSON.stringify({revision: source, tarballs}));
  await writeFile(join(nodeDirectory, 'release.json'), JSON.stringify({version: 'actql-package-release/0.1',
    sourceSha: source, preparedAt: '2000-01-01T00:00:00.000Z', cohort,
    recipeSha256: 'b'.repeat(64), cohortSha256: 'c'.repeat(64), toolchain: {fixture: true},
    generation: 'normal-prepack-then-metadata-and-license-only', packages}));
  // Same original independently authored metadata; no engine or image.
  pythonDirectory = join(scratch, 'original-python');
  await writeInertPythonReleaseCohort(pythonDirectory, 'python3');
});
after(async () => {if (scratch) await rm(scratch, {recursive: true, force: true});});

async function freeze(t, python = false) {
  const destination = join(scratch, `fixed-${crypto.randomUUID()}`);
  const fixed = await freezeReleaseSet({request: request(python), policy, cohorts: [descriptor(python)], destination});
  return {destination, fixed};
}

test('actual Node release verifier feeds a fixed upper set without rebuilding its original archives', async t => {
  const original = await readFile(join(nodeDirectory, 'release.json'));
  const {destination, fixed} = await freeze(t);
  assert.equal(fixed.manifest.artifacts.length, 4);
  assert(!Object.hasOwn(fixed.manifest, 'sha256'));
  assert.equal(sha(await readFile(join(destination, 'release-set.json'))), fixed.sha256);
  assert.deepEqual(await verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), fixed);
  assert.deepEqual(await readFile(join(nodeDirectory, 'release.json')), original);
  assert.equal(fixed.manifest.acceptance, 'unaccepted');
});

test('actual Python wheel metadata checker uses the common RC version and preserves packaging-only scope', async t => {
  const {destination, fixed} = await freeze(t, true);
  assert(fixed.manifest.artifacts.every(item => item.version === '0.0.7rc1'));
  assert.match(fixed.manifest.cohorts[0].verification, /not component execution.*Linux or public acceptance/u);
  assert.deepEqual(await verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), fixed);
});

test('versioned Python metadata lineage feeds the fixed release set without granting runtime acceptance', async t => {
  const path = join(pythonDirectory, 'cohort.json'), original = await readFile(path);
  const child = JSON.parse(original);
  child.release_metadata = {version: '0.0.7-rc.1', source_package_version: '0.0.0.dev0',
    source_artifact_sha256: 'a'.repeat(64), transforms: [
      'stages/python-product/pyproject.toml', 'stages/python-sdk/pyproject.toml',
      'stages/python-local-runtime/pyproject.toml',
      'stages/python-local-runtime/src/actql_local_runtime/artifact.json',
    ].map(file => ({file, before_sha256: 'a'.repeat(64), after_sha256: 'b'.repeat(64)}))};
  try {
    const wire = Buffer.from(JSON.stringify(child)); await writeFile(path, wire);
    const {destination, fixed} = await freeze(t, true);
    assert.equal(fixed.manifest.cohorts[0].sha256, sha(wire));
    assert.deepEqual(await readFile(join(destination, fixed.manifest.cohorts[0].path)), wire);
    assert.equal(fixed.manifest.acceptance, 'unaccepted');
    assert.deepEqual(await verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), fixed);
    child.release_metadata.version = '0.0.7-rc.2';
    await writeFile(path, JSON.stringify(child));
    await assert.rejects(freeze(t, true));
  } finally {await writeFile(path, original);}
});

test('wrong source or incomplete target cohort refuses before creating output', async () => {
  const value = request(); value.source.commit = 'b'.repeat(40);
  const destination = join(scratch, 'must-not-create');
  await assert.rejects(freezeReleaseSet({request: value, policy, cohorts: [descriptor(false)], destination}));
  await assert.rejects(readFile(join(destination, 'release-set.json')), {code: 'ENOENT'});
  await assert.rejects(freezeReleaseSet({request: request(), policy, cohorts: [], destination}));
});

test('fixed artifact tamper and missing bytes remain failures, never absence or rebuild permission', async t => {
  const {destination, fixed} = await freeze(t);
  const path = join(destination, fixed.manifest.artifacts[0].path);
  const original = await readFile(path); await writeFile(path, 'changed');
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: fixed.sha256}));
  await writeFile(path, original); await rm(path);
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), {code: 'ENOENT'});
});

test('changed request or detached digest cannot reuse the externally retained original manifest identity', async t => {
  const {destination, fixed} = await freeze(t);
  const changed = structuredClone(fixed.manifest); changed.request.targets[0].channels = ['latest'];
  const bytes = Buffer.from(JSON.stringify(changed)); await writeFile(join(destination, 'release-set.json'), bytes);
  await writeFile(join(destination, 'release-set.sha256'), `${sha(bytes)}  release-set.json\n`);
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), /externally retained digest/u);
});

test('an upper artifact identity cannot diverge from its complete original child manifest', async t => {
  const {destination, fixed} = await freeze(t);
  const changed = structuredClone(fixed.manifest); changed.artifacts[0].name = '@actql/wrong';
  const bytes = Buffer.from(JSON.stringify(changed)); await writeFile(join(destination, 'release-set.json'), bytes);
  await writeFile(join(destination, 'release-set.sha256'), `${sha(bytes)}  release-set.json\n`);
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: sha(bytes)}), /original child manifest/u);
});

test('symlinked frozen payload refuses even if it resolves to identical original bytes', async t => {
  const {destination, fixed} = await freeze(t);
  const item = fixed.manifest.artifacts[0], path = join(destination, item.path);
  const keep = join(scratch, `kept-${crypto.randomUUID()}`); await rename(path, keep); await symlink(keep, path);
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), /symlink/u);
});

test('same-bytes resume classification distinguishes confirmed, absent, unknown and conflict without executing', async t => {
  const {destination, fixed} = await freeze(t);
  const observations = fixed.manifest.artifacts.map(item => ({targetId: item.targetId, file: item.file, state: 'absent'}));
  const first = fixed.manifest.artifacts[0]; observations[0] = {targetId: first.targetId, file: first.file,
    state: 'present', identity: Object.fromEntries(['name','version','bytes','sha256','integrity'].map(k => [k, first[k]]))};
  const plan = resumeReleaseSet(await verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), observations);
  assert.deepEqual(plan.plan.map(item => item.action), ['reuse-identical', 'missing-same-bytes', 'missing-same-bytes', 'missing-same-bytes']);
  assert.equal(plan.blocked, false);
  observations[1].state = 'unknown'; assert.equal(resumeReleaseSet(fixed, observations).blocked, true);
  observations[0].identity.sha256 = 'f'.repeat(64); assert.throws(() => resumeReleaseSet(fixed, observations), /differs/u);
});

test('unsupported Linux Python and unverified Native archives cannot inherit another verifier', async () => {
  const value = request(true); value.targets[0].platforms = ['manylinux_2_28_x86_64'];
  await assert.rejects(freezeReleaseSet({request: value, policy, cohorts: [descriptor(true)], destination: join(scratch, 'no-linux')}));
  const native = request(); native.targets[0] = {...native.targets[0], ecosystem: 'native', destination: 'https://github.com/actql/actql'};
  await assert.rejects(freezeReleaseSet({request: native, policy, cohorts: [{...descriptor(false), kind: 'native-standalone'}], destination: join(scratch, 'no-standalone')}), /native-standalone[.]json/u);
});

test('human summary comes from the fixed manifest and new external CLI operations stay unavailable', async t => {
  const {destination, fixed} = await freeze(t);
  const summary = releaseSetSummary(fixed); assert.equal(summary.manifestSha256, fixed.sha256);
  assert(summary.markdown.includes(source)); assert(summary.markdown.includes(fixed.manifest.artifacts[0].sha256));
  assert.deepEqual(await runRelease(['verify', destination, fixed.sha256]), fixed);
  for (const operation of ['stage','publish','promote','resume']) {
    await assert.rejects(runRelease([operation, 'absent']), /External release operation is unavailable/u);
  }
});

test('original cohort tag must be explicitly included before freeze and on cold verification', async t => {
  const {destination, fixed} = await freeze(t);
  const value = request(); value.targets[0].channels = ['latest'];
  await assert.rejects(freezeReleaseSet({request: value, policy, cohorts: [descriptor(false)],
    destination: join(scratch, 'undeclared-tag')}), /cohort tag/u);
  const changed = structuredClone(fixed.manifest); changed.request = value;
  const bytes = Buffer.from(JSON.stringify(changed)); await writeFile(join(destination, 'release-set.json'), bytes);
  await writeFile(join(destination, 'release-set.sha256'), `${sha(bytes)}  release-set.json\n`);
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: sha(bytes)}), /cohort tag/u);
});

test('Python filename and packaging-only flags cannot contradict their original wheel identity', async () => {
  const directory = join(scratch, 'changed-python'); await cp(pythonDirectory, directory, {recursive: true});
  const cohortFile = join(directory, 'cohort.json'), original = await readFile(cohortFile);
  const cohort = JSON.parse(original), first = cohort.wheels[0];
  const old = first.file; first.file = first.file.replace('0.0.7rc1', '0.0.8');
  await rename(join(directory, 'wheels', old), join(directory, 'wheels', first.file));
  await writeFile(cohortFile, JSON.stringify(cohort));
  await assert.rejects(freezeReleaseSet({request: request(true), policy,
    cohorts: [{...descriptor(true), directory}], destination: join(scratch, 'wrong-wheel-filename')}), /filename differs/u);
  await rename(join(directory, 'wheels', first.file), join(directory, 'wheels', old));
  const changed = JSON.parse(original); changed.runtime_executed = true;
  await writeFile(cohortFile, JSON.stringify(changed));
  await assert.rejects(freezeReleaseSet({request: request(true), policy,
    cohorts: [{...descriptor(true), directory}], destination: join(scratch, 'forged-wheel-acceptance')}), /cannot supply runtime or publication acceptance/u);
});

test('fixed header binds the explicit release line and every version projection', async t => {
  const {destination, fixed} = await freeze(t);
  assert.deepEqual(fixed.manifest.release, {version: '0.0.7', pythonVersion: '0.0.7',
    line: '0.0', gitTag: 'v0.0.7', prerelease: false});
  assert.deepEqual(await verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), fixed);
  const changed = structuredClone(fixed.manifest); changed.release.line = '0.1';
  const bytes = Buffer.from(JSON.stringify(changed)); await writeFile(join(destination, 'release-set.json'), bytes);
  await writeFile(join(destination, 'release-set.sha256'), `${sha(bytes)}  release-set.json\n`);
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: sha(bytes)}), /Release header differs/u);
});

test('v0.0.3 fixed set retains four exact wheel members from the original RC pair', async () => {
  // Small synthetic byte files stand in for wheels here. Actual wheel metadata
  // and installed acceptance belong to the RC whose output is pinned by freeze.
  const directory = join(scratch, 'original-python-pair');
  await mkdir(directory);
  const pairRequest = request(true);
  pairRequest.version = '0.0.3';
  const [target] = pairRequest.targets;
  target.platforms = ['linux-x64', 'darwin-arm64'];
  const contents = new Map();
  const wheel = (distribution, file, data) => {
    const bytes = Buffer.from(data);
    contents.set(file, bytes);
    return {distribution, file, bytes: bytes.length, sha256: sha(bytes)};
  };
  const sdk = wheel('actql-sdk', 'actql_sdk-0.0.3-py3-none-any.whl', 'same SDK bytes');
  const facade = wheel('actql', 'actql-0.0.3-py3-none-any.whl', 'same facade bytes');
  const runtimes = [
    wheel('actql-local-runtime', 'actql_local_runtime-0.0.3-py3-none-manylinux_2_28_x86_64.whl', 'Linux runtime'),
    wheel('actql-local-runtime', 'actql_local_runtime-0.0.3-py3-none-macosx_11_0_arm64.whl', 'Darwin runtime'),
  ];
  const producerArchives = {};
  const pair = {sourceSha: source, packageVersion: pairRequest.version, wheelRunId: '100', wheelRunAttempt: '1',
    platforms: [], publishWheels: [facade, sdk, ...runtimes], publishWheelOrigins: []};
  const writeArchive = async ({platform, runtime, path, replacement}) => {
    const manifest = JSON.stringify({source_sha: source, package_version: pairRequest.version, platform,
      wheels: [sdk, runtime, facade]});
    const members = {'cohort/cohort.json': Buffer.from(manifest).toString('base64')};
    for (const item of [sdk, runtime, facade]) {
      const member = item === runtime && replacement ? replacement : contents.get(item.file);
      members[`cohort/wheels/${item.file}`] = member.toString('base64');
    }
    execFileSync('python3', ['-I', '-B', '-c', [
      'import base64, json, sys, zipfile',
      'with zipfile.ZipFile(sys.argv[1], "x", compression=zipfile.ZIP_DEFLATED) as archive:',
      '    for name, encoded in json.loads(sys.argv[2]).items():',
      '        archive.writestr(name, base64.b64decode(encoded))',
    ].join('\n'), path, JSON.stringify(members)]);
    return {manifestSha256: sha(manifest), archiveSha256: sha(await readFile(path))};
  };
  for (const [index, platform] of target.platforms.entries()) {
    const runtime = runtimes[index];
    const path = join(directory, `${platform}.zip`);
    producerArchives[platform] = path;
    pair.platforms.push({platform, producerRepository: 'actql/actql', producerArtifactId: String(9 + index),
      producerJobId: 50 + index, producerArtifactName: `python-wheel-acceptance-${platform}-100-1`,
      gateBSha256: 'a'.repeat(64), wheels: {sdk, runtime, facade}, ...await writeArchive({platform, runtime, path})});
  }
  pair.publishWheelOrigins = pair.publishWheels.map(({file}) => ({file,
    members: pair.platforms.filter(receipt => Object.values(receipt.wheels).some(pin => pin.file === file))
      .map(({platform, producerArtifactId}) => ({platform, producerArtifactId, member: `cohort/wheels/${file}`}))}));
  const pairFile = join(directory, 'python-release-pair.json');
  const pin = async value => {
    const raw = JSON.stringify(value) + '\n';
    await writeFile(pairFile, raw);
    return sha(raw);
  };
  const pairSha256 = await pin(pair);
  const paired = {targetId: target.id, kind: 'python-wheel-pair', directory, pairSha256, producerArchives};
  const destination = join(scratch, 'fixed-python-pair');
  const input = {request: pairRequest, policy, cohorts: [paired], destination};
  const requestFile = join(directory, 'request.json'), descriptorFile = join(directory, 'descriptor.json');
  await writeFile(requestFile, JSON.stringify(pairRequest));
  await writeFile(descriptorFile, JSON.stringify([paired]));
  const fixed = await runRelease(['freeze', requestFile, descriptorFile, destination]);
  assert.equal(fixed.manifest.acceptance, 'unaccepted');
  assert.equal(fixed.manifest.cohorts[0].sha256, pairSha256);
  assert.deepEqual(await readFile(join(destination, target.id, 'python-release-pair.json')), await readFile(pairFile));
  assert.deepEqual(fixed.manifest.artifacts.map(item => item.file), [sdk.file, ...runtimes.map(item => item.file), facade.file]);
  for (const item of fixed.manifest.artifacts) assert.deepEqual(await readFile(join(destination, item.path)), contents.get(item.file));
  assert.deepEqual(await verifyReleaseSet(destination, {expectedSha256: fixed.sha256}), fixed);

  const reject = async (name, pattern, overrides = {}) => {
    const output = join(scratch, name);
    await assert.rejects(freezeReleaseSet({...input, ...overrides, destination: output}), pattern);
    await assert.rejects(readFile(join(output, 'release-set.json')), {code: 'ENOENT'});
    await assert.rejects(mkdir(join(output, 'unexpected')), {code: 'ENOENT'});
  };
  await reject('fixed-loose-python', /requires the original two-platform pair/, {cohorts: [descriptor(true)]});
  await reject('fixed-wrong-pair', /Expected values to be strictly equal/,
    {cohorts: [{...paired, pairSha256: '0'.repeat(64)}]});
  await reject('fixed-swapped-python', /SHA-256 mismatch/, {cohorts: [{...paired, producerArchives: {
    'linux-x64': producerArchives['darwin-arm64'], 'darwin-arm64': producerArchives['linux-x64']}}]});
  const wrongSource = structuredClone(pairRequest);
  wrongSource.source.commit = 'b'.repeat(40);
  await reject('fixed-foreign-source', /Foreign Python release pair source/, {request: wrongSource});
  const missing = structuredClone(pair);
  missing.publishWheelOrigins[0].members.pop();
  await reject('fixed-missing-pure-origin', /Python wheel origins differ/,
    {cohorts: [{...paired, pairSha256: await pin(missing)}]});
  const altered = structuredClone(pair);
  const alternate = join(directory, 'altered-runtime.zip');
  const replaced = Buffer.from('Wrong runtime');
  assert.equal(replaced.length, runtimes[0].bytes);
  Object.assign(altered.platforms[0], await writeArchive({platform: 'linux-x64', runtime: runtimes[0],
    path: alternate, replacement: replaced}));
  await reject('fixed-wheel-substitution', /Original Python wheel digest mismatch/, {cohorts: [{
    ...paired, pairSha256: await pin(altered), producerArchives: {...producerArchives, 'linux-x64': alternate}}]});
  await writeFile(join(destination, target.id, runtimes[1].file), 'unexpected published runtime');
  await assert.rejects(verifyReleaseSet(destination, {expectedSha256: fixed.sha256}));
});

test('v0.0.3 freeze retains the primary failure when both original archives fail to close', async () => {
  const paired = await writeInertPairedPythonReleaseCohort(join(scratch, 'close-originals'), 'python3');
  const pairRequest = request(true);
  pairRequest.version = '0.0.3';
  pairRequest.targets[0].platforms = ['linux-x64', 'darwin-arm64'];
  const archives = Object.values(paired.producerArchives);
  const cleanup = archives.map((path, index) => new Error(`Unconfirmed archive close ${index}`));
  const closed = [];
  const open = fs.promises.open;
  try {
    fs.promises.open = async (path, ...args) => {
      const handle = await open(path, ...args);
      const index = archives.indexOf(path);
      if (index !== -1) {
        const close = handle.close.bind(handle);
        handle.close = async () => {
          await close();
          closed.push(path);
          throw cleanup[index];
        };
      }
      return handle;
    };
    syncBuiltinESMExports();
    const existing = join(scratch, 'close-existing-output');
    await mkdir(existing);
    const input = {request: pairRequest, policy, cohorts: [paired], destination: existing};
    const afterPair = structuredClone(pairRequest);
    afterPair.targets.push(request().targets[0]);
    const missing = join(scratch, 'close-missing-node-cohort');
    const uncreated = join(scratch, 'close-no-output');
    const failedVerification = {...input, request: afterPair, destination: uncreated,
      cohorts: [paired, {...descriptor(false), directory: missing}]};
    for (const [options, code, path] of [
      [failedVerification, 'ENOENT', missing],
      [input, 'EEXIST', existing],
    ]) {
      closed.length = 0;
      await assert.rejects(freezeReleaseSet(options), error => {
        assert(error instanceof AggregateError);
        assert.equal(error.cause, error.errors[0]);
        assert.equal(error.cause?.code, code);
        assert.equal(error.cause?.path, path);
        assert.deepEqual(error.errors[1].errors, cleanup);
        return true;
      });
      assert.deepEqual([...closed].sort(), [...archives].sort());
      await assert.rejects(readFile(join(options.destination, 'release-set.json')), {code: 'ENOENT'});
    }
    closed.length = 0;
    const written = join(scratch, 'close-unconfirmed-output');
    await assert.rejects(freezeReleaseSet({...input, destination: written}), error => {
      assert(error instanceof AggregateError);
      assert.deepEqual(error.errors, cleanup);
      return true;
    });
    assert.deepEqual([...closed].sort(), [...archives].sort());
    assert.equal((await verifyReleaseSet(written)).manifest.acceptance, 'unaccepted');
  } finally {
    fs.promises.open = open;
    syncBuiltinESMExports();
  }
});
