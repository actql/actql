import assert from 'node:assert/strict';
import test from 'node:test';
import {access, mkdtemp, mkdir, readFile, realpath, rename, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {parse as parseModule} from 'acorn';
import {execFile, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {promisify} from 'node:util';
import {readFileSync, chmodSync} from 'node:fs';
import {parse} from 'yaml';
import {assertReleaseProjectCohort, prepareReleaseProjectNode, retainReleaseProjectArchives, runReleaseProjectCli} from './release-project-sequence-install.mjs';
import {nativeMockInstallOptions} from './test-native-cli-mock-install.mjs';
import type {ImportDeclaration} from 'acorn';
import type {SpawnSyncReturns} from 'node:child_process';
import type {BinaryLike} from 'node:crypto';

type CliCall = {command: string; args: readonly string[]; cwd: string};
type LockPackage = {dependencies?: Record<string, string>; version?: string; integrity?: string; resolved?: string};
type Workflow = {jobs: Record<string, {needs: string[]; steps: {
  run?: string; uses?: string; 'continue-on-error'?: boolean; with?: {path: string};
}[]}>};

const source = 'a'.repeat(40), registry = {url: 'http://127.0.0.1:32123/'};
const native = {sourceSha: source, cohort: {packageVersion: '0.0.2'}};
const sha256 = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');
const fixtureArchive = (file: string) => Buffer.from('Independent exact archive bytes for ' + file);
const nodeManifest = () => ({sourceSha: source, cohort: {packageVersion: '0.0.2', packages: ['client-wire', 'sdk', 'local-node', 'node']},
  packages: ['client-wire', 'sdk', 'local-node', 'node'].map(name => {
    const file = name + '.tgz', originalFile = 'original-' + file;
    return {name: '@actql/' + name, version: '0.0.2', file, originalFile, integrity: 'sha512:independent-' + name,
      bytes: fixtureArchive(file).length, sha256: sha256(fixtureArchive(file)),
      originalSha256: sha256(fixtureArchive(originalFile)), files: []};
  })});

test('RC CLI init creates its own project from the existing parent; later commands use that project', async t => {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'actql-rc-cli-cwd-')));
  t.after(() => rm(root, {recursive: true, force: true}));
  const projects = join(root, 'projects'), project = join(projects, 'fresh-project'), launcher = join(root, 'launcher.mjs');
  await mkdir(projects);
  await writeFile(launcher, `import assert from 'node:assert/strict';
import {access, mkdir, writeFile} from 'node:fs/promises';
const [command, ...args] = process.argv.slice(2);
if (command === 'init') {
  await assert.rejects(access(args[2]), {code: 'ENOENT'});
  await mkdir(args[2]);
  await writeFile(args[2] + '/created-by-init', 'original initializer');
}
if (command === 'refuse') process.exitCode = 19;
console.log(JSON.stringify({cwd: process.cwd(), command, args}));
`);
  const execute = promisify(execFile), calls: CliCall[] = [];
  const run = async (command: string, args: readonly string[], cwd: string) => {
    calls.push({command, args, cwd});
    return JSON.parse((await execute(command, args, {cwd, encoding: 'utf8', timeout: 5000})).stdout);
  };
  await assert.rejects(access(project), {code: 'ENOENT'});
  const initArgs = ['init', '--template', 'deal-review-mock', project];
  assert.deepEqual(await runReleaseProjectCli(run, launcher, initArgs, project),
    {cwd: projects, command: 'init', args: initArgs.slice(1)});
  assert.equal(await readFile(join(project, 'created-by-init'), 'utf8'), 'original initializer');
  assert.deepEqual(await runReleaseProjectCli(run, launcher, ['status', 'original-run'], project),
    {cwd: project, command: 'status', args: ['original-run']});
  assert(calls.every(value => value.command === process.execPath && value.args[0] === launcher));
  await assert.rejects(runReleaseProjectCli(run, launcher, ['refuse'], project), {code: 19});
  const missing = join(root, 'missing-parent', 'uncreated-project');
  await assert.rejects(runReleaseProjectCli(run, launcher, ['init', '--template', 'deal-review-mock', missing], missing), {code: 'ENOENT'});
  await assert.rejects(runReleaseProjectCli(run, launcher, ['status', 'original-run'], missing), {code: 'ENOENT'});
  await assert.rejects(access(missing), {code: 'ENOENT'});
});

