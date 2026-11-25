// Compile-only coverage of the same relocated fixture used by the packed
// external installation consumer. No runtime package or Connector is invoked.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {cp, mkdir, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

test('external installed helper types retain their public declarations after relocation', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-external-helper-types-', label: 'external installed helper types'});
  const consumer = scratch.path;
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  for (const name of ['client-wire', 'sdk', 'local-node']) {
    const source = join(repository, 'packages', name);
    const target = join(consumer, 'node_modules', '@actql', name);
    const manifest = await readFile(join(source, 'package.json'), 'utf8');
    await mkdir(target, {recursive: true});
    await writeFile(join(target, 'package.json'), manifest);
    for (const path of JSON.parse(manifest).files) {
      if (!/\.d\.[cm]?ts$/u.test(path)) continue;
      const destination = join(target, path);
      await mkdir(dirname(destination), {recursive: true});
      await cp(join(source, path), destination);
    }
  }
  await cp(join(repository, 'packages/local-node/connector-installation.typecheck.mts'),
    join(consumer, 'helpers.typecheck.mts'));
  const result = spawnSync(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'),
    '--noEmit', '--strict', '--module', 'NodeNext', '--moduleResolution', 'NodeNext',
    '--target', 'ES2022', 'helpers.typecheck.mts'],
  {cwd: consumer, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024});
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  scratch.passed();
});
