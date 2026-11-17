// Actual transport facades with explicit nominal Core ports. These cases
// establish exact routing and alias retirement, not Source/Preview admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from './runtime-core.mjs';

const ok = value => ({$tag: 1, _0: value});
const cid = value => 'sha256:' + value.repeat(64);
function fixture() {
  const parent = {}, prepared = {}, request = {}, sourceOriginal = {}, candidate = {}, issued = {};
  const view = {}, source = {}, capacity = {}, calls = [], definitionOriginal = {name: 'run_definition', identity: cid('1'), wire: '{}'};
  const limits = {maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64, maxFields: 8, maxWork: 1000};
  const referenceLimits = {maxBytes: 16384, maxNodes: 256, maxDepth: 32, maxTextUnits: 16384};
  let available = true, onCurrent, refusal;
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'fixture metadata',
    strategyPublicationAdmit: (name, wire) => ok({name, wire, identity: cid('2')}),
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
    strategyRunEvidenceAdmit: (name, wire) => ok({name, wire, identity: cid('3')}),
    strategyRunEvidenceName: value => value.name,
    strategyRunEvidenceIdentity: value => value.identity,
    strategyRunEvidenceJson: value => value.wire,
    strategyAdmitEffectComputationPreview: () => ok({previewOriginal: true}),
    strategyAdmitCapturedEffectSourceFromCapture: () => ok(source),
    clientProgramInstalledEffectKeyedOriginal(...args) {
      assert.deepEqual(args, [parent, prepared, request]); calls.push('original'); return ok(sourceOriginal);
    },
    clientProgramEffectKeyedOriginalSourceEvidenceFacts(...args) {
      assert.deepEqual(args, [sourceOriginal, prepared, request]); calls.push('facts');
      return ok(['ref', cid('4'), cid('5'), cid('6'), 'internal', cid('7')]);
    },
    clientProgramRecoveredContentIssuerKind(...args) {
      calls.push('family'); assert.deepEqual(args, ['saved wire', 16384, 256, 32, 16384]);
      if (refusal) return {$tag: 0, _0: refusal}; return ok('connector_capture');
    },
    clientProgramRecoveredSourceContentCandidate(...args) {
      assert.deepEqual(args, [sourceOriginal, prepared, request, 'saved wire', '{"same":true}',
        16384, 256, 32, 16384]); calls.push('candidate'); return ok(candidate);
    },
    clientProgramRecoveredSourceContentConstructionCapacity(...args) {
      assert.deepEqual(args, ['saved wire', '', 16384, 256, 32, 16384, 'metadata']); calls.push('quote'); return capacity;
    },
    clientProgramCapturedContentHoldingCid(value) {
      assert.strictEqual(value, candidate); calls.push('holding'); return cid('8');
    },
    clientProgramRecoverSourceEffectCommandContent(...args) {
      assert.strictEqual(args[0], sourceOriginal); assert.strictEqual(args[1], prepared);
      assert.strictEqual(args[2], request); assert.equal(args[3].name, 'run_definition');
      assert.equal(args[4].name, 'captured_run'); assert.equal(args[5].previewOriginal, true);
      assert.equal(args[6].name, 'run_invocation'); assert.strictEqual(args[7], source);
      assert.deepEqual(args.slice(8), [cid('9'), 0, 1, 'content', candidate, issued,
        8, 1000, 1000000, 100000, 64]);
      calls.push('bind'); return ok(view);
    },
    clientProgramRecoveredSourceEffectCommandContentMatches(actual, original, owner, input, definition, captured, preview,
      member, row, name) {
      assert.strictEqual(actual, view); assert.strictEqual(original, sourceOriginal);
      assert.strictEqual(owner, prepared); assert.strictEqual(input, request);
      assert.equal(definition.name, 'run_definition'); assert.equal(captured.name, 'captured_run');
      assert.equal(preview.previewOriginal, true); assert.deepEqual([member, row, name], [0, 1, 'content']);
      onCurrent?.(); return available;
    },
    clientProgramRecoveredSourceEffectCommandContentMatchesIssued(actual, value) {
      assert.strictEqual(actual, view); return value === issued && available;
    },
    clientProgramRecoveredSourceEffectCommandContentWire(actual) {
      assert.strictEqual(actual, view); return ok('saved wire');
    },
    clientProgramRecoveredSourceEffectCommandContentRelease(actual) {
      assert.strictEqual(actual, view); calls.push('release'); available = false;
    },
  };
  const core = runtimeCore(moon), control = core.publicationControl;
  const definition = control.admit('run_definition', definitionOriginal.wire, limits);
  const captured = control.admit('captured_run', '{}', limits);
  const invocation = control.admit('run_invocation', '{}', limits);
  const authoring = control.admitRunEvidence('authoring_context', '{}', limits);
  const preview = control.admitEffectComputationPreview('{}', definition, authoring, limits);
  const artifact = control.admit('effect_source_artifact', '{}', limits);
  const sourceView = control.admitCapturedEffectSourceFromCapture(preview, 0, invocation, artifact, captured, cid('9'), limits);
  const context = {runtime: moon, value: parent, prepared, request, closed: false};
  return {core, control, moon, context, sourceOriginal, prepared, request, candidate, issued, capacity, calls, referenceLimits,
    family: () => control.recoveredContentIssuerKind('saved wire', referenceLimits),
    refuse(value) {refusal = value;}, onCurrent(value) {onCurrent = value;},
    bind(overrides = {}) {return control.recoverSourceEffectCommandContent({sourceOriginal, prepared, request,
      definition, captured, preview, invocation, source: sourceView, storeAuthorityCid: cid('9'),
      memberIndex: 0, row: 1, inputName: 'content', candidate, issued, limits, ...overrides});}};
}

