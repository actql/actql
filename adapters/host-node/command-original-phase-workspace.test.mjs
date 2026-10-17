import assert from 'node:assert/strict';
import test from 'node:test';
import {moon, originalCommandKeyFixture} from './fixtures/command-original-key.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {exportPinnedEffectInput} from './effect-input-export.mjs';
import {advanceEffectCommandKey, retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';

// Actual Common/managed Host/Resource execution, with the existing explicitly
// synthetic policy evidence. Neither that evidence nor this phase establishes
// installed permission, physical Content borrowing or normal Model funding.
const pending = scope => moon.clientProgramEffectCommandKeyWorkspacePending(scope);
const close = scope => retireEffectCommandKeyWorkspace(() =>
  checked(moon.clientProgramCloseEffectCommandKeyWorkspace(scope)));
function start(scope) {
  try { return checked(moon.clientProgramStartEffectCommandKeyWorkspace(scope)); }
  finally { moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(scope); }
}

test('actual original Host assigns Command workspace before managed import and keeps it beyond temporary export', async () => {
  const fixture = await originalCommandKeyFixture();
  const {owned, execution, inputs, limits} = fixture;
  let scope, key;
  const plans = [], chunks = [];
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(owned, inputs, 0, limits, 10000));
    assert(scope);
    assert.equal(pending(scope), true);
    let prepared = false;
    const summary = await exportPinnedEffectInput({moon, execution, inputs,
      memberIndex: 0, limits, commandWorkspace: scope,
      async prepareProposal() {
        key = start(scope);
        await advanceEffectCommandKey(moon, key, undefined, 1);
        plans.push(checked(moon.clientProgramEffectProposalBeginWithKey(inputs, 0, 10, 10000, key)));
        prepared = true;
      },
      onChunk(chunk) { assert.equal(prepared, true); chunks.push(chunk); },
    });
    assert.equal(summary.rowCount, 1);
    assert.deepEqual(JSON.parse(chunks.join('')), [{id: 'one', value: 'original'}]);
    // exportPinnedEffectInput has cancelled its temporary import/receipt;
    // the original captured payload and its actual byte borrower remain.
    assert.equal(pending(scope), true);
    plans.push(checked(moon.clientProgramEffectProposalBeginWithKey(inputs, 0, 10, 10000, key)));
    for (const plan of plans.splice(0)) moon.clientProgramEffectProposalCancel(plan);
    await close(scope);
    assert.equal(pending(scope), false);
    assert.throws(() => checked(moon.clientProgramEffectProposalBeginWithKey(inputs, 0, 10, 10000, key)),
      {code: 'MoonBitHostFailure'});
    assert.throws(() => start(scope), {code: 'MoonBitHostFailure'});
    assert.equal(checked(moon.clientProgramCloseEffectCommandKeyWorkspace(scope)), true);
  } finally {
    for (const plan of plans) moon.clientProgramEffectProposalCancel(plan);
    if (scope !== undefined) await close(scope);
    await fixture.close();
  }
});

test('actual assigned key phase refuses duplicate input before bytes and retires its same borrower', async () => {
  const fixture = await originalCommandKeyFixture({rows: [
    {id: 'one', value: 'original'}, {id: 'one', value: 'different'},
  ]});
  const {owned, execution, inputs, limits} = fixture;
  let scope, chunks = 0, started = false;
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(owned, inputs, 0, limits, 10000));
    assert(scope);
    await assert.rejects(exportPinnedEffectInput({moon, execution, inputs,
      memberIndex: 0, limits, commandWorkspace: scope,
      async prepareProposal() {
        const key = start(scope); started = true;
        await advanceEffectCommandKey(moon, key, undefined, 1);
      }, onChunk() { chunks++; },
    }), {code: 'MoonBitHostFailure'});
    assert.equal(started, true);
    assert.equal(chunks, 0);
    assert.equal(pending(scope), true);
    await close(scope);
    assert.equal(pending(scope), false);
  } finally {
    if (scope !== undefined) await close(scope);
    await fixture.close();
  }
});

test('actual original phase rejects a foreign Run or member and leaves absent-key behavior explicit', async () => {
  const first = await originalCommandKeyFixture();
  const second = await originalCommandKeyFixture();
  const absent = await originalCommandKeyFixture({inputKey: false});
  let scope;
  try {
    assert.throws(() => checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
      first.owned, second.inputs, 0, first.limits, 10000)), {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
      first.owned, first.inputs, 9, first.limits, 10000)), {code: 'MoonBitHostFailure'});
    assert.equal(checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
      absent.owned, absent.inputs, 0, absent.limits, 10000)), undefined);
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
      first.owned, first.inputs, 0, first.limits, 10000));
    let chunks = 0;
    await assert.rejects(exportPinnedEffectInput({moon, execution: second.execution,
      inputs: second.inputs, memberIndex: 0, limits: second.limits,
      commandWorkspace: scope, onChunk() { chunks++; },
    }), {code: 'MoonBitHostFailure'});
    assert.equal(chunks, 0);
    await close(scope);
    assert.equal(pending(scope), false);
  } finally {
    if (scope !== undefined) await close(scope);
    await Promise.all([first.close(), second.close(), absent.close()]);
  }
});

test('refused nested synchronous preparation cannot release the outer original stack fence', async () => {
  const fixture = await originalCommandKeyFixture();
  let scope;
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
      fixture.owned, fixture.inputs, 0, fixture.limits, 10000));
    // A private synchronous caller has entered but not yet reached its
    // finally, including when the original operation refuses before import.
    assert.throws(() => checked(moon.clientProgramStartEffectCommandKeyWorkspace(scope)),
      {code: 'MoonBitHostFailure'});
    assert.equal(checked(moon.clientProgramCloseEffectCommandKeyWorkspace(scope)), false);
    assert.throws(() => start(scope), {code: 'MoonBitHostFailure'});
    // The nested helper's finally must leave the OUTER entry outstanding.
    assert.equal(checked(moon.clientProgramCloseEffectCommandKeyWorkspace(scope)), false);
    moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(scope);
    await close(scope);
    assert.equal(pending(scope), false);
  } finally {
    if (scope !== undefined) {
      moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(scope);
      await close(scope);
    }
    await fixture.close();
  }
});
