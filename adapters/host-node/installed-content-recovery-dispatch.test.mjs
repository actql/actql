// Actual installed Content dispatcher/children with explicit nominal ports.
// Genuine Source candidate and captured member admission are Core coverage.
import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeContentRun} from './installed-content-run.mjs';

function fixture() {
  const moon = {}, prepared = {}, request = {}, parent = {}, allowed = {}, compiled = {}, sourceOriginal = {}, quote = {};
  const calls = [], marker = new Error('same Source candidate refusal');
  const definition = {identity: 'definition', wire: '{"valid_until":"2099-01-01T00:00:00.000Z"}'};
  let family = 'connector_capture', familyFailure, nativeFailure, insideRead = false, insideNative = false, binding;
  const reference = {metadata: {content_store_id: 'local', expires_at: '2099-01-01T00:00:00.000Z',
    effective_data_policy_cid: 'caller policy', data_classification: 'caller classification',
    issuer_evidence: {content_store_cid: 'Store', workspace_scope_cid: 'scope', capture_authority_cid: 'capture'}}};
  const context = {runtime: moon, value: parent, prepared, request, closed: false};
  context.controlConstruction = (receiver, method, args, capacity) => {
    assert.strictEqual(capacity, quote); calls.push('native begin');
    if (nativeFailure) throw nativeFailure;
    insideNative = true;
    try {return Reflect.apply(method, receiver, args);}
    finally {insideNative = false; calls.push('native finish');}
  };
  const publications = {
    recoveredContentIssuerKind() {
      assert.equal(insideRead, true); calls.push('family'); if (familyFailure) throw familyFailure; return family;
    },
    recoveredSourceContentConstructionCapacity() {calls.push('quote'); return quote;},
    installedEffectKeyedOriginal(actual, owner) {
      assert.equal(insideNative, true); assert.strictEqual(actual, context); assert.strictEqual(owner, prepared);
      calls.push('original'); return sourceOriginal;
    },
    effectKeyedOriginalSourceEvidenceFacts(actual, owner, input) {
      assert.equal(insideNative, true); assert.deepEqual([actual, owner, input], [sourceOriginal, prepared, request]);
      calls.push('facts'); return ['ref', 'contract', 'schema', 'Source policy', 'internal', 'view'];
    },
    adoptCheckedClientEffectSerializationRun(actual, run) {
      assert.strictEqual(actual, allowed); assert.strictEqual(run, definition); calls.push('serialization'); return compiled;
    },
    compiledSerializationPolicy(actual) {
      assert.strictEqual(actual, compiled); return {cid: 'generated policy', wire: '{"classification":"internal"}'};
    },
  };
  const capture = {recoveryCandidateForEffectOriginal(original, owner, input, wire, bindingWire) {
    assert.equal(insideRead, true); assert.equal(insideNative, true);
    assert.deepEqual([original, owner, input], [sourceOriginal, prepared, request]);
    assert.equal(wire, JSON.stringify(reference)); binding = JSON.parse(bindingWire);
    calls.push('candidate'); throw marker;
  }};
  const run = installNodeContentRun({moon, core: {publicationControl: publications,
    contentCaptureControl: capture, contentGenerationControl: {workspaceCapacity: () => ({})}},
    namespaceId: 'local', authorityScopeCid: 'scope', storeAuthorityCid: 'Store',
    ownerPrincipal: 'actor', now: () => '2026-11-16T00:00:00.000Z', authorize: () => true});
  const captured = {}, store = {storeAuthorityCid: 'Store', status: () => ({closed: false})};
  const resources = {constructCapturedValidation(original, receiver, method, argument) {
    assert.strictEqual(original, captured); assert.equal(insideRead, false); insideRead = true;
    try {return Reflect.apply(method, receiver, [argument]);} finally {insideRead = false;}
  }};
  const options = () => ({prepared, allowed, definition, captured, store, principalId: 'actor',
    managedContext: context, memberIndex: 0, row: 0, inputName: 'content',
    referenceWire: JSON.stringify(reference), recoveryResources: resources, limits: {},
    assertCurrent() {if (context.closed) throw new Error('original retired');}});
  return {calls, marker, context, reference, compiled, run, options,
    family(value) {family = value;}, refuseFamily(value) {familyFailure = value;}, refuseNative(value) {nativeFailure = value;},
    binding: () => binding,
    child(extra = {}) {return resources.constructCapturedValidation(captured, undefined,
      () => run.prepareRecoveredCommandContent({...options(), ...extra}));}};
}

test('installed Content selects the Source Reference under the original Read and native output reservation', async () => {
  const f = fixture(), child = f.child();
  assert.equal(f.calls.includes('serialization'), false); assert.equal(f.calls.includes('candidate'), false);
  await assert.rejects(child.prepare(), error => error === f.marker);
  const binding = f.binding();
  assert.equal(binding.effective_data_policy_cid, 'Source policy'); assert.equal(binding.data_classification, 'internal');
  assert.equal(binding.capture_authority_cid, 'capture'); assert.equal(binding.content_store_id, 'local');
  assert.equal(await child.release(), true); assert.equal(child.status().pending, false);
});

test('installed Content chooses each actual Reference family even in the same mixed Program', async () => {
  const f = fixture(), source = f.child(); await source.release();
  f.family('content_derivation'); const generated = f.child(); await generated.release();
  assert.equal(f.calls.filter(value => value === 'original').length, 1);
  assert.equal(f.calls.filter(value => value === 'serialization').length, 1);
  const before = f.calls.length; const legacy = f.run.prepareRecoveredCommandContent({...f.options(), compiled: f.compiled});
  await legacy.release(); assert.equal(f.calls.length, before, 'explicit generated callers keep their original entrance');
});

test('installed Content preserves parser and funding refusals without selecting another family', () => {
  const f = fixture(), primary = new Error('strict original Ref refused'); f.refuseFamily(primary);
  assert.throws(() => f.child(), error => error === primary);
  assert.deepEqual(f.calls, ['quote', 'native begin', 'family', 'native finish']);
  const g = fixture(), refused = new Error('same native reservation refused'); g.refuseNative(refused);
  assert.throws(() => g.child(), error => error === refused);
  assert.deepEqual(g.calls, ['quote', 'native begin']);
});

test('installed Content rejects a mismatched installed namespace before creating a Source child or candidate', () => {
  const f = fixture(); f.reference.metadata.content_store_id = 'foreign';
  assert.throws(() => f.child(), /RecoveredSourceContentBindingMismatch/);
  assert.equal(f.calls.includes('candidate'), false); assert.equal(f.calls.includes('serialization'), false);
});
