import test from 'node:test';
import assert from 'node:assert/strict';
import {registerRetainedInput, retainedInputContract, consumeRetainedInput,
  retainedStorageBody, retainedStorageContract, retainedInputSupportsFile,
  withRetainedInputFile} from './representations.mjs';

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

test('direct file access requires the exact live consumer before and after native use', async () => {
  const material = {}, input = {};
  let live = true, calls = 0;
  registerRetainedInput(material, value => live && value === input, {
    async consume() {},
    nativeFilePath() { return '/trusted-fixture'; },
    async withVerifiedFile(use) { calls++; return use({path: '/trusted-fixture'}); },
  }, {maxFrameBytes: 10, wire: {max_bytes: 10}});
  assert.equal(retainedInputSupportsFile(material, input), true);
  await assert.rejects(withRetainedInputFile({}, input, () => {}), {code: 'RetainedInputUnavailable'});
  await assert.rejects(withRetainedInputFile(material, {}, () => {}), {code: 'RetainedInputUnavailable'});
  assert.equal(calls, 0);
  assert.equal(await withRetainedInputFile(material, input, () => 'verified'), 'verified');
  await assert.rejects(withRetainedInputFile(material, input, () => { live = false; }),
    {code: 'RetainedInputUnavailable'});
  assert.equal(calls, 2);
});

test('unsupported direct access and already-cancelled use do not enter native code', async () => {
  const material = {}, input = {};
  registerRetainedInput(material, value => value === input, {async consume() {}},
    {maxFrameBytes: 10, wire: {max_bytes: 10}});
  assert.equal(retainedInputSupportsFile(material, input), false);
  await assert.rejects(withRetainedInputFile(material, input, () => {}), /UnsupportedRetainedFileAccess/);
  const controller = new AbortController();
  const reason = Error('cancelled'); controller.abort(reason);
  await assert.rejects(withRetainedInputFile(material, input, () => {}, controller.signal), error => error === reason);
});

test('direct physical admission is forwarded only for the exact live input', async () => {
  const material = {}, input = {};
  const rejected = Error('physical budget exceeded');
  let charged = 0, used = 0;
  registerRetainedInput(material, value => value === input, {
    async consume() {}, nativeFilePath() { return '/trusted-fixture'; },
    async withVerifiedFile(use, signal, beforeRead) {
      await beforeRead(12); used++; return use({path: '/trusted-fixture', bytes: 12});
    },
  }, {maxFrameBytes: 12, wire: {max_bytes: 12}});
  const charge = bytes => { charged += bytes; throw rejected; };
  await assert.rejects(withRetainedInputFile(material, {}, () => {}, undefined, charge),
    {code: 'RetainedInputUnavailable'});
  assert.equal(charged, 0);
  await assert.rejects(withRetainedInputFile(material, input, () => {}, undefined, charge),
    error => error === rejected);
  assert.equal(charged, 12); assert.equal(used, 0);
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
