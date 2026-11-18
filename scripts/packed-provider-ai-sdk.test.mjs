import assert from 'node:assert/strict';
import test from 'node:test';
import {access, lstat, mkdtemp, mkdir, writeFile, readFile, copyFile, cp, rm, glob} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'yaml';
import {CLIENT_PACKAGES, packClientPackages} from './packed-client-packages.mjs';
import {prepareHealthPackages} from './health-monitor-adapters.mjs';
import {runPackedProviderAI} from './test-packed-provider-ai-sdk.mjs';

async function withFixtureGitHubSource(source, action) {
  const original = process.env.GITHUB_SHA;
  process.env.GITHUB_SHA = source;
  try {return await action();}
  finally {
    if (original === undefined) delete process.env.GITHUB_SHA;
    else process.env.GITHUB_SHA = original;
  }
}

// Real Git/tar/inventory acquisition; installs and business processes below are
// explicit command ports, not a Common, normal Host or provider acceptance run.
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-optional-provider-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const repository = join(root, 'source'), retained = join(root, 'original'), archives = join(root, 'archives');
  for (const dir of [repository, retained, archives]) await mkdir(dir);
  await writeFile(join(repository, 'package.json'), '{"private":true,"type":"module"}');
  for (const name of [...CLIENT_PACKAGES, 'provider-ai-sdk']) {
    const pkg = join(repository, 'packages', name); await mkdir(pkg, {recursive: true});
    await writeFile(join(pkg, 'package.json'), JSON.stringify({name: '@actql/' + name,
      version: '0.0.0-development', private: true, files: ['index.mjs', 'npm-shrinkwrap.json'],
      scripts: {prepack: 'node -e "process.stderr.write(\'original lifecycle\\n\')"'}}));
    await writeFile(join(pkg, 'index.mjs'), 'export const fixture = "' + name + '";\n');
    await writeFile(join(pkg, 'npm-shrinkwrap.json'), '{"lockfileVersion":3}');
    const stage = join(archives, name); await mkdir(stage);
    await cp(pkg, join(stage, 'package'), {recursive: true});
    execFileSync('tar', ['-czf', join(archives, 'actql-' + name + '-0.0.0-development.tgz'), '-C', stage, 'package']);
  }
  for (const file of ['normal-openai-installed.fixture.mjs', 'external-rest/conformance.mjs']) {
    await mkdir(join(repository, 'scripts/fixtures', file, '..'), {recursive: true});
    await copyFile(new URL('./fixtures/' + file, import.meta.url), join(repository, 'scripts/fixtures', file));
  }
  const git = args => execFileSync('git', args, {cwd: repository, encoding: 'utf8'}).trim();
  git(['init', '-q']); git(['add', '.']);
  git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']);
  const source = {sha: git(['rev-parse', 'HEAD']), dirty: false};
  const pack = destination => name => copyFile(join(archives, 'actql-' + name + '-0.0.0-development.tgz'),
    join(destination, 'actql-' + name + '-0.0.0-development.tgz'));
  await packClientPackages({repository, destination: retained, pack: pack(retained)});
  const optional = join(retained, 'optional-provider');
  await packClientPackages({repository, destination: optional, names: ['provider-ai-sdk'], pack: pack(optional)});
  const phases = [], installs = [], preparations = [], phaseCalls = [];
  const command = async (cmd, args, options) => {
    // Exercise the same exclusive output rule as execute(), so reusing one
    // install-node raw filename across preparations is an actual fixture error.
    if (options.raw) await writeFile(join(options.raw, options.name + '.stdout'), '', {flag: 'wx'});
    if (cmd === 'npm') {
      installs.push(args);
      preparations.push({cwd: options.cwd, raw: options.raw});
      for (const name of [...CLIENT_PACKAGES, 'provider-ai-sdk']) {
        await cp(join(archives, name, 'package'), join(options.cwd, 'node_modules/@actql', name), {recursive: true});
      }
      return {stdout: '', pid: 70000};
    }
    const phase = args[1]; phases.push(phase);
    const modules = await lstat(join(options.cwd, 'node_modules'));
    assert(modules.isDirectory() && !modules.isSymbolicLink());
    if (phase === 'cold') await access(join(options.cwd, '.state'));
    else {await assert.rejects(access(join(options.cwd, '.state')), {code: 'ENOENT'}); await mkdir(join(options.cwd, '.state'));}
    const pid = 70001 + phaseCalls.length;
    phaseCalls.push({phase, cwd: options.cwd, raw: options.raw, modulesInode: modules.ino, pid});
    return {pid, stdout: JSON.stringify({phase,
      firstCloseReturned: true, aliveScopedFD0: true, calls: phase === 'cold' ? 0 : phase === 'warm' ? 2 : 1,
      ...(phase === 'warm' ? {tasks: 2, requests: 2} : phase === 'cold'
        ? {originalSavedFirst: true, egressChecks: 0}
        : {tasks: 1, requests: 1, usageMode: phase.slice(6), usageCaptures: 1})})};
  };
  return {root, repository, retained, optional, source, command, phases, installs, preparations, phaseCalls};
}

