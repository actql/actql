// Same original C adapter and platform SQLite; selected-module provenance,
// managed Store scope and normal Host consumers require separate evidence.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence, commandSource} from './packed-query-evidence.mjs';

async function checkFixture(args, expected) {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  const root = process.cwd(), moon = process.env.MOON_HOME;
  assert(moon, 'explicit pinned toolchain required');
  const clang = execFileSync('xcrun', ['--find', 'clang'], {encoding: 'utf8'}).trim();
  const sdk = execFileSync('xcrun', ['--show-sdk-path'], {encoding: 'utf8'}).trim();
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'read-statement-c-', label: 'physical read statement controls',
    digests: () => ['read-statement']});
  const evidence = createCommandEvidence({scratch: join(root, '_build/read-statement-c-evidence'),
    revision: commandSource(root).revision, cwd: root});
  try {
    const compile = ['-Wl,-dead_strip', '-std=c11', '-O0', '-DMOONBIT_ALLOCATOR=2',
      `-I${moon}/include`, join(root, 'scripts/fixtures/native-sqlite-read-statement.c'),
      `${moon}/lib/runtime/runtime.c`, `${moon}/lib/runtime/backtrace.c`,
      `${moon}/lib/libmoonbitrun.o`, '-isysroot',
      sdk,
      '-lsqlite3', '-o', join(scratch.path, 'read-statement')];
    const built = evidence.capture(clang,
      compile, {timeout: 20000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024});
    assert.equal(built.result.status, 0, built.result.stderr);
    assert(!built.result.error && !built.result.signal && !built.writeFailure);
    const actual = evidence.capture(join(scratch.path, 'read-statement'), args,
      {timeout: 20000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024}, result => {
        const matches = [...(result.stdout ?? '').matchAll(/^.+: PASS$/gm)];
        const valid = result.status === 0 && !result.signal && !result.error &&
          matches.length === expected && (result.stdout ?? '').includes(`Physical read statement C cases: ${expected}/${expected}`);
        return {status: valid ? 0 : 1, counts: {tests: matches.length,
          passed: valid ? expected : 0, failed: valid ? 0 : matches.length,
          cancelled: 0, skipped: 0, todo: 0}};
      });
    process.stdout.write(actual.result.stdout ?? '');
    process.stderr.write(actual.result.stderr ?? '');
    assert.equal(actual.result.status, 0);
    assert(!actual.result.error && !actual.result.signal && !actual.writeFailure);
    assert.equal(actual.checked.status, 0);
    assert.equal(actual.checked.counts.tests, expected);
    evidence.finish('passed');
    assert(evidence.summary.complete);
    scratch.passed();
  } catch (error) {
    evidence.finish('failed');
    throw error;
  }
}

test('physical journal reads reuse one finite original-Database statement and retain checked close',
  () => checkFixture([], 1));

test('physical journal statement reset errors limits transactions and pending close retain original semantics',
  () => checkFixture(['controls'], 8));

test('prepared selected SQLite table and original-Database statement keep actual current and close', async () => {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  const root = process.cwd(), moon = process.env.MOON_HOME;
  assert(moon && process.env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION,
    'Existing exact-source preparation is required; no component producer fallback');
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'selected-read-statement-c-', label: 'selected read statement controls',
    digests: () => ['selected-read-statement']});
  const evidence = createCommandEvidence({scratch: join(root, '_build/selected-read-statement-c-evidence'),
    revision: commandSource(root).revision, cwd: root});
  try {
    const {sqliteLibrary} = prepareNativeRuntimeBundleLibraries(root, join(scratch.path, 'unused-producer'),
      {moonHome: moon, preparation: process.env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION});
    const clang = execFileSync('xcrun', ['--find', 'clang'], {encoding: 'utf8'}).trim();
    const sdk = execFileSync('xcrun', ['--show-sdk-path'], {encoding: 'utf8'}).trim();
    const selected = join(scratch.path, 'actor');
    const built = evidence.capture('python3', ['-B', 'scripts/prepare-native-sqlite-read-statement-fixture.py',
      '--destination', selected, '--moon-home', moon, '--clang', clang, '--sdk', sdk],
      {timeout: 180000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024});
    assert.equal(built.result.status, 0, built.result.stderr);
    assert(!built.result.error && !built.result.signal && !built.writeFailure);
    const actual = evidence.capture(join(selected, 'read-statement'), [sqliteLibrary],
      {timeout: 30000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024}, result => {
        const rows = [...(result.stdout ?? '').matchAll(/^.+: PASS$/gm)];
        const valid = result.status === 0 && !result.signal && !result.error && rows.length === 2 &&
          result.stdout.includes('Selected read statement C cases: 2/2');
        return {status: valid ? 0 : 1, counts: {tests: rows.length, passed: valid ? 2 : 0,
          failed: valid ? 0 : rows.length, cancelled: 0, skipped: 0, todo: 0}};
      });
    process.stdout.write(actual.result.stdout ?? '');
    process.stderr.write(actual.result.stderr ?? '');
    assert.equal(actual.result.status, 0);
    assert(!actual.result.error && !actual.result.signal && !actual.writeFailure);
    assert.equal(actual.checked.status, 0);
    assert.equal(actual.checked.counts.tests, 2);
    evidence.finish('passed');
    assert(evidence.summary.complete);
    scratch.passed();
  } catch (error) {
    evidence.finish('failed');
    throw error;
  }
});
