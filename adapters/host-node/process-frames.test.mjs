import test from 'node:test';
import assert from 'node:assert/strict';
import { encodeProcessFrame, createProcessFrameReader } from './process-frames.mjs';
const limits = Object.freeze({ maxBytes: 128, maxNodes: 20, maxDepth: 4 });

test('private IPC frames survive every byte split and preserve control payloads', () => {
  const input = { session: 'é😀', attempt: 2, body: ['K', 'k', null] };
  const frame = encodeProcessFrame(input, limits);
  for (let split = 0; split <= frame.length; split++) {
    const values = [];
    const reader = createProcessFrameReader(limits, value => values.push(value));
    reader.feed(frame.subarray(0, split)); reader.feed(frame.subarray(split)); reader.end();
    assert.equal(JSON.stringify(values[0]), JSON.stringify(input));
    assert.equal(values.length, 1);
  }
});

test('byte node depth and announced size limits reject before dispatch', () => {
  for (const input of ['x'.repeat(129), Array(21).fill(null), [[[[[null]]]]]]) {
    assert.throws(() => encodeProcessFrame(input, limits));
  }
  let calls = 0;
  const reader = createProcessFrameReader(limits, () => calls++);
  const header = Buffer.alloc(4); header.writeUInt32BE(0xffffffff);
  assert.throws(() => reader.feed(header), { code: 'FrameByteLimit' });
  assert.equal(calls, 0);
  assert.throws(() => reader.feed(encodeProcessFrame(null, limits)), { code: 'FrameReaderClosed' });
});

test('snapshot rejects getters cycles and class instances without invoking them', () => {
  let calls = 0;
  const item = { get value() { calls++; return 1; } };
  assert.throws(() => encodeProcessFrame(item, limits), { code: 'InvalidFrameValue' });
  assert.equal(calls, 0);
  const cycle = {}; cycle.self = cycle;
  assert.throws(() => encodeProcessFrame(cycle, limits), { code: 'InvalidFrameValue' });
  assert.throws(() => encodeProcessFrame(new Date(), limits), { code: 'InvalidFrameValue' });
});

test('truncated invalid UTF8 and reentrant frames never count as complete messages', () => {
  const frame = encodeProcessFrame('é', limits);
  const reader = createProcessFrameReader(limits, () => assert.fail('truncated dispatch'));
  reader.feed(frame.subarray(0, frame.length - 1));
  assert.throws(() => reader.end(), { code: 'TruncatedFrame' });
  const corrupt = Buffer.from([0, 0, 0, 3, 34, 255, 34]);
  assert.throws(() => createProcessFrameReader(limits, () => assert.fail('bad UTF8')).feed(corrupt));
  let recursive;
  recursive = createProcessFrameReader(limits, () => recursive.feed(frame));
  assert.throws(() => recursive.feed(frame), { code: 'FrameReaderClosed' });
});
