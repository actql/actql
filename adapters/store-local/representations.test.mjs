import test from 'node:test';
import assert from 'node:assert/strict';
import {registerRetainedInput, retainedInputContract, consumeRetainedInput,
  retainedStorageBody, retainedStorageContract} from './representations.mjs';

test('installed representation access preserves exact material and port without exposing file configuration', async () => {
  const material = {};
  const input = {};
  const configuration = {parentDirectory: '/not-public', maxFrameBytes: 64,
    wire: {max_bytes: 100, max_nodes: 20, max_depth: 4, max_columns: 2, max_order_work: 100}};
  const body = {async consume(accept) { await accept(new Uint8Array([1, 2])); }};
  registerRetainedInput(material, read => read === input, body, configuration);
  configuration.maxFrameBytes = 1000;
  configuration.wire.max_bytes = 1000;
  const contract = retainedInputContract(material, input);
  assert.equal(contract.maxFrameBytes, 64);
  assert.equal(contract.wire.max_bytes, 100);
  assert.deepEqual(Object.keys(contract).sort(), ['maxFrameBytes', 'wire']);
  assert.equal(retainedStorageBody(material), body);
  assert.equal(retainedStorageContract(material), contract);
  assert.throws(() => retainedStorageBody({}), /ForeignRetainedStorage/);
  assert.throws(() => retainedStorageContract({}), /ForeignRetainedStorage/);
  assert.throws(() => registerRetainedInput(material, () => true, body, configuration));
  await assert.rejects(consumeRetainedInput({}, input, () => {}), {code: 'RetainedInputUnavailable'});
  await assert.rejects(consumeRetainedInput(material, {}, () => {}), {code: 'RetainedInputUnavailable'});
  let received;
  await consumeRetainedInput(material, input, chunk => { received = [...chunk]; });
  assert.deepEqual(received, [1, 2]);
});

test('release or cancellation during a provisional read cannot become verified consumption', async () => {
  for (const cancel of [false, true]) {
    const material = {};
    const input = {};
    const controller = new AbortController();
    let live = true;
    registerRetainedInput(material, read => live && read === input,
      {async consume(accept) { await accept(new Uint8Array([1])); }},
      {maxFrameBytes: 1, wire: {max_bytes: 1}});
    let calls = 0;
    await assert.rejects(consumeRetainedInput(material, input, async () => {
      calls++;
      if (cancel) controller.abort(); else live = false;
    }, controller.signal));
    assert.equal(calls, 1);
  }
});
