import assert from 'node:assert/strict';
import test from 'node:test';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';

// Explicit Common/physical sequencing doubles. These opaque-looking tokens
// are not issued targets, keys, authenticated Preview or installed authority.
type Options = Parameters<typeof verifyPinnedEffectPlan>[0];
type Runtime = Options['moon'];
type FixtureRuntime = {
  -readonly [Name in keyof Runtime as Exclude<Name, 'clientProgramEffectPlanCancelPreparation'>]?: Runtime[Name];
} & {
  // The fixture never takes this cancellation path.
  clientProgramEffectPlanCancelPreparation(): void;
};
const ok = (value: unknown) => ({$tag: 1, _0: value});
const bounds = {maxFields: 10, maxWork: 100, maxBytes: 100,
  maxNodes: 100, maxDepth: 10, maxUtf16Units: 100};
function fixture({target, key, reject = false}: Readonly<{target: unknown; key: unknown; reject?: boolean}>) {
  const previewInputs = {}, input = {}, task = {}, completed = {}, material = {}, limits = {};
  let calls = 0, reads = 0, cancelled = 0;
  const importing = {}, preparation = {}, cursor = {}, proof = {};
  const expected = target === undefined ? key === undefined ? 'clientProgramEffectPlanImportBegin'
    : 'clientProgramEffectPlanImportBeginWithKey' : key === undefined
    ? 'clientProgramEffectPlanImportBeginWithTarget' : 'clientProgramEffectPlanImportBeginWithTargetAndKey';
  const moon: FixtureRuntime = {
    clientProgramEffectPreviewInputAt(owner, index) { assert.equal(owner, previewInputs); assert.equal(index, 0); return input; },
    clientProgramEffectInputTask(value) { assert.equal(value, input); return task as unknown as number; },
    clientProgramEffectPlanAdvance: () => ok({_0: true, _1: 1}),
    clientProgramEffectPlanReady: () => ok(cursor),
    clientProgramEffectPlanNext: () => ok(undefined),
    clientProgramEffectPlanFinish: () => ok({_0: {}, _1: '[]', _2: proof}),
    clientProgramEffectInputExportFields: () => [],
    clientProgramEffectInputExportLogicalCid: () => 'fixture-only',
    clientProgramEffectInputExportReleaseReceipt() {},
    clientProgramEffectPlanCancel() {},
    clientProgramEffectPlanCancelPreparation() {},
    clientProgramEffectPlanCancelImport(value) { assert.equal(value, importing); cancelled++; },
  };
  for (const name of ['clientProgramEffectPlanImportBegin', 'clientProgramEffectPlanImportBeginWithKey',
    'clientProgramEffectPlanImportBeginWithTarget', 'clientProgramEffectPlanImportBeginWithTargetAndKey'] as const) {
    moon[name] = function (this: typeof moon, ...args: unknown[]) {
      assert.equal(this, moon);
      assert.equal(name, expected, 'no target/key fallback');
      assert.deepEqual(args.slice(0, 7), [previewInputs, 0, completed, material, limits, 10, 100]);
      assert.equal(args[7], target === undefined ? key : target);
      if (target !== undefined && key !== undefined) assert.equal(args[8], key);
      calls++;
      return reject ? {$tag: 0, _0: 'ForeignBinding'} : ok(importing);
    };
  }
  const options: Options = {moon: moon as unknown as Runtime, previewInputs, previewIndex: 0, limits, planLimits: bounds,
    publishedTarget: target, inputKey: key, onChunk() {},
    execution: {effectPhysicalSource(value) { assert.equal(value, task); return {completed, material,
      async withRows(_append, _signal, finish) { reads++; return finish(); }}; }}};
  moon.clientProgramEffectPlanImportFinish = () => ok(preparation);
  return {options, facts: () => ({calls, reads, cancelled}), proof};
}

test('Preview import selects each existing original target/key combination without cloning or fallback', async () => {
  for (const target of [undefined, Object.freeze({})]) for (const key of [undefined, Object.freeze({})]) {
    const f = fixture({target, key});
    assert.equal((await verifyPinnedEffectPlan(f.options)).proof, f.proof);
    assert.deepEqual(f.facts(), {calls: 1, reads: 1, cancelled: 1});
  }
});

test('original target refusal happens before physical rows and never falls back to the key-only entrance', async () => {
  const f = fixture({target: Object.freeze({}), key: Object.freeze({}), reject: true});
  await assert.rejects(verifyPinnedEffectPlan(f.options), error => (error as Error & {code?: string}).code === 'MoonBitHostFailure' && (error as Error).cause === 'ForeignBinding');
  assert.deepEqual(f.facts(), {calls: 1, reads: 0, cancelled: 0});
});
