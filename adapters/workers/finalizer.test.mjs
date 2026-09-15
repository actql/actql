import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {fileURLToPath} from 'node:url';
import {createTestRuntime} from './runtime.mjs';

test('workerd retains unconfirmed finalizer ownership without implicit retry', async () => {
  // Bundle the actual common driver and scoped Host with a protocol test double;
  // no alternate lifecycle implementation or Node globals in the Worker.
  const bundle = await build({
    stdin: {contents: `import {finalizerCase} from '../host-node/finalizer-fixture.mjs';
      export default {async fetch(request) {
        const {kind,scoped} = await request.json();
        return Response.json(await finalizerCase(kind,scoped));
      }};`, resolveDir: fileURLToPath(new URL('.', import.meta.url))},
    bundle: true, platform: 'browser', format: 'esm', write: false,
  });
  const runtime = createTestRuntime(bundle.outputFiles[0].text);
  try {
    for (const kind of ['error', 'undefined', 'null']) {
      for (const scoped of [false, true]) {
        const response = await runtime.dispatchFetch('http://worker.test/', {
          method: 'POST', body: JSON.stringify({kind, scoped}),
        });
        assert.deepEqual(await response.json(), scoped ? {
          failed: true, firstPreserved: true, pending: true, cleanup: false,
          finished: 2, closed: 1, consumed: 0,
        } : {
          failed: true, firstPreserved: true, output: 1, pending: true,
          cleanups: [false, false], cleanup: false, finished: 2, closed: 1,
        });
      }
    }
  } finally { await runtime.dispose(); }
});
