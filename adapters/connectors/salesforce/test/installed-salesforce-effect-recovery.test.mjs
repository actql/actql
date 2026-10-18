// Recovery through the normal installed Row Effect, independent of the
// separate JSON literal identity corpus exercised by installed-row-json tests.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {accountConfiguration, effectHost, effectProgram, installedEffect,
  recordEntry} from './installed-salesforce-effect.fixture.mjs';

const writesOf = org => org.seen.filter(item => item.method === 'PATCH' ||
  item.method === 'POST');
const ids = ['a00000000000001', 'a00000000000002'];
const update = {resource: 'Test_Record__c', kind: 'update', fields: ['Name']};

function updateProgram(mappings, rows = ids.map(id => ({id}))) {
  return effectProgram(Object.fromEntries(mappings.map((mapping, index) =>
    [index === 0 ? 'save' : `save_${index}`, {update: {
      target: mapping.target, mapping: mapping.mappingRef,
      from: {result: 'rows'}, id: 'id', set: {Name: {field: 'id'}}}}])),
  rows);
}

// A Host that stops right after the first row's applied outcome is durable:
// the second row's dispatch is refused before it claims or sends anything.
const stopAfterFirstRow = stage => ({...stage, apply: {...stage.apply,
  bindDispatch: binding => {
    const dispatch = stage.apply.bindDispatch(binding);
    let rows = 0;
    return async row => {
      if (++rows === 2) {
        throw Object.assign(new Error('HostStoppedAfterFirstRow'),
          {code: 'HostStoppedAfterFirstRow'});
      }
      return dispatch(row);
    };
  }}});

test('a restart after a partial apply sends only the unsent rows',
  async t => {
    // A stateful org: the first PATCH changes the stored record, so a later
    // target read observes the change this Set itself made.
    const installation = await installedEffect(t, {writes: [update],
      org: {statefulRecords: true}});
    const state = join(installation.root, 'host');
    const first = await effectHost(t, installation, state,
      {wrapStage: stopAfterFirstRow});
    const stopped = await first.run(updateProgram(first.installed.mappings),
      'partial-resume').then(() => undefined, error => error);
    assert.equal(stopped?.code, 'HostStoppedAfterFirstRow',
      String(stopped?.code));
    // Exactly the first row was sent and applied.
    const firstWrites = writesOf(installation.org);
    assert.deepEqual(firstWrites.map(item => [item.path.split('/').at(-1),
      item.body]), [['a00000000000001', '{"Name":"a00000000000001"}']]);
    assert.deepEqual(installation.org.records().map(record => record.Name),
      ['a00000000000001', 'record-2', 'record-3']);
    const {stage} = first.outcomes[0];
    const continuation = JSON.parse(stage.continuationWire);
    const runDefinitionCid = stopped.accepted.ref.runDefinitionCid;
    await first.close();
    // Restart: the applied row is not resent; the unchanged unsent row
    // continues and the Set publishes.
    const second = await effectHost(t, installation, state);
    const resumed = await second.resume('partial-resume', runDefinitionCid,
      continuation).then(value => value, error => ({error}));
    assert.equal(resumed.error, undefined,
      `${resumed.error?.code}: ${resumed.error?.message}`);
    assert.equal(resumed.result.status, 'published');
    assert.deepEqual(writesOf(installation.org).map(item =>
      item.path.split('/').at(-1)), ['a00000000000001', 'a00000000000002']);
    assert.deepEqual(installation.org.records().map(record => record.Name),
      ['a00000000000001', 'a00000000000002', 'record-3']);
  });

// Stop after the first applied row, then restart with `resume` options.
async function partiallyApplied(t, requestId, org = {}) {
  const installation = await installedEffect(t, {writes: [update],
    org: {statefulRecords: true, ...org}});
  const state = join(installation.root, 'host');
  const first = await effectHost(t, installation, state,
    {wrapStage: stopAfterFirstRow});
  const stopped = await first.run(updateProgram(first.installed.mappings),
    requestId).then(() => undefined, error => error);
  assert.equal(stopped?.code, 'HostStoppedAfterFirstRow',
    String(stopped?.code));
  const continuation = JSON.parse(first.outcomes[0].stage.continuationWire);
  await first.close();
  return {installation, state, continuation,
    runDefinitionCid: stopped.accepted.ref.runDefinitionCid};
}

test('after a partial apply, an unsent row changed outside is refused before sending',
  async t => {
    const {installation, state, continuation, runDefinitionCid} =
      await partiallyApplied(t, 'partial-stale');
    // The unsent second row changed outside ActQL while the Host was down.
    installation.org.setRecord('a00000000000002', {Name: 'changed-outside'});
    const second = await effectHost(t, installation, state);
    const failure = await second.resume('partial-stale', runDefinitionCid,
      continuation).then(() => undefined, error => error);
    // Refused for the changed unsent row (row 1), not for the row this Set
    // already applied (row 0).
    // The common guard issue: Guard(Current(StalePreview(member, row))).
    const stale = failure?.cause?._0?._0;
    assert.deepEqual([stale?._0, stale?._1], [0, 1], String(failure?.code));
    assert.equal(writesOf(installation.org).length, 1);
    assert.equal(installation.org.records()[1].Name, 'changed-outside');
  });

test('after a partial apply, a revoked commit sends nothing more',
  async t => {
    const {installation, state, continuation, runDefinitionCid} =
      await partiallyApplied(t, 'partial-denied');
    // Same installation; the account now denies the Effect commit.
    const second = await effectHost(t, installation, state, {
      effect: await installation.load({accountConfigurationWire:
        accountConfiguration([recordEntry(installation.org.orgId, 'read'),
          recordEntry(installation.org.orgId, 'effect', 'deny')])})});
    const failure = await second.resume('partial-denied', runDefinitionCid,
      continuation).then(() => undefined, error => error);
    assert.equal(failure?.authorization?.action ?? failure?.code, 'deny',
      String(failure?.code));
    assert.equal(writesOf(installation.org).length, 1);
  });

test('an unknown row is never resent after a restart', async t => {
  // The org applies the first write and its reply is lost: the row is
  // unknown and, under halt, nothing more is sent.
  const installation = await installedEffect(t, {writes: [update],
    org: {statefulRecords: true, loseReplyAfterApply: [1]}});
  const state = join(installation.root, 'host');
  const first = await effectHost(t, installation, state);
  const started = await first.run(updateProgram(first.installed.mappings),
    'partial-unknown').then(value => value, error => ({error}));
  const continuation = JSON.parse(first.outcomes[0].stage.continuationWire);
  const runDefinitionCid = (started.accepted ?? started.error.accepted).ref
    .runDefinitionCid;
  assert.equal(writesOf(installation.org).length, 1);
  await first.close();
  const second = await effectHost(t, installation, state);
  const resumed = await second.resume('partial-unknown', runDefinitionCid,
    continuation).then(value => value, error => ({error}));
  assert.equal(resumed.result?.status ?? resumed.error?.code,
    'needs_reconciliation');
  assert.equal(writesOf(installation.org).length, 1);
  assert.equal(installation.org.records()[0].Name, 'a00000000000001');
});