test('Source recovery facades borrow only the current managed original and exact Core reference family', () => {
  const f = fixture();
  assert.strictEqual(f.control.installedEffectKeyedOriginal(f.context, f.prepared), f.sourceOriginal);
  assert.equal(f.control.effectKeyedOriginalSourceEvidenceFacts(f.sourceOriginal, f.prepared, f.request)[3], cid('6'));
  assert.equal(f.family(), 'connector_capture');
  const primary = {}; f.refuse(primary);
  assert.throws(f.family, error => error.code === 'MoonBitHostFailure' && error.cause === primary);
  for (const context of [{...f.context, closed: true}, {...f.context, runtime: {}}, {...f.context, prepared: {}}]) {
    assert.throws(() => f.control.installedEffectKeyedOriginal(context, f.prepared), /Foreign recovered Effect Source original/);
  }
  assert.deepEqual(f.calls, ['original', 'facts', 'family', 'family']);
});

test('Source recovery candidate stays on the captured facade original and refuses a copied candidate', () => {
  const f = fixture(), capture = f.core.contentCaptureControl;
  const value = capture.recoveryCandidateForEffectOriginal(f.sourceOriginal, f.prepared, f.request,
    'saved wire', '{"same":true}', f.referenceLimits);
  assert.strictEqual(value, f.candidate); assert.equal(capture.holdingCid(value), cid('8'));
  assert.throws(() => capture.holdingCid({...value}), /Foreign captured Content candidate/);
  assert.deepEqual(f.calls, ['candidate', 'holding']);
});

test('Source construction forwards the exact opaque Core quote and refuses an unavailable quote', () => {
  const f = fixture();
  assert.strictEqual(f.control.recoveredSourceContentConstructionCapacity('saved wire', '', f.referenceLimits), f.capacity);
  assert.throws(() => f.control.recoveredSourceContentConstructionCapacity('saved wire', '',
    {...f.referenceLimits, maxNodes: 0}), /Invalid recovered Source Content construction limits/);
  f.moon.clientProgramRecoveredSourceContentConstructionCapacity = () => undefined;
  assert.throws(() => f.control.recoveredSourceContentConstructionCapacity('saved wire', '', f.referenceLimits),
    /Recovered Source Content construction unavailable/);
  assert.deepEqual(f.calls, ['quote']);
});

test('Source Command transport keeps the exact returned original until explicit release', () => {
  const f = fixture(), borrow = f.bind();
  assert.equal(borrow.current(), true); assert.equal(borrow.matchesIssued(f.issued), true);
  assert.equal(borrow.matchesIssued({...f.issued}), false); assert.equal(borrow.wire(), 'saved wire');
  borrow.release(); borrow.release();
  assert.equal(borrow.current(), false); assert.equal(borrow.matchesIssued(f.issued), false);
  assert.throws(() => borrow.wire(), /Recovered Source Effect Content unavailable/);
  assert.deepEqual(f.calls, ['bind', 'release']);
});

test('Source Command current callback retirement cannot hand off its prior true result', () => {
  const f = fixture(), borrow = f.bind(); f.onCurrent(() => borrow.release());
  assert.equal(borrow.current(), false); assert.equal(borrow.matchesIssued(f.issued), false);
  assert.deepEqual(f.calls, ['bind', 'release']);
});
