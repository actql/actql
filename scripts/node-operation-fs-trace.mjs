// Optional diagnostic clock calibration, never a product startup requirement.
import assert from 'node:assert/strict';
import {access} from 'node:fs/promises';

export async function recordFilesystemClockMarker(path) {
  const beforeUs = Number(process.hrtime.bigint() / 1000n);
  await access(path);
  return {path, beforeUs, afterUs: Number(process.hrtime.bigint() / 1000n)};
}
const filesystem = event => event.cat?.split(',').includes('node.fs');
const key = event => JSON.stringify([event.pid, event.name, event.id]);

export function pairFilesystemTrace(events, pid) {
  const pairs = [], unpaired = [], asynchronous = new Map(), synchronous = new Map();
  for (const event of events.filter(row => row.pid === pid && filesystem(row))) {
    assert(Number.isFinite(event.ts));
    if (event.ph === 'b') {
      const id = key(event);
      assert(!asynchronous.has(id), 'Overlapping asynchronous trace identity');
      asynchronous.set(id, event);
    } else if (event.ph === 'e') {
      const id = key(event), begin = asynchronous.get(id);
      if (begin) {pairs.push({begin, end: event}); asynchronous.delete(id);}
      else unpaired.push({reason: 'end without begin', event});
    } else if (event.ph === 'B') {
      const stack = synchronous.get(event.tid) ?? [];
      stack.push(event); synchronous.set(event.tid, stack);
    } else if (event.ph === 'E') {
      const stack = synchronous.get(event.tid) ?? [], begin = stack.pop();
      if (begin) {
        assert.equal(begin.name, event.name, 'Synchronous trace nesting mismatch');
        pairs.push({begin, end: event});
      } else unpaired.push({reason: 'end without begin', event});
    }
  }
  for (const event of [...asynchronous.values(), ...[...synchronous.values()].flat()]) {
    unpaired.push({reason: 'begin without end', event});
  }
  for (const pair of pairs) assert(pair.begin.ts <= pair.end.ts);
  return {pairs, unpaired};
}

export function calibrateFilesystemClock(events, markers, pid) {
  assert(markers.length >= 2, 'At least two actual clock markers are required');
  const {pairs} = pairFilesystemTrace(events, pid), paths = new Set();
  const bounds = markers.map(marker => {
    assert(typeof marker.path === 'string' && !paths.has(marker.path));
    paths.add(marker.path);
    assert(Number.isFinite(marker.beforeUs) && Number.isFinite(marker.afterUs) &&
      marker.beforeUs <= marker.afterUs);
    const actual = pairs.filter(pair => pair.begin.name === 'access' &&
      pair.begin.args?.path === marker.path);
    assert.equal(actual.length, 1, 'Each marker requires one actual paired access event');
    const {begin, end} = actual[0];
    assert.equal(end.args?.result, 0, 'Clock marker access must succeed');
    return {minimumUs: marker.beforeUs - begin.ts, maximumUs: marker.afterUs - end.ts};
  });
  const minimumUs = Math.max(...bounds.map(row => row.minimumUs));
  const maximumUs = Math.min(...bounds.map(row => row.maximumUs));
  assert(minimumUs <= maximumUs, 'Actual clock observation intervals disagree');
  return {minimumUs, maximumUs, markerCount: markers.length,
    relation: 'hrtime_us = filesystem_trace_us + offset'};
}

export function attributeFilesystemOperation(events, {pid, startUs, endUs}, clock) {
  assert(Number.isFinite(startUs) && Number.isFinite(endUs) && startUs <= endUs);
  assert(Number.isFinite(clock.minimumUs) && Number.isFinite(clock.maximumUs) &&
    clock.minimumUs <= clock.maximumUs);
  const {pairs, unpaired} = pairFilesystemTrace(events, pid);
  const contained = [], boundary = [], outside = [];
  for (const pair of pairs) {
    if (pair.begin.ts + clock.minimumUs >= startUs &&
        pair.end.ts + clock.maximumUs <= endUs) contained.push(pair);
    else if (pair.end.ts + clock.maximumUs >= startUs &&
        pair.begin.ts + clock.minimumUs <= endUs) boundary.push(pair);
    else outside.push(pair);
  }
  const counts = {};
  for (const {begin} of contained) counts[begin.name] = (counts[begin.name] ?? 0) + 1;
  return {counts, contained, boundary, outside, unpaired,
    qualification: 'Completed Node filesystem API intervals only. Boundary/unpaired events remain explicit. '
      + 'Intervals include scheduling and queueing; they are not device CPU, SQLite-native fsyncs, '
      + 'MAC/hash/Account validation counts, or fsync-to-path attribution.'};
}
