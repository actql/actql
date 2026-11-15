import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectManagedPlanRun} from './installed-effect-managed-run.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const ok = value => ({$tag: 1, _0: value});
function fixture({changedWire = false, quoteFailure} = {}) {
  const prepared = {}, request = {}, graph = {}, acquisition = {}, allowed = {};
  const definition = {name: 'run_definition', identity: 'sha256:' + '1'.repeat(64), wire: '{"original":true}'};
  const journalView = Object.freeze({...definition, wire: changedWire ? '{"original":false}' : definition.wire});
  const calls = [], reached = new Error('original compiled continuation reached');
  const control = runtimeCore({strategyRemoteManagedOutputEvidenceKind: () => 'component metadata',
    clientProgramAllowedEffectRunAdmission(value) {assert.strictEqual(value, allowed); return {};},
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
  }).publicationControl;
  const runtime = {clientProgramEffectAcquisitionCount: () => 1,
    clientProgramEffectSingleKeyedAcquisition: value => {assert.strictEqual(value, prepared); return ok(acquisition);}};
  const publicationControl = {...control,
    originalCheckedClientEffectPublication(...args) {
      assert.equal(calls.at(-1), 'quoted-graph');
      assert.strictEqual(args[0], allowed); assert.strictEqual(args[1], definition);
      calls.push('original-view'); return control.originalCheckedClientEffectPublication(...args);
    },
    adoptCheckedClientEffectKeyedRun(value, view, selected) {
      assert.strictEqual(value, allowed); assert.strictEqual(selected, graph);
      assert.notStrictEqual(view, journalView);
      assert.equal(view.wire, definition.wire); assert.equal(view.identity, definition.identity);
      calls.push('original-compiled'); throw reached;
    }};
  const facts = Object.freeze({prepared, identity: request, compilation: {}, allowed, definition,
    queryTimePreparation: undefined, modelCompiled: undefined, runDefinition: journalView});
  return {calls, reached, run() {
    return prepareInstalledEffectManagedPlanRun({runs: new WeakMap(), liveRuns: new Set(),
      runtime, manager: {prepareEffectKeyedPlan() {
        calls.push('quoted-graph');
        if (quoteFailure !== undefined) throw quoteFailure;
        return graph;
      }},
      prepared, request, requestInput: {}, selection: {}, facts, inputs: {},
      publicationControl, assertCurrent() {}, checked: value => {assert.equal(value.$tag, 1); return value._0;}});
  }};
}

test('initial keyed preparation projects its same checked Definition after the original graph quote', () => {
  const f = fixture(); assert.throws(f.run, error => error === f.reached);
  assert.deepEqual(f.calls, ['quoted-graph', 'original-view', 'original-compiled']);
});

test('initial keyed preparation refuses changed full Definition bytes before compiled or Plan binding', () => {
  const f = fixture({changedWire: true}); assert.throws(f.run, {code: 'ForeignInstalledEffectManagedRun'});
  assert.deepEqual(f.calls, ['quoted-graph', 'original-view']);
});

test('initial keyed preparation preserves graph reservation refusal before projecting any original view', () => {
  const primary = new Error('original graph capacity refused');
  const f = fixture({quoteFailure: primary});
  assert.throws(f.run, error => error === primary);
  assert.deepEqual(f.calls, ['quoted-graph']);
});
