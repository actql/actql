import assert from 'node:assert/strict';
import test from 'node:test';
import * as sdk from './index.mjs';

const profile = () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'principal', capabilities: ['result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}});
const connect = reply => sdk.connectInProcess({mode: 'local', owner: 'local'}, {
  perform(operation) {assert.equal(operation, 'connect'); return reply;},
});

test('connection: profile fields are captured once before admission', async t => {
  const reply = profile(), reads = {scopeRef: 0, maxRows: 0};
  Object.defineProperty(reply, 'scopeRef', {enumerable: true,
    get() {return ++reads.scopeRef === 1 ? 'principal' : 'foreign-principal';}});
  Object.defineProperty(reply.limits, 'maxRows', {enumerable: true,
    get() {return ++reads.maxRows === 1 ? 10 : 20;}});
  const client = await connect(reply); t.after(() => client.close());
  assert.equal(client.profile.scopeRef, 'principal', '[check-mutation:profile-capture-once]');
  assert.equal(client.profile.limits.maxRows, 10, '[check-mutation:profile-capture-once]');
  assert.deepEqual(reads, {scopeRef: 1, maxRows: 1});
  assert.deepEqual(client.profile, profile());
});

test('connection: a throwing profile getter is a safe profile refusal', async () => {
  const reply = profile(); let reads = 0;
  Object.defineProperty(reply, 'scopeRef', {enumerable: true,
    get() {reads++; throw new Error('private-profile-secret');}});
  await assert.rejects(connect(reply), error => {
    assert.equal(error.code, 'InvalidHostProfile');
    assert.doesNotMatch(JSON.stringify(error), /private-profile-secret/);
    assert.equal(sdk.explainCheckFailure(error), undefined);
    return true;
  });
  assert.equal(reads, 1);
});

test('connection: reused profile data cannot replace retained context or limits', async t => {
  const reply = profile(), client = await connect(reply); t.after(() => client.close());
  reply.scopeRef = 'foreign-principal'; reply.limits.maxRows = 20;
  reply.capabilities.push('private-capability');
  assert.deepEqual(client.profile, profile());
  assert.equal(Object.isFrozen(reply), false);
  for (const value of [client.profile, client.profile.limits, client.profile.capabilities]) {
    assert.equal(Object.isFrozen(value), true);
  }
});

for (const fault of ['replacement', 'mutation']) {
  test(`connection: profile admission does not invoke a redundant ${fault} conversion`, async t => {
    const clone = globalThis.structuredClone;
    t.after(() => {globalThis.structuredClone = clone;});
    let conversions = 0;
    globalThis.structuredClone = value => {
      const copy = clone(value);
      if (value.version === 'actql-client-host/0.1') {
        conversions++;
        if (fault === 'replacement') copy.scopeRef = 'foreign-principal';
        else value.scopeRef = 'foreign-principal';
      }
      return copy;
    };
    const client = await connect(profile()); t.after(() => client.close());
    assert.deepEqual(client.profile, profile());
    assert.equal(conversions, 0);
  });
}

for (const kind of ['Date', 'Proxy']) {
  test(`connection: own profile fields on a ${kind} DTO remain admissible`, async t => {
    const data = profile(); let serializations = 0;
    const reply = kind === 'Date' ? Object.assign(new Date(0), data) : new Proxy(data, {});
    Object.defineProperty(reply, 'toJSON', {value() {serializations++; throw new Error('must not serialize');}});
    const client = await connect(reply); t.after(() => client.close());
    assert.deepEqual(client.profile, profile());
    assert.equal(serializations, 0);
  });
}
