// Reuse the independently authored public Effect acceptance. This adapter adds
// only an OTLP collector; no receipt, approval or execution owner is replaced.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {connect} from '../sdk/index.mjs';
import {openInstalledRemoteHttpHost} from '../local-node/http-host.mjs';
import {publishEffect} from '../local-node/index.mjs';
import {createNodeHostObservability} from './index.mjs';
import {runInstalledEffectInventoryAcceptance} from
  '../../scripts/fixtures/installed-effect-inventory-acceptance.mjs';
import {records, attributes} from './test/otlp-fixture.mjs';

test('public HTTPS Effect approval, restart and lost reply retain Owner outcomes', async t => {
  const packets = [], adapters = [];
  let received = 0;
  const collector = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) {
      received += chunk.length;
      assert.ok(received <= 8 * 1024 * 1024, 'finite acceptance payload');
      chunks.push(chunk);
    }
    assert.ok(packets.length < 4096);
    packets.push({path: request.url, body: Buffer.concat(chunks)});
    response.end();
  }).listen(0, '127.0.0.1');
  await once(collector, 'listening');
  t.after(async () => {
    for (const adapter of adapters) await adapter.close();
    await new Promise(resolve => collector.close(resolve));
  });
  const endpoint = `http://127.0.0.1:${collector.address().port}`;
  const result = await runInstalledEffectInventoryAcceptance({connect, publishEffect,
    profile: 'observability',
    async openInstalledRemoteHttpHost(options) {
      const adapter = createNodeHostObservability({endpoint,
        logs: {endpoint: `${endpoint}/v1/logs`},
        operations: {include: ['run', 'effect', 'approval', 'checkpoint',
          'recovery', 'cleanup', 'publication']}});
      adapters.push(adapter);
      const host = await openInstalledRemoteHttpHost({...options,
        observation: adapter.connection});
      return Object.freeze({...host, async close() {
        await host.close();
        await adapter.close();
      }});
    }});
  assert.equal(result.successfulPluralRuns, 1);
  assert.equal(result.cancelledWithoutSend, 1);
  assert.equal(result.unknownAfterRestart, 1);
  assert.deepEqual(result.providerSends, [1, 1],
    'approval/restart/unknown observation never adds an Effect send');
  const logs = records(packets, 'logs').map(record => attributes(record, 6));
  const applications = logs.filter(value => value['actql.operation'] === 'effect' &&
    value['actql.event'] === 'application_observed');
  assert.ok(applications.some(value => value['actql.outcome'] === 'committed'));
  assert.ok(applications.some(value => value['actql.outcome'] === 'needs_reconciliation'),
    'a lost reply retains the common receipt Owner uncertainty');
  assert.ok(logs.some(value => value['actql.outcome'] === 'waiting_checkpoint'));
  assert.ok(logs.some(value => value['actql.outcome'] === 'cancelled'));
  assert.ok(logs.some(value => value['actql.event'] === 'checkpoint_resolved'));
  for (const packet of packets) for (const secret of [
    'synthetic-owner-token', 'synthetic-reviewer-token', 'synthetic-ephemeral-',
    'beta lost reply', 'alpha forward', 'I_ALPHA', 'I_BETA']) {
    assert.equal(packet.body.includes(Buffer.from(secret)), false, secret);
  }
});
