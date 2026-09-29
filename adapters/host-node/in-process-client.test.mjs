import assert from 'node:assert/strict';
import test from 'node:test';
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
