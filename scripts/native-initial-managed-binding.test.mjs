// Selected Darwin allocator/receiver diagnostic, not ordinary entry admission.
import assert from 'node:assert/strict';
import {before, after, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence, commandSource} from './packed-query-evidence.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const digest = path => createHash('sha256').update(readFileSync(path)).digest('hex');
let scratch, evidence, executable;
let failed = false;

before(async () => {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  assert.ok(process.env.MOON_HOME, 'select the repository-pinned Native toolchain');
  const moon = resolve(process.env.MOON_HOME);
  const allocator = join(moon, 'lib/libmoonbitrun.o');
  assert.equal(digest(allocator),
    'd9db2413e755c00ab374901211a03a9551222fe779022bc3648235747ed2bd96',
    'the private geometry and option ABI require this selected runtime object');
  scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'initial-managed-', label: 'initial managed C fixture',
    digests: () => ['initial-managed']});
  evidence = createCommandEvidence({scratch: join(root, '_build/initial-managed-evidence'),
    revision: commandSource(root).revision, cwd: root});
  executable = join(scratch.path, 'initial-managed');
  try {
    const build = evidence.capture('/Library/Developer/CommandLineTools/usr/bin/clang',
      ['-std=c11', '-O0', '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
        '-isysroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
        '-I'+join(moon, 'include'),
        // This original entry must precede the allocator's automatic initializer.
        join(root, 'src/platform_native/host_bootstrap/fixtures/initial_managed.c'),
        join(moon, 'lib/runtime/runtime.c'), join(moon, 'lib/runtime/backtrace.c'),
        allocator, '-o', executable],
      {timeout: 90_000, killSignal: 'SIGTERM', maxBuffer: 2*1024*1024});
    assert.ifError(build.result.error);
    assert.equal(build.result.signal, null);
    assert.equal(build.result.status, 0, build.result.stderr);
    assert.equal(build.writeFailure, undefined);
    console.log(JSON.stringify({executable, executableSha256: digest(executable),
      allocatorSha256: digest(allocator),
      qualification: 'Actual C/O0 original binding with synthetic selection; not an ordinary complete envelope, command or numerical profile. Default restoration and process termination are not mapping/metadata retirement ACKs.'}));
  } catch (error) { failed = true; throw error; }
});

const cases = [
  ['missing', 'missing', {}, 'initial managed refusal passed'],
  ['invalid geometry', 'invalid', {}, 'initial managed refusal passed'],
  ['original receiver', 'ready', {}, 'initial managed original custody passed'],
  ['partial heap', 'partial', {}, 'initial managed original custody passed'],
  ['failed mapping', 'mapping-failed', {}, 'initial managed partial backing passed'],
  ['partial registration', 'registration-failed', {}, 'initial managed partial backing passed'],
  ['foreign default', 'changed-default', {}, 'initial managed original custody passed'],
  ['changed selection', 'changed-selection', {}, 'initial managed original custody passed'],
  ['changed options', 'options-changed', {}, 'initial managed original custody passed'],
  ['parent and payload exhaustion', 'backing-exhaustion', {}, 'initial managed original custody passed'],
  ['bounded environment', 'environment-vectors', {}, 'initial managed environment vectors passed'],
  ['upper-case reservation option', 'environment-refusal',
    {MIMALLOC_RESERVE_OS_MEMORY: '1M'}, 'initial managed environment refusal passed'],
  ['lower-case huge-page option', 'environment-refusal',
    {mimalloc_reserve_huge_os_pages: '1'}, 'initial managed environment refusal passed'],
  ['mixed-case cleanup option', 'environment-refusal',
    {MiMaLlOc_DESTROY_ON_EXIT: '1'}, 'initial managed environment refusal passed'],
];

for (const [name, mode, options, expected] of cases) {
  test(`initial managed binding: ${name}`, () => {
    try {
      // Fixtures explicitly select the default-option condition. Negative cases
      // supply the actual startup option; product invocation never strips it.
      const env = Object.fromEntries(Object.entries(process.env)
        .filter(([key]) => !key.toLowerCase().startsWith('mimalloc_')));
      Object.assign(env, options);
      const actual = evidence.capture(executable, [mode],
        {env, timeout: 20_000, killSignal: 'SIGTERM', maxBuffer: 2*1024*1024}, result => {
          const passed = !result.error && !result.signal && result.status === 0 &&
            result.stdout.trim() === expected;
          return {status: passed ? 0 : 1, counts: {tests: 1,
            passed: passed ? 1 : 0, failed: passed ? 0 : 1,
            cancelled: 0, skipped: 0, todo: 0}};
        });
      assert.ifError(actual.result.error);
      assert.equal(actual.result.signal, null);
      assert.equal(actual.result.status, 0, actual.result.stderr);
      assert.equal(actual.result.stdout.trim(), expected);
      assert.equal(actual.checked.status, 0);
      assert.equal(actual.writeFailure, undefined);
    } catch (error) { failed = true; throw error; }
  });
}

after(() => {
  if (!evidence) return;
  evidence.finish(failed ? 'failed' : 'passed');
  assert.ok(evidence.summary.complete);
  if (!failed) scratch.passed();
});