test('RC CLI init creates its own project from the existing parent; later commands use that project', async t => {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'actql-rc-cli-cwd-')));
  t.after(() => rm(root, {recursive: true, force: true}));
  const projects = join(root, 'projects'), project = join(projects, 'fresh-project'), launcher = join(root, 'launcher.mjs');
  await mkdir(projects);
  await writeFile(launcher, `import assert from 'node:assert/strict';
import {access, mkdir, writeFile} from 'node:fs/promises';
const [command, ...args] = process.argv.slice(2);
if (command === 'init') {
  await assert.rejects(access(args[2]), {code: 'ENOENT'});
  await mkdir(args[2]);
  await writeFile(args[2] + '/created-by-init', 'original initializer');
}
if (command === 'refuse') process.exitCode = 19;
console.log(JSON.stringify({cwd: process.cwd(), command, args}));
`);
  const execute = promisify(execFile), calls: CliCall[] = [];
  const run = async (command: string, args: readonly string[], cwd: string) => {
    calls.push({command, args, cwd});
    return JSON.parse((await execute(command, args, {cwd, encoding: 'utf8', timeout: 5000})).stdout);
  };
  await assert.rejects(access(project), {code: 'ENOENT'});
  const initArgs = ['init', '--template', 'deal-review-mock', project];
  assert.deepEqual(await runReleaseProjectCli(run, launcher, initArgs, project),
    {cwd: projects, command: 'init', args: initArgs.slice(1)});
  assert.equal(await readFile(join(project, 'created-by-init'), 'utf8'), 'original initializer');
  assert.deepEqual(await runReleaseProjectCli(run, launcher, ['status', 'original-run'], project),
    {cwd: project, command: 'status', args: ['original-run']});
  assert(calls.every(value => value.command === process.execPath && value.args[0] === launcher));
  await assert.rejects(runReleaseProjectCli(run, launcher, ['refuse'], project), {code: 19});
  const missing = join(root, 'missing-parent', 'uncreated-project');
  await assert.rejects(runReleaseProjectCli(run, launcher, ['init', '--template', 'deal-review-mock', missing], missing), {code: 'ENOENT'});
  await assert.rejects(runReleaseProjectCli(run, launcher, ['status', 'original-run'], missing), {code: 'ENOENT'});
  await assert.rejects(access(missing), {code: 'ENOENT'});
});

test('RC sequence option is explicit, paired and cannot enter a formal or foreign consumer', () => {
  assert.equal(nativeMockInstallOptions([], 'darwin').projectSequenceNodeRelease, undefined);
  assert.equal(nativeMockInstallOptions(['--measure-approval-resources', '--release-project-sequences', '/own/node-rc'], 'darwin')
    .projectSequenceNodeRelease, '/own/node-rc');
  for (const args of [['--release-project-sequences'], ['--release-project-sequences', ''],
    ['--release-project-sequences', '/own/node-rc', '--measure-approval-resources'],
    ['--release-project-sequences', '/one', '--release-project-sequences', '/two'],
    ['--campaign-worker', '30', '--release-project-sequences', '/own/node-rc']])
    assert.throws(() => nativeMockInstallOptions(args, 'darwin'));
  assert.throws(() => nativeMockInstallOptions(['--release-project-sequences', '/own/node-rc'], 'linux'));
});

test('Original Mock regression selection reuses exact Mac companion and stays separate from Stage2', () => {
  const options = nativeMockInstallOptions(['--measure-approval-resources', '--original-mock-regressions', '/own/node-rc'], 'darwin');
  assert.equal(options.projectSequenceNodeRelease, '/own/node-rc'); assert.equal(options.originalMockRegressions, true);
  assert.equal(nativeMockInstallOptions(['--release-project-sequences', '/own/node-rc'], 'darwin').originalMockRegressions, undefined);
  for (const args of [['--original-mock-regressions'], ['--original-mock-regressions', ''],
    ['--release-project-sequences', '/one', '--original-mock-regressions', '/two'],
    ['--original-mock-regressions', '/one', '--release-project-sequences', '/two']])
    assert.throws(() => nativeMockInstallOptions(args, 'darwin'));
  assert.throws(() => nativeMockInstallOptions(['--original-mock-regressions', '/own/node-rc'], 'linux'));
});

test('RC companion fences exact source, version and complete Node roles before installation', () => {
  assertReleaseProjectCohort(native, nodeManifest());
  for (const mutate of [(value: ReturnType<typeof nodeManifest>) => {value.sourceSha = 'b'.repeat(40);},
    (value: ReturnType<typeof nodeManifest>) => {value.cohort.packageVersion = '0.0.3';}, (value: ReturnType<typeof nodeManifest>) => {value.cohort.packages.pop();},
    (value: ReturnType<typeof nodeManifest>) => {value.packages.pop();}, (value: ReturnType<typeof nodeManifest>) => {value.packages.push({...value.packages[0]});}]) {
    const candidate = nodeManifest(); mutate(candidate); assert.throws(() => assertReleaseProjectCohort(native, candidate));
  }
});

