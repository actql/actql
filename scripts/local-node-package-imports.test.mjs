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
