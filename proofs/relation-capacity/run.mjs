import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { artifacts, bindings, checkBindings, coverage, fixture, identityFixture, snapshot, targets, validate } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const selected = process.argv[2] ?? 'all';
if (selected !== 'all' && !targets.includes(selected)) throw new Error('Use all, js, wasm or native');
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const moon = join(home, 'bin/moon'), env = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
const compiler = spawnSync(join(home, 'bin/moonc'), ['-v'], { env, encoding: 'utf8' });
if (compiler.status !== 0 || compiler.stdout.trim() !== pin.moonc) throw new Error('Wrong MoonBit pin');
const requested = bindings(); checkBindings(root, requested);
const source = snapshot(root), directory = join(root, '.artifacts/relation-capacity');
mkdirSync(directory, { recursive: true });
const revision = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).stdout.trim();
function run(id, command, args, target = 'model', pkg = null) {
  const start = performance.now();
  const result = spawnSync(command, args, { cwd: root, env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `${id}.log`), output);
  const count = pkg ? Number(output.match(/Total tests: (\d+), passed: (\d+), failed: 0/)?.[2] ?? 0) : null;
  if (result.error || result.status !== 0 || (pkg && !count)) throw result.error ?? new Error(`${id} failed: ${output}`);
  console.log(`${id}: ${count ?? 'proof'} passed`);
  return { command: [command === moon ? 'moon' : command, ...args], passed: true, exit: 0, target, count,
    milliseconds: Math.round(performance.now() - start), sourceDigest: source.digest,
    artifacts: pkg ? artifacts(root, target, pkg) : {} };
}
const lean = run('lean', process.execPath, ['proofs/relation-capacity/check.mjs']);
for (const target of selected === 'all' ? targets : [selected]) {
  const runs = { lean };
  for (const [kind, path, pkg] of [['capacity', fixture, 'query_integration'], ['identity', identityFixture, 'execution_relation'], ['ledger', 'src/physical_resources/ledger_wbtest.mbt', 'physical_resources']]) {
    runs[`${kind}-${target}`] = run(`${kind}-${target}`, moon, ['test', path, '--target', target, '--deny-warn'], target, pkg);
  }
  const current = snapshot(root);
  current.builtArtifacts = Object.assign({}, ...['query_integration', 'execution_relation', 'physical_resources'].map(pkg => artifacts(root, target, pkg)));
  const report = { version: 'actql-relation-capacity-evidence/0.1', mode: 'report-only', revision, source, toolchain: pin, target,
    coverage: coverage(), runs, requested,
    evidenceKinds: { model: 'formal-model', correspondence: 'finite tested-refinement', mutations: 'JS assertion detection only' } };
  report.claims = validate(requested, report, current, target);
  writeFileSync(join(directory, `${target}.json`), `${JSON.stringify(report, null, 2)}\n`);
  console.log(`${target}: ${report.claims.length} conditional allocation claims; parent/child sizing remains unproved`);
}
