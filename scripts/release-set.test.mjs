import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, rm, cp, rename, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import test, {before, after} from 'node:test';
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
  // Real wheel containers, independently authored metadata. They contain NO
  // engine/image: this exercises the existing metadata verifier, not runtime.
  pythonDirectory = join(scratch, 'original-python'); await mkdir(pythonDirectory);
  execFileSync('python3', ['-c', `
import pathlib,zipfile,json,hashlib
p=pathlib.Path(__import__('sys').argv[1]);w=p/'wheels';w.mkdir();records=[]
for name in ['actql-sdk','actql-local-runtime','actql']:
 tag='py3-none-macosx_11_0_arm64' if name=='actql-local-runtime' else 'py3-none-any'
 version='0.0.7rc1';stem=name.replace('-','_');path=w/(stem+'-'+version+'-'+tag+'.whl');info=stem+'-'+version+'.dist-info/'
 deps={'actql':['actql-sdk=='+version,'actql-local-runtime=='+version],'actql-sdk':['httpx==0.28.1','rfc8785==0.1.4'],'actql-local-runtime':['wasmtime==38.0.0']}[name]
 with zipfile.ZipFile(path,'w') as z:
  z.writestr(info+'METADATA','Metadata-Version: 2.4\\nName: '+name+'\\nVersion: '+version+'\\n'+''.join('Requires-Dist: '+v+'\\n' for v in deps))
  z.writestr(info+'WHEEL','Wheel-Version: 1.0\\nTag: '+tag+'\\n')
  z.writestr(info+'RECORD','')
  if name=='actql':
   for n in ['__init__.py','__init__.pyi','py.typed']:z.writestr('actql/'+n,'')
 records.append(dict(distribution=name,file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
cohort=dict(source_sha='a'*40,package_version='0.0.7rc1',artifact_sha256='b'*64,platform='darwin-arm64',core_abi=1,module_sha256='c'*64,duckdb_sha256='d'*64,image_sha256='e'*64,engine_recipe_sha256='f'*64,host_capacity_sha256=None,wheels=records,runtime_executed=False,public_local_accepted=False,recovery_accepted=False,published=False)
(p/'cohort.json').write_text(json.dumps(cohort))
`, pythonDirectory], {encoding: 'utf8', stdio: 'pipe'});
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

test('unsupported Linux Python and standalone Native paths cannot inherit another verifier', async () => {
  const value = request(true); value.targets[0].platforms = ['manylinux_2_28_x86_64'];
  await assert.rejects(freezeReleaseSet({request: value, policy, cohorts: [descriptor(true)], destination: join(scratch, 'no-linux')}));
  const native = request(); native.targets[0] = {...native.targets[0], ecosystem: 'native', destination: 'https://github.com/actql/actql'};
  await assert.rejects(freezeReleaseSet({request: native, policy, cohorts: [{...descriptor(false), kind: 'standalone-native'}], destination: join(scratch, 'no-standalone')}), /standalone Native/u);
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
