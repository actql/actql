import assert from 'node:assert/strict';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {build} from 'esbuild';

test('the browser SDK bundle selects the unavailable loopback stub without Node imports', async () => {
  const bundled = await build({entryPoints: [fileURLToPath(new URL('./index.mjs', import.meta.url))],
    bundle: true, platform: 'browser', format: 'esm', target: 'es2022',
    write: false, metafile: true});
  const inputs = Object.keys(bundled.metafile.inputs);
  assert.ok(inputs.some(path => path.endsWith('/loopback-http-unavailable.mjs')));
  assert.equal(inputs.some(path => path.endsWith('/loopback-http.mjs')), false);
  for (const output of Object.values(bundled.metafile.outputs)) {
    assert.equal(output.imports.some(item => item.path.startsWith('node:')), false);
  }
  const sdk = await import(`data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString('base64')}`);
  let credentials = 0;
  await assert.rejects(sdk.connect('actql://localhost:8080/workspace?transport=http',
    {token: () => {credentials++; return 'fixture-only';}}), {code: 'LoopbackHttpUnavailable'});
  assert.equal(credentials, 0);
});
