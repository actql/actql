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
import {nativePrivateHostFixture, nativeOriginalSigningFixture} from './native-private-host-fixture.mjs';
import {nativeRuntimeReaderCustodyFixture} from './native-runtime-reader-custody-fixture.mjs';
import {nativeCoreCCompiler} from './native-core-c-compiler.mjs';
import {nativeProjectConfigurationFixture, nativeProjectContentCaseFixture} from './native-project-configuration-fixture.mjs';
import {nativeCoreTestSelection, nativeCoreScopedAllocationProfile, nativeCoreScopedBackingPages,
  nativeRelationWorkTestFile, nativeRelationCaptureTestFiles, nativeCorePartitionProfiles,
  nativeProjectMockContentTestFile, nativeRelationTargetIOTestFile, nativeRelationTargetIOLineageTestFile,
  nativeClientFileResponseTestFile} from './native-core-test-selection.mjs';
import {nativeProcessRegionFixture} from './native-process-region-fixture.mjs';
import {nativeCoreOrdinaryProcessFixture} from './native-core-scoped-fixture.mjs';
import {nativeHttpLifetimeFixture} from './native-http-lifetime-fixture.mjs';
import {nativeClientFileFixture} from './native-client-file-fixture.mjs';

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
for (const name of ['standard', 'bundles', 'executor-slot', 'retained-task-file', 'retained-task', 'cli-parent', 'bounded-files', 'filesystem-custody']) {
  mkdirSync(join(namespace, name), {mode: 0o700});
}
const bundle = nativeCompletedRestorationBundle();
const args = process.argv.slice(2);
const full = !['focused', 'reporting'].includes(classifyMoon('test', args).classification);
// Keep the unscoped classification and its original fixture/backing setup.
// Only the compiler-owned case inventory below receives this checked closure.
const executionPackages = full && (process.env.CI_PLAN || process.env.CI_PLAN_PATH)
  ? (await import('./ci-moon-tests.mjs')).nativeMoonPackages() : undefined;
const partition = process.env.ACTQL_TEST_NATIVE_CORE_PARTITION;
if (partition && !full) throw new Error('Native Core partitions require the complete original selection');
// Select the test-only compiler once before either original checkpoint
// producer. Changing its executable PATH before the full child invalidates the
// same release/strip test C cache. Every phase keeps the original backend,
// environment, Moon IR, runtime allocator, package C++/stub and product flags.
const testCompiler = full && args.lastIndexOf('--release') >
    Math.max(args.lastIndexOf('--debug'), args.lastIndexOf('-g'))
  ? nativeCoreCCompiler(root, namespace) : {};
const compilerEnvironment = {...process.env, ACTQL_TEST_NATIVE_CORE_PARTITION: undefined, ...testCompiler,
  ACTQL_TEST_NATIVE_FILE_RECEIPT_ROOT: undefined,
  ...Object.fromEntries(['APPROVE', 'REJECT', 'CONFLICT'].flatMap(mode =>
    ['RESOLUTION', 'VERIFIED'].map(kind => [`ACTQL_TEST_CLIENT_FILE_RECEIPT_${mode}_${kind}_WIRE`, undefined])))};
// Keep the original full classification and fixture/budget decisions. These
// compiler-selected directories omit only packages with no Native test cases.
const selection = full ? nativeCoreTestSelection(root, args,
  // One absolute metadata-preparation envelope covers four dry-run plans and
  // all original driver generations. It grants no extra test or C-build time.
  {env: compilerEnvironment, partitionProfiles: true, ordinaryPartitions: Boolean(partition),
    timeoutMs: 5 * 60_000, executionPackages}) : undefined;
