import assert from 'node:assert/strict';
import {before, after, test} from 'node:test';
import {readFileSync, writeFileSync, realpathSync} from 'node:fs';
import {join, isAbsolute} from 'node:path';
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
  scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'command-initial-stdio-', label: 'initial standard FILE C fixture',
    digests: () => ['command-initial-stdio']});
  evidence = createCommandEvidence({scratch: join(root, '_build/command-initial-stdio-evidence'),
    revision: commandSource(root).revision, cwd: root});
  executable = join(scratch.path, 'command-initial-stdio');
  const compiler = '/Library/Developer/CommandLineTools/usr/bin/clang';
  const dependencies = join(scratch.path, 'compiler.d');
  try {
    const build = evidence.capture(compiler,
      ['-std=c11', '-O0', '-mmacosx-version-min=11.0', '-isysroot',
        '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
        '-MD', '-MF', dependencies,
        join(root, 'scripts/fixtures/native-command-initial-stdio.c'), '-o', executable],
      {timeout: 60_000, killSignal: 'SIGTERM', maxBuffer: 2*1024*1024});
    assert.ifError(build.result.error);
    assert.equal(build.result.signal, null);
    assert.equal(build.result.status, 0, build.result.stderr);
    assert.equal(build.writeFailure, undefined);
    const text = readFileSync(dependencies, 'utf8').replace(/\\\r?\n/gu, ' ');
    const inputs = [...new Set((text.slice(text.indexOf(':') + 1)
      .match(/(?:\\.|[^\s])+/gu) ?? []).map(value => value.replace(/\\(.)/gu, '$1')))];
    assert.ok(inputs.length > 3 && inputs.every(isAbsolute));
    const records = inputs.map(path => ({path, sha256: digest(path)}));
    assert.ok(records.some(value => value.path.endsWith('/command_initial_stdio.h')));
    assert.ok(records.some(value => value.path.endsWith('/command_output.h')));
    writeFileSync(join(evidence.directory, 'compiler-inputs.json'), JSON.stringify({
      source: commandSource(root).revision, compiler: realpathSync(compiler),
      compilerSha256: digest(compiler), inputs: records,
      executableSha256: digest(executable),
      qualification: 'Actual C/O0 selected Darwin standard FILE identity, preinitialization refusal and buffer/flush diagnostics. No complete initial envelope, Host, Read, installed CLI or numerical profile.'}, null, 2) + '\n');
    console.log(JSON.stringify({executable, executableSha256: digest(executable),
      actualCompilerInputs: records.length}));
  } catch (error) { failed = true; throw error; }
});

for (const mode of ['original', 'buffered-output', 'buffered-error',
  'used-error', 'foreign-output', 'changed-metadata']) {
  test(`initial command standard FILE originals: ${mode}`, () => {
    try {
      const actual = evidence.capture(executable, [mode],
        {timeout: 10_000, killSignal: 'SIGTERM', maxBuffer: 1024*1024});
      assert.ifError(actual.result.error);
      assert.equal(actual.result.signal, null);
      assert.equal(actual.result.status, 0, actual.result.stderr);
      assert.equal(actual.result.stdout,
        (mode === 'original' ? 'O'.repeat(5000) : '') + 'original initial stdio passed\n');
      assert.equal(actual.result.stderr,
        mode === 'original' ? 'E'.repeat(5000) : mode === 'used-error' ? 'X' : '');
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
