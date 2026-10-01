import { fixedCorpus, coverage } from './corpus.mjs';
import { registrations } from './obligations.mjs';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { oracle } from './engine.mjs';
import { baseRegistry, registry } from './registry.mjs';
import { execute, executions, root, environment, toolchain } from './execute.mjs';
import { snapshot, hash } from './inventory.mjs';
import { profile, inherited, premises, validate, reviewRoute, compareSemantics } from './evidence.mjs';
const target = process.argv[2] ?? 'all';
const selected = process.argv[3] === 'base' ? baseRegistry : registry;
if (!['js', 'wasm', 'native', 'all'].includes(target)) throw new Error('Use js, wasm, native or all');
reviewRoute(root);
const source = snapshot(root);
const directory = join(root, '.artifacts/relation-pipeline');
mkdirSync(directory, { recursive: true });
const models = {};
for (const [id, path] of [['session', 'proofs/bounded-session/check.mjs'], ['chain', 'proofs/relation-chain/check.mjs']]) {
  const result = spawnSync(process.execPath, [path], { cwd: root, env: environment, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  const log = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `${id}-model.log`), log);
  if (result.status !== 0) throw new Error(`Existing model check failed ${id}`);
  models[id] = { command: [process.execPath, path], exit: result.status, passed: true, sourceDigest: source.digest,
    logPath: `.artifacts/relation-pipeline/${id}-model.log`, logDigest: hash(log) };
}
const cases = fixedCorpus(selected, registrations);
const obligations = coverage(cases, selected, registrations);
for (const backend of target === 'all' ? ['js', 'wasm', 'native'] : [target]) {
  const start = executions.length;
  const started = performance.now();
  const results = execute(cases, selected, backend, true, process.argv[3] === 'base' ? 'base' : 'normal');
  results.forEach((result, i) => compareSemantics(cases[i], result, selected));
  const actual = executions.slice(start);
  const report = { version: 'actql-relation-pipeline-evidence/0.1', profile,
    revision: spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).stdout.trim(),
    source, target: backend, registry: selected.map(d => d.name),
    models, inherited, premises, toolchain, evidenceKinds: ['formal-model', 'tested-refinement', 'independent-semantic-check'],
    residual: ['No arbitrary registry/length implementation refinement; capacity remains conditional',
      'child/runtime capacity bounds and 256-byte allowance unproved', 'physical Store and backend boundaries retain existing tests'],
    caseCount: cases.length, obligations, durationMs: performance.now() - started, requested: actual.flatMap(e => e.receipt.cases.map(c => c.caseDigest)), executions: actual };
  validate(report, snapshot(root), selected);
  writeFileSync(join(directory, `${process.argv[3] === 'base' ? 'base-' : ''}${backend}.json`), JSON.stringify(report, null, 2) + '\n');
  const pairs = cases.filter(c => c.id.startsWith('pair:')).map(c => c.steps.map(s => s.op).join('/'));
  console.log(`${backend}: ${cases.length} checked, registered and completed cases; ${pairs.length} adjacent obligations; ${selected.length} descriptors`);
  console.log(`semantic corpus digest ${hash(JSON.stringify(cases))}; empty output ${cases.filter(c => !oracle(c, selected).rows.length).length}`);
}