test('RC companion checks payload/lock on both sides of the original child and preserves its primary', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-rc-companion-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const directory = join(root, 'node-rc'), manifest = nodeManifest(), primary = new Error('original child failed');
  const development = join(directory, 'development');
  await mkdir(development, {recursive: true});
  await writeFile(join(directory, 'release.json'), JSON.stringify(manifest));
  const developmentManifest = Buffer.from(JSON.stringify({revision: source}));
  await writeFile(join(development, 'packed-client-packages.json'), developmentManifest);
  for (const item of manifest.packages) {
    await writeFile(join(directory, item.file), fixtureArchive(item.file));
    await writeFile(join(development, item.originalFile), fixtureArchive(item.originalFile));
  }
  let calls = 0, releaseChecks = 0, originalLock: string | undefined, consumer: string | undefined,
    childEntry: string | undefined, fail = false;
  const prepared = await prepareReleaseProjectNode({directory, nativeManifest: native, root,
    originalNodeManifest: manifest, originalNodeManifestBytes: await readFile(join(directory, 'release.json')),
    originalNodeDevelopmentManifestBytes: developmentManifest,
    repository: fileURLToPath(new URL('../', import.meta.url)), registry,
    verifySource() {assert.equal(manifest.sourceSha, source);},
    async verifyManifest(path) {releaseChecks++; assert.equal(path, directory); return structuredClone(manifest);},
    async run(command, args, cwd) {
      calls++;
      if (command === 'npm') {
        consumer = cwd;
        assert(args.includes('--ignore-scripts') && args.includes('--engine-strict'));
        const packages: Record<string, LockPackage> = {'': {dependencies: {'@actql/node': '0.0.2'}}};
        for (const item of manifest.packages) {
          await mkdir(join(cwd, 'node_modules', item.name), {recursive: true});
          packages['node_modules/' + item.name] = {version: item.version, integrity: item.integrity,
            resolved: registry.url + 'archives/' + item.file};
        }
        originalLock = JSON.stringify({lockfileVersion: 3, packages});
        await writeFile(join(cwd, 'package-lock.json'), originalLock!);
        return {code: 0, signal: null};
      }
      assert.equal(command, process.execPath);
      childEntry = args[0];
      if (fail) {await writeFile(join(directory, 'release.json'), 'changed while failed'); throw primary;}
      await writeFile(args[2], JSON.stringify({pid: 4321, firstClose: {attempted: true, returned: true}}));
      return {code: 0, signal: null, pid: 4321};
    },
  });
  const label = {template: 'churn-risk-mock', family: 'node-sequential', ordinal: 1, phase: 'start'};
  await prepared.node({kind: 'start'}, prepared.projects, label);
  assert.equal(releaseChecks, 1, 'Canonical verification belongs to a cohort boundary, not a Node child');
  await prepared.verifyRelease();
  assert.equal(releaseChecks, 2);
  const before = calls;
  const lock = JSON.parse(originalLock!); lock.packages['node_modules/@actql/sdk'].integrity = 'foreign-SRI';
  await writeFile(join(consumer!, 'package-lock.json'), JSON.stringify(lock));
  await assert.rejects(prepared.node({kind: 'start'}, prepared.projects, label));
  assert.equal(calls, before, 'Failed admission cannot start even the fixture child');
  await writeFile(join(consumer!, 'package-lock.json'), originalLock!);
  const fixture = childEntry!, originalFixture = await readFile(fixture);
  const imports = parseModule(originalFixture.toString('utf8'), {sourceType: 'module', ecmaVersion: 'latest'}).body
    .filter((statement): statement is ImportDeclaration =>
      statement.type === 'ImportDeclaration' && (statement.source.value as string).startsWith('.'));
  assert.equal(imports.length, 2);
  const dependencies = await Promise.all(imports.map(statement =>
    import(new URL(statement.source.value as string, pathToFileURL(fixture)).href)));
  assert(dependencies.some(namespace => typeof namespace.runReleaseProjectNodeAction === 'function'));
  assert(dependencies.some(namespace => typeof namespace.workflowWorkObservation === 'function'));
  await writeFile(fixture, 'foreign fixture implementation');
  await assert.rejects(prepared.node({kind: 'start'}, prepared.projects, label));
  assert.equal(calls, before);
  await writeFile(fixture, originalFixture);
  const originalFile = manifest.packages[0].originalFile;
  const originalArchive = join(development, originalFile);
  await writeFile(originalArchive, Buffer.alloc(fixtureArchive(originalFile).length, 113));
  await assert.rejects(prepared.node({kind: 'start'}, prepared.projects, label), /Original archive bytes changed/u);
  assert.equal(calls, before);
  assert.equal(releaseChecks, 2);
  await writeFile(originalArchive, fixtureArchive(originalFile));
  fail = true;
  await assert.rejects(prepared.node({kind: 'start'}, prepared.projects, label), value => value === primary);
});