if (selection?.executionScope) console.log('Native Core dependency scope: ' + JSON.stringify(selection.executionScope));
if (selection && partition) {
  const originalCases = selection.profiles.ordinary.cases;
  selection.profiles = nativeCorePartitionProfiles(selection.profiles, partition);
  console.log('Native Core ordinary partition: ' + JSON.stringify({partition,
    originalCases, selectedCases: selection.profiles.ordinary.cases}));
}
if (selection) console.log('Native test selection: ' + JSON.stringify({cases: selection.cases,
  packages: selection.packages, prunedDrivers: selection.prunedDrivers,
  ...(selection.benchmarkDeclarations ? {benchmarkDeclarations: selection.benchmarkDeclarations} : {}),
  profiles: {ordinary: selection.profiles.ordinary.cases,
    http: selection.profiles.http.cases,
    source: selection.profiles.source.cases,
    scoped: selection.profiles.scoped.cases, physical: selection.profiles.physicalCases,
    repeatedGeometry: selection.profiles.repeatedGeometryCases}}));
const projectConfiguration = full || args.some(arg => arg.includes('cmd/native_client'))
  ? nativeProjectConfigurationFixture(namespace)
  : {ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: undefined};
const privateHost = full || args.some(arg =>
  arg.includes('platform_native/filesystem') || arg.includes('platform_native/client_host'))
  ? nativePrivateHostFixture(namespace) : {};
const originalSigning = full || args.some(arg => arg.includes('platform_native/signature'))
  ? nativeOriginalSigningFixture(namespace) : {};
const processRegion = full || args.some(arg => arg.includes('platform_native/host_bootstrap'))
  ? nativeProcessRegionFixture(root, namespace) : {};
const clientCheckpoint = full || args.some(arg => arg.includes('platform_native/client_host'))
  // Match optimization, debug and warning modes before the original producers
  // populate the cache. Changing the mode afterwards invalidates their Core
  // dependencies even when the physical test source has not changed.
  ? nativeClientCheckpointFixture(root, compilerEnvironment,
    args.lastIndexOf('--strip') > args.lastIndexOf('--no-strip'),
    args.includes('--deny-warn') || args.includes('-d'), args.includes('--release'),
    selection?.profiles.scoped.tests.some(test => test.source === nativeClientFileResponseTestFile) ?? false) : {};
const fileReceiptCheckpoint = Object.fromEntries(Object.entries(clientCheckpoint)
  .filter(([key]) => key.startsWith('ACTQL_TEST_CLIENT_FILE_RECEIPT_')));
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
const clientFiles = full || args.some(arg => arg.includes('cmd/native_client'))
  ? nativeClientFileFixture(namespace) : {};
const httpLifetime = full || args.some(arg => arg.includes('cmd/native_remote_resident_site'))
  ? nativeHttpLifetimeFixture(namespace) : {};
