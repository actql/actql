import test from 'node:test';
import assert from 'node:assert/strict';
import { encodeProcessFrame, createProcessFrameReader, snapshotProcessValue } from './process-frames.mjs';
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


test('pure configuration snapshots preserve framed JSON values without transport copies', () => {
  const inputs = [JSON.parse('{"__proto__":{"safe":true},"constructor":"data"}'),
    {zero: -0, values: [0, -0, null, true, 'é😀']}, Object.assign(Object.create(null), {a: 1})];
  for (const input of inputs) {
    const framed = JSON.parse(encodeProcessFrame(input, limits).subarray(4).toString('utf8'));
    const pure = snapshotProcessValue(input, limits);
    assert.deepStrictEqual(pure, framed);
    assert.equal(Object.getPrototypeOf(pure), Object.prototype);
    if (Object.hasOwn(input, '__proto__')) {
      assert.equal(Object.hasOwn(pure, '__proto__'), true);
      assert.equal(pure.safe, undefined);
    }
  }
});

test('pure configuration snapshots preserve frame refusal boundaries', () => {
  const accessor = Object.defineProperty({}, 'x', {enumerable: true,
    get() {assert.fail('configuration getter must not run');}});
  const cycle = {}; cycle.self = cycle;
  const inputs = [Array(1), [undefined], {a: undefined}, NaN, Infinity,
    Object.create({inherited: true}), new Date(0), accessor, cycle,
    'x'.repeat(129), Array(21).fill(null), [[[[[null]]]]]];
  for (const input of inputs) {
    let expected;
    assert.throws(() => encodeProcessFrame(input, limits), error => {expected = error.code; return true;});
    assert.throws(() => snapshotProcessValue(input, limits), {code: expected});
  }
});

test('original frame body admission runs before its first body allocation and preserves the original refusal', () => {
  const original = Object.freeze(new Error('OriginalFrameCapacityRefusal'));
  const lengths = [], allocations = [];
  const reader = createProcessFrameReader(limits, () => assert.fail('refused body cannot dispatch'), length => {
    lengths.push(length); throw original;
  });
  const header = Buffer.alloc(4); header.writeUInt32BE(100);
  const allocate = Buffer.allocUnsafe;
  let failure;
  try {
    Buffer.allocUnsafe = function(size) { allocations.push(size); return Reflect.apply(allocate, this, [size]); };
    try { reader.feed(header); } catch (error) { failure = error; }
  } finally { Buffer.allocUnsafe = allocate; }
  assert.strictEqual(failure, original);
  assert.deepEqual(lengths, [100]);
  assert.deepEqual(allocations, []);
  assert.throws(() => reader.feed(Buffer.from('null')), {code:'FrameReaderClosed'});
});

test('frame body admission is once per complete header across byte splits and stays behind byte limits', () => {
  const frame = encodeProcessFrame({value:'e\u0301\r\n'}, limits), lengths = [], values = [];
  const reader = createProcessFrameReader(limits, value => values.push(value), length => lengths.push(length));
  for (const byte of frame) reader.feed(Buffer.from([byte]));
  reader.end();
  assert.deepEqual(lengths,[frame.length-4]);
  assert.equal(values[0].value,'e\u0301\r\n');
  for (const length of [0,limits.maxBytes+1]) {
    const invalid = Buffer.alloc(4);invalid.writeUInt32BE(length);
    assert.throws(()=>createProcessFrameReader(limits,()=>assert.fail('invalid dispatch'),()=>assert.fail('invalid allocation handoff')).feed(invalid),{code:'FrameByteLimit'});
  }
});

test('current callback cannot allocate a frame after closing the same reader', () => {
  let reader;
  reader = createProcessFrameReader(limits,()=>assert.fail('closed dispatch'),()=>{
    assert.throws(()=>reader.end(),{code:'TruncatedFrame'});
  });
  const header=Buffer.alloc(4);header.writeUInt32BE(4);
  assert.throws(()=>reader.feed(header),{code:'FrameReaderClosed'});
});

test('complete original IPC body is observed once before UTF8 or JSON decoding, including refused bodies', () => {
  const malformed = Buffer.from('{not JSON'), header = Buffer.alloc(4);
  header.writeUInt32BE(malformed.length);
  let received;
  const calls = [];
  const reader = createProcessFrameReader(limits, () => assert.fail('invalid JSON cannot dispatch'),
    length => {assert.equal(length, malformed.length);calls.push('reserve');},
    body => {assert(Buffer.isBuffer(body));received = body;calls.push('receive');});
  reader.feed(header);
  assert.equal(received,undefined,'an announcement is never a received body');
  assert.throws(() => reader.feed(malformed), SyntaxError);
  assert.deepEqual(calls,['reserve','receive']);
  assert.deepEqual(received,malformed);
  assert.throws(() => reader.feed(malformed), {code:'FrameReaderClosed'});
});

test('original IPC received-body refusal or reentry cannot decode or accept the body', () => {
  const frame = encodeProcessFrame({value:'original'},limits);
  const cause = Object.freeze({original:'received-body-refusal'});
  let accepts = 0;
  const reader = createProcessFrameReader(limits,()=>{accepts++;},undefined,()=>{throw cause;});
  assert.throws(()=>reader.feed(frame), error=>error===cause);
  assert.equal(accepts,0);
  let reentrant;
  reentrant = createProcessFrameReader(limits,()=>assert.fail('closed received body dispatch'),undefined,()=>{
    assert.throws(()=>reentrant.end(),{code:'TruncatedFrame'});
  });
  assert.throws(()=>reentrant.feed(frame),{code:'FrameReaderClosed'});
});
