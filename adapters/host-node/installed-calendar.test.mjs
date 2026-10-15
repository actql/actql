import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {snapshotInstalledCalendar, installedCalendarIdentity, installedCalendarIdentityCid,
  installedCalendarSelection, admitInstalledCalendar} from './installed-calendar.mjs';
import {calendarSourceArtifact, calendarSourceSelection, calendarSourceArtifactLimits}
  from '../../scripts/fixtures/calendar-source-input.mjs';

const original = () => ({selection: {...calendarSourceSelection},
  // File framing is removed explicitly by this fixture supplier. Admission
  // receives the exact original canonical body and performs no normalization.
  tableBytes: Buffer.from(calendarSourceArtifact.slice(0, -1)),
  limits: {...calendarSourceArtifactLimits}, maxSelectionWork: 10000});

test('omitted Calendar installation retains the original environment without enabling a profile', () => {
  const environment = Object.freeze({original: true});
  assert.equal(snapshotInstalledCalendar(undefined), undefined);
  assert.equal(installedCalendarIdentity(undefined), undefined);
  assert.equal(installedCalendarSelection(undefined), undefined);
  assert.equal(admitInstalledCalendar({}, environment, undefined), environment);
});

test('Calendar installation snapshots exact original bytes metadata and finite limits', () => {
  const value = original(), bytes = Buffer.from(value.tableBytes);
  const selected = snapshotInstalledCalendar(value);
  value.tableBytes.fill(0); value.selection.tzdb_version = 'changed';
  value.limits.max_work = 1; value.limits.max_bytes = 0;
  value.maxSelectionWork = 0;
  assert.deepEqual(installedCalendarSelection(selected), calendarSourceSelection);
  assert.deepEqual(selected.limits, calendarSourceArtifactLimits);
  assert.equal(selected.maxSelectionWork, 10000);
  assert.equal(selected.artifactBytesCid,
    `sha256:${createHash('sha256').update(bytes).digest('hex')}`);
  assert.equal(selected.artifactBytesCid, calendarSourceSelection.table_bytes_cid);
  assert(Object.isFrozen(selected)); assert(Object.isFrozen(selected.selection));
  assert(Object.isFrozen(selected.limits));
  const originalEnvironment = {}, admittedEnvironment = {};
  let calls = 0;
  const moon = {clientProgramCheckEnvironmentWithCalendarArtifact(...args) {
    calls += 1; assert.equal(args[0], originalEnvironment);
    assert.deepEqual(Buffer.from(args[1]), bytes);
    assert.deepEqual(args.slice(2), [1000, 100, 8, 1, 0, 10000]);
    return admittedEnvironment;
  }};
  assert.equal(admitInstalledCalendar(moon, originalEnvironment, selected), admittedEnvironment);
  assert.equal(calls, 1);
});

test('Calendar snapshot rejects incomplete extra and nonfinite installation shapes before admission', () => {
  const fixtures = [null, {}, {...original(), extra: true},
    {...original(), tableBytes: 'text'}, {...original(), tableBytes: [1]},
    {...original(), maxSelectionWork: Infinity}, {...original(), maxSelectionWork: -1},
    {...original(), limits: {...calendarSourceArtifactLimits, max_nodes: 0.5}},
    {...original(), limits: {...calendarSourceArtifactLimits, extra: 1}},
    {...original(), limits: {...calendarSourceArtifactLimits, max_bytes: 1}},
    {...original(), selection: {...calendarSourceSelection, table_bytes_cid: 'old'}},
    {...original(), selection: {...calendarSourceSelection, extra: 'wrong'}}];
  for (const value of fixtures) assert.throws(() => snapshotInstalledCalendar(value),
    {name: 'TypeError', message: 'InvalidInstalledCalendar'});
});

test('Calendar semantic refusal remains owned by the original artifact admission API', () => {
  const selected = snapshotInstalledCalendar(original()), environment = {};
  let calls = 0;
  assert.throws(() => admitInstalledCalendar({clientProgramCheckEnvironmentWithCalendarArtifact(value) {
    calls += 1; assert.equal(value, environment); return undefined;
  }}, environment, selected), {name: 'TypeError', message: 'InvalidInstalledCalendar'});
  assert.equal(calls, 1);
  assert.throws(() => admitInstalledCalendar({}, environment, selected),
    {name: 'TypeError', message: 'InvalidInstalledCalendar'});
  assert.throws(() => admitInstalledCalendar({}, environment, {...selected}),
    {name: 'TypeError', message: 'InvalidInstalledCalendar'});
});

test('Calendar installation identity binds actual bytes and budgets without claiming semantic validity', () => {
  const value = original(), first = snapshotInstalledCalendar(value);
  value.tableBytes[0] ^= 1;
  const changed = snapshotInstalledCalendar(value);
  assert.notEqual(installedCalendarIdentity(first).artifactBytesCid,
    installedCalendarIdentity(changed).artifactBytesCid);
  assert.deepEqual(first.selection, changed.selection);
  assert.throws(() => installedCalendarIdentity({...first}),
    {name: 'TypeError', message: 'InvalidInstalledCalendar'});
  const narrowed = snapshotInstalledCalendar({...original(), maxSelectionWork: 1});
  assert.equal(narrowed.artifactBytesCid, first.artifactBytesCid);
  assert.notDeepEqual(installedCalendarIdentity(narrowed), installedCalendarIdentity(first));
});

test('Calendar semantic metadata identity keeps composed and decomposed values distinct', () => {
  const first = original();first.selection.tzdb_version='e\u0301';
  const second = original();second.selection.tzdb_version='é';
  const a = snapshotInstalledCalendar(first), b = snapshotInstalledCalendar(second);
  assert.equal(a.artifactBytesCid,b.artifactBytesCid);
  assert.notEqual(installedCalendarIdentityCid(a),installedCalendarIdentityCid(b));
  assert.equal(installedCalendarSelection(a).tzdb_version,'e\u0301');
  assert.equal(installedCalendarSelection(b).tzdb_version,'é');
});
