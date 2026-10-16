// Acceptance maintenance only; this does not execute a Provider or Host.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
const read = path => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('ordinary installed HubSpot keeps both original public assertion bodies with only owned child paths adapted', async () => {
  const original = await read('adapters/connectors/hubspot/test/hubspot-public-client.integration.test.mjs');
  const installed = await read('scripts/fixtures/packed-hubspot-public.mjs');
  const anchor = "for (const entrance of ['Local', 'HTTPS']) test(";
  assert(original.includes(anchor) && installed.includes(anchor));
  const expected = original.slice(original.indexOf(anchor))
    .replaceAll('adapters/connectors/hubspot/test/hubspot-client-restart.fixture.mjs',
      'scripts/fixtures/packed-hubspot-restart.mjs')
    .replaceAll("new URL('../../../../', import.meta.url)", "new URL('../../', import.meta.url)");
  assert.equal(installed.slice(installed.indexOf(anchor)), expected);
});

test('ordinary fresh-process HubSpot restoration only changes to the normal public package entrance', async () => {
  const original = await read('adapters/connectors/hubspot/test/hubspot-client-restart.fixture.mjs');
  const installed = await read('scripts/fixtures/packed-hubspot-restart.mjs');
  assert.equal(installed, original
    .replace("import {connectEmbeddedLocal} from '../../../host-node/embedded-local.mjs';", "import {connect} from '@actql/node';")
    .replace('await connectEmbeddedLocal(', 'await connect('));
});
