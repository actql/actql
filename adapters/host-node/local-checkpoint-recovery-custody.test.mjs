import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createLocalCheckpointAnswer} from './local-checkpoint-answer.mjs';
import {parse} from 'acorn';

// Exact Host functions with explicit original recovery/release ports. These
// counters do not supply a Common, captured Run, Store, permission or native ACK.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}), nodes = [];
function walk(value) {
  if (value === null || typeof value !== 'object') return;
  if (typeof value.type === 'string') nodes.push(value);
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) child.forEach(walk);
    else if (child !== null && typeof child === 'object') walk(child);
  }
}
walk(tree);
const release = nodes.filter(n => n.type === 'FunctionDeclaration' && n.id.name === 'releaseLocalSigningRecovery');
const load = nodes.filter(n => n.type === 'Property' && n.key.name === 'loadRunOriginal');
assert.equal(release.length, 1); assert.equal(load.length, 1);
const code = source.slice(release[0].start, release[0].end) +
  '\nreturn {releaseLocalSigningRecovery, load: ({' + source.slice(load[0].start, load[0].end) + '}).loadRunOriginal};';

function fixture({wrongPreview = false, releaseFailure, trackResource = false} = {}) {
  const store = {}, moon = {}, localSigningRecoveries = new Set(), calls = [];
  let current = true, recoveredCount = 0, fail = releaseFailure, resourceClosed = false;
  const fence = () => {if (!current) throw new Error('Original current refusal');};
  const snapshot = {revision: 3, runDefinition: {wire: 'original-definition'}, cancellationRequested: false};
  const view = {runDefinitionCid: 'original-definition-cid', requiredArtifact: {cid: 'original-preview'}};
  const computation = {execution: null, storedResults: {}, computation: {}, preview: {}, invocation: {}};
  const recovered = {materials: {}, computation, requestIdentity: {},
    originalSubmittedIntent: {referenceWire: 'original-reference', assertCurrent: fence}};
  if (trackResource) recovered.recoveryResources = {async close() {resourceClosed = true; return true;}};
  const control = {effectComputationPreviewSemanticCid(value) {
    assert.strictEqual(value, computation.preview); return wrongPreview ? 'foreign-preview' : 'original-preview';
  }};
  const suspend = async options => {
    assert(localSigningRecoveries.has(recovered), 'custody must precede the release callback');
    assert.strictEqual(options.store, store); assert.strictEqual(options.control, control);
    for (const name of Object.keys(computation)) assert.strictEqual(options[name], computation[name]);
    calls.push(options);
    if (fail !== undefined) throw fail;
  };
  const api = new Function('store', 'control', 'localSigningRecoveries',
    'suspendCompletedEffectfulComputation', 'namespaceId', 'authorityScopeCid', 'journal', 'moon',
    'clientOperationError', 'recoverEffectCapture', 'assertProjectRuntime', 'preparation', code)(
      store, control, localSigningRecoveries, suspend, 'namespace', 'authority',
      {lookupRunDefinition() {return snapshot;}}, moon,
      code => Object.assign(new Error(code), {code}), async () => {recoveredCount++; return recovered;},
      fence, {assertResultPublicationCurrent: fence});
  return {...api, recovered, view, localSigningRecoveries, calls,
    recoveredCount: () => recoveredCount, resourceClosed: () => resourceClosed, failRelease(value) {fail = value;}, revoke() {current = false;}};
}

test('signing recovery relinquishes only its original temporary schema custody after consuming metadata', async () => {
  const f = fixture(); let observation;
  const result = await f.load(f.view, undefined, async original => {
    assert.strictEqual(original.materials, f.recovered.materials);
    assert.strictEqual(original.invocation, f.recovered.computation.invocation);
    assert(f.localSigningRecoveries.has(f.recovered)); original.assertCurrent();
    observation = original.assertCurrent; return 'original bounded answer';
  });
  assert.equal(result, 'original bounded answer');
  assert.equal(f.localSigningRecoveries.size, 0); assert.equal(f.calls.length, 1);
  assert.equal(f.recoveredCount(), 1);
  assert.throws(observation, {code: 'LocalSigningOriginalConflict'});
});

