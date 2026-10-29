// Actual compiled Calendar Catalog boundary. This does not open an Account,
// Credential Site, provider transport, RowRun or normally installed Source.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import * as calendar from '../../../../_build/js/release/build/connectors/calendar/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';

const limits = [16384, 1024, 16, 4, 10, 4096, 100, 4096];
const start = '2026-10-17T00:00:00.000Z';
const end = '2026-10-18T00:00:00.000Z';
const query = (ids = ['a@example.test', 'b']) =>
  checked(calendar.calendarPrepareFreeBusyQuery(ids, start, end, ...limits));
const response = () => ({kind: 'calendar#freeBusy', timeMin: start, timeMax: end,
  calendars: {b: {busy: []}, 'a@example.test': {busy: [
    {start: '2026-10-17T10:00:00+09:00', end: '2026-10-17T10:30:00.5000+09:00'},
    {start: '2026-10-17T01:00:00Z', end: '2026-10-17T01:30:00.5Z'},
  ]}}});
const project = (body, original = query(), bounds = limits) =>
  checked(calendar.calendarProjectFreeBusy(Buffer.from(JSON.stringify(body)), original, ...bounds));
const rows = page => JSON.parse(checked(calendar.calendarFreeBusyRowsWire(page,
  ['calendar_id', 'start', 'end'], 4096, 100, 8)));

test('actual Calendar bridge preserves original query and exact fixed request', () => {
  const ids = ['b', 'a@example.test'];
  const original = query(ids);
  ids.reverse();
  assert.deepEqual(JSON.parse(calendar.calendarFreeBusyRequestWire(original)), {
    timeMin: start, timeMax: end, timeZone: 'UTC', calendarExpansionMax: 2,
    items: [{id: 'b'}, {id: 'a@example.test'}],
  });
  for (const selection of [[], [''], ['a', 'a']]) assert.throws(() => query(selection));
});

test('actual Calendar projection binds original query and preserves duplicate interval occurrences', () => {
  const original = query();
  const body = response();
  const page = project(body, original);
  const expected = {calendar_id: 'a@example.test', start: '2026-10-17T01:00:00.000Z',
    end: '2026-10-17T01:30:00.500Z'};
  assert.deepEqual(rows(page), [expected, expected]);
  assert.equal(calendar.calendarFreeBusyMatchesQuery(page, original), true);
  assert.equal(calendar.calendarFreeBusyMatchesQuery(page, query()), false);
  assert.deepEqual(JSON.parse(calendar.calendarFreeBusyMetadataJson(page)), {
    responseSha256: createHash('sha256').update(JSON.stringify(body)).digest('hex'), rowCount: 2,
  });
});

test('actual Calendar complete response refuses foreign selection window and per-calendar failures', () => {
  const foreign = response(); foreign.calendars.other = foreign.calendars.b; delete foreign.calendars.b;
  assert.throws(() => project(foreign));
  const window = response(); window.timeMax = '2026-10-19T00:00:00.000Z';
  assert.throws(() => project(window));
  const partial = response(); partial.calendars.b.errors = [{reason: 'notFound'}];
  assert.throws(() => project(partial));
  const group = response(); group.groups = {group: {calendars: ['b']}};
  assert.throws(() => project(group));
});

test('actual Calendar response preserves empty source schema without inventing a key', () => {
  const body = response(); body.calendars['a@example.test'] = {};
  assert.deepEqual(rows(project(body)), []);
  assert.deepEqual(calendar.calendarFreeBusyColumnNames(), ['calendar_id', 'start', 'end']);
  assert.deepEqual(JSON.parse(checked(calendar.calendarFreeBusySchemaWire(4096, 100, 8))), {
    calendar_id: {type: 'string', nullable: false},
    start: {type: 'timestamp', nullable: false}, end: {type: 'timestamp', nullable: false},
  });
  assert.deepEqual(JSON.parse(calendar.calendarFreeBusyRelationFactsWire()), {});
  body.calendars.b.busy = null;
  assert.throws(() => project(body));
});

test('actual Calendar response never rounds an unrepresentable timestamp or hides a cell outside projection', () => {
  for (const value of ['2026-10-17T01:00:00.0000000001Z', '2026-02-29T01:00:00Z',
    '2026-10-17T01:00:00-00:00', null]) {
    const body = response(); body.calendars['a@example.test'].busy[0].start = value;
    assert.throws(() => project(body));
  }
  const body = response(); body.calendars['a@example.test'].busy[0].end = '2026-10-17T01:00:00Z';
  assert.throws(() => project(body));
});

test('actual Calendar complete projection preserves finer UTC instants and the original response', () => {
  const original = query();
  assert.equal(rows(project(response(), original)).length, 2);
  const body = response();
  body.calendars['a@example.test'].busy = [{
    start: '2026-10-17T01:00:00.0001Z', end: '2026-10-17T01:00:00.000100001Z',
  }];
  const page = project(body, original);
  assert.deepEqual(rows(page), [{calendar_id: 'a@example.test',
    start: '2026-10-17T01:00:00.0001Z', end: '2026-10-17T01:00:00.000100001Z'}]);
  assert.equal(calendar.calendarFreeBusyMatchesQuery(page, original), true);
  assert.deepEqual(JSON.parse(calendar.calendarFreeBusyMetadataJson(page)), {
    responseSha256: createHash('sha256').update(JSON.stringify(body)).digest('hex'), rowCount: 1,
  });
});

test('actual Calendar interval order compares instants across different fractional widths', () => {
  const original = query();
  const body = response();
  body.calendars['a@example.test'].busy = [{
    start: '2026-10-17T01:00:00.0001Z', end: '2026-10-17T01:30:00.500Z',
  }];
  assert.deepEqual(rows(project(body, original)), [{calendar_id: 'a@example.test',
    start: '2026-10-17T01:00:00.0001Z', end: '2026-10-17T01:30:00.500Z'}]);
  for (const interval of [
    {start: '2026-10-17T02:00:00.000Z', end: '2026-10-17T01:00:00.0001Z'},
    {start: '2026-10-17T01:00:00.001Z', end: '2026-10-17T01:00:00.0001Z'},
  ]) {
    body.calendars['a@example.test'].busy = [interval];
    assert.throws(() => project(body, original));
  }
});

test('actual Calendar bridge enforces independent response rows value and output ceilings', () => {
  for (const [index, value] of [[0, 1], [1, 3], [2, 2], [3, 1], [4, 1], [6, 5], [7, 1]]) {
    const smaller = limits.slice(); smaller[index] = value;
    assert.throws(() => project(response(), query(), smaller));
  }
  const page = project(response());
  assert.throws(() => checked(calendar.calendarFreeBusyRowsWire(page, ['missing'], 4096, 100, 8)));
  assert.throws(() => checked(calendar.calendarFreeBusyRowsWire(page, ['start', 'start'], 4096, 100, 8)));
  assert.throws(() => checked(calendar.calendarFreeBusyRowsWire(page, ['end'], 1, 100, 8)));
});
