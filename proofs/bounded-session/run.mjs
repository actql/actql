import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { inventoryAction, serializeManifest } from './action-inputs.mjs';
import { artifacts, checkBindings, checkRetirements, connectionSuites, executedConnectionCoverage, graph, nestLocalSuites, snapshot, targets, validate } from './evidence.mjs';
import { recordExistingAction } from '../ci-evidence/collect.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const selected = process.argv[2] ?? 'all';
if (selected !== 'all' && !targets.includes(selected)) throw new Error('Use all, js, wasm or native');
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json'), 'utf8'));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const moon = join(home, 'bin/moon');
const env = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
const bindings = JSON.parse(readFileSync(new URL('bindings.json', import.meta.url)));
checkBindings(root, bindings);
const retirements = checkRetirements(root);
const source = snapshot(root);
const directory = join(root, '.artifacts/bounded-session');
mkdirSync(directory, { recursive: true });
const revision = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).stdout.trim();
const worktreeDirty = spawnSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).stdout.trim().length > 0;
const compiler = spawnSync(join(home, 'bin/moonc'), ['-v'], { env, encoding: 'utf8' });
if (compiler.status !== 0 || compiler.stdout.trim() !== pin.moonc) throw new Error('Wrong MoonBit toolchain');

function run(id, command, args, target = 'model', packagePath = null) {
  const start = performance.now();
  const result = spawnSync(command, args, { cwd: root, env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const milliseconds = Math.round(performance.now() - start);
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `${id}.log`), output);
  const count = packagePath ? Number(output.match(/Total tests: (\d+), passed: (\d+), failed: 0/)?.[2] ?? 0) : null;
  if (result.error || result.status !== 0 || (packagePath && count === 0)) {
    process.stderr.write(output);
    throw result.error ?? new Error(`${id} failed or executed no tests`);
  }
  console.log(`${id}: passed${count ? ` ${count} tests` : ''} (${milliseconds} ms)`);
  const execution = {
    command: [command === moon ? 'moon' : command, ...args], target, exit: result.status,
    passed: true, count, milliseconds, sourceDigest: source.digest,
    artifacts: packagePath ? artifacts(root, target, packagePath) : {},
  };
  recordExistingAction({id: id === 'lean' ? 'model' : id,
    command: [command === moon ? 'moon' : command === process.execPath ? 'node' : command, ...args],
    output, status: result.status, milliseconds, result: execution});
  return execution;
}

// Fresh Stage B inventory of this exact launch. This report cannot skip or
// replace the theorem/type/axiom check immediately below, or any later gate.
const inventoryStart = performance.now();
const actionInputs = inventoryAction({
  root, env, executable: process.execPath, args: ['proofs/bounded-session/check.mjs'], cwd: root,
  sourceRevision: /^[a-f0-9]{40}$/.test(revision) ? revision : null,
});
writeFileSync(join(directory, 'action-inputs.json'), serializeManifest(actionInputs));
console.log(`Lean input inventory: ${actionInputs.inputs.files.length} entries (${Math.round(performance.now() - inventoryStart)} ms); report-only, reuse ineligible`);
const lean = run('lean', process.execPath, ['proofs/bounded-session/check.mjs']);
for (const target of selected === 'all' ? targets : [selected]) {
  const runs = { lean };
  runs[`session-${target}`] = run(`session-${target}`, moon,
    ['test', 'src/bounded_execution', '--target', target, '--deny-warn'], target, 'bounded_execution');
  runs[`adapter-${target}`] = run(`adapter-${target}`, moon,
    ['test', 'src/connectors/local', '--target', target, '--deny-warn'], target, 'connectors/local');
  for (const suite of connectionSuites) {
    runs[`${suite.id}-${target}`] = run(`${suite.id}-${target}`, moon,
      ['test', suite.fixture, '--target', target, '--deny-warn'], target, 'query_integration');
    // Reviewed per-fixture scope is independent of the caller's bindings.
    runs[`${suite.id}-${target}`].coverage = executedConnectionCoverage(suite.id);
  }
  for (const suite of nestLocalSuites) {
    runs[`${suite.id}-${target}`] = run(`${suite.id}-${target}`, moon,
      ['test', suite.fixture, '--target', target, '--deny-warn', ...(suite.filter ? ['--filter', suite.filter] : [])], target, 'execution_relation');
  }
  const report = {
    version: 'actql-bounded-session-evidence/0.1', mode: 'report-only', revision, worktreeDirty,
    source, toolchain: pin, target, runs, claims: graph(bindings, target), retirements,
    trust: ['Lean kernel and permitted foundational axioms', 'MoonBit compiler/runtime',
      'reviewed source connection plus executed integration fixture',
      'finite correspondence domains; operation/kernel premises remain obligations'],
  };
  const current = snapshot(root);
  current.builtArtifacts = Object.assign({},
    artifacts(root, target, 'bounded_execution'), artifacts(root, target, 'connectors/local'),
    artifacts(root, target, 'query_integration'), artifacts(root, target, 'execution_relation'));
  const derived = validate(report.claims, report, current, target);
  writeFileSync(join(directory, `${target}.json`), `${JSON.stringify(report, null, 2)}\n`);
  console.log(`${target}: ${derived.length} conditional derived claim(s); existing resource gates remain authoritative`);
}
