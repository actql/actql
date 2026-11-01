import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';

test('nested Salesforce adapter uses the public exact-value SDK export', () => {
  const path = 'adapters/connectors/salesforce/host/installed-salesforce-site.mjs';
  const source = readFileSync(path, 'utf8');
  const result = rewriteLocalNodePackageImports(source, path);
  assert.ok(result.includes("import {canonicalJson as canonicalValueJson} from '@actql/sdk/host-port';"));
  assert.doesNotMatch(result, /(?:\.\.\/)+packages\//u);
  assert.equal(result.replace("'@actql/sdk/host-port'", "'../../../../packages/sdk/host-port.mjs'"), source);
});

test('shallow and nested imports keep quotes and unknown package paths fail', () => {
  assert.equal(rewriteLocalNodePackageImports(`import x from '../../packages/sdk/index.mjs';
import y from "../../../packages/client-wire/index.mjs";`, 'adapter.mjs'),
    `import x from '@actql/sdk';
import y from "@actql/client-wire";`);
  for (const prefix of ['../../', '../../../../']) {
    assert.throws(() => rewriteLocalNodePackageImports(`import '${prefix}packages/sdk/private.mjs';`, 'adapter.mjs'),
      /UnpackagedLocalNodeImport:adapter.mjs:sdk\/private\.mjs/u);
  }
  const ordinary = "import './local.mjs'; const url = 'connector://crm/records';";
  assert.equal(rewriteLocalNodePackageImports(ordinary, 'adapter.mjs'), ordinary);
});

test('Source preparation delivery retains the same private SDK module in the installed Host', () => {
  const path = 'adapters/host-node/embedded-local-lifecycle.mjs';
  const source = readFileSync(path, 'utf8');
  const copied = rewriteLocalNodePackageImports(source, path);
  assert.ok(copied.includes("'@actql/sdk/_internal/source-preparation'"));
  assert.doesNotMatch(copied, /(?:\.\.\/)+packages\//u);
  const manifest = JSON.parse(readFileSync('packages/sdk/package.json', 'utf8'));
  assert.equal(manifest.exports['./_internal/source-preparation'],
    './internal/private-source-preparation.mjs');
});

test('ordinary Host native filesystem fallbacks retain only the exact package-local assets', () => {
  const path = 'adapters/host-node/local-files-native.mjs';
  const source = readFileSync(path, 'utf8');
  const copied = rewriteLocalNodePackageImports(source, path);
  assert.equal((source.match(/\.\.\/\.\.\/packages\/local-node\/_build\/native\//gu) ?? []).length, 6);
  const expected = source
    .replaceAll("'../../packages/client-wire/index.mjs'", "'@actql/client-wire'")
    .replaceAll("'../../packages/sdk/host-port.mjs'", "'@actql/sdk/host-port'")
    .replaceAll("'../../packages/sdk/internal/private-source-preparation.mjs'", "'@actql/sdk/_internal/source-preparation'")
    .replaceAll('../../packages/local-node/_build/native/', '../../_build/native/');
  assert.equal(copied, expected);
  assert.doesNotMatch(copied, /(?:\.\.\/)+packages\//u);
  for (const asset of ['_build/native/directory-darwin-arm64.node',
    '_build/native/directory-darwin-x64.node', '_build/native/local-files-linux-x64.node']) {
    for (const prefix of ['../../', '../../../../']) {
      const original = `const file = new URL('${prefix}packages/local-node/${asset}', import.meta.url);\n` +
        `const binding = require("${prefix}packages/local-node/${asset}");`;
      assert.equal(rewriteLocalNodePackageImports(original, path),
        `const file = new URL('${prefix}${asset}', import.meta.url);\n` +
        `const binding = require("${prefix}${asset}");`);
    }
  }
  for (const asset of ['directory-darwin-foreign.node', 'directory-darwin-arm64.node.js',
    'local-files-linux-arm64.node', 'local-files-linux-x64.node.js',
    '../native/directory-darwin-arm64.node', 'directory-original.json']) {
    assert.throws(() => rewriteLocalNodePackageImports(
      `require('../../packages/local-node/_build/native/${asset}');`, path),
    /UnpackagedLocalNodeImport/u);
  }
});

test('HTTP Request freeze uses the exact existing private bridge and packaged import', async () => {
  const path = 'adapters/host-node/http-request-preparation.mjs';
  const source = readFileSync(path, 'utf8');
  const copied = rewriteLocalNodePackageImports(source, path);
  assert.ok(copied.includes("import {freezeInput} from '@actql/sdk/_internal/source-preparation';"));
  assert.doesNotMatch(copied, /(?:\.\.\/)+packages\//u);
  const original = await import('../packages/sdk/internal/data.mjs');
  const bridge = await import('../packages/sdk/internal/private-source-preparation.mjs');
  assert.strictEqual(bridge.freezeInput, original.freezeInput);
  const child = {value: null}, body = {rows: [child], text: 'e\u0301\r\n'};
  assert.strictEqual(bridge.freezeInput(body), body);
  assert.strictEqual(body.rows[0], child);
  assert.ok(Object.isFrozen(body) && Object.isFrozen(body.rows) && Object.isFrozen(child));
});
