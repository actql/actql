import assert from 'node:assert/strict';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, symlinkSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../', import.meta.url));
const directory = resolve(process.argv[2] ?? join(root, '.artifacts/relation-pipeline'));
// Keep originals, source snapshots, receipts, commands, logs and binaries intact.
// Each alternate audit directory changes only which whole report occupies a slot.
const parent = join(root, '.artifacts/relation-pipeline-target-regression');
mkdirSync(parent, { recursive: true });
const output = mkdtempSync(join(parent, 'run-'));
const baselineSlots = existsSync(join(directory, 'base-js-L-M0.json')) ? ['base-js-L-M0.json', 'base-js-L-M1.json'] : ['base-js.json'];
const reports = new Set([...baselineSlots, 'js.json', 'wasm.json', 'native.json']);
const cases = [
  { name: 'healthy-three-targets', replacements: {}, expected: null },
  { name: 'native-in-js-slot', replacements: { 'js.json': 'native.json' }, expected: 'Report target differs from requested audit target js' },
  { name: 'native-in-wasm-slot', replacements: { 'wasm.json': 'native.json' }, expected: 'Report target differs from requested audit target wasm' },
  { name: 'native-in-both-slots', replacements: { 'js.json': 'native.json', 'wasm.json': 'native.json' }, expected: 'Report target differs from requested audit target js' },
  ...baselineSlots.map(slot => ({ name: `native-in-${slot.slice(0, -5)}-slot`, replacements: { [slot]: 'native.json' }, expected: 'Baseline report target differs from requested audit target js' })),
];
const results = [], negatives = [];
for (const entry of cases) {
  const alternate = join(output, entry.name);
  mkdirSync(alternate);
  for (const name of readdirSync(directory)) {
    if (reports.has(name)) copyFileSync(join(directory, entry.replacements[name] ?? name), join(alternate, name));
    else symlinkSync(join(directory, name), join(alternate, name));
  }
  if (entry.expected !== null) {
    negatives.push({ ...entry, directory: alternate });
    continue;
  }
  // Preserve the ordinary healthy CLI independently of the batched negatives.
  const actual = spawnSync(process.execPath, ['proofs/relation-pipeline/audit.mjs', alternate],
    { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  assert.ifError(actual.error);
  const log = `${actual.stdout ?? ''}${actual.stderr ?? ''}`;
  writeFileSync(join(output, `${entry.name}.log`), log);
  assert.equal(actual.status, 0, `Healthy audit failed: ${log}`);
  for (const target of ['js', 'wasm', 'native']) assert(log.includes(`${target}: exact normal corpus`));
  results.push({ ...entry, exit: actual.status, directory: alternate });
  console.log(`${entry.name}: accepted`);
}
// The actual audit CLI owns mandatory preparation once, and still performs the
// full audit independently for every alternate report directory. Originals and
// the checkout stay read-only for the lifetime of this subprocess.
const plan = join(output, 'batch-plan.json');
writeFileSync(plan, JSON.stringify(negatives, null, 2) + '\n');
const actual = spawnSync(process.execPath, ['proofs/relation-pipeline/audit.mjs', '--target-regressions', plan],
  { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
assert.ifError(actual.error);
writeFileSync(join(output, 'batch.log'), `${actual.stdout ?? ''}${actual.stderr ?? ''}`);
assert.equal(actual.status, 0, `Target regression batch failed: ${actual.stdout ?? ''}${actual.stderr ?? ''}`);
const batch = JSON.parse(actual.stdout);
assert.deepEqual(batch.results.map(entry => entry.name), negatives.map(entry => entry.name), 'Incomplete target regression batch');
for (const [index, entry] of negatives.entries()) {
  const result = batch.results[index];
  assert.equal(result.rejected, true, `Audit accepted ${entry.name}`);
  assert(result.log.includes(entry.expected), `Wrong rejection for ${entry.name}: ${result.log}`);
  writeFileSync(join(output, `${entry.name}.log`), result.log);
  results.push({ ...entry, rejected: result.rejected, batchExit: actual.status });
  console.log(`${entry.name}: rejected at requested target binding`);
}
writeFileSync(join(output, 'timings.json'), JSON.stringify({
  preparation: batch.preparation,
  cases: batch.results.map(({ name, auditMs }) => ({ name, auditMs })),
}, null, 2) + '\n');
console.log(`Target regression preparation: ${JSON.stringify(batch.preparation)}`);
writeFileSync(join(output, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
console.log(`Actual audit entrypoint regression evidence retained at ${output}`);
