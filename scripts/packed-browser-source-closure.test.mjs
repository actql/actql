import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {assertRemoteBrowserDependencyBoundary} from './installed-interface-correspondence.mjs';

test('packed browser closure matches the actual authored SDK entry and preserves foreign-input refusal', () => {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const graph = buildSync({absWorkingDir: repository, entryPoints: ['packages/sdk/index.mjs'],
    bundle: true, platform: 'browser', format: 'esm', target: 'es2022', metafile: true,
    write: false, logLevel: 'silent'});
  const inputs = Object.fromEntries(Object.entries(graph.metafile.inputs).map(([path, input]) => {
    assert.match(path, /^packages\/(?:sdk|client-wire)\//u,
      'Browser entry may not acquire Local/Node/Core or an unrelated package');
    return [path.replace(/^packages\/sdk\//u, 'node_modules/@actql/sdk/')
      .replace(/^packages\/client-wire\//u, 'node_modules/@actql/client-wire/'), input];
  }));
  assert(Object.values(graph.metafile.outputs).every(output => output.imports.length === 0));
  assert.equal(Object.keys(inputs).some(path => path.endsWith('/loopback-http.mjs')), false,
    'The browser condition must keep the unavailable loopback transport');
  const metadata = {...graph.metafile, inputs};
  assertRemoteBrowserDependencyBoundary(metadata);
  for (const extra of ['node_modules/@actql/local-node/index.mjs',
    'node_modules/@actql/sdk/internal/Core.js', 'node_modules/foreign/index.mjs']) {
    assert.throws(() => assertRemoteBrowserDependencyBoundary({...metadata,
      inputs: {...inputs, [extra]: {imports: []}}}), {code: 'ERR_ASSERTION'});
  }
  const absent = {...inputs}; delete absent['node_modules/@actql/sdk/index.mjs'];
  assert.throws(() => assertRemoteBrowserDependencyBoundary({...metadata, inputs: absent}), {code: 'ERR_ASSERTION'});
});
