// JS assertion detection against production sources. These observations do not
// certify the native/Wasm mutational domain or any allocation byte-size bound.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { snapshot, fixture, identityFixture } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const env = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
const path = 'src/connectors/local/selected_relation_provider.mbt';
const cases = [
  ['max-child-instead-of-overlap', path, 'live_children += child.retained_bytes + child.execution_bytes',
    'live_children = Int64::max(live_children, child.retained_bytes + child.execution_bytes)', fixture, 1],
  ['omit-child-retained', path, 'live_children += child.retained_bytes + child.execution_bytes',
    'live_children += child.execution_bytes', fixture, 1],
  ['omit-parent-handles', path, 'let handles = count.to_int64() * 256L', 'let handles = count.to_int64() * 0L', fixture, 1],
  ['unchecked-handle-overflow', path, 'if live_children > 9223372036854775807L - handles {',
    'if live_children < 0L {', fixture, 1],
  ['pending-cleanup-is-complete', path, 'Ok(false) => return Ok(false)', 'Ok(false) => return Ok(true)', fixture, 1],
  ['copy-occurrence-arrays-as-aliases', 'src/execution_relation/managed_independent_output.mbt',
    'rows: rows.rows.map(row => row.copy()),', 'rows: rows.rows,', identityFixture, 2],
];
const before = snapshot(root), directory = join(root, '.artifacts/relation-capacity');
mkdirSync(directory, { recursive: true });
const results = [];
for (const [id, path, original, changed, suite, sites] of cases) {
  const file = join(root, path), text = readFileSync(file, 'utf8');
  if (text.split(original).length !== sites + 1) throw new Error(`Review mutation sites: ${id}`);
  let result;
  try {
    writeFileSync(file, text.replaceAll(original, changed));
    result = spawnSync(join(home, 'bin/moon'), ['test', suite, '--target', 'js', '--deny-warn'], {
      cwd: root, env, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
    });
  } finally { writeFileSync(file, text); }
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `mutation-${id}.log`), output);
  const failureCount = Number(output.match(/Total tests: \d+, passed: \d+, failed: (\d+)/)?.[1] ?? 0);
  if (result.error || result.status === 0 || !failureCount || /Error: \[\d+\]/.test(output)) throw result.error ?? new Error(`Not killed by assertions: ${id}\n${output}`);
  results.push({ id, path, suite, target: 'js', killed: true, failureCount });
  console.log(`${id}: detected by JS assertions`);
}
if (snapshot(root).digest !== before.digest) throw new Error('Unrestored source after mutations');
writeFileSync(join(directory, 'mutations.json'), `${JSON.stringify({ source: before, results }, null, 2)}\n`);
