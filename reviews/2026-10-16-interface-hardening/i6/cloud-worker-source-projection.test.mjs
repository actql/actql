import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {typescriptInterfaceInputs} from '../../../scripts/typescript-interface-inventory.mjs';

test('original Cloud resolved Worker root retains its actual production TypeScript input closure', () => {
  const directory = '/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/';
  const root = '/private/tmp/actql-f-if-cloud-owners-20261016';
  const input = readFileSync(directory + 'f-cloud-owner-source-roots.json');
  assert.equal(createHash('sha256').update(input).digest('hex'),
    'a6e9d5c1acb89c60a426c01cb20a7173f06f0ef4e2d34d1fccd7117d76ff9660');
  const original = JSON.parse(input);
  assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim(), original.sourceSha);
  assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'}), '');
  for (const module of original.modules) assert.equal(
    createHash('sha256').update(readFileSync(join(root, module.module))).digest('hex'), module.sha256);
  const entrances = original.roots.filter(value => value.kind === 'worker').flatMap(value => value.entrances);
  assert(entrances.length);
  const result = typescriptInterfaceInputs(root, entrances);
  assert(result.modules.length > entrances.length);
  assert(result.modules.some(value => value.module === 'src/run/run-record-owner.ts'));
  writeFileSync(directory + 'b-cloud-worker-interface-projection.json', JSON.stringify({
    qualification: 'original-config-root-and-TypeScript-source-closure; not-web-or-artifact-admission',
    source: original.sourceSha, readerSource: execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
    ...result}, null, 2) + '\n');
  console.log(JSON.stringify({modules: result.modules.length, assets: result.assets.length,
    externalReferences: result.external.length, qualification: 'Worker-source-only'}));
});
