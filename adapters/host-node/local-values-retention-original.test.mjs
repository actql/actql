import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredEffectPublicationAdmission, keyedInputRetentionSelection,
  sourceFreeInferEffectPublicationPlan} from './local-values-plan.mjs';

// Actual JavaScript admission/selection/publication callers, with explicit
// nominal Core ports. This is not Common ABI, physical Model or Store evidence.
function fixture(start = '2026-11-12T00:00:00.000Z') {
  let at = start, reads = 0, clockFailure = false;
  const firstFailure = Object.freeze({original: 'clock'});
  let clockCause = firstFailure;
  const now = () => {reads++; if (clockFailure) throw clockCause; return at;};
  const prepared = {}, compilation = {}, allowed = {}, definition = {};
  const header = {created_at: start, valid_until: '2026-11-12T00:30:00.000Z'};
  const observation = {wire: JSON.stringify({captured_input_artifact_cids: [],
    data_policy_cid: 'model-policy'})};
  const contract = (name, wire) => Object.freeze({name, wire, identity: name});
  const moon = {
    clientProgramEffectCompilationTemplateWire(actual) {assert.equal(actual, compilation); return '{}';},
    clientProgramAllowedEffectRunPrepared(actual) {assert.equal(actual, allowed); return {};},
    clientProgramAllowedEffectRunAuthorization(actual) {assert.equal(actual, allowed); return {};},
    clientProgramEffectCompilationCompiledPlanWire(actual) {assert.equal(actual, compilation); return '{}';},
    strategyRunEvidenceJson() {return '{}';},
    strategyPublicationContractJson(actual) {assert.equal(actual, definition); return JSON.stringify(header);},
    clientProgramEffectDefinitionCid(actual) {assert.equal(actual, prepared); return 'program';},
    clientProgramEffectCompilationResultNames(actual) {assert.equal(actual, compilation); return ['result'];},
    clientProgramEffectCompilationResultTransformation(actual, owner, index) {
      assert.equal(actual, compilation); assert.equal(owner, prepared); assert.equal(index, 0);
      return {$tag: 1, _0: undefined};
    },
  };
  const control = {admitRunEvidence: contract, admit: contract, seal: contract,
    sealRunEvidence: contract, admitCheckedClientEffectRunPublication: () => ({}),
    checkedClientEffectInferInvocation(owner, compiled, run) {
      assert.equal(owner, prepared); assert.equal(compiled, compilation);
      assert.equal(run, acquired.runDefinition);
      return {observation, invocation: {}, owner: {}};
    }, compiledInferSourceFreeResultPolicy: () => ({cid: 'model-policy'})};
  const acquired = acquiredEffectPublicationAdmission({moon, control, prepared,
    compilation, allowed, definition, authorityScopeCid: 'authority', namespaceId: 'namespace',
    storeAuthorityCid: 'store', now, identity: {}});
  const publish = () => sourceFreeInferEffectPublicationPlan({acquired,
    compiled: {}, issuedModel: {}, modelEvidence: []}).plan;
  return {acquired, publish, now, firstFailure,
    advance(value) {at = value;}, failClock() {clockFailure = true;},
    failClockWithUndefined() {clockFailure = true; clockCause = undefined;},
    get reads() {return reads;}};
}

test('one admitted Effect retains its original input retention after the Model clock advances', () => {
  const f = fixture();
  assert.equal(f.reads, 0, 'admission does not move the original first selection boundary');
  const selected = keyedInputRetentionSelection(f.acquired);
  assert.equal(f.reads, 1);
  assert(Object.isFrozen(selected));
  f.advance('2026-11-12T00:05:00.000Z');
  const plan = f.publish(), body = JSON.parse(plan.effectInputRetention.wire);
  assert.equal(body.available_until, '2026-11-12T01:00:00.000Z');
  assert.equal(body.delete_by, '2026-11-12T02:00:00.000Z');
  assert.equal(body.metadata_delete_by, '2026-11-19T00:00:00.000Z');
  assert.equal(body.available_until, selected.availableUntil);
  assert.equal(body.delete_by, selected.deleteBy);
  assert.equal(body.metadata_delete_by, selected.metadataDeleteBy);
  assert.equal(body.extension_ceiling_at, selected.metadataDeleteBy);
  assert.equal(f.reads, 1, 'publication does not select another retention clock');
  assert.equal(keyedInputRetentionSelection(f.acquired), selected);
  assert.equal(plan.now, f.now, 'the live current/time clock is not frozen');
  assert.equal(plan.now(), '2026-11-12T00:05:00.000Z');
  f.failClock();
  assert.throws(() => plan.now(), error => error === f.firstFailure);
  assert.equal(keyedInputRetentionSelection(f.acquired), selected);
});

test('different admitted Effects retain independent selections without a global cache', () => {
  const first = fixture(), second = fixture('2026-11-12T00:10:00.000Z');
  const a = keyedInputRetentionSelection(first.acquired);
  const b = keyedInputRetentionSelection(second.acquired);
  assert.notEqual(a, b);
  assert.equal(a.availableUntil, '2026-11-12T01:00:00.000Z');
  assert.equal(b.availableUntil, '2026-11-12T01:10:00.000Z');
  assert.equal(first.reads, 1); assert.equal(second.reads, 1);
});

test('a failed original retention selection keeps thrown undefined and never resamples', () => {
  const f = fixture();
  f.failClockWithUndefined();
  const failsOriginal = operation => {
    let failed = false;
    try {operation();} catch (cause) {failed = true; assert.equal(cause, undefined);}
    assert.equal(failed, true);
  };
  failsOriginal(() => keyedInputRetentionSelection(f.acquired));
  assert.equal(f.reads, 1);
  failsOriginal(() => keyedInputRetentionSelection(f.acquired));
  failsOriginal(() => f.publish());
  assert.equal(f.reads, 1);
});
