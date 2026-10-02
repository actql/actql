import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {ClientError} from './index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1',
  mode: 'local', owner: 'local', durability: 'volatile',
  scopeRef: 'local-scope', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 256, maxRowWireBytes: 128,
    maxRowRetainedValueBytes: 512, maxRetainedValueBytes: 1024,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 1024}};
const admission = {ref, durability: 'volatile', revision: 1};

test('one Client facade reads typed Local frames without HTTP or JSONL',
  async t => {
    const network = mock.method(globalThis, 'fetch', () => {
      throw new Error('UnexpectedCloudOrHTTP');
    });
    t.after(() => mock.restoreAll());
    const calls = [];
    const port = {async perform(operation, request, signal) {
      calls.push({operation, request});
      if (operation === 'connect') return profile;
      if (operation === 'submit' || operation === 'attach') {
        return admission;
      }
      if (operation === 'read') {
        assert.equal(request.format, 'typed');
        return {kind: 'rows', frames: (async function* () {
          signal.throwIfAborted();
          if (request.resultName === 'empty') return;
          yield {value: {id: 1, label: null}, byteLength: 24};
          yield {value: {id: 2, label: 'two'}, byteLength: 27};
        })()};
      }
      throw new Error(`UnexpectedOperation:${operation}`);
    }};
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      port);
    const execution = await client.aql('{"version":"actql/0.1"}',
      {format: 'json', requestId: 'local-request'});
    const result = execution.result('answer');
    assert.deepEqual(await result.all(), [
      {id: 1, label: null}, {id: 2, label: 'two'},
    ]);
    const attached = await client.attach(ref);
    assert.deepEqual(await attached.result('answer').all(), [
      {id: 1, label: null}, {id: 2, label: 'two'},
    ]);
    assert.deepEqual(await execution.result('empty').all(), []);
    const partial = result.rows({maxWireBytes: 50});
    const prefix = [];
    await assert.rejects(async () => {
      for await (const row of partial) prefix.push(row);
    }, error => error.code === 'ResultWireLimit' &&
      error.attemptId === partial.attemptId);
    assert.deepEqual(prefix, [{id: 1, label: null}]);
    assert.equal(partial.state(), 'prefix');
    assert.equal(calls.filter(call => call.operation === 'submit').length, 1);
    assert.equal(calls.filter(call => call.operation === 'read').length, 4);
    assert.equal(calls.filter(call => call.operation === 'cancel').length, 0);
    assert.deepEqual(calls[1].request, {connection: {
      mode: 'local', owner: 'local', consentRefs: [], runners: [],
    }, requestId: 'local-request', kind: 'aql',
    input: {text: '{"version":"actql/0.1"}', format: 'json'},
    parameters: null});
    assert.equal(network.mock.callCount(), 0);
    client.close();
  });

test('in-process submit uncertainty retains the request ID', async () => {
  const client = await connectInProcess({mode: 'local', owner: 'local'},
    {async perform(operation) {
      if (operation === 'connect') return profile;
      throw new Error('AcceptanceResponseLost');
    }});
  await assert.rejects(client.start({version: 'actql/0.1'},
    {requestId: 'saved-local-id'}), error =>
    error.code === 'SubmissionUnknown' &&
    error.requestId === 'saved-local-id');
  client.close();
});

test('in-process Host rejection does not masquerade as uncertain submit',
  async () => {
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      {async perform(operation) {
        if (operation === 'connect') return profile;
        throw new ClientError('ClientRequestIntentConflict');
      }});
    await assert.rejects(client.start({version: 'actql/0.1'},
      {requestId: 'conflicting-local-id'}),
    {code: 'ClientRequestIntentConflict'});
    client.close();
  });


for (const count of [1, 2]) {
  test(`typed read abort stays a prefix after the first of ${count} frames`,
    async () => {
      const operations = [];
      let released = 0;
      const port = {async perform(operation) {
        operations.push(operation);
        if (operation === 'connect') return profile;
        if (operation === 'attach') return admission;
        if (operation === 'read') return {kind: 'rows',
          frames: (async function* () {
            try {
              for (let n = 1; n <= count; n++) {
                yield {value: {n}, byteLength: 8};
              }
            } finally { released++; }
          })()};
        throw new Error(`unexpected ${operation}`);
      }};
      const client = await connectInProcess({mode: 'local', owner: 'local'},
        port);
      const result = (await client.attach(ref)).result('answer');
      const controller = new AbortController();
      const reader = result.rows({signal: controller.signal});
      const iterator = reader[Symbol.asyncIterator]();
      assert.deepEqual(await iterator.next(), {done: false, value: {n: 1}});
      controller.abort();
      await assert.rejects(iterator.next(), error =>
        error.code === 'ResultReadUnknown' &&
        error.attemptId === reader.attemptId &&
        error.cause?.name === 'AbortError');
      assert.equal(reader.state(), 'prefix');
      assert.equal(released, 1);
      assert.deepEqual(operations, ['connect', 'attach', 'read']);
      client.close();
    });
}