test('foreign Preview refusal still releases its already acquired original recovery', async () => {
  const f = fixture({wrongPreview: true});
  await assert.rejects(f.load(f.view, undefined, () => assert.fail('foreign Preview cannot enter consumer')), {code: 'LocalSigningOriginalConflict'});
  assert.equal(f.localSigningRecoveries.size, 0); assert.equal(f.calls.length, 1);
});

test('failed recovery release stays with the same Host and retries without reacquisition or current authority', async () => {
  const failure = new Error('Original temporary schema close failed');
  const f = fixture({wrongPreview: true, releaseFailure: failure});
  await assert.rejects(f.load(f.view, undefined, () => assert.fail('foreign Preview cannot enter consumer')), error => {
    assert.equal(error.code, 'LocalSigningCaptureCleanupPending');
    assert.equal(error.cause.code, 'LocalSigningOriginalConflict');
    assert.strictEqual(error.errors[1], failure); return true;
  });
  assert(f.localSigningRecoveries.has(f.recovered));
  f.revoke(); f.failRelease(undefined);
  await f.releaseLocalSigningRecovery(f.recovered);
  assert.equal(f.localSigningRecoveries.size, 0); assert.equal(f.calls.length, 2);
  assert.equal(f.recoveredCount(), 1);
});


test('original signing consumer stays within SAME recovered resource until its awaited work ends', async () => {
  const f = fixture({trackResource: true});
  let enter, proceed;
  const entered = new Promise(resolve => {enter = resolve;});
  const gate = new Promise(resolve => {proceed = resolve;});
  const result = Object.freeze({resolutionWire: 'bounded-original-answer'});
  const flight = f.load(f.view, undefined, async original => {
    assert.equal(original.materials, f.recovered.materials);
    assert.equal(original.invocation, f.recovered.computation.invocation);
    assert.equal(f.resourceClosed(), false);
    assert(f.localSigningRecoveries.has(f.recovered));
    enter(); await gate; original.assertCurrent(); return result;
  });
  const state = await Promise.race([entered.then(() => 'entered'), flight.then(() => 'premature-return')]);
  assert.equal(state, 'entered');
  assert.equal(f.calls.length, 0); assert.equal(f.resourceClosed(), false);
  proceed(); assert.equal(await flight, result);
  assert.equal(f.calls.length, 1); assert.equal(f.resourceClosed(), true);
  assert.equal(f.localSigningRecoveries.size, 0); assert.equal(f.recoveredCount(), 1);
});

test('actual signer keeps original recovery through key await and preserves nullable consumer failures', async () => {
  for (const primary of [null, undefined, new Error('original signing consumer failed')]) {
    const f = fixture({trackResource: true});
    let enter, proceed;
    const entered = new Promise(resolve => {enter = resolve;});
    const gate = new Promise(resolve => {proceed = resolve;});
    const unavailable = () => assert.fail('no proof/subject/native signing after original consumer refusal');
    const moon = Object.fromEntries(['clientLocalCheckpointProofPrepare', 'clientLocalCheckpointProofPreimage',
      'clientLocalCheckpointProofActor', 'clientLocalCheckpointProofSeal',
      'clientLocalCheckpointProofEffectSubject'].map(name => [name, unavailable]));
    const answer = createLocalCheckpointAnswer({moon,
      checkpoints: {journal: {localSigningRecord() {return undefined;}, transitionLocalSigningRecord: unavailable},
        async localSigningContext() {return {view: f.view, wire: 'original-context', assertCurrent() {}};}},
      mockAccount: {reviewer: {resource: 'original-reviewer'}, signingOriginal: unavailable,
        async assertSigningCurrent() {enter(); await gate; throw primary;}},
      store: {}, authorityScopeCid: 'original-authority', principalId: 'original-principal',
      metadata: {}, assertCurrent() {}, loadRunOriginal: f.load, now: () => 1});
    const flight = answer({checkpointCid: 'sha256:' + 'a'.repeat(64)}, 'rejected')
      .then(() => assert.fail('original consumer failure must reject'), cause => cause);
    await entered;
    assert.equal(f.resourceClosed(), false);
    assert(f.localSigningRecoveries.has(f.recovered));
    assert.equal(f.calls.length, 0);
    proceed(); assert.equal(await flight, primary);
    assert.equal(f.resourceClosed(), true); assert.equal(f.calls.length, 1);
    assert.equal(f.localSigningRecoveries.size, 0); assert.equal(f.recoveredCount(), 1);
  }
});
