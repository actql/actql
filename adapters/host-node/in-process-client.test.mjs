import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:http';
import {generateKeyPairSync, sign} from 'node:crypto';
import {connect} from '../../packages/sdk/index.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local',
  owner: 'local', durability: 'volatile', scopeRef: 'local-principal',
  capabilities: [], limits: {maxReadWireBytes: 4096,
    maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
    maxBatchRetainedValueBytes: 2048}};

test('in-process Host checks current scope and exact attach reference',
  async () => {
    let attached = 0;
    const host = createNodeInProcessClientHost({
      authenticate: () => 'local-principal',
      authorizeConnection: ({ref: requested}) =>
        requested === undefined || requested.namespaceId === 'namespace-a',
      negotiate: () => profile,
      attach: () => {
        attached++;
        return {ref: {...ref, runDefinitionCid: cid('c')},
          durability: 'volatile', revision: 1};
      },
      maxRowBytes: 1024,
    });
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      host);
    await assert.rejects(client.attach({...ref, namespaceId: 'namespace-b'}),
      {code: 'ClientConnectionDenied'});
    assert.equal(attached, 0);
    await assert.rejects(client.attach(ref),
      {code: 'InvalidClientHostAdmission'});
    assert.equal(attached, 1);
    client.close();
  });

test('in-process Checkpoint operations use the public Host contract',
  async () => {
    const calls = [];
    const host = createNodeInProcessClientHost({
      authenticate: () => 'local-principal',
      authorizeConnection: ({operation}) => {
        calls.push(operation);
        return true;
      },
      negotiate: () => profile,
      checkpoints: () => ({items: []}),
      checkpointReview: () => {
        throw Object.assign(new Error('CheckpointReviewDenied'),
          {code: 'CheckpointReviewDenied'});
      },
      maxRowBytes: 1024,
    });
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      host);
    assert.deepEqual(await client.checkpoints(), {items: []});
    await assert.rejects(client.reviewCheckpoint(cid('c')),
      {code: 'CheckpointReviewDenied'});
    assert.ok(calls.includes('checkpoints'));
    assert.ok(calls.includes('checkpoint-review'));
    client.close();
  });



const checkpoint = {
  checkpointId: 'prepare-a-preparation', checkpointCid: cid('c'),
  kind: 'run_scope', phase: 'preflight',
  subject: {kind: 'prepare_attempt', prepareAttemptId: 'prepare-a',
    requestId: 'saved-a'},
  requiredArtifact: {type: 'prepared_invocation', cid: cid('d')},
  reviewProjectionCid: cid('e'), requirements: ['invocation_scope_approved'],
  createdAt: '2026-09-26T00:00:00.000Z',
  expiresAt: '2026-09-27T00:00:00.000Z', humanSummary: 'Run on site-a',
};

async function checkpointClient(t, transport, handlers) {
  const configuration = {
    authenticate: () => 'local-principal', authorizeConnection: () => true,
    negotiate: () => profile, maxRowBytes: 1024, ...handlers,
  };
  let client;
  if (transport === 'in-process') {
    client = await connectInProcess({mode: 'local', owner: 'local'},
      createNodeInProcessClientHost(configuration));
  } else {
    const server = createServer(createClientHttpHandler(configuration));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(async () => {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    });
    client = await connect({mode: 'local', owner: 'local',
      endpoint: `http://127.0.0.1:${server.address().port}/`,
      token: 'test-token'});
  }
  t.after(() => client.close());
  return client;
}

for (const transport of ['http', 'in-process']) {
  for (const failure of ['internal-error', 'malformed-reply']) {
    for (const operation of ['cancel-request', 'resolve']) {
      test(`${transport} ${operation} retains recovery after ${failure}`,
        async t => {
          const received = [];
          let recovering = false, signatures = 0;
          const keys = generateKeyPairSync('ed25519');
          const signer = {keyId: 'test-key', reviewerId: 'reviewer',
            sign(bytes) { signatures++; return sign(null, bytes, keys.privateKey); }};
          const handler = request => {
            received.push(structuredClone(request));
            if (!recovering) {
              if (failure === 'internal-error') {
                throw new Error('reply failed after the mutation was recorded');
              }
              return {};
            }
            if (operation === 'cancel-request') {
              return {requestId: request.requestId, kind: 'already_requested'};
            }
            return {results: request.items.map(item => ({
              checkpointCid: item.checkpointCid, status: 'duplicate',
              decision: 'rejected',
              resolutionCid: JSON.parse(item.resolutionWire).resolution_cid,
            }))};
          };
          const client = await checkpointClient(t, transport,
            operation === 'cancel-request' ? {cancelRequest: handler}
              : {resolve: handler});
          let uncertain;
          await assert.rejects(operation === 'cancel-request'
            ? client.cancelRequest('saved-a')
            : client.resolveCheckpoints([{checkpoint, decision: 'rejected'}],
              {signer}), error => {
            uncertain = error;
            return error.code === (operation === 'cancel-request'
              ? 'CancellationUnknown' : 'ResolutionUnknown');
          });
          assert.equal(received.length, 1);
          assert.equal(uncertain.cause.status, 500);
          recovering = true;
          if (operation === 'cancel-request') {
            assert.equal(uncertain.requestId, 'saved-a');
            await client.cancelRequest(uncertain.requestId);
            assert.equal(received[1].requestId, received[0].requestId);
            assert.equal(signatures, 0);
          } else {
            assert.deepEqual(uncertain.signed, received[0].items);
            const recovered = await client.resolveCheckpoints(uncertain.signed);
            assert.equal(recovered.results[0].status, 'duplicate');
            assert.deepEqual(received[1].items, received[0].items);
            assert.equal(signatures, 1);
          }
          assert.equal(received.length, 2);
        });
    }
  }

  for (const refusal of ['authentication', 'connection', 'request', 'handler']) {
    test(`${transport} Checkpoint ${refusal} refusal remains known`, async t => {
      let connected = false, invoked = 0;
      const denied = code => { throw Object.assign(new Error(code), {code}); };
      const client = await checkpointClient(t, transport, {
        authenticate() {
          if (connected && refusal === 'authentication') {
            denied('ClientAuthenticationDenied');
          }
          return 'local-principal';
        },
        authorizeConnection: () => !(connected && refusal === 'connection'),
        cancelRequest() { invoked++; denied('ClientRequestCancellationDenied'); },
        resolve() { invoked++; denied('CheckpointAnswerDenied'); },
      });
      connected = true;
      const expected = refusal === 'authentication' ? 'ClientAuthenticationDenied'
        : refusal === 'connection' ? 'ClientConnectionDenied'
          : refusal === 'request' ? 'InvalidClientRequest'
            : 'ClientRequestCancellationDenied';
      await assert.rejects(client.cancelRequest(refusal === 'request'
        ? 'x'.repeat(257) : 'saved-a'), error => error.code === expected &&
          error.requestId === undefined);
      assert.equal(invoked, refusal === 'handler' ? 1 : 0);
      if (refusal === 'request') return;
      const keys = generateKeyPairSync('ed25519');
      await assert.rejects(client.resolveCheckpoints([
        {checkpoint, decision: 'rejected'},
      ], {signer: {keyId: 'test-key', reviewerId: 'reviewer',
        sign: bytes => sign(null, bytes, keys.privateKey)}}), error =>
        error.code === (refusal === 'handler' ? 'CheckpointAnswerDenied'
          : expected) && error.signed === undefined);
      assert.equal(invoked, refusal === 'handler' ? 2 : 0);
    });
  }
}
