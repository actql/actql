import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {connect} from './index.mjs';

const ref = {namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const profile = {version: 'actql-client-host/0.1', mode: 'local',
  owner: 'local', durability: 'volatile', scopeRef: 'scope-a',
  capabilities: ['aql-document', 'result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};

async function listen(handler) {
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return server;
}

test('Client Host redirects never resend submit or read to another Host',
  async t => {
    const forwarded = [];
    const selected = [];
    let redirectStatus = 307;
    const target = await listen(async (request, response) => {
      let body = '';
      for await (const chunk of request) body += chunk;
      forwarded.push({method: request.method, body});
      response.end('{}');
    });
    const first = await listen(async (request, response) => {
      let body = '';
      for await (const chunk of request) body += chunk;
      const operation = request.url.split('/').at(-1);
      selected.push({operation, body: JSON.parse(body)});
      if (operation === 'submit' || operation === 'read') {
        response.writeHead(redirectStatus, {location:
          `http://127.0.0.1:${target.address().port}/actql/client/0.1/${operation}`});
        response.end();
      } else {
        response.setHeader('content-type', 'application/json');
        response.end(JSON.stringify(operation === 'connect' ? profile :
          operation === 'attach' ? {ref, durability: 'volatile', revision: 1} :
            {kind: 'not_found'}));
      }
    });
    t.after(async () => {
      first.closeAllConnections();
      target.closeAllConnections();
      await Promise.all([new Promise(resolve => first.close(resolve)),
        new Promise(resolve => target.close(resolve))]);
    });
    const client = await connect({mode: 'local', owner: 'local',
      endpoint: `http://127.0.0.1:${first.address().port}/`,
      token: 'scoped-token'});
    for (const status of [301, 302, 303, 307, 308]) {
      redirectStatus = status;
      const requestId = `redirect-${status}`;
      await assert.rejects(client.start({version: 'actql/0.1'},
        {requestId}), error => {
        assert.equal(error.code, 'SubmissionUnknown');
        assert.equal(error.requestId, requestId);
        assert.equal(error.lookupContext.scopeRef, 'scope-a');
        assert.equal(error.lookupContext.endpoint,
          `http://127.0.0.1:${first.address().port}/`);
        return true;
      });
      assert.deepEqual(await client.lookupRequest(requestId),
        {kind: 'not_found'});
      const execution = await client.attach(ref);
      await assert.rejects(execution.result('answer').all(), error =>
        error.code === 'ClientTransportUnknown' && !!error.attemptId);
    }
    assert.equal(forwarded.length, 0);
    assert.deepEqual(selected.map(item => item.operation),
      ['connect', ...Array.from({length: 5}, () =>
        ['submit', 'lookup-request', 'attach', 'read']).flat()]);
    assert.deepEqual(selected.filter(item => item.operation === 'submit')
      .map(item => item.body.requestId),
    [301, 302, 303, 307, 308].map(status => `redirect-${status}`));
    client.close();
  });
