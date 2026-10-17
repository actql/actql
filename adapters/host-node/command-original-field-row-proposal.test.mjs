import assert from 'node:assert/strict';
import test from 'node:test';
import {moon} from './fixtures/command-original-key.fixture.mjs';
import {originalFieldCommandKeyFixture} from './fixtures/command-original-field-key.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {exportPinnedEffectLocalResult} from './effect-input-export.mjs';
import {advanceEffectCommandKey, retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';

// Actual Common, RowRun ReferenceIssuer, managed Local Result, full key and
// nonempty row projection. Admission policy is an explicit fixture; this does
// not issue an installed target, authenticated Preview, apply or normal funding.
function originalLocal(f) {
  const indexes = [];
  for (let index = 0; index < moon.clientProgramEffectLocalResultCount(f.inputs); index++) {
    if (moon.clientProgramEffectLocalResultMatchesMember(f.inputs, index, 0)) indexes.push(index);
  }
  assert.equal(indexes.length, 1);
  return indexes[0];
}
const close = scope => scope === undefined ? undefined : retireEffectCommandKeyWorkspace(() =>
  checked(moon.clientProgramCloseEffectCommandKeyWorkspace(scope)));
function start(runtime, scope) {
  try { return checked(runtime.clientProgramStartEffectCommandKeyWorkspace(scope)); }
  finally { runtime.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(scope); }
}

test('actual original Local key and issued Reference project the exact nonempty Command row', async () => {
  const f = await originalFieldCommandKeyFixture();
  let scope, key, proposal;
  const rows = [], pieces = [];
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(f.owned,
      f.inputs, 0, f.limits, 10000));
    const summary = await exportPinnedEffectLocalResult({moon, execution: f.execution,
      inputs: f.inputs, resultIndex: originalLocal(f), memberIndex: 0,
      limits: f.limits, commandWorkspace: scope,
      async prepareProposal() {
        assert.equal(pieces.length, 0);
        key = start(moon, scope);
        await advanceEffectCommandKey(moon, key, undefined, 1);
        proposal = checked(moon.clientProgramEffectProposalBeginWithKey(
          f.inputs, 0, 10, 10000, key));
      },
      canonicalRowLimits: {maxNodes: 10000, maxDepth: 64, maxUtf16Units: 100000},
      onCanonicalRow(index, row) {
        assert(proposal);
        const projected = checked(moon.clientProgramEffectProposalRow(
          proposal, row, index, 10, 10000, 100000, 10000, 64));
        rows.push({index, target: JSON.parse(runtimeField(projected, 0)),
          input: JSON.parse(runtimeField(projected, 1))});
      },
      onChunk(piece) { assert(key); pieces.push(piece); },
    });
    checked(moon.clientProgramEffectProposalFinish(proposal, summary.rowCount));
    proposal = undefined;
    assert.equal(summary.rowCount, 1);
    assert.deepEqual(rows, [{index: 0, target: f.rows[0].resource,
      input: {id: 'one', value: 'original'}}]);
    assert.deepEqual(JSON.parse(pieces.join('')), f.rows);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), true);
    const retained = checked(moon.clientProgramEffectProposalBeginWithKey(
      f.inputs, 0, 10, 10000, key));
    moon.clientProgramEffectProposalCancel(retained);
    await close(scope);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
    assert.throws(() => checked(moon.clientProgramEffectProposalBeginWithKey(
      f.inputs, 0, 10, 10000, key)), {code: 'MoonBitHostFailure'});
  } finally {
    if (proposal !== undefined) moon.clientProgramEffectProposalCancel(proposal);
    await close(scope); await f.close();
  }
});

test('actual duplicate original IDs finish no key and emit no Command row or payload', async () => {
  const f = await originalFieldCommandKeyFixture({duplicate: true});
  let scope, starts = 0, keys = 0, rows = 0, chunks = 0;
  const runtime = {...moon, clientProgramStartEffectCommandKeyWorkspace(...args) {
    starts++;
    return moon.clientProgramStartEffectCommandKeyWorkspace(...args);
  }};
  try {
    scope = checked(moon.clientProgramPlanEffectCommandKeyWorkspace(f.owned,
      f.inputs, 0, f.limits, 10000));
    await assert.rejects(exportPinnedEffectLocalResult({moon: runtime,
      execution: f.execution, inputs: f.inputs, resultIndex: originalLocal(f),
      memberIndex: 0, limits: f.limits, commandWorkspace: scope,
      async prepareProposal() {
        const key = start(runtime, scope);
        await advanceEffectCommandKey(runtime, key, undefined, 1);
        keys++;
      },
      canonicalRowLimits: {maxNodes: 10000, maxDepth: 64, maxUtf16Units: 100000},
      onCanonicalRow() { rows++; }, onChunk() { chunks++; },
    }), {code: 'MoonBitHostFailure'});
    assert.equal(starts, 1, 'the actual duplicate algorithm was reached');
    assert.equal(keys, 0); assert.equal(rows, 0); assert.equal(chunks, 0);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), true);
    await close(scope);
    assert.equal(moon.clientProgramEffectCommandKeyWorkspacePending(scope), false);
  } finally { await close(scope); await f.close(); }
});
