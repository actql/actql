// One owned SQLite namespace per invocation, including local CI reruns.
// A caller-supplied root is a parent, never a directory we adopt or remove.
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const parent = process.env.ACTQL_TEST_NATIVE_SQLITE_ROOT ??
  join(process.env.RUNNER_TEMP ?? tmpdir(), 'core-sqlite');
const scratch = await createOwnedScratch({parent: resolve(parent),
  prefix: 'native-', label: 'Native core SQLite'});
console.log(`Native core SQLite namespace: ${scratch.path}`);
const result = spawnSync('moon', ['test', '--target', 'native',
  ...process.argv.slice(2)], {cwd: root, stdio: 'inherit', env: {
  ...process.env,
  ACTQL_TEST_NATIVE_SQLITE_LIBRARY:
    process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
    (process.platform === 'darwin' ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0'),
  ACTQL_TEST_NATIVE_SQLITE_ROOT: scratch.path,
}});
if (result.error) throw result.error;
if (result.status !== 0) {
  if (result.signal) console.error(`Native core test stopped by ${result.signal}`);
  process.exit(result.status ?? 1);
}
// spawnSync has reaped the only child; within-run database reopen is unchanged.
scratch.passed();
