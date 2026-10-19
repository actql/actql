import assert from 'node:assert/strict';
import {before, after, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence, commandSource} from './packed-query-evidence.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
let scratch, evidence, executable;
let failed = false;
before(async () => {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'command-output-', label: 'original command output C fixture',
    digests: () => ['command-output']});
  evidence = createCommandEvidence({scratch: join(root, '_build/command-output-evidence'),
    revision: commandSource(root).revision, cwd: root});
  executable = join(scratch.path, 'command-output');
  try {
    const build = evidence.capture('/Library/Developer/CommandLineTools/usr/bin/clang',
      ['-std=c11', '-O0', '-mmacosx-version-min=11.0', '-isysroot',
        '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
        join(root, 'scripts/fixtures/native-command-output.c'), '-o', executable],
      {timeout: 60_000, killSignal: 'SIGTERM', maxBuffer: 2*1024*1024});
    assert.ifError(build.result.error);
    assert.equal(build.result.signal, null);
    assert.equal(build.result.status, 0, build.result.stderr);
    assert.equal(build.writeFailure, undefined);
    console.log(JSON.stringify({executable,
      executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
      qualification: 'Actual C/O0 private libc FILE/buffer binding and controlled setup faults. Fixture-owned FILEs only; no complete entry, Host, physical domain, ordinary CLI or numerical profile.'}));
  } catch (error) {failed = true; throw error;}
});

for (const mode of ['original', 'first-failed', 'second-failed',
  'status-only', 'changed-buffer', 'invalid']) {
  test(`original command output: ${mode}`, () => {
    try {
      const actual = evidence.capture(executable, [mode],
        {timeout: 10_000, killSignal: 'SIGTERM', maxBuffer: 1024*1024});
      assert.ifError(actual.result.error);
      assert.equal(actual.result.signal, null);
      assert.equal(actual.result.status, 0, actual.result.stderr);
      assert.equal(actual.result.stdout.trim(), 'original command output binding passed');
      assert.equal(actual.writeFailure, undefined);
    } catch (error) {failed = true; throw error;}
  });
}

after(() => {
  if (!evidence) return;
  evidence.finish(failed ? 'failed' : 'passed');
  assert.ok(evidence.summary.complete);
  if (!failed) scratch.passed();
});
