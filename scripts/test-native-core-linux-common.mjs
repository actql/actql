// Establish actual Linux coverage before retiring any corresponding Darwin case.
import assert from 'node:assert/strict';
import {realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCoreCCompiler} from './native-core-c-compiler.mjs';
import {nativeCoreFocusedTestCount} from './native-core-test-selection.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {runFocusedTests} from './test-execution.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
export const nativeCoreLinuxCommonArguments = Object.freeze([
  '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose',
  'src/capacity_arithmetic', 'src/canonical_value', 'src/value_admission',
]);

export async function runNativeCoreLinuxCommon({root = repository, env = process.env,
  platform = process.platform, countTests = nativeCoreFocusedTestCount,
  selectCompiler = nativeCoreCCompiler, executeTests = runFocusedTests,
  createScratch = createOwnedScratch} = {}) {
  assert.equal(platform, 'linux', 'The common Native cohort requires an actual Linux runner');
  root = realpathSync(root);
  const scratch = await createScratch({parent: resolve(env.RUNNER_TEMP ?? tmpdir(), 'core-linux-common'),
    prefix: 'native-', label: 'Linux common Native compiler'});
  // Use the same generated-C test-only O0 adapter as full Native Core. Do not
  // import Darwin ccache, xcrun, physical providers or checkpoint producers.
  const environment = {...env, MOONBIT_NEW_NATIVE: '0', ...selectCompiler(root, scratch.path, env)};
  const args = [...nativeCoreLinuxCommonArguments];
  const expectedTests = countTests(root, args, {env: environment, timeoutMs: 5 * 60_000});
  assert(Number.isSafeInteger(expectedTests) && expectedTests > 0, 'Nonempty compiler-owned Native cohort required');
  console.log(`Linux common Native: ${expectedTests} original compiler-owned cases`);
  const status = executeTests('moon', ['--target', 'native', ...args], {
    cwd: root, env: environment, expectedTests, timeout: 60 * 60_000,
  });
  if (status === 0) scratch.passed();
  return status;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 2, 'The Linux common cohort has one closed compiler profile');
  process.exitCode = await runNativeCoreLinuxCommon();
}
