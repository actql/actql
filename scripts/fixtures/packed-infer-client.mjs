import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {connect} from '@actql/node';
import {exercisePublicInferInput} from './public-infer-input.mjs';

// The packed test controller copies these three application/fixture files
// into the clean installation. The setup module belongs to the real test
// Host profile and must install A's common owner and deterministic ModelTask.
// Missing setup is a failure, never a skipped/passed acceptance run.
assert.equal(process.argv.length, 3,
  'Usage: node packed-infer-client.mjs <real-host-setup.mjs>');
const fixture = JSON.parse(await readFile(new URL('./infer-acceptance.json',
  import.meta.url), 'utf8'));
const {openInferTestHost} = await import(pathToFileURL(resolve(process.argv[2])));
assert.equal(typeof openInferTestHost, 'function');
for (const mode of ['local', 'remote']) {
  const host = await openInferTestHost({mode, fixture: structuredClone(fixture)});
  try {
    assert.equal(host.options.mode, mode);
    const records = await exercisePublicInferInput(connect, host.options, {
      fixture, requestPrefix: `packed-infer-${mode}`,
      prepareCase: host.prepareCase, observe: host.observe,
      signal: AbortSignal.timeout(120_000),
    });
    console.log(JSON.stringify({mode, execution_status: 'passed', records}));
  } finally {
    await host.close();
  }
}
