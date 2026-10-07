import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {connect} from './index.mjs';
import {submissionEpoch} from './submission-fixture.mjs';

const ref = {namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const profile = {version: 'actql-client-host/0.1', mode: 'local',
  owner: 'local', durability: 'volatile', scopeRef: 'scope-a',
  submissionEpoch,
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
      if (operation === 'submit-intent' || operation === 'read') {
        response.writeHead(redirectStatus, {location:
          `http://127.0.0.1:${target.address().port}/actql/client/0.1/${operation}`});
        response.end();
      } else {
        response.setHeader('content-type', 'application/json');
        response.end(JSON.stringify(operation === 'connect' ? profile :
          operation === 'attach' ? {ref, durability: 'volatile', revision: 1} :
            {kind: 'unresolvable', submissionRef: JSON.parse(body).submissionRef,
              problem: {code: 'submission_history_unresolvable'}}));
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
      const submissionRef = client.newSubmission({nonce: requestId});
      await assert.rejects(client.start({version: 'actql/0.1'},
        {submissionRef}), error => {
        assert.equal(error.code, 'SubmissionUnknown');
        assert.equal(error.requestId, requestId);
        assert.deepEqual(error.submissionRef, submissionRef);
        assert.equal(error.lookupContext.scopeRef, 'scope-a');
        assert.equal(error.lookupContext.endpoint,
          `http://127.0.0.1:${first.address().port}/`);
        return true;
      });
      assert.deepEqual(await client.lookupSubmission(submissionRef),
        {kind: 'unresolvable', submissionRef,
          problem: {code: 'submission_history_unresolvable'}});
      const execution = await client.attach(ref);
      await assert.rejects(execution.result('answer').all(), error =>
        error.code === 'ClientTransportUnknown' && !!error.attemptId);
    }
    assert.equal(forwarded.length, 0);
    assert.deepEqual(selected.map(item => item.operation),
      ['connect', ...Array.from({length: 5}, () =>
        ['submit-intent', 'lookup-submission', 'attach', 'read']).flat()]);
    assert.deepEqual(selected.filter(item => item.operation === 'submit-intent')
      .map(item => item.body.submissionRef.nonce),
    [301, 302, 303, 307, 308].map(status => `redirect-${status}`));
    for (const sent of selected.filter(item => item.operation === 'submit-intent')) {
      const lookup = selected.find(item => item.operation === 'lookup-submission' &&
        item.body.submissionRef.nonce === sent.body.submissionRef.nonce);
      assert.deepEqual(lookup.body.submissionRef, sent.body.submissionRef);
      assert.equal(sent.body.intentCid,
        'sha256:aad8d443977762aef13b3ea1e41135c63df11879000b6443b11836ada421aaa6');
    }
    client.close();
  });
