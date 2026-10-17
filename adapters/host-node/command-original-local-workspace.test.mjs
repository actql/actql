import assert from 'node:assert/strict';
import test from 'node:test';
import {moon} from './fixtures/command-original-key.fixture.mjs';
import {originalFieldCommandKeyFixture} from './fixtures/command-original-field-key.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {exportPinnedEffectLocalResult} from './effect-input-export.mjs';
import {advanceEffectCommandKey, retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';

// Real Common RowRun/ReferenceIssuer/captured Run and original Local managed
// material. Policy evidence remains an explicit admission fixture, not normal
// installation, physical Content funding, authenticated approval or dispatch.
function originalLocal(f) {
  const indexes = [];
  for (let index = 0; index < moon.clientProgramEffectLocalResultCount(f.inputs); index++) {
    if (moon.clientProgramEffectLocalResultMatchesMember(f.inputs, index, 0)) indexes.push(index);
  }
  assert.equal(indexes.length, 1);
  const index = indexes[0];
  const result = moon.clientProgramEffectLocalResultAt(f.inputs, index);
  const physical = f.execution.effectPhysicalSource(moon.clientProgramEffectLocalResultTask(result));
  assert(physical, 'the original local Result has its own managed physical material');
  return {index, physical};
}
const plan = f => checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
  f.owned, f.inputs, 0, f.limits, 10000));
const close = scope => scope === undefined ? undefined : retireEffectCommandKeyWorkspace(() =>
  checked(moon.clientProgramCloseEffectCommandKeyWorkspace(scope)));
function start(scope) {
  try { return checked(moon.clientProgramStartEffectCommandKeyWorkspace(scope)); }
  finally { moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(scope); }
}
function begin(scope, f, index, physical, overrides = {}) {
  try {
    return checked(moon.clientProgramBeginEffectLocalCommandKeyWorkspace(
      scope, overrides.inputs ?? f.inputs, overrides.member ?? 0, index, f.limits,
      physical.completed, physical.material));
  } finally { moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(scope); }
}

test('same original Local Result obtains its member workspace before import and whole-key proposal', async () => {
  const f = await originalFieldCommandKeyFixture();
  let scope, key;
  const proposals = [], pieces = [];
  try {
    const {index} = originalLocal(f);
    scope = plan(f);
    assert(scope);
    const summary = await exportPinnedEffectLocalResult({moon, execution: f.execution,
      inputs: f.inputs, resultIndex: index, memberIndex: 0, limits: f.limits,
      commandWorkspace: scope,
      async prepareProposal(originalExport, importing) {
        assert(originalExport); assert(importing);
        assert.equal(pieces.length, 0);
        key = start(scope);
        await advanceEffectCommandKey(moon, key, undefined, 1);
        proposals.push(checked(moon.clientProgramEffectProposalBeginWithKey(
          f.inputs, 0, 10, 10000, key)));
      },
      onChunk(piece) { assert(key); pieces.push(piece); },
    });
    assert.equal(summary.rowCount, 1);
    assert.deepEqual(JSON.parse(pieces.join('')), f.rows);
    proposals.push(checked(moon.clientProgramEffectProposalBeginWithKey(
      f.inputs, 0, 10, 10000, key)));
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), true,
      'temporary export/import completion does not return the parent borrower');
    for (const proposal of proposals.splice(0)) moon.clientProgramEffectProposalCancel(proposal);
    await close(scope);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
    assert.throws(() => checked(moon.clientProgramEffectProposalBeginWithKey(
      f.inputs, 0, 10, 10000, key)), {code: 'MoonBitHostFailure'});
  } finally {
    for (const proposal of proposals) moon.clientProgramEffectProposalCancel(proposal);
    await close(scope); await f.close();
  }
});

test('Local workspace refuses foreign index/member/Run and original managed material substitution', async () => {
  const f = await originalFieldCommandKeyFixture();
  const foreign = await originalFieldCommandKeyFixture();
  let scope;
  try {
    const own = originalLocal(f), other = originalLocal(foreign);
    for (const invoke of [
      value => begin(value, f, own.index + 1, own.physical),
      value => begin(value, f, own.index, own.physical, {member: 1}),
      value => begin(value, f, own.index, own.physical, {inputs: foreign.inputs}),
      value => begin(value, f, own.index, other.physical),
      value => begin(value, f, own.index,
        {...own.physical, material: other.physical.material}),
    ]) {
      scope = plan(f); assert(scope);
      assert.throws(() => invoke(scope), {code: 'MoonBitHostFailure'});
      await close(scope);
      assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
      scope = undefined;
    }
  } finally { await close(scope); await foreign.close(); await f.close(); }
});

test('Local workspace does not replace a missing physical supplier with a captured-data fallback', async () => {
  const f = await originalFieldCommandKeyFixture();
  let scope;
  try {
    const {index} = originalLocal(f);
    scope = plan(f);
    let chunks = 0;
    await assert.rejects(exportPinnedEffectLocalResult({moon,
      execution: {effectPhysicalSource: () => undefined}, inputs: f.inputs,
      resultIndex: index, memberIndex: 0, limits: f.limits, commandWorkspace: scope,
      onChunk() { chunks++; }}), {message: 'EffectCommandWorkspaceUnavailable'});
    assert.equal(chunks, 0);
    await close(scope);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
  } finally { await close(scope); await f.close(); }
});