const fixtureEnvironment = {
  ...process.env,
  ACTQL_TEST_NATIVE_CORE_PARTITION: undefined,
  ACTQL_TEST_NATIVE_IMPORT_QUOTE: undefined,
  ACTQL_TEST_NATIVE_FILE_RECEIPT_ROOT: undefined,
  ...Object.fromEntries(['APPROVE', 'REJECT', 'CONFLICT'].flatMap(mode =>
    ['RESOLUTION', 'VERIFIED'].map(kind => [`ACTQL_TEST_CLIENT_FILE_RECEIPT_${mode}_${kind}_WIRE`, undefined]))),
  // A full selection provisions this one physical case itself. Ambient roots
  // must not activate a different case or reuse an initialized relation Store.
  ...(full ? Object.fromEntries(['ORIGINAL_ROOT', 'RUNTIME_ROOT', 'RUNTIME_SOURCE',
    'RUNTIME_PLATFORM', 'RUNTIME_DIGEST', 'ORIGINAL_MODE']
    .map(key => [`ACTQL_TEST_RELATION_${key}`, undefined])) : {}),
  ...httpLifetime,
  ...clientFiles,
  ...bundle,
  ...clientCheckpoint,
  ...Object.fromEntries(Object.keys(fileReceiptCheckpoint).map(key => [key, undefined])),
  ...privateHost,
  ...originalSigning,
  ...processRegion,
  ...readerCustody,
  ...projectConfiguration,
  ...(walFixture ? {ACTQL_TEST_NATIVE_UNCLOSED_SQLITE_FIXTURE: walFixture} : {}),
  ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: join(namespace, 'standard'),
  ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT: join(namespace, 'bundles'),
  ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT: join(namespace, 'executor-slot'),
  ACTQL_TEST_NATIVE_RETAINED_TASK_FILE_ROOT: join(namespace, 'retained-task-file'),
  ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT: join(namespace, 'retained-task'),
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
  ACTQL_TEST_DUCKDB_LIBRARY: process.env.ACTQL_TEST_DUCKDB_LIBRARY ?? join(root,
    'adapters', 'connectors', 'duckdb', 'node', 'node_modules', '@duckdb',
    `node-bindings-${process.platform}-${process.arch}`,
    process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so'),
  ACTQL_TEST_NATIVE_SQLITE_ROOT: namespace,
  ...(full || args.some(arg => arg.includes('platform_native/bounded_files'))
    ? {ACTQL_TEST_NATIVE_BOUNDED_FILES_ROOT: join(namespace, 'bounded-files')} : {}),
};
// Keep physical file inputs separate from the selected-provider environment.
// Only the ordinary child/focused Arena caller receives these fresh originals.
const ordinaryProcess = (full ? selection.profiles.ordinary.args !== null :
  args.some(arg => arg.includes('platform_native/installed_arena_control')))
  ? nativeCoreOrdinaryProcessFixture(namespace) : {};
const checkChild = result => {
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (result.signal) console.error(`Native core test stopped by ${result.signal}`);
    process.exit(result.status ?? 1);
  }
};
if (full) {
  if (selection.profiles.http.args !== null) {
    console.log(`Native Core HTTP profile: ${selection.profiles.http.cases} required cases`);
    checkChild(spawnSync(process.execPath, ['scripts/test-native-http-client.mjs'], {
      cwd: root, stdio: 'inherit', env: {...compilerEnvironment,
        ACTQL_TEST_SCRATCH_ROOT: namespace,
        ACTQL_TEST_PRESERVE_SCRATCH: '1',
        ACTQL_TEST_NATIVE_HTTP_FOCUS: 'core-http',
        ACTQL_TEST_NATIVE_CORE_HTTP_ARGS: JSON.stringify(selection.profiles.http.args),
        ACTQL_TEST_NATIVE_CORE_HTTP_COUNT: String(selection.profiles.http.cases)},
    }));
  }
  // Each configuration executes its original compiler-owned cases. The
  // ordinary configuration also checks that no physical provider was selected;
  // physical custody cases must instead run with the real scoped provider.
  const runProfile = (profile, environment) => {
    if (profile.args === null) return;
    console.log(`Native Core profile: ${profile.cases} required cases`);
    checkChild(spawnSync(process.execPath, ['scripts/test-native-salesforce-effect-preview.mjs',
      '--core-test-json', JSON.stringify(profile.args), '--core-test-count', String(profile.cases)],
    {cwd: root, stdio: 'inherit', env: environment}));
  };
  runProfile(selection.profiles.ordinary, {...fixtureEnvironment, ...ordinaryProcess, ...testCompiler,
    ACTQL_TEST_NATIVE_CORE_PARTITION: partition});
  // The Source package uses the existing complete Source/HTTP fixture owner.
  // Its peer environment must never activate other ordinary Core packages.
  if (selection.profiles.source.args !== null) {
    checkChild(spawnSync(process.execPath, ['scripts/test-native-http-client.mjs'], {
      cwd: root, stdio: 'inherit', env: {...compilerEnvironment,
        ACTQL_TEST_SCRATCH_ROOT: namespace, ACTQL_TEST_PRESERVE_SCRATCH: '1',
        ACTQL_TEST_NATIVE_HTTP_FOCUS: 'core-source',
        ACTQL_TEST_NATIVE_CORE_SOURCE_ARGS: JSON.stringify(selection.profiles.source.args),
        ACTQL_TEST_NATIVE_CORE_SOURCE_COUNT: String(selection.profiles.source.cases)},
    }));
  }
  if (selection.profiles.scoped.args !== null) {
    const scopedScratch = await createOwnedScratch({parent: join(root, '_build', 'native-core-scoped'),
      prefix: 'profile-', label: 'Native Core scoped compiler', preserve: true});
    const {prepareNativeCoreScopedProfile} = await import('./native-core-scoped-profile.mjs');
    const {nativeCoreScopedFixture, nativeRelationFileCaptureFixture, nativeCoreModelFrameFixture,
      nativeRelationTargetIOFixture, nativeRelationTargetIOLineageFixture,
      nativeClientFileResponseFixture} = await import('./native-core-scoped-fixture.mjs');
    const {prepareNativeRuntimeBundleLibraries} = await import('./native-runtime-bundle-fixture.mjs');
    // The scoped component entrance binds its owned API to this executable's
    // provider. Raw system SQLite/OpenSSL remain the ordinary fixture inputs.
    const components = prepareNativeRuntimeBundleLibraries(root,
      join(scopedScratch.path, 'components'), {seconds: 900});
    // Prepare only when the compiler selected the exact physical Work case.
    // The existing producer owns current-source components. Common constructs
    // setup data in a separate JS target; it never executes the Native query.
    let relationRuntime, relationFixture;
    if (selection.profiles.scoped.tests.some(test => test.source === nativeRelationWorkTestFile)) {
      const helper = await import('./native-core-relation-work-fixture.mjs');
      relationRuntime = await helper.prepareNativeCoreRelationRuntime(root,
        join(scopedScratch.path, 'relation-inputs'), components, {env: compilerEnvironment});
      relationFixture = helper.nativeRelationOriginalWorkFixture;
    }
    // These physical cases use the SQLite/Reader fixtures above. Salesforce's
    // request/response oracle belongs to the ordinary selection and remains
    // required there; the selected cases must not pretend to execute it again.
    console.log(`Native Core scoped profile: ${selection.profiles.scoped.cases} required cases`);
    const scopedDeadline = Date.now() + 3600000;
    // Local keeps ordinary copied Moon values on the runtime. The explicitly
    // scoped Arena and file-capture diagnostics exercise Read-owned managed aliases.
    // Their existing allocation profiles must never share a compiled target.
    for (const profile of ['runtime-values', 'scoped-review-values']) {
      const tests = selection.profiles.scoped.tests.filter(test =>
        nativeCoreScopedAllocationProfile(test.source) === profile);
      if (tests.length === 0) continue;
      const profileNamespace = join(scopedScratch.path, profile);
      mkdirSync(profileNamespace, {mode: 0o700});
      // Start from the original PATH, not the ordinary test-only compiler shim.
      const scoped = prepareNativeCoreScopedProfile(root, profileNamespace,
        ['--target', 'native', ...args, ...new Set(tests.map(test => test.source))],
        {env: fixtureEnvironment, profile});
      console.log(`Native Core ${profile}: ${tests.length} required cases`);
      // Each original case initializes its own physical region header. Closing
      // that region does not erase the header, and the cases require different
      // exact backing extents. Keep the compiled target, never reset a used file.
      for (const [ordinal, test] of tests.entries()) {
        const caseNamespace = join(namespace, `scoped-${profile}-case-${ordinal}`);
        mkdirSync(caseNamespace, {mode: 0o700});
        const physical = test.source === nativeRelationWorkTestFile
          ? await relationFixture(caseNamespace, relationRuntime)
          : nativeRelationCaptureTestFiles.includes(test.source)
          ? nativeRelationFileCaptureFixture(caseNamespace)
          : test.source === nativeRelationTargetIOTestFile
          ? nativeRelationTargetIOFixture(caseNamespace, test.index)
          : test.source === nativeRelationTargetIOLineageTestFile
          ? nativeRelationTargetIOLineageFixture(caseNamespace, test.index)
          : test.source === nativeClientFileResponseTestFile
          ? nativeClientFileResponseFixture(caseNamespace, test.index)
          : test.source === 'src/platform_native/installed_arena_control/model_read_frame_physical_scoped_wbtest.mbt'
          ? nativeCoreModelFrameFixture(caseNamespace)
          : nativeCoreScopedFixture(caseNamespace, {
          cryptoLibrary: components.cryptoLibrary,
          sqliteLibrary: components.sqliteLibrary,
          backingPages: nativeCoreScopedBackingPages(test.source),
        });
        const content = test.source === nativeProjectMockContentTestFile
          ? nativeProjectContentCaseFixture(caseNamespace, test.index,
            fixtureEnvironment.ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT)
          : {ACTQL_TEST_NATIVE_METADATA_REMAINDER: undefined, ACTQL_TEST_NATIVE_CONTENT_LOOKUPS: undefined, ACTQL_TEST_NATIVE_MODEL_SOURCE_CLOSURE: undefined,
            ACTQL_TEST_NATIVE_EFFECT_PLAN_ONLY: undefined, ACTQL_TEST_NATIVE_RAW_SNAPSHOT: undefined,
            ACTQL_TEST_NATIVE_RAW_SNAPSHOT_CID: undefined, ACTQL_TEST_NATIVE_RAW_SNAPSHOT_BYTES: undefined,
            ACTQL_TEST_NATIVE_BATCH_PLAN: undefined, ACTQL_TEST_NATIVE_ACTIVATION: undefined,
            ACTQL_TEST_NATIVE_RAW_STORE: undefined, ACTQL_TEST_NATIVE_RAW_STORE_REFUSAL: undefined,
            ACTQL_TEST_NATIVE_LEFT_IDENTITY: undefined, ACTQL_TEST_NATIVE_SOURCE_ARTIFACTS: undefined,
            ACTQL_TEST_NATIVE_ATTEMPT_USAGE: undefined, ACTQL_TEST_NATIVE_CAPTURED_PAGE: undefined,
            ACTQL_TEST_NATIVE_LOOKUP_COMPLETION: undefined, ACTQL_TEST_NATIVE_LOOKUP_DEPENDENCIES: undefined,
            ACTQL_TEST_NATIVE_LOOKUP_CLOSURE: undefined, ACTQL_TEST_NATIVE_SOURCE_UNIT_EVIDENCE: undefined};
        const scopedArgs = ['--target', 'native', ...args, test.source, '--index', String(test.index),
          '--target-dir', scoped.targetDirectory];
        const timeout = scopedDeadline - Date.now();
        if (timeout <= 0) throw new Error('Selected Native Core deadline exhausted');
        checkChild(spawnSync(process.execPath, ['--input-type=module', '-e',
          "import {runFocusedTests} from './scripts/test-execution.mjs'; " +
          "process.exitCode = runFocusedTests('moon', " + JSON.stringify(scopedArgs) +
          ", {timeout: " + timeout + ", expectedTests: 1, evidenceScratch: " +
          JSON.stringify(scopedScratch.path) + "});"],
        {cwd: root, stdio: 'inherit', env: {...fixtureEnvironment, ...scoped.environment,
          ACTQL_TEST_NATIVE_TARGET_IO_ROOT: undefined, ...physical, ...content,
          ...(test.source === nativeClientFileResponseTestFile ? fileReceiptCheckpoint : {}),
          ACTQL_TEST_NATIVE_IMPORT_QUOTE:
            test.source === 'src/cmd/native_client/local_project_mock_request_physical_scoped_wbtest.mbt' &&
            test.index === 10 ? '1' : undefined}}));
      }
    }
    scopedScratch.passed();
  }
} else {
  checkChild(spawnSync('moon', ['test', '--target', 'native', ...args],
    {cwd: root, stdio: 'inherit', env: {...fixtureEnvironment, ...ordinaryProcess, ...testCompiler}}));
}
// spawnSync has reaped every child; within-run database reopen is unchanged.
scratch.passed();
