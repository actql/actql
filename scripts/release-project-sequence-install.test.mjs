import assert from 'node:assert/strict';
import test from 'node:test';
import {access, mkdtemp, mkdir, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile, spawnSync} from 'node:child_process';
import {promisify} from 'node:util';
import {readFileSync, chmodSync} from 'node:fs';
import {parse} from 'yaml';
import {assertReleaseProjectCohort, prepareReleaseProjectNode, runReleaseProjectCli} from './release-project-sequence-install.mjs';
import {nativeMockInstallOptions} from './test-native-cli-mock-install.mjs';

const source = 'a'.repeat(40), registry = {url: 'http://127.0.0.1:32123/'};
const native = {sourceSha: source, cohort: {packageVersion: '0.0.2'}};
const nodeManifest = () => ({sourceSha: source, cohort: {packageVersion: '0.0.2', packages: ['client-wire', 'sdk', 'local-node', 'node']},
  packages: ['client-wire', 'sdk', 'local-node', 'node'].map(name => ({name: '@actql/' + name,
    version: '0.0.2', file: name + '.tgz', integrity: 'sha512:independent-' + name, files: []}))});

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
  const execute = promisify(execFile), calls = [];
  const run = async (command, args, cwd) => {
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
  for (const mutate of [value => {value.sourceSha = 'b'.repeat(40);},
    value => {value.cohort.packageVersion = '0.0.3';}, value => {value.cohort.packages.pop();},
    value => {value.packages.pop();}, value => {value.packages.push({...value.packages[0]});}]) {
    const candidate = nodeManifest(); mutate(candidate); assert.throws(() => assertReleaseProjectCohort(native, candidate));
  }
});

test('RC companion checks payload/lock on both sides of the original child and preserves its primary', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-rc-companion-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const directory = join(root, 'node-rc'), manifest = nodeManifest(), primary = new Error('original child failed');
  await mkdir(directory); await writeFile(join(directory, 'release.json'), JSON.stringify(manifest));
  let calls = 0, originalLock, consumer, fail = false;
  const prepared = await prepareReleaseProjectNode({directory, nativeManifest: native, root,
    originalNodeManifest: manifest, originalNodeManifestBytes: await readFile(join(directory, 'release.json')),
    repository: fileURLToPath(new URL('../', import.meta.url)), registry,
    verifySource() {assert.equal(manifest.sourceSha, source);},
    async verifyManifest(path) {assert.equal(path, directory); return structuredClone(manifest);},
    async run(command, args, cwd) {
      calls++;
      if (command === 'npm') {
        consumer = cwd;
        assert(args.includes('--ignore-scripts') && args.includes('--engine-strict'));
        const packages = {'': {dependencies: {'@actql/node': '0.0.2'}}};
        for (const item of manifest.packages) {
          await mkdir(join(cwd, 'node_modules', item.name), {recursive: true});
          packages['node_modules/' + item.name] = {version: item.version, integrity: item.integrity,
            resolved: registry.url + 'archives/' + item.file};
        }
        originalLock = JSON.stringify({lockfileVersion: 3, packages});
        await writeFile(join(cwd, 'package-lock.json'), originalLock);
        return {code: 0, signal: null};
      }
      assert.equal(command, process.execPath);
      if (fail) {await writeFile(join(directory, 'release.json'), 'changed while failed'); throw primary;}
      await writeFile(args[2], JSON.stringify({pid: 4321, firstClose: {attempted: true, returned: true}}));
      return {code: 0, signal: null, pid: 4321};
    },
  });
  const label = {template: 'churn-risk-mock', family: 'node-sequential', ordinal: 1, phase: 'start'};
  await prepared.node({kind: 'start'}, prepared.projects, label);
  const before = calls;
  const lock = JSON.parse(originalLock); lock.packages['node_modules/@actql/sdk'].integrity = 'foreign-SRI';
  await writeFile(join(consumer, 'package-lock.json'), JSON.stringify(lock));
  await assert.rejects(prepared.node({kind: 'start'}, prepared.projects, label));
  assert.equal(calls, before, 'Failed admission cannot start even the fixture child');
  await writeFile(join(consumer, 'package-lock.json'), originalLock);
  const fixture = join(consumer, 'sequence.mjs'), originalFixture = await readFile(fixture);
  await writeFile(fixture, 'foreign fixture implementation');
  await assert.rejects(prepared.node({kind: 'start'}, prepared.projects, label));
  assert.equal(calls, before);
  await writeFile(fixture, originalFixture);
  fail = true;
  await assert.rejects(prepared.node({kind: 'start'}, prepared.projects, label), value => value === primary);
});

test('RC actual command selects only Mac project sequences and preserves failures', async t => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/release-candidate.yml', import.meta.url), 'utf8'));
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
    const value = spawnSync('bash', ['-eo', 'pipefail', '-c', functional.run], {cwd: scratch,
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
  const outputs = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@')).with.path;
  for (const forbidden of ['sequence-consumer', 'node_modules', '.actql', '*.request.json', 'keys/', '*.db'])
    assert(!outputs.includes(forbidden), forbidden);
});
