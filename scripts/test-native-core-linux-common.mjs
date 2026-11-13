// Establish actual Linux coverage before retiring any corresponding Darwin case.
import assert from 'node:assert/strict';
import {realpathSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCoreFocusedTestCount, nativeCoreTestSelection} from './native-core-test-selection.mjs';
import {readNativeCorePlatformPackages} from './native-core-platform-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
export const nativeCoreLinuxCommonArguments = Object.freeze([
  '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose',
]);
export const nativeCoreLinuxCommonPartitions = Object.freeze(
  Array.from({length: 8}, (_, index) => `linux-common-${index + 1}/8`));

async function executeOriginalNativeProfile(root, args, {env}) {
  assert.equal(realpathSync(root), realpathSync(repository), 'The original Native entry must own this checkout');
  assert(process.argv.length === 3 && nativeCoreLinuxCommonPartitions.includes(process.argv[2]),
    'Original one-shot Linux cohort CLI required');
  // Enter the existing full ordinary profile in the SAME process. Its original
  // compiler, fixture namespace, counted child and cleanup remain the owners;
  // there is no new subprocess or second compiler wrapper to time out/leak.
  Object.assign(process.env, env);
  process.argv.splice(2, process.argv.length - 2, ...args);
  await import('./test-native-core.mjs');
  return process.exitCode ?? 0;
}

export async function runNativeCoreLinuxCommon({root = repository, env = process.env,
  platform = process.platform, partition, countTests = nativeCoreFocusedTestCount,
  platformPackages = readNativeCorePlatformPackages, selectTests = nativeCoreTestSelection,
  executeProfile = executeOriginalNativeProfile} = {}) {
  assert.equal(platform, 'linux', 'The common Native cohort requires an actual Linux runner');
  assert(nativeCoreLinuxCommonPartitions.includes(partition), 'One original Linux common partition required');
  root = realpathSync(root);
  // The full ordinary entry owns its one generated-C O0 adapter and fixtures.
  // Metadata discovery itself must neither compile nor allocate another owner.
  const environment = {...env, MOONBIT_NEW_NATIVE: '0'};
  const scope = platformPackages(root, {env: environment});
  assert(Array.isArray(scope.importers), 'Missing original Native importer inventory');
  const selection = selectTests(root, [...nativeCoreLinuxCommonArguments], {env: environment,
    timeoutMs: 5 * 60_000, executionPackages: [...scope.common, ...scope.importers].sort(), partitionProfiles: true, ordinaryPartitions: 8,
    allowNestedFileInputs: true});
  assert.equal(selection.executionScope?.mode, 'subset', 'Linux common selection cannot fall back to physical profiles');
  assert.equal(selection.profiles.http.cases + selection.profiles.source.cases + selection.profiles.scoped.cases, 0,
    'Linux common cannot adopt an unrelated physical fixture');
  assert.equal(selection.profiles.ordinary.partitions.length, 8);
  const args = selection.profiles.ordinary.partitions[nativeCoreLinuxCommonPartitions.indexOf(partition)].args;
  assert(Array.isArray(args) && args.length > nativeCoreLinuxCommonArguments.length);
  const expectedTests = countTests(root, args, {env: environment, timeoutMs: 5 * 60_000});
  assert(Number.isSafeInteger(expectedTests) && expectedTests > 0, 'Nonempty compiler-owned Native cohort required');
  console.log('Linux common Native: ' + JSON.stringify({partition, expectedTests,
    packages: args.slice(nativeCoreLinuxCommonArguments.length), graphSha256: scope.graphSha256}));
  return await executeProfile(root, [...nativeCoreLinuxCommonArguments], {
    env: {...environment, ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: 'linux-common-importers',
      ACTQL_TEST_NATIVE_CORE_PARTITION: partition.slice('linux-common-'.length)},
    expectedTests,
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'The Linux common cohort requires one closed partition');
  process.exitCode = await runNativeCoreLinuxCommon({partition: process.argv[2]});
}
