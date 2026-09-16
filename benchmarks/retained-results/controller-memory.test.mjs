import test from 'node:test';
import assert from 'node:assert/strict';
import {setTimeout as delay} from 'node:timers/promises';
import {sampleControllerMemory} from './controller-memory.mjs';

const usage = n => ({rss: n, heapTotal: n, heapUsed: n, external: n, arrayBuffers: n});

test('memory sampling aggregates bounded snapshots and stops idempotently', async () => {
  let reads = 0;
  const sampler = sampleControllerMemory({intervalMs: 1, read: () => usage(++reads * 10)});
  await delay(15);
  const report = sampler.stop();
  assert.equal(report.status, 'observed');
  assert.equal(report.baseline.rss, 10);
  assert.equal(report.last.rss, reads * 10);
  assert.equal(report.observedPeak.rss, reads * 10);
  assert.equal(report.peakAboveBaseline.rss, (reads - 1) * 10);
  assert.equal(report.samples, reads);
  assert(reads >= 3);
  assert(Object.isFrozen(report.observedPeak));
  const stopped = reads;
  await delay(5);
  assert.equal(reads, stopped);
  assert.equal(sampler.stop(), report);
});

test('memory sampling retains transient peaks without summing overlapping categories', () => {
  const values = [usage(100), usage(30)];
  const report = sampleControllerMemory({read: () => values.shift()}).stop();
  assert.equal(report.observedPeak.rss, 100);
  assert.equal(report.last.rss, 30);
  assert.equal(report.peakAboveBaseline.rss, 0);
  assert.equal(report.samples, 2);
});

test('invalid or failed sampling cannot be reported as an observed memory result', () => {
  for (const intervalMs of [0, -1, 1.5, Infinity, 1001]) {
    assert.throws(() => sampleControllerMemory({intervalMs}));
  }
  assert.throws(() => sampleControllerMemory({read: () => ({rss: 1})}), /InvalidMemorySample/);
  let calls = 0;
  const sampler = sampleControllerMemory({read: () => ++calls === 1 ? usage(100) : usage(NaN)});
  assert.equal(sampler.stop().status, 'incomplete');
  assert.equal(sampler.stop().samples, 1);
  for (const reason of [undefined, null, false, 0, '']) {
    let reads = 0;
    const failed = sampleControllerMemory({read: () => {
      if (reads++) throw reason;
      return usage(100);
    }});
    assert.equal(failed.stop().status, 'incomplete');
  }
});
