import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {createInstalledOpenAIChatRegistration} from './index.mjs';
import {originalMaterialsConfiguration as configuration} from './original-materials.fixture.mjs';

const functions = [
  'clientProgramStartOpenAIChatProjection', 'clientProgramAdvanceOpenAIChatProjection',
  'clientProgramRetireOpenAIChatProjection', 'clientProgramInstallAsyncModelProvider',
  'clientProgramModelRequestGeneration', 'clientProgramModelRequestPreflight',
  'clientProgramModelAsyncPhysicalRequestPlan', 'clientProgramModelPhysicalCallForRequest',
  'clientProgramModelPhysicalPending', 'clientProgramModelPhysicalUnknown',
  'clientProgramModelPhysicalSavedChat',
];
function borrowedSelection(original) { return () => original.available; }
function fixture(refusal) {
  const config = configuration();
  const original = Object.freeze({available: true});
  config.originalMaterials.rawCaptureSelection.selectionAvailable = borrowedSelection(original);
  const references = {
    config: new WeakRef(config), materials: new WeakRef(config.originalMaterials),
    selection: new WeakRef(original),
  };
  const profile = Object.freeze({original: 'runtime-owned-double'});
  const calls = {profile: 0, policy: 0, transport: 0};
  const moon = Object.fromEntries(functions.map(name => [name, () =>
    assert.fail('No Model, SDK, transport, Entry or physical allocation')]));
  moon.clientProgramReadModelResponseProfile = () => {
    calls.profile++;
    return refusal === 'profile' ? {$tag: 0, _0: {}} : {$tag: 1, _0: profile};
  };
  moon.clientProgramAdmitEffectDependencyBody = () => {
    calls.policy++;
    return refusal === 'policy' ? {$tag: 0, _0: {}} : {$tag: 1, _0: Object.freeze({})};
  };
  moon.clientProgramModelResponseProfileTransportMatches = actual => {
    calls.transport++;
    assert.strictEqual(actual, profile);
    return refusal !== 'transport';
  };
  return {references, profile, calls, moon, register: createInstalledOpenAIChatRegistration(config)};
}

async function collected(reference) {
  assert.equal(typeof global.gc, 'function', 'Use the selected --expose-gc Node recipe');
  for (let i = 0; i < 24; i++) {
    await turn();
    global.gc();
    await turn();
    if (reference.deref() === undefined) return true;
  }
  return false;
}

// Reachability only: neither collection nor dropping one alias establishes a
// physical heap bound, native retirement, Store ACK, funding or public Run.
test('material snapshot does not retain the caller containers before Host registration',
  {timeout: 5000}, async () => {
    const f = fixture();
    assert.equal(await collected(f.references.config), true);
    assert.equal(await collected(f.references.materials), true);
    const [entry] = f.register(f.moon);
    assert.strictEqual(entry.rawCaptureSelection.profile, f.profile);
    assert.equal(entry.rawCaptureSelection.selectionAvailable(), true);
    assert.deepEqual(f.calls, {profile: 1, policy: 4, transport: 1});
    assert.throws(() => f.register(f.moon), {code: 'OpenAIOriginalInstallationReused'});
  });

test('spent material admission refuses retry and retires only its unused snapshot aliases',
  {timeout: 5000}, async () => {
    for (const refusal of ['profile', 'policy', 'transport']) {
      const f = fixture(refusal);
      assert.throws(() => f.register(f.moon), {code: refusal === 'transport'
        ? 'OpenAIOriginalTransportLimitsMismatch' : 'OpenAIOriginalMaterialsRefused'});
      const calls = {...f.calls};
      assert.throws(() => f.register(f.moon), {code: 'OpenAIOriginalInstallationReused'});
      assert.deepEqual(f.calls, calls, 'A spent callback never repeats admission');
      assert.equal(await collected(f.references.selection), true,
        `The refused ${refusal} loader must not retain an unused selection callback`);
    }
  });

test('missing runtime leaves the original snapshot available for its first actual Host',
  {timeout: 5000}, async () => {
    const f = fixture();
    assert.throws(() => f.register(null), {code: 'OpenAIOriginalRuntimeUnavailable'});
    assert.deepEqual(f.calls, {profile: 0, policy: 0, transport: 0});
    await turn(); global.gc(); await turn();
    assert.ok(f.references.selection.deref(), 'Not entered: the original snapshot remains required');
    const [entry] = f.register(f.moon);
    assert.equal(entry.rawCaptureSelection.selectionAvailable(), true);
    assert.ok(f.references.selection.deref(), 'The actual installed entry still owns its callback');
    assert.throws(() => f.register({...f.moon}), {code: 'OpenAIOriginalInstallationReused'});
  });
