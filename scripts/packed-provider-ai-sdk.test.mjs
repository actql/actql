import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, writeFile, readFile, copyFile, cp, rm} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'yaml';
import {CLIENT_PACKAGES, packClientPackages} from './packed-client-packages.mjs';
import {prepareHealthPackages} from './health-monitor-adapters.mjs';
import {runPackedProviderAI} from './test-packed-provider-ai-sdk.mjs';

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
  const phases = [], installs = [];
  const command = async (cmd, args, options) => {
    if (cmd === 'npm') {
      installs.push(args);
      for (const name of [...CLIENT_PACKAGES, 'provider-ai-sdk']) {
        await cp(join(archives, name, 'package'), join(options.cwd, 'node_modules/@actql', name), {recursive: true});
      }
      return {stdout: '', pid: 70000};
    }
    const phase = args[1]; phases.push(phase);
    return {pid: phase === 'warm' ? 70001 : 70002, stdout: JSON.stringify({phase,
      firstCloseReturned: true, aliveScopedFD0: true, calls: phase === 'warm' ? 2 : 0,
      ...(phase === 'warm' ? {tasks: 2, requests: 2} : {originalSavedFirst: true, egressChecks: 0})})};
  };
  return {root, repository, retained, optional, source, command, phases, installs};
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

test('optional install verifies original six payloads and runs warm then distinct cold ports', async t => {
  const f = await fixture(t);
  const result = await runPackedProviderAI(join(f.root, 'consumer-case'), f);
  assert.equal(result.complete, true); assert.deepEqual(f.phases, ['warm', 'cold']);
  assert.equal(f.installs.length, 1);
  const args = f.installs[0];
  assert(args.includes('--ignore-scripts=false')); assert(!args.includes('--offline'));
  assert.equal(args.filter(x => x.endsWith('.tgz')).length, CLIENT_PACKAGES.length + 1);
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

test('warm failure preserves primary and cannot start a cold replacement port', async t => {
  const f = await fixture(t), primary = new Error('OriginalWarmFailure');
  await assert.rejects(runPackedProviderAI(join(f.root, 'failed'), {...f,
    command: async (cmd, args, options) => {
      if (cmd !== 'npm') {f.phases.push(args[1]); throw primary;}
      return f.command(cmd, args, options);
    }}), actual => actual === primary);
  assert.deepEqual(f.phases, ['warm']);
  const report = JSON.parse(await readFile(join(f.root, 'failed/summary.json')));
  assert.equal(report.complete, false);
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
