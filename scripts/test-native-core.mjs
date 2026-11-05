// One owned Native fixture namespace per invocation, including local CI reruns.
// A caller-supplied root is a parent, never a directory we adopt or remove.
import {spawnSync} from 'node:child_process';
import {mkdirSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {nativeCompletedRestorationBundle} from './native-completed-restoration-fixture.mjs';
import {classifyMoon} from './local-checks-policy.mjs';
import {nativeClientCheckpointFixture} from './native-client-checkpoint-fixture.mjs';
import {nativePrivateHostFixture} from './native-private-host-fixture.mjs';
import {nativeRuntimeReaderCustodyFixture} from './native-runtime-reader-custody-fixture.mjs';
import {nativeCoreCCompiler} from './native-core-c-compiler.mjs';
import {nativeProjectConfigurationFixture} from './native-project-configuration-fixture.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const parent = process.env.ACTQL_TEST_NATIVE_SQLITE_ROOT ??
  join(process.env.RUNNER_TEMP ?? tmpdir(), 'core-sqlite');
const scratch = await createOwnedScratch({parent: resolve(parent),
  prefix: 'native-', label: 'Native core SQLite'});
// Resolve only the newly created owned directory. SQLite's existing-only
// NOFOLLOW boundary must not receive a parent alias such as macOS /var.
// Cleanup still belongs to the original scratch handle; caller data is never
// adopted and the product's path/identity checks remain unchanged.
const namespace = realpathSync(scratch.path);
console.log(`Native core SQLite namespace: ${namespace}`);
// These unconditional fixtures share the existing restoration owner, not the
// optional publication Store root. Enabling that global root would let unrelated
// packages contend on one Store lock and contaminate its format admission.
for (const name of ['standard', 'bundles', 'executor-slot', 'retained-task-file', 'cli-parent']) {
  mkdirSync(join(namespace, name), {mode: 0o700});
}
const bundle = nativeCompletedRestorationBundle();
const args = process.argv.slice(2);
const full = !['focused', 'reporting'].includes(classifyMoon('test', args).classification);
const projectConfiguration = full || args.some(arg => arg.includes('cmd/native_client'))
  ? nativeProjectConfigurationFixture(namespace)
  : {ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: undefined};
const privateHost = full || args.some(arg => arg.includes('platform_native/filesystem'))
  ? nativePrivateHostFixture(namespace) : {};
const clientCheckpoint = full || args.some(arg => arg.includes('platform_native/client_host'))
  // Match optimization, debug and warning modes before the original producers
  // populate the cache. Changing the mode afterwards invalidates their Core
  // dependencies even when the physical test source has not changed.
  ? nativeClientCheckpointFixture(root, process.env,
    args.lastIndexOf('--strip') > args.lastIndexOf('--no-strip'),
    args.includes('--deny-warn') || args.includes('-d'), args.includes('--release')) : {};
// Only the final Native test child receives the injection environment. The
// existing checkpoint producers and other preparation commands do not.
const readerCustody = full || args.some(arg =>
  arg.includes('platform_native/client_host') || arg.includes('cmd/native_client'))
  ? nativeRuntimeReaderCustodyFixture(root, namespace) : {};
// The WAL inspection fixture must use exec, not SQLite in a forked child.
// macOS system SQLite calls platform services that are unsafe before exec.
let walFixture;
if (full || args.some(arg => arg.includes('platform_native/remote_journal'))) {
  walFixture = join(namespace, 'unclosed-sqlite-fixture');
  const compiled = spawnSync('cc', ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
    join(root, 'scripts/fixtures/native-unclosed-sqlite.c'), '-o', walFixture,
    ...(process.platform === 'linux' ? ['-ldl'] : [])], {stdio: 'inherit'});
  if (compiled.error || compiled.signal || compiled.status !== 0) {
    throw new Error(`Native WAL fixture compilation failed: ${compiled.error?.message ?? compiled.signal ?? compiled.status}`);
  }
}
// Prepare the original checkpoint/Reader/WAL fixtures with their unchanged
// compiler settings. Only the final complete release test child uses O0 C;
// the same optimized Moon IR and every Native test remain selected. Re-running
// the C optimizer over these large test units otherwise exhausts the CI budget.
const testCompiler = full && args.lastIndexOf('--release') >
    Math.max(args.lastIndexOf('--debug'), args.lastIndexOf('-g'))
  ? nativeCoreCCompiler(root, namespace) : {};
// The full suite includes real target-observation tests. Provision their
// private HTTPS/credential fixture instead of treating missing inputs as passes.
const result = spawnSync(full ? process.execPath : 'moon', full
  ? ['scripts/test-native-salesforce-effect-preview.mjs', '--core-test-json', JSON.stringify(args)]
  : ['test', '--target', 'native', ...args], {cwd: root, stdio: 'inherit', env: {
  ...process.env,
  ...bundle,
  ...clientCheckpoint,
  ...privateHost,
  ...readerCustody,
  ...projectConfiguration,
  ...testCompiler,
  ...(walFixture ? {ACTQL_TEST_NATIVE_UNCLOSED_SQLITE_FIXTURE: walFixture} : {}),
  ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: join(namespace, 'standard'),
  ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT: join(namespace, 'bundles'),
  ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT: join(namespace, 'executor-slot'),
  ACTQL_TEST_NATIVE_RETAINED_TASK_FILE_ROOT: join(namespace, 'retained-task-file'),
  ACTQL_TEST_NATIVE_CLI_PARENT_ROOT: join(namespace, 'cli-parent'),
  ACTQL_REQUIRE_NATIVE_RETAINED_TEST: '1',
  ACTQL_TEST_NATIVE_CRYPTO_MISSING_LIBRARY: join(namespace, 'missing-crypto-library'),
  ACTQL_TEST_NATIVE_CRYPTO_LIBRARY:
    process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
    (process.platform === 'darwin' ?
      '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib' : 'libcrypto.so.3'),
  ACTQL_TEST_NATIVE_SQLITE_LIBRARY:
    process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
    (process.platform === 'darwin' ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0'),
  ACTQL_TEST_NATIVE_SQLITE_ROOT: namespace,
}});
if (result.error) throw result.error;
if (result.status !== 0) {
  if (result.signal) console.error(`Native core test stopped by ${result.signal}`);
  process.exit(result.status ?? 1);
}
// spawnSync has reaped the only child; within-run database reopen is unchanged.
scratch.passed();
