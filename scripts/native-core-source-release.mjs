// Complete Linux execution of the existing Core Source release profile. The
// default/debug Source and every Darwin obligation remain independently owned.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCoreLinuxCommonArguments} from './ci-core-partitions.mjs';
import {nativeCoreTestCaseInventory} from './native-core-test-selection.mjs';
import {nativeCoreCCompiler} from './native-core-c-compiler.mjs';
import {verifyNativeResidentPortablePreparation} from './native-resident-portable-preparation.mjs';
import {commandSource} from './packed-query-evidence.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {runLocalCheck} from './local-checks-guard.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sourcePackage = 'src/platform_native/remote_resident_source_compute_tests';

function requireLinuxSourceOwner(platform, arch, env) {
  assert.equal(platform, 'linux', 'Actual Linux Source owner required');
  assert.equal(arch, 'x64');
  for (const name of ['MOON_CC', 'CC', 'CXX']) assert.equal(env[name], undefined,
    'The release proof requires the original PATH-selected C/C++ compiler profile');
  assert(typeof env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION === 'string' &&
    env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION.length > 0,
  'The existing completed portable preparation is required');
}

export function nativeCoreSourceReleaseSelection(inventory) {
  assert(Array.isArray(inventory?.records) && inventory.records.length > 0,
    'Complete nonempty compiler-owned Source inventory required');
  const identities = new Set();
  for (const record of inventory.records) {
    assert.equal(record.directory, sourcePackage, 'Foreign Source package');
    assert(typeof record.entry[1] === 'string' && !/[\\/]/u.test(record.entry[1]),
      'Original Source file name required');
    assert.equal(record.source, sourcePackage + '/' + record.entry[1], 'Foreign Source input');
    assert.deepEqual(JSON.parse(record.entry[0]),
      ['actql/actql/platform_native/remote_resident_source_compute_tests', 'whitebox']);
    const test = record.entry[2];
    assert.equal(record.benchmark, false, 'Benchmarks cannot qualify required Source execution');
    assert.deepEqual(test.attrs, [], 'Required Source cases cannot be skipped');
    assert(Number.isSafeInteger(test.index) && test.index >= 0 && typeof test.name === 'string');
    const identity = JSON.stringify([record.entry[0], record.entry[1], test.index]);
    assert(!identities.has(identity), 'Duplicate Source case');
    identities.add(identity);
  }
  assert.equal(inventory.runnableCases, inventory.records.length,
    'Complete Source count must match its actual compiler inventory');
  return {args: [...nativeCoreLinuxCommonArguments, sourcePackage],
    cases: inventory.runnableCases};
}

// The portable receipt is verified before the fixture enters this boundary.
// Only the Native child receives this original release-test C profile; the JS
// preparation's compiler/environment identity is never rewritten to match it.
export function nativeCoreSourceCompilerEnvironment(args, root, scratch, env,
  {platform = process.platform, compiler = nativeCoreCCompiler} = {}) {
  if (platform !== 'linux' || !args.includes('--release')) return env;
  assert.deepEqual(args, [...nativeCoreLinuxCommonArguments, sourcePackage],
    'The Linux proof must retain the complete original Core Source recipe');
  return {...env, ...compiler(root, scratch, env)};
}

export async function runNativeCoreSourceRelease({root = repository, env = process.env,
  platform = process.platform, arch = process.arch, execute = runLocalCheck} = {}) {
  requireLinuxSourceOwner(platform, arch, env);
  assert.equal(realpathSync(root), realpathSync(repository), 'Same checkout required');
  return await execute({root, heavy: true, timeoutSeconds: 1200, graceSeconds: 5,
    steps: [{name: 'Complete original Source release profile on Linux', command: process.execPath,
      args: ['scripts/native-core-source-release.mjs', 'execute'],
      env: {...env, MOONBIT_NEW_NATIVE: '0'}}]});
}

export async function executeNativeCoreSourceRelease({root = repository, env = process.env,
  platform = process.platform, arch = process.arch,
  source = commandSource, verifyPreparation = verifyNativeResidentPortablePreparation,
  scratch = createOwnedScratch, discover = nativeCoreTestCaseInventory,
  execute = spawnSync, report = console.log} = {}) {
  requireLinuxSourceOwner(platform, arch, env);
  root = realpathSync(root);
  const original = source(root);
  assert(original.revision && original.dirty === false, 'Clean same-source checkout required');
  verifyPreparation(root, env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION, {env});
  const owner = await scratch({parent: join(env.RUNNER_TEMP ?? tmpdir(), 'native-source-release'),
    prefix: 'source-', label: 'Linux Core Source release'});
  const inventory = discover(root, [...nativeCoreLinuxCommonArguments, sourcePackage], {env});
  const selection = nativeCoreSourceReleaseSelection(inventory);
  report('ACTQL_NATIVE_SOURCE_RELEASE_SELECTION ' + JSON.stringify({source: original,
    target: 'native', profile: 'release', ...selection, records: inventory.records,
    darwinRetired: false}));
  const result = execute(process.execPath, ['scripts/test-native-http-client.mjs'], {
    cwd: root, stdio: 'inherit', env: {...env, MOONBIT_NEW_NATIVE: '0',
      ACTQL_TEST_SCRATCH_ROOT: owner.path,
      // The inner legacy fixture must not erase a failed original. This outer
      // handle removes its own namespace only after the complete proof joins.
      ACTQL_TEST_PRESERVE_SCRATCH: '1',
      ACTQL_TEST_NATIVE_HTTP_FOCUS: 'core-source',
      ACTQL_TEST_NATIVE_HTTP_SOURCE_OWNER: undefined,
      ACTQL_TEST_NATIVE_CORE_SOURCE_ARGS: JSON.stringify(selection.args),
      ACTQL_TEST_NATIVE_CORE_SOURCE_COUNT: String(selection.cases)},
  });
  if (result.error) throw result.error;
  assert.equal(result.signal, null, 'Source fixture must join without a signal');
  if (result.status !== 0) return result.status ?? 1;
  assert.deepEqual(source(root), original, 'Source changed during complete release execution');
  owner.passed(); owner.close();
  report('ACTQL_NATIVE_SOURCE_RELEASE_EXECUTION ' + JSON.stringify({source: original.revision,
    target: 'native', profile: 'release', cases: selection.cases, darwinRetired: false}));
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert(process.argv.length === 2 || process.argv.length === 3 && process.argv[2] === 'execute');
  process.exitCode = process.argv[2] === 'execute'
    ? await executeNativeCoreSourceRelease() : await runNativeCoreSourceRelease();
}
