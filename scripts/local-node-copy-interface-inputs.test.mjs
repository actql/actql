import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, rmSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {buildLocalNodeAdapters, localNodeAdapterSourceInputs} from './build-local-node-adapters.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
function destination(t) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-interface-copy-'));
  t.after(() => rmSync(directory, {recursive: true}));
  return directory;
}

test('ordinary copy-input reader feeds the unchanged actual package byte check without a compiler', async t => {
  const output = destination(t), inputs = localNodePackageInputs(root);
  const copies = await localNodeAdapterSourceInputs({root, inputs});
  for (const entry of inputs.adapterEntries) assert(copies.some(value => value.path === entry));
  await buildLocalNodeAdapters({root, inputs, destination: output});
  await buildLocalNodeAdapters({root, inputs, destination: output, check: true});
  for (const entry of copies) {
    const source = readFileSync(entry.source);
    const expected = entry.path.endsWith('.mjs')
      ? Buffer.from(rewriteLocalNodePackageImports(source.toString('utf8'), entry.path)) : source;
    assert.deepEqual(readFileSync(join(output, entry.path)), expected, entry.path);
  }
});

test('ordinary actual copy checks reject extra helpers, changed bytes and a missing declared asset', async t => {
  const output = destination(t), inputs = localNodePackageInputs(root);
  await buildLocalNodeAdapters({root, inputs, destination: output});
  const check = () => buildLocalNodeAdapters({root, inputs, destination: output, check: true});
  const extra = join(output, 'adapters/hidden-decision.mjs');
  writeFileSync(extra, 'export const unknownIsUnsent = true;');
  await assert.rejects(check, /StaleLocalNodeAdapter:hidden-decision.mjs/u);
  unlinkSync(extra);
  const selected = join(output, inputs.adapterEntries[0]), original = readFileSync(selected);
  writeFileSync(selected, Buffer.concat([original, Buffer.from('\n// changed installed input\n')]));
  await assert.rejects(check, /StaleLocalNodeAdapter/u);
  writeFileSync(selected, original);
  const asset = inputs.dataFiles.find(path => path.startsWith('adapters/') && path.endsWith('.py'));
  assert(asset);
  unlinkSync(join(output, asset));
  await assert.rejects(check, {code: 'ENOENT'});
});
