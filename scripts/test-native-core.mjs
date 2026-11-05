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
import {nativeCoreTestSelection} from './native-core-test-selection.mjs';

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
// Select the test-only compiler once before either original checkpoint
// producer. Changing its executable PATH before the full child invalidates the
// same release/strip test C cache. Every phase keeps the original backend,
// environment, Moon IR, runtime allocator, package C++/stub and product flags.
const testCompiler = full && args.lastIndexOf('--release') >
    Math.max(args.lastIndexOf('--debug'), args.lastIndexOf('-g'))
  ? nativeCoreCCompiler(root, namespace) : {};
const compilerEnvironment = {...process.env, ...testCompiler};
// Keep the original full classification and fixture/budget decisions. These
// compiler-selected directories omit only packages with no Native test cases.
const selection = full ? nativeCoreTestSelection(root, args,
  {env: compilerEnvironment, partitionProfiles: true}) : undefined;
if (selection) console.log('Native test selection: ' + JSON.stringify({cases: selection.cases,
  packages: selection.packages, prunedDrivers: selection.prunedDrivers,
  profiles: {ordinary: selection.profiles.ordinary.cases,
    scoped: selection.profiles.scoped.cases, physical: selection.profiles.physicalCases,
    repeatedGeometry: selection.profiles.repeatedGeometryCases}}));
const projectConfiguration = full || args.some(arg => arg.includes('cmd/native_client'))
  ? nativeProjectConfigurationFixture(namespace)
  : {ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: undefined};
const privateHost = full || args.some(arg => arg.includes('platform_native/filesystem'))
  ? nativePrivateHostFixture(namespace) : {};
const clientCheckpoint = full || args.some(arg => arg.includes('platform_native/client_host'))
  // Match optimization, debug and warning modes before the original producers
  // populate the cache. Changing the mode afterwards invalidates their Core
  // dependencies even when the physical test source has not changed.
  ? nativeClientCheckpointFixture(root, compilerEnvironment,
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
const fixtureEnvironment = {
  ...process.env,
  ...bundle,
  ...clientCheckpoint,
  ...privateHost,
  ...readerCustody,
  ...projectConfiguration,
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
};
const checkChild = result => {
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (result.signal) console.error(`Native core test stopped by ${result.signal}`);
    process.exit(result.status ?? 1);
  }
};
if (full) {
  // Both configurations execute their original compiler-owned cases. The
  // ordinary configuration also checks that no physical provider was selected;
  // physical custody cases must instead run with the real scoped provider.
  const runProfile = (profile, environment) => {
    if (profile.args === null) return;
    console.log(`Native Core profile: ${profile.cases} required cases`);
    checkChild(spawnSync(process.execPath, ['scripts/test-native-salesforce-effect-preview.mjs',
      '--core-test-json', JSON.stringify(profile.args), '--core-test-count', String(profile.cases)],
    {cwd: root, stdio: 'inherit', env: environment}));
  };
  runProfile(selection.profiles.ordinary, {...fixtureEnvironment, ...testCompiler});
  if (selection.profiles.scoped.args !== null) {
    const scopedScratch = await createOwnedScratch({parent: join(root, '_build', 'native-core-scoped'),
      prefix: 'profile-', label: 'Native Core scoped compiler', preserve: true});
    const {prepareNativeCoreScopedProfile} = await import('./native-core-scoped-profile.mjs');
    const {nativeCoreScopedFixture} = await import('./native-core-scoped-fixture.mjs');
    const {prepareNativeRuntimeBundleLibraries} = await import('./native-runtime-bundle-fixture.mjs');
    // The scoped component entrance binds its owned API to this executable's
    // provider. Raw system SQLite/OpenSSL remain the ordinary fixture inputs.
    const components = prepareNativeRuntimeBundleLibraries(root,
      join(scopedScratch.path, 'components'), {seconds: 900});
    // Start from the original PATH, not the ordinary test-only compiler shim.
    const scoped = prepareNativeCoreScopedProfile(root, scopedScratch.path,
      ['--target', 'native', ...selection.profiles.scoped.args], {env: fixtureEnvironment});
    // These physical cases use the SQLite/Reader fixtures above. Salesforce's
    // request/response oracle belongs to the ordinary selection and remains
    // required there; the selected cases must not pretend to execute it again.
    console.log(`Native Core scoped profile: ${selection.profiles.scoped.cases} required cases`);
    const scopedDeadline = Date.now() + 3600000;
    // Each original case initializes its own physical region header. Closing
    // that region does not erase the header, and the cases require different
    // exact backing extents. Keep the compiled target, never reset a used file.
    for (const [ordinal, test] of selection.profiles.scoped.tests.entries()) {
      const caseNamespace = join(namespace, `scoped-case-${ordinal}`);
      mkdirSync(caseNamespace, {mode: 0o700});
      const physical = nativeCoreScopedFixture(caseNamespace, {
        cryptoLibrary: components.cryptoLibrary,
        sqliteLibrary: components.sqliteLibrary,
        backingPages: test.source ===
          'src/platform_native/installed_arena_control/local_host_crypto_physical_scoped_wbtest.mbt'
          ? 8192 : 256,
      });
      const scopedArgs = ['--target', 'native', ...args, test.source, '--index', String(test.index),
        '--target-dir', scoped.targetDirectory];
      const timeout = scopedDeadline - Date.now();
      if (timeout <= 0) throw new Error('Selected Native Core deadline exhausted');
      checkChild(spawnSync(process.execPath, ['--input-type=module', '-e',
        "import {runFocusedTests} from './scripts/test-execution.mjs'; " +
        "process.exitCode = runFocusedTests('moon', " + JSON.stringify(scopedArgs) +
        ", {timeout: " + timeout + ", expectedTests: 1, evidenceScratch: " +
        JSON.stringify(scopedScratch.path) + "});"],
      {cwd: root, stdio: 'inherit', env: {...fixtureEnvironment, ...scoped.environment, ...physical}}));
    }
    scopedScratch.passed();
  }
} else {
  checkChild(spawnSync('moon', ['test', '--target', 'native', ...args],
    {cwd: root, stdio: 'inherit', env: {...fixtureEnvironment, ...testCompiler}}));
}
// spawnSync has reaped every child; within-run database reopen is unchanged.
scratch.passed();
