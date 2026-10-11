import assert from 'node:assert/strict';
import {startExplorerGateway} from './gateway.mjs';
import {createExplorerBrowserSource} from './browser-source.mjs';

// Shared acceptance consumer: supply the actual public Client and independent
// Program/Run expectations. This helper never creates/submits a Run itself.
export async function assertOriginalGatewayReads({client, program, ref, runId,
  revision, expectedOperators, expectedColumns}) {
  const gateway = await startExplorerGateway({client});
  let cookie;
  const source = createExplorerBrowserSource({origin: gateway.origin,
    async fetch(url, options) {
      // Node acceptance emulates browser same-origin Origin/cookie handling.
      const response = await fetch(url, {...options, headers: {...options.headers,
        Origin: gateway.origin, ...(cookie ? {Cookie: cookie} : {})}});
      const installed = response.headers.get('set-cookie');
      if (installed) cookie = installed.split(';')[0];
      return response;
    }});
  try {
    const capabilities = await source.connect(gateway.issueBootstrap().bootstrap);
    assert.deepEqual(capabilities, {plan: true, run: true, resultMetadata: true,
      resultPayload: false, control: false, sample: false});
    const plan = await source.plan(program);
    assert.equal(plan.observation, 'static'); assert.equal(plan.providerIO, 0);
    assert.deepEqual(plan.nodes.map(node => node.operator), expectedOperators);
    assert.deepEqual(plan.sourceOrigins, {state: 'unavailable', reason: 'not_in_projection'});
    const view = await source.inspect(ref);
    assert.deepEqual(view.run_ref, ref);
    assert.equal(view.run_state.run_id, runId);
    assert.equal(view.run_state.status, 'succeeded');
    assert.equal(view.run_state.control_revision, revision);
    assert.equal(view.consistency, 'non_atomic');
    const description = await source.describe(ref, 'answer');
    assert.deepEqual(description.columns, expectedColumns);
    source.close();
    await assert.rejects(source.inspect(ref), {code: 'ExplorerSessionExpired'});
  } finally {source.close(); await gateway.close();}
}
