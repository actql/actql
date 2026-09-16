import test from 'node:test';
import assert from 'node:assert/strict';
import { createRetainedRowFrames } from './row-frames.mjs';

const limits = { maxBytes: 4096, maxRows: 10, maxRowBytes: 1024, maxDepth: 10, maxFrameBytes: 4096 };

test('physical framing accepts portable byte arrays without a Node Buffer global', async () => {
  const { runInNewContext } = await import('node:vm');
  const { readFile } = await import('node:fs/promises');
  const source = await readFile(new URL('./row-frames.mjs', import.meta.url), 'utf8');
  const framed = runInNewContext(`${source.replaceAll('export ', '')}\ncreateRetainedRowFrames`,
    {Uint8Array, TextDecoder});
  const rows = [];
  const parser = framed(limits, row => rows.push(row));
  const bytes = new TextEncoder().encode('[{"name":"😀"}]');
  await parser.feed(bytes);
  assert.equal(parser.finish().bytes, bytes.length);
  assert.deepEqual(rows, ['{"name":"😀"}']);
  const invalid = framed(limits, () => assert.fail('not bytes'));
  await assert.rejects(invalid.feed([91, 93]), error => error.code === 'InvalidRowFrame');
});

test('retained rows are framed across every byte boundary without rewriting Unicode or nested values', async () => {
  const expected = ['{"K":"é😀\\\"}","k":[null,{"x":2}]}', '{"id":3}'];
  const text = `[${expected.join(',')}]`;
  const bytes = Buffer.from(text);
  for (let split = 0; split <= bytes.length; split++) {
    const received = [];
    const parser = createRetainedRowFrames(limits, (row, index) => { assert.equal(index, received.length); received.push(row); });
    await parser.feed(bytes.subarray(0, split));
    await parser.feed(bytes.subarray(split));
    assert.deepEqual(parser.finish(), { bytes: bytes.length, rows: 2 });
    assert.deepEqual(received, expected);
  }
  const empty = createRetainedRowFrames({ ...limits, maxRows: 0 }, () => assert.fail('empty row'));
  await empty.feed(Buffer.from('[]'));
  assert.equal(empty.finish().rows, 0);
});

test('row framing enforces cumulative bytes rows depth and scratch bounds before acceptance', async () => {
  for (const [override, text, code] of [
    [{ maxBytes: 3 }, '[{}]', 'RowFrameByteLimit'],
    [{ maxRows: 1 }, '[{},{}]', 'RowCountLimit'],
    [{ maxRowBytes: 2 }, '[{"x":1}]', 'RowSizeLimit'],
    [{ maxDepth: 1 }, '[{"x":[]}]', 'RowDepthLimit'],
    [{ maxFrameBytes: 1 }, '[]', 'RowFrameByteLimit'],
  ]) {
    const parser = createRetainedRowFrames({ ...limits, ...override }, () => {});
    await assert.rejects(parser.feed(Buffer.from(text)), { code });
    assert.throws(() => parser.finish(), { code: 'RowFramesClosed' });
  }
  const parser = createRetainedRowFrames({ ...limits, maxBytes: 3 }, () => {});
  await parser.feed(Buffer.from('[{}'));
  await assert.rejects(parser.feed(Buffer.from(']')), { code: 'RowFrameByteLimit' });
});

test('invalid structure UTF8 and incomplete files cannot seal a conversion', async () => {
  for (const text of ['{}', '[,]', '[{},]', '[{]}', '[{}]x', '[[]]']) {
    const parser = createRetainedRowFrames(limits, () => {});
    await assert.rejects(parser.feed(Buffer.from(text)));
  }
  for (const text of ['', '[', '[{', '[{"x":"unfinished']) {
    const parser = createRetainedRowFrames(limits, () => {});
    await parser.feed(Buffer.from(text));
    assert.throws(() => parser.finish(), { code: 'IncompleteRowArray' });
  }
  const invalid = createRetainedRowFrames(limits, () => assert.fail('invalid UTF8'));
  await assert.rejects(invalid.feed(Buffer.from([91, 123, 34, 120, 34, 58, 34, 255, 34, 125, 93])));
});

test('awaited row acceptance provides backpressure and cancellation cannot finish successfully', async () => {
  let entered, release;
  const inside = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  const controller = new AbortController();
  let calls = 0;
  const parser = createRetainedRowFrames(limits, async () => { calls++; entered(); await gate; });
  const work = parser.feed(Buffer.from('[{},{}]'), controller.signal);
  await inside;
  assert.equal(calls, 1);
  controller.abort(); release();
  await assert.rejects(work);
  assert.equal(calls, 1);
  assert.throws(() => parser.finish(), { code: 'RowFramesClosed' });
});
