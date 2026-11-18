// Actual HTTPS transport using the existing TLS fixture and authored service
// facts and the existing funded HTTP Request preparation. This does not issue
// Explanation originals or execute a Run, Source or funded explanation supplier.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {runExplanation} from '../../scripts/fixtures/explanation-facts-vectors.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {fundedClientPreparation} from './funded-client-preparation.fixture.mjs';

test('TLS Execution.explain preserves original ref and named read refusals without submit', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-g-explanation-tls-'));
  const trust = getCACertificates('default'); let server, client, reads = 0, mode = 'projected';
  t.after(async () => {
    try {
      await client?.close();
      if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
      await rm(root, {recursive: true, force: true});
    } finally {setDefaultCACertificates(trust);}
  });
  const certificates = await fixtureCertificates(root);
  setDefaultCACertificates([...trust, certificates.ca.toString('utf8')]);
  const profile = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote', durability: 'volatile',
    scopeRef: 'explanation-tls', capabilities: [], limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 2048}};
  const environmentWire = await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8');
  const environmentBody = JSON.parse(environmentWire);
  const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
    environmentBody.evidence_bundle_cid, false, false, true, true, false, false, false);
  assert.ok(environment);
  const preparation = await fundedClientPreparation(t, {moon, environment, http: true});
  server = createServer({key: certificates.key, cert: certificates.cert}, createClientHttpHandler({
    prepareRequest: preparation.prepareRequest,
    authenticate: () => 'caller', authorizeConnection: () => true, negotiate: () => profile,
    attach: value => ({ref: value.ref, durability: 'volatile', revision: 0}),
    runExplanation(value, consume) {
      reads++; assert.deepEqual(value.ref, runExplanation.run_ref);
      if (mode !== 'projected') throw Object.assign(new Error(mode), {code: mode});
      return consume(structuredClone(runExplanation));
    }, submit() {assert.fail('Explanation cannot submit');}}));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  client = await connect({mode: 'remote', token: 'fixture-caller', endpoint: `https://127.0.0.1:${server.address().port}/`});
  const run = await client.attach(runExplanation.run_ref);
  assert.deepEqual(await run.explain(), runExplanation);
  for (mode of ['RunObservationAccessDenied', 'RunExplanationReadLimit', 'RunExplanationEncodingRejected']) {
    await assert.rejects(run.explain(), {code: mode});
  }
  assert.equal(reads, 4);
});
