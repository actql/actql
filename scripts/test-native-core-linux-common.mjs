// Establish actual Linux coverage before retiring any corresponding Darwin case.
import assert from 'node:assert/strict';
import {realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCoreCCompiler} from './native-core-c-compiler.mjs';
import {nativeCoreFocusedTestCount, nativeCoreTestSelection} from './native-core-test-selection.mjs';
import {readNativeCorePlatformPackages} from './native-core-platform-packages.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {runFocusedTests} from './test-execution.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
export const nativeCoreLinuxCommonArguments = Object.freeze([
  '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose',
]);
export const nativeCoreLinuxCommonPartitions = Object.freeze(
  Array.from({length: 8}, (_, index) => `linux-common-${index + 1}/8`));

export async function runNativeCoreLinuxCommon({root = repository, env = process.env,
  platform = process.platform, partition, countTests = nativeCoreFocusedTestCount,
  platformPackages = readNativeCorePlatformPackages, selectTests = nativeCoreTestSelection,
  selectCompiler = nativeCoreCCompiler, executeTests = runFocusedTests,
  createScratch = createOwnedScratch} = {}) {
  assert.equal(platform, 'linux', 'The common Native cohort requires an actual Linux runner');
  assert(nativeCoreLinuxCommonPartitions.includes(partition), 'One original Linux common partition required');
  root = realpathSync(root);
  const scratch = await createScratch({parent: resolve(env.RUNNER_TEMP ?? tmpdir(), 'core-linux-common'),
    prefix: 'native-', label: 'Linux common Native compiler'});
  // Use the same generated-C test-only O0 adapter as full Native Core. Do not
  // import Darwin ccache, xcrun, physical providers or checkpoint producers.
  const environment = {...env, MOONBIT_NEW_NATIVE: '0', ...selectCompiler(root, scratch.path, env)};
  const scope = platformPackages(root, {env: environment});
  const selection = selectTests(root, [...nativeCoreLinuxCommonArguments], {env: environment,
    timeoutMs: 5 * 60_000, executionPackages: scope.common, partitionProfiles: true, ordinaryPartitions: 8,
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
  const status = executeTests('moon', ['--target', 'native', ...args], {
    cwd: root, env: environment, expectedTests, timeout: 60 * 60_000,
  });
  if (status === 0) scratch.passed();
  return status;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'The Linux common cohort requires one closed partition');
  process.exitCode = await runNativeCoreLinuxCommon({partition: process.argv[2]});
}
