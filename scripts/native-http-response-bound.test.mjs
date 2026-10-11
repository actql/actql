import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, realpathSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('matching Native HTTP Owner projects its original response ceiling without physical entry', () => {
  assert(process.env.MOON_HOME, 'The pinned MoonBit runtime is required');
  const root = fileURLToPath(new URL('../', import.meta.url));
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-d-http-response-bound-'));
  const executable = join(scratch, 'diagnostic');
  const compile = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    '-Wno-unused-parameter', '-I', join(process.env.MOON_HOME, 'include'),
    join(root, 'scripts/fixtures/native-http-response-bound.c'),
    join(root, 'src/platform_native/filesystem/filesystem_stub.c'),
    join(process.env.MOON_HOME, 'lib/runtime/runtime.c'),
    ...(process.platform === 'linux' ? ['-ldl', '-lm'] : []), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(compile.status, 0, `${compile.error ?? ''}\n${compile.stdout}\n${compile.stderr}`);
  const result = spawnSync(executable, [], {cwd: root, encoding: 'utf8', timeout: 10_000});
  assert.equal(result.status, 0, `${result.error ?? ''}\n${result.stderr}`);
  assert.deepEqual(JSON.parse(result.stdout), {cases: 10, physical_entries: 0, public_acceptance: false});
  console.log(JSON.stringify({cases: 10, physical_entries: 0,
    diagnosticExecutableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    runtimeSourceSha256: createHash('sha256').update(
      readFileSync(join(process.env.MOON_HOME, 'lib/runtime/runtime.c'))).digest('hex')}));
  // Preserve failed diagnostics; discard only this fully reaped successful copy.
  rmSync(scratch, {recursive: true});
});
