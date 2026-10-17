import assert from 'node:assert/strict';
import test from 'node:test';
import {moon, originalCommandKeyFixture} from './fixtures/command-original-key.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {originalFieldCommandKeyFixture} from './fixtures/command-original-field-key.fixture.mjs';
import {preparePinnedEffectSourceSet} from './effect-input-export.mjs';
import {retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

// Actual Common captured inputs, managed Result, key continuation and proposals.
// The positive uses original acquisition and publication Owners. Its Store and
// the two negative publication paths remain explicit sequencing doubles, not
// physical storage, authenticated Preview, dispatch or installation evidence.
function publicationDoubles(originalControl) {
  const events = {chunks: [], writers: [], releases: 0};
  const control = {
    publicationPreparedReleaseAction(index, _count, inspected, pending, attempted) {
      return index < 0 ? 'finished' : !inspected ? 'inspect'
        : pending && !attempted ? 'release' : 'advance';
    },
    publicationCleanupOwnerAction(index, count, inspected, pending, available, attempted) {
      return index >= count ? 'finished' : !inspected ? 'inspect'
        : pending && available && !attempted ? 'retry' : 'advance';
    },
    issueEffectSourceArtifactFromExport: () => Object.freeze({identity: 'sequence-only-source', wire: '{}'}),
    issueSourceFreeLocalEffectResultArtifact: () => Object.freeze({identity: 'sequence-only-result', wire: '{}'}),
    issueLocalEffectResultManifest: () => Object.freeze({identity: 'sequence-only-manifest', wire: '{}'}),
  };
  const store = {
    storeAuthorityCid: `sha256:${'a'.repeat(64)}`,
    createPreparedObjectWriter() {
      const chunks = [];
      events.writers.push(chunks);
      let bytes = 0, pending = true;
      const release = async () => { pending = false; events.releases++; };
      return {async append(chunk) {
        chunks.push(chunk); events.chunks.push(chunk); bytes += Buffer.byteLength(chunk);
      },
        async seal(cid) { return {cid, bytes, prepared: {release, retry: release, status: () => ({pending})}}; },
        async cancel() { pending = false; }, status: () => ({reservationHeld: pending})};
    },
  };
  return {events, control: originalControl ?? control, store};
}

async function close(scope) {
  if (scope !== undefined) await retireEffectCommandKeyWorkspace(() =>
    checked(moon.clientProgramCloseEffectCommandKeyWorkspace(scope)));
}

function options(fixture, doubled, scope, onKey, onRow) {
  return {moon, checkedOwner: fixture.prepared, checkedHost: fixture.owned,
    inputs: fixture.inputs, execution: fixture.execution, limits: fixture.limits,
    commandWorkspaces: Object.freeze([scope]), onCommandKey: onKey,
    maxMembers: 1, maxGroupingWork: 100, maxBytes: 100000,
    control: doubled.control, store: doubled.store,
    sourceBindingCid: `sha256:${'b'.repeat(64)}`, invocation: {}, retention: {},
    contractLimits: {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64},
    localEvidenceContext: {admission: {}, runDefinition: {}, runInvocation: {}, observation: {}, sourceFreeDependencyClosure: true},
    proposalLimits: {maxFields: 10, maxWork: 10000, maxBytes: 100000, maxNodes: 10000, maxDepth: 64, maxUtf16Units: 100000},
    onProposalRow: onRow};
}

test('ordinary Source set finishes the original funded whole key before proposing any row', async () => {
  const fixture = await originalFieldCommandKeyFixture();
  const control = runtimeCore(moon).publicationControl;
  const doubled = publicationDoubles(control);
  let scope, key, sources;
  const rows = [];
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(fixture.owned,
      fixture.inputs, 0, fixture.limits, 10000));
    assert(scope);
    sources = await preparePinnedEffectSourceSet({...options(fixture, doubled, scope,
      (member, original) => {
        assert.equal(member, 0);
        // The preceding Unit's Result is exported before its consumer can
        // validate the key. No consumer row or payload precedes that proof.
        assert.equal(rows.length, 0);
        assert.equal(doubled.events.writers.length, 2);
        assert.equal(doubled.events.writers[1].length, 0);
        key = original;
      },
      (member, index, row) => { assert(key); rows.push([member, index, JSON.parse(row.changesWire)]); }),
      ...fixture.publicationContext(control)});
    assert.equal(rows.length, 1);
    assert.deepEqual(rows[0].slice(0, 2), [0, 0]);
    assert.equal(doubled.events.writers.length, 2);
    for (const chunks of doubled.events.writers) {
      assert.deepEqual(JSON.parse(chunks.join('')), fixture.rows);
    }
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), true,
      'temporary exporter close does not release the capture borrower');
    const plan = checked(moon.clientProgramEffectProposalBeginWithKey(fixture.inputs, 0, 10, 10000, key));
    moon.clientProgramEffectProposalCancel(plan);
    await sources.payloads[0].prepared.release();
    await close(scope);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
    assert.throws(() => checked(moon.clientProgramEffectProposalBeginWithKey(fixture.inputs, 0, 10, 10000, key)), {code: 'MoonBitHostFailure'});
  } finally {
    if (sources) await sources.payloads[0].prepared.release();
    await close(scope); await fixture.close();
  }
});

test('ordinary Source set duplicate input rejects before proposal or output and retains original cleanup', async () => {
  const fixture = await originalCommandKeyFixture({rows: [{id: 'one', value: 'first'}, {id: 'one', value: 'second'}]});
  const doubled = publicationDoubles();
  let scope, keys = 0, rows = 0;
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(fixture.owned,
      fixture.inputs, 0, fixture.limits, 10000));
    assert(scope);
    await assert.rejects(preparePinnedEffectSourceSet(options(fixture, doubled, scope,
      () => keys++, () => rows++)), {code: 'MoonBitHostFailure'});
    assert.equal(keys, 0); assert.equal(rows, 0); assert.equal(doubled.events.chunks.length, 0);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), true);
    await close(scope);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
  } finally { await close(scope); await fixture.close(); }
});


test('completed key correspondence does not invent a missing original published target', async () => {
  const fixture = await originalCommandKeyFixture();
  const doubled = publicationDoubles();
  let scope, key, rows = 0;
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(fixture.owned,
      fixture.inputs, 0, fixture.limits, 10000));
    await assert.rejects(preparePinnedEffectSourceSet(options(fixture, doubled, scope,
      (_member, original) => { key = original; }, () => rows++)), {code: 'MoonBitHostFailure'});
    assert(key, 'the original whole key completed before target projection refused');
    assert.equal(rows, 0); assert.equal(doubled.events.chunks.length, 0);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), true);
    await close(scope);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
  } finally { await close(scope); await fixture.close(); }
});
