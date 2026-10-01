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
const session = 'src/bounded_execution/session.mbt';
const adapter = 'src/connectors/local/bounded_session_provider.mbt';
const cases = [
  ['stale-token-reuse', session, 'session.ordinal += 1L', 'session.ordinal += 0L', 'src/bounded_execution', 'session contract*'],
  ['zero-quantum', session, 'if work_quanta <= 0 {', 'if work_quanta < 0 {', 'src/bounded_execution', 'session contract*'],
  ['terminal-resume', session, 'if session.terminal {', 'if session.terminal && false {', 'src/bounded_execution', 'session contract*'],
  ['cleanup-changed-as-complete', session,
    'if session.state_reclaimed && session.result_reclaimed {\n    return Ok(false)',
    'if session.state_reclaimed && session.result_reclaimed {\n    return Ok(true)',
    'src/bounded_execution', 'session contract*'],
  ['cumulative-as-delta', adapter, 'let work_delta = next_work - work.val', 'let work_delta = next_work', 'src/connectors/local', 'adapter contract*'],
  ['reset-budget-history', adapter, 'work.val = next_work', 'work.val = 0L', 'src/connectors/local', 'adapter contract*'],
  ['accept-backward-work', adapter, 'if next_progress < progress.val || next_work < work.val {', 'if next_progress < progress.val {', 'src/connectors/local', 'adapter contract*'],
  ['adapter-terminal-resume', adapter, 'if quantum <= 0 || terminated.val {', 'if quantum <= 0 {', 'src/connectors/local', 'adapter contract*'],
  ['premature-cleanup-success', adapter, 'Ok(false) => Ok(false)', 'Ok(false) => Ok(true)', 'src/connectors/local', 'adapter contract*'],
  ['cleanup-retry-reruns-callback', adapter, 'if reclaimed.val {', 'if reclaimed.val && false {', 'src/connectors/local', 'adapter contract*'],
  ['actual-set-path-reaches-adapter', adapter, 'let terminated = Ref(false)', 'let terminated = Ref(true)',
    'src/query_integration/local_managed_set_wbtest.mbt', 'Local managed row sets*'],
  ['actual-nest-path-reaches-adapter', adapter, 'let terminated = Ref(false)', 'let terminated = Ref(true)',
    'src/query_integration/local_managed_nest_wbtest.mbt', 'Local managed nest reaches two consumers*'],
  ['nest-parent-child-ports-swapped', 'src/connectors/local/nest_provider.mbt',
    '          parent,\n          child,', '          child,\n          parent,',
    'src/query_integration/local_managed_nest_wbtest.mbt', 'Local managed nest reaches two consumers*'],
];
const before = snapshot(root);
const directory = join(root, '.artifacts/bounded-session');
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
