import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';

test('manifest discovery includes new SDK and CLI outside fixed product directories', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-roots-'));
  t.after(() => rmSync(root, {recursive: true}));
  const put = (path, data) => {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), JSON.stringify(data));
  };
  put('elsewhere/new-sdk/package.json', {name: '@actql/new-sdk', exports: './entry.mjs'});
  put('new-cli/package.json', {name: 'new-cli', bin: {new: './cli.mjs'}});
  put('fixtures/third-source/package.json', {name: '@fixture/source', exports: './entry.mjs'});
  const roots = npmInterfaceRoots(root, ['elsewhere/new-sdk/package.json',
    'new-cli/package.json', 'fixtures/third-source/package.json']);
  assert.deepEqual(roots.map(value => [value.kind, value.name, value.entrances]), [
    ['npm-package', '@actql/new-sdk', ['elsewhere/new-sdk/entry.mjs']],
    ['npm-cli', 'new-cli', ['new-cli/cli.mjs']],
  ]);
});

test('current normal package roots include all thirteen products, not only normal4', () => {
  const roots = npmInterfaceRoots(process.cwd());
  assert(roots.length >= 13);
  for (const name of ['@actql/provider-http', '@actql/provider-ai-sdk', '@actql/explorer-ui',
    '@actql/coordinator-core', '@actql/transfer-core', '@actql/otel-node', 'actql']) {
    assert(roots.some(value => value.name === name), `Missing normal product: ${name}`);
  }
});
