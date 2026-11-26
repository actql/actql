// Optional diagnostic clock calibration, never a product startup requirement.
import assert from 'node:assert/strict';
import {access} from 'node:fs/promises';

export type FilesystemTraceEvent = {
  pid: number;
  tid: number;
  ts: number;
  name: string;
  ph: string;
  cat?: string;
  id?: string | number;
  args?: {path?: string; result?: number};
};
type TracePair = {begin: FilesystemTraceEvent; end: FilesystemTraceEvent};
type UnpairedEvent = {reason: 'end without begin' | 'begin without end'; event: FilesystemTraceEvent};
export type FilesystemClockMarker = {path: string; beforeUs: number; afterUs: number};
type ClockWindow = {minimumUs: number; maximumUs: number};
type OperationWindow = {pid: number; startUs: number; endUs: number};

export async function recordFilesystemClockMarker(path: string): Promise<FilesystemClockMarker> {
  const beforeUs = Number(process.hrtime.bigint() / 1000n);
  await access(path);
  return {path, beforeUs, afterUs: Number(process.hrtime.bigint() / 1000n)};
}
const filesystem = (event: FilesystemTraceEvent) => event.cat?.split(',').includes('node.fs');
const key = (event: FilesystemTraceEvent) => JSON.stringify([event.pid, event.name, event.id]);

export function pairFilesystemTrace(events: readonly FilesystemTraceEvent[], pid: number) {
  const pairs: TracePair[] = [], unpaired: UnpairedEvent[] = [],
    asynchronous = new Map<string, FilesystemTraceEvent>(), synchronous = new Map<number, FilesystemTraceEvent[]>();
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

export function calibrateFilesystemClock(
  events: readonly FilesystemTraceEvent[], markers: readonly FilesystemClockMarker[], pid: number,
) {
  assert(markers.length >= 2, 'At least two actual clock markers are required');
  const {pairs} = pairFilesystemTrace(events, pid), paths = new Set<string>();
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

export function attributeFilesystemOperation(
  events: readonly FilesystemTraceEvent[], {pid, startUs, endUs}: OperationWindow, clock: ClockWindow,
) {
  assert(Number.isFinite(startUs) && Number.isFinite(endUs) && startUs <= endUs);
  assert(Number.isFinite(clock.minimumUs) && Number.isFinite(clock.maximumUs) &&
    clock.minimumUs <= clock.maximumUs);
  const {pairs, unpaired} = pairFilesystemTrace(events, pid);
  const contained: TracePair[] = [], boundary: TracePair[] = [], outside: TracePair[] = [];
  for (const pair of pairs) {
    if (pair.begin.ts + clock.minimumUs >= startUs &&
        pair.end.ts + clock.maximumUs <= endUs) contained.push(pair);
    else if (pair.end.ts + clock.maximumUs >= startUs &&
        pair.begin.ts + clock.minimumUs <= endUs) boundary.push(pair);
    else outside.push(pair);
  }
  const counts: Record<string, number> = {};
  for (const {begin} of contained) counts[begin.name] = (counts[begin.name] ?? 0) + 1;
  return {counts, contained, boundary, outside, unpaired,
    qualification: 'Completed Node filesystem API intervals only. Boundary/unpaired events remain explicit. '
      + 'Intervals include scheduling and queueing; they are not device CPU, SQLite-native fsyncs, '
      + 'MAC/hash/Account validation counts, or fsync-to-path attribution.'};
}
