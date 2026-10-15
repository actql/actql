// Explicit exact-FFI callback faults; the real SQLite/Moon caller is tested
// separately. These callbacks do not establish real kernel or SQLite faults.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {join} from 'node:path';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence, commandSource} from './packed-query-evidence.mjs';

test('original ordinal FFI refuses unacknowledged reads without allocation', async () => {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  const root = process.cwd(), moon = process.env.MOON_HOME;
  assert(moon, 'explicit pinned toolchain required');
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'original-claim-c-', label: 'original claim C faults',
    digests: () => ['original-claim-lookup']});
  const evidence = createCommandEvidence({scratch: join(root, '_build/original-claim-c-evidence'),
    revision: commandSource(root).revision, cwd: root});
  try {
    const compile = ['-Wl,-dead_strip', '-std=c11', '-O0', '-DMOONBIT_ALLOCATOR=2',
      `-I${moon}/include`, join(root, 'scripts/fixtures/native-sqlite-original-claim-lookup.c'),
      `${moon}/lib/runtime/runtime.c`, `${moon}/lib/runtime/backtrace.c`,
      `${moon}/lib/libmoonbitrun.o`, '-isysroot',
      '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
      '-o', join(scratch.path, 'original-claim-lookup')];
    const built = evidence.capture('/Library/Developer/CommandLineTools/usr/bin/clang',
      compile, {timeout: 20000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024});
    assert.equal(built.result.status, 0, built.result.stderr);
    assert(!built.result.error && !built.result.signal && !built.writeFailure);
    const actual = evidence.capture(join(scratch.path, 'original-claim-lookup'), [],
      {timeout: 20000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024}, result => {
        const matches = [...(result.stdout ?? '').matchAll(/^.+: PASS$/gm)];
        const valid = result.status === 0 && !result.signal && !result.error &&
          matches.length === 12 && (result.stdout ?? '').includes('Original claim lookup C cases: 12/12');
        return {status: valid ? 0 : 1, counts: {tests: matches.length,
          passed: valid ? 12 : 0, failed: valid ? 0 : matches.length,
          cancelled: 0, skipped: 0, todo: 0}};
      });
    process.stdout.write(actual.result.stdout ?? '');
    process.stderr.write(actual.result.stderr ?? '');
    assert.equal(actual.result.status, 0);
    assert(!actual.result.error && !actual.result.signal && !actual.writeFailure);
    assert.equal(actual.checked.status, 0);
    assert.equal(actual.checked.counts.tests, 12);
    evidence.finish('passed');
    assert(evidence.summary.complete);
    scratch.passed();
  } catch (error) {
    evidence.finish('failed');
    throw error;
  }
});