test('optional normal pack reuses lifecycle producer without changing required five', async t => {
  const f = await fixture(t);
  const required = await readFile(join(f.retained, 'packed-client-packages.json'));
  // Exercise the actual default npm callback on a tiny authored package only.
  const extra = join(f.root, 'actual-optional');
  await packClientPackages({repository: f.repository, destination: extra, names: ['provider-ai-sdk']});
  const original = JSON.parse(await readFile(join(extra, 'packed-client-packages.json')));
  assert.deepEqual(Object.keys(original.tarballs), ['provider-ai-sdk']);
  assert.equal(original.revision, f.source.sha);
  assert.deepEqual(Object.keys(JSON.parse(required).tarballs), CLIENT_PACKAGES);
  assert.deepEqual(await readFile(join(f.retained, 'packed-client-packages.json')), required);
});

test('optional usage consumers retain separate fresh installations and warm shares only its cold original', async t => {
  const f = await fixture(t), original = process.env.GITHUB_SHA;
  const result = await withFixtureGitHubSource(f.source.sha,
    () => runPackedProviderAI(join(f.root, 'consumer-case'), f));
  assert.equal(process.env.GITHUB_SHA, original);
  assert.equal(result.complete, true); assert(result.phases.every(row => row.status === 'passed'));
  const [warm, cold, ...usage] = f.phaseCalls;
  assert.equal(warm.cwd, cold.cwd); assert.notEqual(warm.pid, cold.pid);
  assert.equal(warm.modulesInode, cold.modulesInode);
  for (const value of usage) {
    assert.notEqual(value.cwd, warm.cwd); assert.notEqual(value.modulesInode, warm.modulesInode);
    const mode = value.phase.slice(6), actual = result.phases.find(row => row.phase === value.phase).actual;
    assert.equal(actual.usageMode, mode); assert.equal(actual.usageCaptures, 1);
  }
  assert.equal(new Set(usage.map(row => row.cwd)).size, 3);
  assert.equal(new Set(usage.map(row => row.modulesInode)).size, 3);
  assert.equal(new Set(f.preparations.map(row => row.raw)).size, 4);
  for (const args of f.installs) {
    assert(args.includes('--ignore-scripts=false')); assert(!args.includes('--offline'));
    assert.equal(args.filter(x => x.endsWith('.tgz')).length, CLIENT_PACKAGES.length + 1);
  }
  assert.equal(result.preparations.length, f.preparations.length);
});

test('required-five consumers remain offline and never discover optional siblings', async t => {
  const f = await fixture(t), root = join(f.root, 'required-only'); await mkdir(root);
  await writeFile(join(f.optional, 'packed-client-packages.json'), 'invalid optional input');
  const prepared = await prepareHealthPackages({...f, root, normalLifecycle: true});
  assert.deepEqual(prepared.manifest.packages.map(row => row.name), CLIENT_PACKAGES.map(name => '@actql/' + name));
  assert(f.installs[0].includes('--offline'));
  assert.equal(f.installs[0].filter(x => x.endsWith('.tgz')).length, CLIENT_PACKAGES.length);
});

test('optional source, selection and changed archive refuse before any install', async t => {
  for (const mode of ['source', 'extra', 'bytes']) {
    const f = await fixture(t), file = join(f.optional, 'packed-client-packages.json');
    const manifest = JSON.parse(await readFile(file));
    if (mode === 'source') manifest.revision = 'f'.repeat(40);
    if (mode === 'extra') manifest.tarballs.sdk = 'a'.repeat(64);
    await writeFile(file, JSON.stringify(manifest));
    if (mode === 'bytes') await writeFile(join(f.optional, 'actql-provider-ai-sdk-0.0.0-development.tgz'), 'changed');
    const root = join(f.root, 'refusal'); await mkdir(root);
    await assert.rejects(prepareHealthPackages({...f, root, optionalProvider: f.optional, normalLifecycle: true}));
    assert.deepEqual(f.installs, []);
  }
});

test('optional consumer refuses a foreign hosted SHA before output or installation and restores the caller environment', async t => {
  const f = await fixture(t), original = process.env.GITHUB_SHA, destination = join(f.root, 'foreign-source');
  const foreign = (f.source.sha[0] === '0' ? '1' : '0') + f.source.sha.slice(1);
  await withFixtureGitHubSource(foreign, () => assert.rejects(runPackedProviderAI(destination, f),
    error => error.code === 'ERR_ASSERTION' && error.actual === f.source.sha && error.expected === foreign));
  assert.equal(process.env.GITHUB_SHA, original);
  assert.deepEqual(f.installs, []); assert.deepEqual(f.phases, []);
  await assert.rejects(access(destination), {code: 'ENOENT'});
});

