import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {viteInterfaceInventory} from '../../../scripts/vite-interface-inventory.mjs';

test('original Cloud web config retains actual Vite authored inputs and pinned external provenance', async () => {
  const directory = '/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/';
  const root = '/private/tmp/actql-f-if-cloud-owners-20261016';
  const original = JSON.parse(readFileSync(directory + 'f-cloud-owner-source-roots.json'));
  assert.equal(original.sourceSha, '9902e2131a3a53f2bbd23e865a48ebe1da958fca');
  assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim(), original.sourceSha);
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'}), '');
  for (const module of original.modules) assert.equal(
    createHash('sha256').update(readFileSync(join(root, module.module))).digest('hex'), module.sha256);
  const result = await viteInterfaceInventory(root, original.roots.filter(value => value.kind === 'web')
    .map(value => value.manifest));
  assert(result.modules.some(value => value.module === 'web/src/main.tsx'));
  assert(result.modules.some(value => value.module === 'web/src/features/effect-checkpoint-preview.tsx'));
  assert(result.externalModules.length);
  writeFileSync(directory + 'b-cloud-web-interface-projection.json', JSON.stringify({
    ...result, source: original.sourceSha,
    readerSource: execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    qualification: 'actual-configured-web-inputs-only; not-deployed-or-installed-admission'}, null, 2) + '\n');
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'}), '');
  console.log(JSON.stringify({modules: result.modules.length, assets: result.assets.length,
    externalModules: result.externalModuleCount, qualification: 'configured-web-inputs-only'}));
});
