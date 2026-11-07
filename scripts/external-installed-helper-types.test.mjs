// Compile-only coverage of the same relocated fixture used by the packed
// external installation consumer. No runtime package or Connector is invoked.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {cp, mkdir, readdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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
    await mkdir(target, {recursive: true});
    await cp(join(source, 'package.json'), join(target, 'package.json'));
    for (const entry of await readdir(source, {withFileTypes: true})) {
      if (entry.isFile() && /\.d\.(?:ts|mts)$/u.test(entry.name)) {
        await cp(join(source, entry.name), join(target, entry.name));
      }
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
