import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {connect} from './index.mjs';
import {submissionEpoch} from './submission-fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'batch-accounting', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const limits = {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
  maxRowRetainedValueBytes: 2048, maxRetainedValueBytes: 4096,
  maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 2048};
const values = [{batch_marker: 'one', n: 1}, {batch_marker: 'two', n: 2}, {batch_marker: 'three', n: 3}];

async function fixture(t, mode = 'local') {
  let reads = 0, returns = 0, closes = 0;
  const profile = {version: 'actql-client-host/0.1', mode, owner: mode,
    durability: mode === 'local' ? 'volatile' : 'durable', scopeRef: 'batch-accounting',
    capabilities: [], limits, ...(mode === 'local' ? {submissionEpoch} : {})};
  const admission = {ref, durability: profile.durability, revision: 1};
  const wire = values.map(value => JSON.stringify(value)).join('\n') + '\n\x1e';
  let client;
  if (mode === 'local') {
    client = await connectInProcess({mode, owner: mode}, {async perform(operation) {
      if (operation === 'connect') return profile;
      if (operation === 'attach') return admission;
      assert.equal(operation, 'read'); reads++;
      return {kind: 'rows', close() {closes++;}, frames: (async function* () {
        try {for (const value of values) yield {value, byteLength: 32};}
        finally {returns++;}
      })()};
    }});
  } else {
    t.mock.method(globalThis, 'fetch', async url => {
      const operation = url.pathname.split('/').at(-1);
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') return Response.json(admission);
      assert.equal(operation, 'read'); reads++; return new Response(wire);
    });
    client = await connect({mode, endpoint: 'https://host.example/', token: 'token'});
  }
  t.after(() => client.close());
  return {result: (await client.attach(ref)).result('answer'), counts: () => ({reads, returns, closes})};
}

for (const mode of ['local', 'remote']) {
  test(`${mode} batches account each unchanged row once`, async t => {
    const f = await fixture(t, mode), original = JSON.stringify, counts = new Map();
    t.mock.method(JSON, 'stringify', function (value, ...args) {
      if (value !== null && typeof value === 'object' && Object.hasOwn(value, 'batch_marker')) {
        counts.set(value.batch_marker, (counts.get(value.batch_marker) ?? 0) + 1);
      }
      return Reflect.apply(original, this, [value, ...args]);
    });
    const reader = f.result.batches({maxBatchRows: 2});
    assert.deepEqual(await Array.fromAsync(reader), [values.slice(0, 2), values.slice(2)]);
    assert.deepEqual(Object.fromEntries(counts), {one: 1, two: 1, three: 1});
    assert.equal(reader.state(), 'complete'); assert.equal(reader.rowsYielded(), 3);
    assert.equal(f.counts().reads, 1);
    if (mode === 'local') assert.deepEqual(f.counts(), {reads: 1, returns: 1, closes: 1});
  });
}

test('batch ceilings use their first captured option values', async t => {
  const f = await fixture(t); let rowReads = 0, byteReads = 0;
  const reader = f.result.batches({
    get maxBatchRows() {return ++rowReads === 1 ? 1 : 3;},
    get maxBatchRetainedValueBytes() {byteReads++; return 2048;},
  });
  assert.deepEqual(await Array.fromAsync(reader), values.map(value => [value]));
  assert.deepEqual({rowReads, byteReads}, {rowReads: 1, byteReads: 1});
  assert.deepEqual(f.counts(), {reads: 1, returns: 1, closes: 1});
});

test('application-transformed rows retain independent batch-size admission', async t => {
  const f = await fixture(t); let validations = 0;
  const reader = f.result.batches({'~standard': {version: 1, vendor: 'batch-accounting',
    validate() {validations++; return {value: {expanded: 'x'.repeat(4096)}};}}});
  await assert.rejects(Array.fromAsync(reader), error => error.code === 'ResultBatchLimit' && error.rowsYielded === 0);
  assert.equal(validations, 1); assert.deepEqual(f.counts(), {reads: 1, returns: 1, closes: 1});
});