test('warm failure preserves primary and cannot start a cold replacement port', async t => {
  const f = await fixture(t), primary = new Error('OriginalWarmFailure');
  const original = process.env.GITHUB_SHA;
  await assert.rejects(withFixtureGitHubSource(f.source.sha, () => runPackedProviderAI(join(f.root, 'failed'), {...f,
    command: async (cmd, args, options) => {
      if (cmd !== 'npm' && args[1] === 'warm') {f.phases.push(args[1]); throw primary;}
      return f.command(cmd, args, options);
    }})), actual => actual === primary);
  assert.equal(process.env.GITHUB_SHA, original);
  assert.equal(f.phases.includes('cold'), false);
  const report = JSON.parse(await readFile(join(f.root, 'failed/summary.json')));
  assert.equal(report.complete, false);
  assert.equal(report.phases.find(row => row.phase === 'warm').status, 'failed');
  assert.equal(report.phases.find(row => row.phase === 'cold').status, 'unexecuted');
  assert(report.phases.filter(row => row.phase.startsWith('usage-')).every(row => row.status === 'passed'));
});

test('optional usage completion refuses mismatched evidence and retained close or FD failures', async t => {
  for (const change of [{usageCaptures: 0}, {calls: 0}, {usageMode: 'reported'}, {aliveScopedFD0: false}]) {
    const f = await fixture(t);
    const root = join(f.root, 'invalid');
    await assert.rejects(withFixtureGitHubSource(f.source.sha, () => runPackedProviderAI(root, {...f, command: async (cmd, args, options) => {
      const result = await f.command(cmd, args, options);
      return args[1] === 'usage-zero' ? {...result, stdout: JSON.stringify({...JSON.parse(result.stdout), ...change})} : result;
    }})));
    const report = JSON.parse(await readFile(join(root, 'summary.json')));
    assert.equal(report.complete, false);
    assert.equal(report.phases.find(row => row.phase === 'usage-zero').status, 'failed');
    assert.equal(report.phases.find(row => row.phase === 'usage-absent').status, 'passed');
  }
});

test('optional diagnostic selection retains nested inventories and bounded usage evidence without keys or state', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-provider-diagnostic-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const ci = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const upload = ci.jobs['client-readme-packed'].steps.find(step => step.with?.path?.includes('/optional-provider/summary.json'));
  const prefix = '${{ runner.temp }}/client-readme-packed/optional-provider/';
  const patterns = upload.with.path.split('\n').filter(path => path.startsWith(prefix)).map(path => path.slice(prefix.length));
  const expected = ['summary.json'];
  const privateFiles = [];
  for (const name of ['warm', 'usage-reported', 'usage-zero', 'usage-absent']) {
    expected.push(`cases/${name}/packages/ordinary-operation-packages.json`,
      `cases/${name}/packages/optional-provider-packages.json`, `raw/${name}/install-node.stdout`);
    if (name !== 'warm') for (const file of ['usage-original.json', 'usage-receipt.json']) expected.push(`cases/${name}/consumer/${file}`);
    for (const file of ['operator-private.fixture', 'api-key.fixture', 'provider.key', '.state/private.db'])
      privateFiles.push(`cases/${name}/consumer/${file}`);
  }
  for (const path of [...expected, ...privateFiles]) {await mkdir(join(root, path, '..'), {recursive: true}); await writeFile(join(root, path), 'fixture');}
  const selected = [];
  for (const pattern of patterns) for await (const path of glob(pattern, {cwd: root})) selected.push(path);
  assert.deepEqual(selected.sort(), expected.sort());
});

test('existing producer and README jobs retain required and optional original inputs', async () => {
  const ci = parse(await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const producer = ci.jobs['client-packages'];
  const optional = producer.steps.filter(step => step.run?.includes("names: ['provider-ai-sdk']"));
  assert.equal(optional.length, 1);
  const upload = producer.steps.find(step => step.id === 'packages');
  assert(producer.steps.indexOf(optional[0]) < producer.steps.indexOf(upload));
  const consumer = ci.jobs['client-readme-packed'].steps.find(step => step.run?.includes('node scripts/test-packed-provider-ai-sdk.mjs '));
  assert(consumer.run.indexOf('command -v lsof') < consumer.run.indexOf('node scripts/'));
  assert.match(consumer.if, /client-inputs\.outcome == 'success'/u);
  const guard = ci.jobs.lint.steps.filter(step => step.run?.includes('scripts/packed-provider-ai-sdk.test.mjs'));
  assert.equal(guard.length, 1);
});
