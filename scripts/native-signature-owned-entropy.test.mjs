// Explicit Darwin OS-entropy component diagnostic; no Host or Library is issued.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence, commandSource} from './packed-query-evidence.mjs';

test('owned Signature OS entropy bounds and complete partial-failure clearing', async () => {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  const root = process.cwd();
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'owned-entropy-c-', label: 'owned entropy C fixture', digests: () => ['entropy']});
  const evidence = createCommandEvidence({scratch: join(root, '_build/owned-entropy-evidence'),
    revision: commandSource(root).revision, cwd: root});
  const executable = join(scratch.path, 'entropy');
  try {
    const built = evidence.capture('/Library/Developer/CommandLineTools/usr/bin/clang', [
      '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-mmacosx-version-min=11.0',
      '-isysroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
      '-MD', '-MF', join(scratch.path, 'entropy.d'),
      join(root, 'scripts/fixtures/native-signature-owned-entropy.c'), '-o', executable,
    ], {timeout: 30_000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024});
    assert.equal(built.result.status, 0, built.result.stderr);
    assert(!built.result.error && !built.result.signal && !built.writeFailure);
    for (const name of ['bounded-os', 'partial-failure', 'input-bounds']) {
      const actual = evidence.capture(executable, [name],
        {timeout: 10_000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024}, result => {
          const valid = result.status === 0 && !result.error && !result.signal &&
            result.stdout === `${name}: PASS\n`;
          return {status: valid ? 0 : 1,
            counts: {tests: 1, passed: valid ? 1 : 0, failed: valid ? 0 : 1,
              cancelled: 0, skipped: 0, todo: 0}};
        });
      process.stdout.write(actual.result.stdout ?? '');
      assert.equal(actual.checked.status, 0, actual.result.stderr);
      assert(!actual.writeFailure);
    }
    console.log(JSON.stringify({executable,
      executableSHA256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
      actualCExecutions: 3,
      qualification: 'Actual OS entropy plus controlled partial failure and bounds; no original Library/Read or normal command acceptance'}));
    evidence.finish('passed');
    assert(evidence.summary.complete);
    scratch.passed();
  } catch (error) {
    evidence.finish('failed');
    throw error;
  }
});
