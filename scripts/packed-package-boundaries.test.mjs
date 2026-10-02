import assert from 'node:assert/strict';
import {mkdtemp, mkdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {auditPackedPackages} from './packed-package-boundaries.mjs';

test('installed graph refuses undeclared dependencies even when separately installed', async () => {
  const root = await mkdtemp(join(tmpdir(), 'packed-package-audit-'));
  try {
    for (const name of ['entry', 'hidden']) {
      const path = join(root, 'node_modules/@actql', name);
      await mkdir(path, {recursive: true});
      await writeFile(join(path, 'package.json'), JSON.stringify({name: `@actql/${name}`,
        type: 'module', exports: './index.mjs'}));
      await writeFile(join(path, 'index.mjs'), name === 'entry'
        ? "export {value} from '@actql/hidden';\n" : 'export const value = 1;\n');
    }
    assert.throws(() => auditPackedPackages(root, ['entry']), /Undeclared dependency/u);
    const entry = join(root, 'node_modules/@actql/entry');
    await writeFile(join(entry, 'package.json'), JSON.stringify({name: '@actql/entry',
      type: 'module', exports: './index.mjs', dependencies: {'@actql/hidden': '1.0.0'}}));
    auditPackedPackages(root, ['entry']);
    await rm(join(entry, 'index.mjs'));
    assert.throws(() => auditPackedPackages(root, ['entry']), /Missing or escaped export/u);
  } finally { await rm(root, {recursive: true, force: true}); }
});
