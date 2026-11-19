import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {readFileSync, chmodSync} from 'node:fs';
import {parse} from 'yaml';
import {assertReleaseProjectCohort, prepareReleaseProjectNode} from './release-project-sequence-install.mjs';
import {nativeMockInstallOptions} from './test-native-cli-mock-install.mjs';

const source = 'a'.repeat(40), registry = {url: 'http://127.0.0.1:32123/'};
const native = {sourceSha: source, cohort: {packageVersion: '0.0.2'}};
const nodeManifest = () => ({sourceSha: source, cohort: {packageVersion: '0.0.2', packages: ['client-wire', 'sdk', 'local-node', 'node']},
  packages: ['client-wire', 'sdk', 'local-node', 'node'].map(name => ({name: '@actql/' + name,
    version: '0.0.2', file: name + '.tgz', integrity: 'sha512:independent-' + name, files: []}))});

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

test('RC actual command selects Mac Node24 companion once without extending ordinary/formal campaigns', async t => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/release-candidate.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['native-installed'];
  assert(job.needs.includes('node-packages') && job.needs.includes('native-packages'));
  const download = job.steps.find(step => step.with?.path?.endsWith('/native-installed/node-companion'));
  assert(download); assert.equal(download.with['artifact-ids'], '${{ needs.node-packages.outputs.artifact-id }}');
  const inputGuard = job.steps.find(step => step.env?.NODE_ARTIFACT_ID);
  assert(inputGuard && job.steps.indexOf(inputGuard) < job.steps.indexOf(download));
  assert.equal(inputGuard.env.NODE_ARTIFACT_ID, '${{ needs.node-packages.outputs.artifact-id }}');
  for (const nodeArtifact of ['456', '', '0', 'foreign']) {
    const guarded = spawnSync('bash', ['-eo', 'pipefail', '-c', inputGuard.run], {encoding: 'utf8', timeout: 5000,
      env: {...process.env, SELECTED_PLATFORM: 'darwin-arm64', ARTIFACT_ID: '123', NODE_ARTIFACT_ID: nodeArtifact}});
    assert.equal(guarded.error, undefined); assert.equal(guarded.status === 0, nodeArtifact === '456');
  }
  const node24 = job.steps.find(step => step.uses?.startsWith('actions/setup-node@') && step.with?.['node-version'] === '24');
  assert(node24 && node24.if === download.if);
  const functional = job.steps.find(step => step.run?.includes('node scripts/test-native-cli-mock-install.mjs'));
  const binding = job.steps.find(step => step.env?.NODE_MANIFEST_SHA256);
  assert(binding && job.steps.indexOf(binding) < job.steps.indexOf(node24));
  assert.equal(binding.env.NODE_MANIFEST_SHA256, '${{ needs.node-packages.outputs.manifest-sha256 }}');
  assert(job.steps.indexOf(node24) < job.steps.indexOf(functional));
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
    const selected = args.indexOf('--release-project-sequences');
    assert.equal(selected >= 0, platform === 'darwin-arm64');
    if (selected >= 0) assert.equal(args[selected + 1], join(scratch, 'native-installed/node-companion/node-release-rc'));
  }
  const ordinary = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const formal = readFileSync(new URL('../scripts/test-native-approval-performance.mjs', import.meta.url), 'utf8');
  assert(!ordinary.includes('--release-project-sequences') && !formal.includes('--release-project-sequences'));
  const outputs = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@')).with.path;
  assert(outputs.includes('/sequence-cases/*.json') && outputs.includes('*.response.json.close'));
  for (const forbidden of ['sequence-consumer', 'node_modules', '.actql', '*.request.json', 'keys/', '*.db'])
    assert(!outputs.includes(forbidden), forbidden);
});
