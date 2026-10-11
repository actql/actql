import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, readdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

test('Native original Store format inspection cannot initialize or repair lost custody', async () => {
  const scratch = await createOwnedScratch({parent: '/private/tmp', prefix: 'actql-native-store-reopen-',
    label: 'Native original Store format no-repair counterexample'});
  assert(process.env.MOON_HOME, 'Select the repository-pinned Native toolchain');
  const stub = fileURLToPath(new URL('../src/platform_native/publication_store/store_format_stub.c', import.meta.url));
  const fixture = join(scratch.path, 'format.c'), executable = join(scratch.path, 'format');
  await writeFile(fixture, `
#include <stdlib.h>
#include ${JSON.stringify(stub)}
int main(int argc, char **argv) {
  if (argc != 3) return 99;
  return actql_native_publication_store_format((unsigned char *)argv[1],
    (int32_t)strlen(argv[1]), atoi(argv[2]));
}
`);
  const compiled = spawnSync('/usr/bin/clang', ['-Wall', '-Wextra', '-Werror',
    '-I' + join(resolve(process.env.MOON_HOME), 'include'), fixture, '-o', executable],
    {encoding: 'utf8', timeout: 10000});
  assert.ifError(compiled.error); assert.equal(compiled.status, 0, compiled.stderr);
  const inspect = (root, mode) => {
    const run = spawnSync(executable, [root, String(mode)], {encoding: 'utf8', timeout: 10000});
    assert.ifError(run.error); assert.equal(run.signal, null); return run.status;
  };
  const root = join(scratch.path, 'store'); await mkdir(root, {mode: 0o700});
  assert.equal(inspect(root, -1), 2, 'Original-only inspection refuses a missing format');
  assert.deepEqual(await readdir(root), [], 'Restoration cannot establish a new format');
  assert.equal(inspect(root, 0), 0, 'Existing fresh-Store read-only preflight remains supported');
  assert.deepEqual(await readdir(root), []);
  assert.equal(inspect(root, 1), 0, 'Explicit fresh initialization remains supported');
  const marker = join(root, 'publication-format.json');
  const body = '{"version":"actql-native-publication-store/0.1","isolation":"execution-namespace"}';
  assert.equal(await readFile(marker, 'utf8'), body);
  assert.equal(inspect(root, -1), 0);
  assert.equal(await readFile(marker, 'utf8'), body);
  await writeFile(marker, 'foreign');
  assert.equal(inspect(root, -1), 2, 'Divergent original is refused');
  assert.equal(await readFile(marker, 'utf8'), 'foreign');
  const lost = join(scratch.path, 'lost'); await mkdir(lost, {mode: 0o700});
  const journal = join(lost, '.actql-publication.sqlite3');
  await writeFile(journal, 'original journal bytes');
  assert.equal(inspect(lost, -1), 1, 'A journal with lost marker is not fresh custody');
  assert.deepEqual(await readdir(lost), ['.actql-publication.sqlite3']);
  assert.equal(await readFile(journal, 'utf8'), 'original journal bytes');
  await scratch.passed();
});
