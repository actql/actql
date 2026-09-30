// Mutate production sources, execute ONLY the replacement correspondence tests,
// and restore every file even on failure. Compile errors do not count as kills.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { snapshot } from './evidence.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const env = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
const chain = 'src/connectors/local/selected_relation_provider.mbt';
const tea = 'src/local_tea_provider/time_series.mbt';
const suite = 'src/query_integration/relation_chain_evidence_wbtest.mbt';
const cases = [
  ['reset-consumed-budget', chain,
    'let start_next = fn() -> Result[Unit, @connector.FixedComputeIssue] {',
    'let start_next = fn() -> Result[Unit, @connector.FixedComputeIssue] {\n    used.val = 0L'],
  ['omit-handoff-accounting', chain,
    'used.val += 1L\n          match start_next()',
    'used.val += 0L\n          match start_next()'],
  ['fresh-budget-for-next-child', chain,
    'let remaining = execution.max_work.to_int64() - used.val\n    if remaining < 1L',
    'let remaining = execution.max_work.to_int64()\n    if remaining < 1L'],
  ['cleanup-reenters-advance', chain,
    'fn() {\n        if reclaimed.val {\n          return Ok(true)',
    'fn() {\n        if current.val is Some(active) { advance_managed_provider(active, 1) |> ignore }\n        if reclaimed.val {\n          return Ok(true)'],
  ['handoff-failure-drops-children', chain,
    'Err(issue) => {\n              terminal.val = true\n              return Ok(managed_provider_failed(issue, 0L, 1L))',
    'Err(issue) => {\n              children.val = []\n              terminal.val = true\n              return Ok(managed_provider_failed(issue, 0L, 1L))'],
  ['pending-cleanup-reported-complete', chain,
    'Ok(false) => return Ok(false)', 'Ok(false) => return Ok(true)'],
  ['cancel-not-forwarded-to-session', tea,
    'fn() { @bounded.request_cancel(control) }', 'fn() { false }'],
  ['row-adapter-cumulative-as-delta', chain,
    'let work_delta = next_work - work.val', 'let work_delta = next_work'],
  ['premature-chain-terminal', chain,
    'let terminal = Ref(false)', 'let terminal = Ref(true)'],
].map(([id, path, original, changed]) => [id, path, original, changed, suite, 'chain evidence*']);
const before = snapshot(root);
const directory = join(root, '.artifacts/relation-chain');
mkdirSync(directory, { recursive: true });
const results = [];
for (const [id, path, original, changed, suite, filter] of cases) {
  const file = join(root, path);
  const source = readFileSync(file, 'utf8');
  if (source.split(original).length !== 2) throw new Error(`Mutation site not unique: ${id}`);
  let result;
  try {
    writeFileSync(file, source.replace(original, changed));
    result = spawnSync(join(home, 'bin/moon'), ['test', suite, '--target', 'js', '--deny-warn', '--filter', filter], {
      cwd: root, env, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024,
    });
  } finally {
    writeFileSync(file, source);
  }
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `mutation-${id}.log`), output);
  const count = Number(output.match(/Total tests: \d+, passed: \d+, failed: (\d+)/)?.[1] ?? 0);
  if (result.error || result.status === 0 || count === 0 || /Error: \[\d+\]/.test(output)) {
    throw result.error ?? new Error(`Mutation ${id} was not killed by a running assertion: ${output}`);
  }
  results.push({ id, path, suite, target: 'js', filter, killed: true, failureCount: count });
  console.log(`${id}: detected by replacement tests`);
}
if (snapshot(root).digest !== before.digest) throw new Error('Mutation runner did not restore the source tree');
writeFileSync(join(directory, 'mutations.json'), `${JSON.stringify({ source: before, results }, null, 2)}\n`);
