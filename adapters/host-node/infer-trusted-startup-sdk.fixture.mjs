import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {setImmediate as turn} from 'node:timers/promises';
import {fixtureStructuredChatOptions, prepareSelectedChat} from '../../packages/provider-ai-sdk/selected-chat.fixture.mjs';
import {createOriginalUndiciFetch} from '@actql/local-node/_internal/model-http-transport';
import {pollSdkPreparation, prepareSdkTransport, startSdkTransport, pollSdkTransport,
  sdkTransportRawObservation, pollSdkDecode, confirmSavedSdkTransportResponse,
  takeSavedSdkDecodedResult, cleanupSdkPreparation} from
  '../../packages/provider-ai-sdk/_internal/intercepted-request.mjs';

// Actual pinned SDK/Undici under the selected real startup. Loopback only:
// no Common Entry, live Provider credentials, Store, resource grant or Result.
const wire = '{"id":"original","model":"synthetic-model","choices":'+
  '[{"index":0,"message":{"role":"assistant","content":"{}"},"finish_reason":"stop"}],"usage":null}';
let requests = 0;
let received;
const server = createServer(async (request, response) => {
  requests++;
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  received = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  response.setHeader('content-type', 'application/json');
  response.end(wire);
});
let handle;
async function until(read, accept) {
  for (let count = 0; count < 1000; count++) {
    const value = read();
    if (accept(value)) return value;
    await turn();
  }
  throw new Error('Selected startup finite SDK observation unavailable');
}
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
  const requestLimits = {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16};
  const responseLimits = {maxBytes: 4096, maxChunkBytes: 512, maxChunks: 8,
    maxHeaderBytes: 1024, observedHeaders: ['content-type']};
  const fetch = createOriginalUndiciFetch({endpoint, requestLimits, responseLimits,
    physicalAcquisitionLimits: {maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64}});
  handle = prepareSelectedChat({selector: 'fixture-task', modelId: 'synthetic-model',
    baseURL: endpoint.slice(0, -'/chat/completions'.length), apiKey: 'synthetic-only',
    maxRequestBytes: requestLimits.maxBytes, maxHeaderBytes: requestLimits.maxHeaderBytes,
    maxHeaders: requestLimits.maxHeaders, notify() {},
    options: fixtureStructuredChatOptions('Original é\r\n', 16)});
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  prepareSdkTransport(handle, {fetch, responseLimits, responseMode: 'saved-sdk'});
  assert.equal(requests, 0);
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.equal(raw.transportComplete, true);
  assert.equal(Buffer.from(raw.body).toString('utf8'), wire);
  assert.equal(pollSdkDecode(handle).kind, 'pending');
  const receipt=Object.freeze({original:Symbol('synthetic saved receipt')});
  confirmSavedSdkTransportResponse(handle,raw,{receipt,bytes:raw.body});
  await until(() => pollSdkDecode(handle), value => value.kind === 'ready');
  assert.deepEqual(takeSavedSdkDecodedResult(handle,receipt,raw.body).content,[{type:'text',text:'{}'}]);
  assert.equal(requests, 1);
  assert.equal(received.model, 'synthetic-model');
  assert.deepEqual(received.messages, [{role: 'system', content: 'Return the fixture object.'},
    {role: 'user', content: 'Original é\r\n'}]);
  await until(() => cleanupSdkPreparation(handle), value => value === true);
  assert.throws(() => startSdkTransport(handle), {code: 'ForeignSdkPreparation'});
  console.log(JSON.stringify({requests, rawComplete: true, sdkDecodedAfterConfirmation: true,
    cleanup: true, actualCommonEntry: false, actualStore: false,
    normalNumericProfile: null, publicE2E: 0}));
} finally {
  // Same physical SDK cleanup only, not another start or fake stop ACK.
  if (handle !== undefined) await until(() => cleanupSdkPreparation(handle), value => value === true);
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
