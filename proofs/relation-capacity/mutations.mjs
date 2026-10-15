// JS assertion detection against production sources. These observations do not
// certify the native/Wasm mutational domain or any allocation byte-size bound.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {runRestoredMutation, requireMutationDetection} from '../bounded-session/mutation-command.mjs';
import { snapshot, fixture, identityFixture } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const env = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
const path = 'src/connectors/local/selected_relation_provider.mbt';
const cases = [
  // Keep the original max(child retained + execution) fault after capacity
  // split retained outputs from either overlapping or reclaimable scratch.
  ['max-child-instead-of-overlap', path, [
    ['let mut scratch = 0L', 'let mut scratch = 0L\n  let mut maximum_child = 0L'],
    ['retained_children += child.retained_bytes',
      'retained_children += child.retained_bytes\n' +
      '    maximum_child = Int64::max(maximum_child, child.retained_bytes + child.execution_bytes)'],
    ['let live_children = retained_children + scratch', 'let live_children = maximum_child'],
  ], fixture, 1],
  ['omit-child-retained', path, [
    ['retained_children += child.retained_bytes', 'retained_children += 0L'],
  ], fixture, 1],
  ['omit-parent-handles', path, [
    ['let handles = count.to_int64() * 256L', 'let handles = count.to_int64() * 0L'],
  ], fixture, 1],
  ['unchecked-handle-overflow', path, [
    ['if handles > 9223372036854775807L - preparation ||\n' +
      '    live_children > 9223372036854775807L - handles - preparation {',
      'if live_children < 0L {'],
  ], fixture, 1],
  ['pending-cleanup-is-complete', path, [
    ['Ok(false) => return Ok(false)', 'Ok(false) => return Ok(true)'],
  ], fixture, 1],
  ['copy-occurrence-arrays-as-aliases', 'src/execution_relation/managed_independent_output.mbt',
    [['rows: rows.rows.map(row => row.copy()),', 'rows: rows.rows,']], identityFixture, 2],
];
const before = snapshot(root), directory = join(root, '.artifacts/relation-capacity');
mkdirSync(directory, { recursive: true });
const results = [];
for (const [id, path, replacements, suite, sites] of cases) {
  const file = join(root, path), text = readFileSync(file, 'utf8');
  let mutated = text;
  for (const [original, changed] of replacements) {
    if (mutated.split(original).length !== sites + 1) throw new Error(`Review mutation sites: ${id}`);
    mutated = mutated.replaceAll(original, changed);
  }
  const result = await runRestoredMutation(file, text, mutated, join(home, 'bin/moon'),
    ['test', suite, '--target', 'js', '--deny-warn'], {
      cwd: root, env, maxBuffer: 8 * 1024 * 1024,
    });
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `mutation-${id}.log`), output);
  let failureCount;
  try { failureCount = requireMutationDetection(result, output); }
  catch (cause) { throw new Error(`Not killed by assertions: ${id}\n${output}`, {cause}); }
  results.push({ id, path, suite, target: 'js', killed: true, failureCount });
  console.log(`${id}: detected by JS assertions`);
}
if (snapshot(root).digest !== before.digest) throw new Error('Unrestored source after mutations');
writeFileSync(join(directory, 'mutations.json'), `${JSON.stringify({ source: before, results }, null, 2)}\n`);