test('RC archive fence refuses same-byte replacement and changes to original manifest bytes', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-rc-archive-fence-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const name = 'native.tgz', bytes = fixtureArchive(name);
  const manifest = {packages: [{file: name, bytes: bytes.length, sha256: sha256(bytes)}]};
  const manifestFile = join(directory, 'release.json'), archive = join(directory, name);
  const raw = Buffer.from(JSON.stringify(manifest));
  await writeFile(manifestFile, raw);
  await writeFile(archive, bytes);
  const verify = await retainReleaseProjectArchives(directory, manifest, raw);
  await verify();
  await writeFile(manifestFile, Buffer.concat([raw, Buffer.from(' ')]));
  await assert.rejects(verify);
  await writeFile(manifestFile, raw);
  await rename(archive, join(directory, 'prior.tgz'));
  await writeFile(archive, bytes);
  await assert.rejects(verify);
});

test('RC actual command selects only Mac project sequences and preserves failures', async t => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/release-candidate.yml', import.meta.url), 'utf8')) as Workflow;
  const job = workflow.jobs['native-installed'];
  assert(job.needs.includes('native-packages'));
  const functional = job.steps.find(step => step.run?.includes('node scripts/test-native-cli-mock-install.mjs'));
  assert(functional);
  assert(!functional['continue-on-error']);
  const scratch = await mkdtemp(join(tmpdir(), 'actql-rc-command-port-'));
  t.after(() => rm(scratch, {recursive: true, force: true}));
  const bin = join(scratch, 'bin'), calls = join(scratch, 'calls'); await mkdir(bin);
  await writeFile(join(bin, 'node'), '#!/bin/sh\nprintf "%s\\n" "$@" > "$CALLS"\nexit "$OUTCOME"\n'); chmodSync(join(bin, 'node'), 0o755);
  for (const platform of ['darwin-arm64', 'linux-x64-gnu']) for (const outcome of [0, 19]) {
    const value: SpawnSyncReturns<string> = spawnSync('bash', ['-eo', 'pipefail', '-c', functional.run!], {cwd: scratch,
      env: {...process.env, PATH: bin + ':/usr/bin:/bin', CALLS: calls, OUTCOME: String(outcome),
        RUNNER_TEMP: scratch, SELECTED_PLATFORM: platform}, encoding: 'utf8', timeout: 5000});
    assert.equal(value.error, undefined); assert.equal(value.status, outcome);
    const args = (await readFile(calls, 'utf8')).trim().split('\n');
    assert.equal(args[0], 'scripts/test-native-cli-mock-install.mjs');
    assert(args.includes('--measure-approval-resources'));
    const options = nativeMockInstallOptions(args.slice(2), platform === 'darwin-arm64' ? 'darwin' : 'linux');
    assert.equal(options.projectSequenceNodeRelease, platform === 'darwin-arm64'
      ? join(scratch, 'native-installed/node-release-input/node-release-rc') : undefined);
    assert.equal(options.measureResources, true);
  }
  const ordinary = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const formal = readFileSync(new URL('../scripts/test-native-approval-performance.mjs', import.meta.url), 'utf8');
  assert(!ordinary.includes('--release-project-sequences') && !formal.includes('--release-project-sequences'));
  const outputs = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'))!.with!.path;
  const sequenceCases = outputs.trim().split('\n').filter(path => path.includes('sequence-cases'));
  assert.deepEqual(sequenceCases, [
    '${{ runner.temp }}/native-installed/scratch/**/sequence-cases/*.json',
    '/tmp/actql-native-mock-install-*/sequence-cases/*.json',
  ], 'Retain only the existing bounded synthetic case records from either admitted scratch root');
  for (const forbidden of ['sequence-consumer', 'node_modules', '.actql', '*.request.json', 'keys/', '*.db'])
    assert(!outputs.includes(forbidden), forbidden);
});
