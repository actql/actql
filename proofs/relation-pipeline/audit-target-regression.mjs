import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, symlinkSync, writeFileSync } from 'node:fs';
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
const reports = new Set(['base-js.json', 'js.json', 'wasm.json', 'native.json']);
const cases = [
  { name: 'healthy-three-targets', replacements: {}, expected: null },
  { name: 'native-in-js-slot', replacements: { 'js.json': 'native.json' }, expected: 'Report target differs from requested audit target js' },
  { name: 'native-in-wasm-slot', replacements: { 'wasm.json': 'native.json' }, expected: 'Report target differs from requested audit target wasm' },
  { name: 'native-in-both-slots', replacements: { 'js.json': 'native.json', 'wasm.json': 'native.json' }, expected: 'Report target differs from requested audit target js' },
  { name: 'native-in-baseline-slot', replacements: { 'base-js.json': 'native.json' }, expected: 'Baseline report target differs from requested audit target js' },
];
const results = [];
for (const entry of cases) {
  const alternate = join(output, entry.name);
  mkdirSync(alternate);
  for (const name of readdirSync(directory)) {
    if (reports.has(name)) copyFileSync(join(directory, entry.replacements[name] ?? name), join(alternate, name));
    else symlinkSync(join(directory, name), join(alternate, name));
  }
  const actual = spawnSync(process.execPath, ['proofs/relation-pipeline/audit.mjs', alternate],
    { cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  assert.ifError(actual.error);
  const log = `${actual.stdout ?? ''}${actual.stderr ?? ''}`;
  writeFileSync(join(output, `${entry.name}.log`), log);
  if (entry.expected === null) {
    assert.equal(actual.status, 0, `Healthy audit failed: ${log}`);
    for (const target of ['js', 'wasm', 'native']) assert(log.includes(`${target}: exact normal corpus`));
  } else {
    assert.notEqual(actual.status, 0, `Audit accepted ${entry.name}`);
    assert(log.includes(entry.expected), `Wrong rejection for ${entry.name}: ${log}`);
  }
  results.push({ ...entry, exit: actual.status, directory: alternate });
  console.log(`${entry.name}: ${entry.expected === null ? 'accepted' : 'rejected at requested target binding'}`);
}
writeFileSync(join(output, 'results.json'), `${JSON.stringify(results, null, 2)}\n`);
console.log(`Actual audit entrypoint regression evidence retained at ${output}`);
