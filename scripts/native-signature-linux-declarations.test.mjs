import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

test('Signature declares its platform loader inspection before system headers', () => {
  assert(process.env.MOON_HOME, 'the repository pinned MoonBit toolchain is required');
  const source = fileURLToPath(new URL('../src/platform_native/signature/', import.meta.url));
  const temporary = mkdtempSync(join(tmpdir(), 'actql-signature-declarations-'));
  const compile = path => spawnSync(process.env.CC || 'cc', [
    '-std=c11', '-Werror=implicit-function-declaration', '-fsyntax-only',
    `-I${join(process.env.MOON_HOME, 'include')}`, `-I${source}`, path,
  ], {encoding: 'utf8'});
  try {
    const actual = compile(join(source, 'signature_stub.c'));
    assert.equal(actual.status, 0, actual.stderr || actual.error?.message);
    if (process.platform === 'linux') {
      const original = readFileSync(join(source, 'signature_stub.c'), 'utf8');
      const withoutDeclaration = original.replace(
        '#if defined(__linux__) && !defined(_GNU_SOURCE)\n#define _GNU_SOURCE\n#endif\n', '');
      assert.notEqual(withoutDeclaration, original);
      const previous = join(temporary, 'without-feature-declaration.c');
      writeFileSync(previous, withoutDeclaration);
      const regression = compile(previous);
      assert.notEqual(regression.status, 0);
      assert.match(regression.stderr, /Dl_info|dladdr/);
    }
  } finally {
    rmSync(temporary, {recursive: true, force: true});
  }
});
