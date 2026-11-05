import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {retainInstalledHostRuntimeFailure} from './installed-host-cleanup.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {assertEffectTargetReadBinding, effectTargetReadContinuation} from './effect-target-read-continuation.mjs';
import {effectTargetReadInventory} from './effect-target-read-inventory.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const tuple = resource => ({connection: 'crm', resource, operation: 'read'});
const inventory = () => ['Account', 'Contact', 'Account'].map((resource, index) => ({
  readTuple: tuple(resource), physicalBinding: {
    version: 'fixture-target/0.1', resource, member: index, mapping: cid(String(index + 1))},
}));
function fixture() {
  const records = [];
  const decisions = new Map();
  const current = new Map();
  const approvals = new Map();
  const events = [];
  let entered = 0;
  const checkpoints = {journal: {
    committedApprovalAt(checkpointCid) {
      const value = approvals.get(checkpointCid);
      if (value === undefined) throw Object.assign(new Error('ResolutionNotCommitted'),
        {code: 'ResolutionNotCommitted'});
      return {current: value};
    },
    completeResume(claim, {checkpoint}) { events.push(['next', claim, checkpoint]); },
  }, async inspectEffectTargetApprovals() { return records; },
  async effectTargetAuthorization(options) {
    const index = options.target.index;
    const resource = options.target.readTuple.resource;
    const scopeCid = cid(String(index + 7));
    return {scopeCid, configurationCid: cid('a'), contextCid: cid('b'),
      async authorize() {
        events.push(['authorize', resource]);
        const action = decisions.get(resource) ?? 'waiting';
        if (action === 'waiting') {
          await options.beforeDefer();
          records.push({view: {checkpointCid: `checkpoint-${index}`,
            closure: 'open', requiredArtifact: {cid: scopeCid},
            subject: {unit_id: 'effect'}}, continuation: JSON.parse(await options.continuation())});
          return {action, checkpoint: {checkpointCid: `checkpoint-${index}`}};
        }
        return {action, basis: 'account'};
      },
      async resume() { events.push(['resume', resource]);
        return {action: 'dispatch', admission: {enter() { entered++; }}}; },
      async current() {
        events.push(['current', resource]);
        return current.get(resource) ?? {action: 'unsupported',
          basis: 'delegate', reason: 'decision_function_not_configured', boundary: 'acquisition'};
      },
      close() { events.push(['close', resource]); },
    };
  }};
  const options = {checkpoints, runId: 'run', runDefinitionCid: cid('c'),
    unitId: 'effect', declaredResults: ['answer'],
    submission: {input: 'the original Program', requestId: 'request'},
    inventory: inventory(), principalId: 'owner'};
  const approve = index => { records[index].view.closure = 'resolved';
    approvals.set(records[index].view.checkpointCid, true); };
  const resume = index => ({view: records[index].view,
    continuation: records[index].continuation, claim: {intentId: `intent-${index}`},
    assertCurrent() { events.push(['fence']); }});
  return {options, records, decisions, current, approvals, events, approve, resume,
    entered: () => entered};
}

test('distinct read tuples require separate approvals before any read can dispatch', async () => {
  const f = fixture();
  const first = await effectTargetReadContinuation(f.options);
  assert.equal((await first.prepare()).checkpoint.checkpointCid, 'checkpoint-0');
  await assert.rejects(first.authorize(tuple('Account')), {code: 'EffectTargetReadNotPrepared'});
  first.close();
  f.approve(0);
  const second = await effectTargetReadContinuation({...f.options, resume: f.resume(0)});
  assert.equal((await second.prepare()).checkpoint.checkpointCid, 'checkpoint-1');
  assert.equal(f.entered(), 0);
  assert.deepEqual(f.records[1].continuation.targets.map(target =>
    [target.readTuple.resource, target.physicalBindings.length]), [['Account', 2], ['Contact', 1]]);
  second.close();
  f.approve(1);
  const third = await effectTargetReadContinuation({...f.options, resume: f.resume(1)});
  assert.deepEqual(await third.prepare(), {status: 'ready'});
  const a = checkpointApprovalFacts(await third.authorize(tuple('Account')));
  const b = checkpointApprovalFacts(await third.authorize(tuple('Contact')));
  assert.equal(a.checkpointCid, 'checkpoint-0');
  assert.equal(b.checkpointCid, 'checkpoint-1');
  a.assertCurrent(); b.assertCurrent();
  assert.equal(f.entered(), 0, 'admission is consumed only at the provider-use fence');
  a.enter(); b.enter();
  assert.equal(f.entered(), 1);
  third.close();
  assert.throws(a.assertCurrent, {code: 'EffectTargetReadOwnerClosed'});
});

test('changed target binding and changed submission refuse restart', async () => {
  const f = fixture();
  const first = await effectTargetReadContinuation(f.options);
  await first.prepare(); first.close(); f.approve(0);
  const changed = inventory(); changed[0].physicalBinding.mapping = cid('d');
  await assert.rejects(effectTargetReadContinuation({...f.options,
    inventory: changed, resume: f.resume(0)}), {code: 'EffectTargetBindingChanged'});
  await assert.rejects(effectTargetReadContinuation({...f.options,
    submission: {...f.options.submission, input: 'different'}, resume: f.resume(0)}),
  {code: 'EffectTargetBindingChanged'});
});

test('target continuation forwards the exact private authority without retaining or serializing it', async () => {
  const f = fixture();
  const authority = {toJSON() { assert.fail('Authority tokens must never be serialized'); }};
  const received = [];
  const authorize = f.options.checkpoints.effectTargetAuthorization;
  f.options.checkpoints.effectTargetAuthorization = options => {
    received.push(options.effectTargetAuthority);
    return authorize(options);
  };
  const owner = await effectTargetReadContinuation({...f.options, effectTargetAuthority: authority});
  assert.deepEqual(received, [authority, authority]);
  assert.ok(received.every(value => value === authority));
  assert.equal((await owner.prepare()).status, 'waiting_checkpoint');
  assert.equal(Object.hasOwn(owner.captureBinding(), 'effectTargetAuthority'), false);
  assert.equal(Object.hasOwn(f.records[0].continuation, 'effectTargetAuthority'), false);
  owner.close();
});

test('expired or rejected earlier target approval cannot be carried forward', async () => {
  const f = fixture();
  const first = await effectTargetReadContinuation(f.options);
  await first.prepare(); first.close(); f.approve(0);
  f.approvals.set('checkpoint-0', false);
  await assert.rejects(effectTargetReadContinuation({...f.options, resume: f.resume(0)}),
    {code: 'ApprovalExpired'});
  f.approvals.delete('checkpoint-0');
  await assert.rejects(effectTargetReadContinuation({...f.options, resume: f.resume(0)}),
    {code: 'ResolutionNotCommitted'});
  assert.equal(f.entered(), 0);
});

test('current denial and another tuple cannot use a retained target approval', async () => {
  const f = fixture();
  f.decisions.set('Contact', 'dispatch');
  const first = await effectTargetReadContinuation(f.options);
  await first.prepare(); first.close(); f.approve(0);
  const restored = await effectTargetReadContinuation({...f.options, resume: f.resume(0)});
  await restored.prepare();
  f.current.set('Account', {action: 'deny', reason: 'account_denied'});
  assert.equal((await restored.authorize(tuple('Account'))).action, 'deny');
  await assert.rejects(restored.authorize(tuple('Opportunity')), {code: 'EffectTargetBindingChanged'});
  assert.equal(f.entered(), 0); restored.close();
});

test('target inventory is immutable, bounded, and does not coalesce distinct bindings', () => {
  const original = inventory();
  const bound = effectTargetReadInventory(original);
  original[0].physicalBinding.mapping = cid('e');
  assert.equal(bound.targets[0].physicalBindings[0].mapping, cid('1'));
  assert.ok(Object.isFrozen(bound.targets[0].physicalBindings));
  assert.notEqual(effectTargetReadInventory(original).inventoryCid, bound.inventoryCid);
  assert.throws(() => effectTargetReadInventory([]), {code: 'InvalidEffectTargetReadInventory'});
  assert.throws(() => effectTargetReadInventory([{readTuple: {...tuple('Account'), operation: 'effect'},
    physicalBinding: {version: 'fixture/0.1'}}]), {code: 'InvalidEffectTargetReadInventory'});
});


const originalText = 'e\u0301\r\nline\rreturn\n' + JSON.stringify({nested: 'e\u0301'});
const exactSubmission = () => ({requestId: 'original-request',
  input: {format: 'json', text: JSON.stringify({document: originalText})},
  parameters: {text: originalText}});
const exactInventory = () => [{readTuple: tuple('Account'), physicalBinding: {
  version: 'fixture-target/0.1', nested: {text: originalText}}}];

test('target inventory retains opaque data and hashes its exact retained preimage', () => {
  const bound = effectTargetReadInventory(exactInventory());
  assert.equal(bound.targets[0].physicalBindings[0].nested.text, originalText);
  // Independently ordered envelope, not the product's encoder or CID helper.
  const preimage = JSON.stringify({targets: [{index: 0,
    physicalBindings: [{nested: {text: originalText}, version: 'fixture-target/0.1'}],
    readTuple: {connection: 'crm', operation: 'read', resource: 'Account'}}],
  version: 'actql-effect-target-read-inventory/0.1'});
  assert.equal(bound.inventoryCid,
    `sha256:${createHash('sha256').update(preimage).digest('hex')}`);
  for (const changed of [originalText.normalize('NFC'), originalText.replace(/\r\n?/gu, '\n')]) {
    const other = exactInventory(); other[0].physicalBinding.nested.text = changed;
    assert.notEqual(effectTargetReadInventory(other).inventoryCid, bound.inventoryCid);
  }
});

test('target continuation and capture retain exact submitted strings', async () => {
  const f = fixture();
  f.options.submission = exactSubmission(); f.options.inventory = exactInventory();
  const owner = await effectTargetReadContinuation(f.options);
  assert.deepEqual(owner.captureBinding().submission, exactSubmission());
  await owner.prepare(); owner.close();
  assert.deepEqual(f.records[0].continuation.submission, exactSubmission());
  assert.deepEqual(f.records[0].continuation.targets[0].physicalBindings,
    [exactInventory()[0].physicalBinding]);
});

for (const mismatch of ['submission', 'binding']) {
  test(`normalization-distinct ${mismatch} refuses target resumption before entry`, async () => {
    const f = fixture();
    f.options.submission = exactSubmission(); f.options.inventory = exactInventory();
    const first = await effectTargetReadContinuation(f.options);
    await first.prepare(); first.close(); f.approve(0);
    const current = structuredClone(f.options[mismatch === 'submission' ? 'submission' : 'inventory']);
    if (mismatch === 'submission') current.parameters.text = current.parameters.text.normalize('NFC');
    else current[0].physicalBinding.nested.text = current[0].physicalBinding.nested.text.normalize('NFC');
    let sends = 0;
    await assert.rejects(async () => {
      const owner = await effectTargetReadContinuation({...f.options,
        [mismatch === 'submission' ? 'submission' : 'inventory']: current,
        resume: f.resume(0)});
      await owner.prepare();
      owner.enterComputation();
      sends++;
    }, {code: 'EffectTargetBindingChanged'});
    assert.equal(sends, 0); assert.equal(f.entered(), 0);
  });
}

test('commit target binding comparison does not fold Unicode data', async () => {
  const f = fixture(); f.options.submission = exactSubmission();
  const owner = await effectTargetReadContinuation(f.options);
  const bound = owner.captureBinding();
  const changed = structuredClone(bound);
  changed.submission.parameters.text = changed.submission.parameters.text.normalize('NFC');
  assert.throws(() => assertEffectTargetReadBinding(changed, bound),
    {code: 'EffectTargetBindingChanged'});
  owner.close();
});


test('Effect data envelopes cannot import the configuration encoder', async () => {
  for (const path of ['effect-target-read-inventory.mjs',
    'effect-target-read-continuation.mjs', 'installed-effect-site.mjs']) {
    const source = await readFile(new URL(path, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /from ['"]\.\/local-account-config\.mjs['"]/u);
    assert.match(source, /canonicalJson as canonicalValueJson/u);
  }
});

test('the same original text remains unchanged in the existing Model envelope', () => {
  const compiled = {template: {wire: originalText}, preparedEvidence: {wire: originalText},
    authorization: {wire: originalText}, compiledPlan: {wire: originalText}};
  const saved = JSON.parse(originalModelRunWire(compiled, {wire: originalText}));
  assert.deepEqual(Object.values(saved), Array(5).fill(originalText));
});


const exactKeys = () => ({'é': 'composed', 'e\u0301': 'decomposed',
  '\r': 'CR', '\n': 'LF', '\r\n': 'CRLF'});

test('target custody preserves raw JSON keys in submission and opaque bindings', async () => {
  const f = fixture();
  f.options.submission.input = {literal: exactKeys()};
  f.options.inventory = exactInventory();
  f.options.inventory[0].physicalBinding.json = exactKeys();
  const owner = await effectTargetReadContinuation(f.options);
  await owner.prepare();
  const captured = owner.captureBinding();
  assert.deepEqual(captured.submission, f.options.submission);
  assert.deepEqual(captured.targets[0].physicalBindings,
    [f.options.inventory[0].physicalBinding]);
  assert.deepEqual(f.records[0].continuation.submission, f.options.submission);
  owner.close(); f.approve(0);
  const resumed = await effectTargetReadContinuation({...f.options, resume: f.resume(0)});
  assert.deepEqual(await resumed.prepare(), {status: 'ready'});
  assert.deepEqual(resumed.captureBinding(), captured);
  resumed.close();
});

for (const member of ['submission', 'binding']) {
  test(`legacy normalized JSON ${member} refuses resume before entering computation`, async () => {
    const f = fixture();
    const payload = {'e\u0301\r\n': 'value'};
    f.options.submission.input = {literal: payload};
    f.options.inventory = exactInventory();
    f.options.inventory[0].physicalBinding.json = payload;
    const first = await effectTargetReadContinuation(f.options);
    await first.prepare(); first.close(); f.approve(0);
    const resume = f.resume(0);
    if (member === 'submission') resume.continuation.submission.input.literal = {'é\n': 'value'};
    else resume.continuation.targets[0].physicalBindings[0].json = {'é\n': 'value'};
    await assert.rejects(effectTargetReadContinuation({...f.options, resume}),
      {code: 'EffectTargetBindingChanged'});
    assert.equal(f.entered(), 0);
  });
}

test('opaque binding identity distinguishes exact keys and ignores insertion order', () => {
  const first = exactInventory(); first[0].physicalBinding.json = exactKeys();
  const reversed = structuredClone(first);
  reversed[0].physicalBinding.json = Object.fromEntries(Object.entries(exactKeys()).reverse());
  assert.equal(effectTargetReadInventory(first).inventoryCid,
    effectTargetReadInventory(reversed).inventoryCid);
  const changed = exactInventory(); changed[0].physicalBinding.json = {'é': 'decomposed'};
  const original = exactInventory(); original[0].physicalBinding.json = {'e\u0301': 'decomposed'};
  assert.notEqual(effectTargetReadInventory(changed).inventoryCid,
    effectTargetReadInventory(original).inventoryCid);
});


// Execute the existing Host's actual read-access resume flight with explicit
// Journal/Request/claim ports. This is caller ordering and custody evidence,
// not a Common compiler, permission, physical cleanup or ordinary Run proof.
async function capturedReadResumeFixture({rejectPrepare = false, failFinish = false} = {}) {
  const source = await readFile(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const flights = [];
  const walk = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.name === 'flight' &&
        node.init?.type === 'CallExpression' && node.init.callee.type === 'ArrowFunctionExpression' &&
        source.slice(node.init.callee.start, node.init.callee.end)
          .includes('await checkpoints.runUnitReadContinuation(view)')) flights.push(node.init.callee);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(flights.length, 1);
  const events = [], captured = Object.freeze({kind: 'program', input: {original: 'authored input'}, parameters: null});
  const prepared = {}, facts = {}, accepted = {ref: {runDefinitionCid: 'same-definition'}};
  const ref = accepted.ref, claim = {}, view = {checkpointCid: 'same-checkpoint', runId: 'same-run'};
  let retainedRequest, held = false, preparing = 0, finishAttempts = 0;
  const primary = undefined, cleanupFailure = new Error('OriginalInputRetirementPending');
  const input = {finish(terminal) {
    assert.equal(this, input);assert.equal(held, true);events.push(['finish', terminal]);finishAttempts++;
    if (failFinish && finishAttempts <= 2) throw cleanupFailure;
    held = false;
  }};
  const preparation = {
    retainEffectRequestInput(runtime, request, intent, original) {
      assert.equal(runtime, moon);assert.equal(intent, undefined);assert.equal(original, captured);
      assert.equal(retainedRequest, undefined);retainedRequest = request;held = true;events.push('retain');return input;
    },
    bindSourceRequest(request, actual) {
      assert.equal(request, retainedRequest);assert.equal(actual, prepared);assert(held);events.push('bind');
    },
  };
  const moon = {}, checkpoints = {async runUnitReadContinuation(actual) {
    assert.equal(actual, view);return {version: 'target', submission: captured};
  }, journal: {
    currentResume() {return {state: 'open'};}, renewResume() {},
    admitResume(actual, options) {assert.equal(actual, claim);assert.equal(options.checkpointCid, view.checkpointCid);return {};},
    refuseUnsentReadResume() {events.push('refuse');assert(held);return {outcome: 'unknown'};},
    getRunState() {return undefined;},
  }};
  const prepareCapturedSubmission = async (request, actualRef) => {
    preparing++;assert.equal(request, retainedRequest, 'same captured Request must be retained before preparation');
    assert.equal(actualRef, ref);assert(held);events.push('prepare');if (rejectPrepare) throw primary;return prepared;
  };
  const localPreparationCustody = {
    adopt(actual, request) {assert.equal(actual, prepared);assert.equal(request, retainedRequest);events.push('adopt');return actual;},
    attach(request, actual) {assert.equal(request, retainedRequest);assert.equal(actual, prepared);request.preparedProgram = actual;events.push('attach');},
  };
  const retained = Object.freeze({kind: 'same admitted Run frame'}), control = {};
  const ports = {authorization: {}, checkpoints, view, claimed: {claim}, ref, preparation, moon, control, retained,
    localPreparationCustody, prepareCapturedSubmission,
    requestOf(request) {assert.equal(request, retainedRequest);assert.equal(request.preparedProgram, prepared);return {effectful: true};},
    inferSelections: new Map(), EFFECT_TARGET_CONTINUATION: 'target',
    admitEffectDefinition(request) {assert.equal(request, retainedRequest);assert(held);events.push('definition');return accepted;},
    effectRun: {restoreComputation(actual) {assert.equal(actual, accepted);return facts;}, reconciliation() {return undefined;}},
    async executeEffectComputation(actual, sourceResume, targetResume) {
      assert.equal(actual, facts);assert.equal(sourceResume, undefined);assert(held);targetResume.assertCurrent();events.push('execute');return {};
    },
    journal: {observeRunCancellation(actual, requestControl, publicationControl, original) {
      assert.equal(actual,ref);assert.equal(requestControl,moon);
      assert.equal(publicationControl,control);assert.equal(original,retained);
      return () => ({cancellationRequested:false});
    }},
    terminal() {return false;}, observeRun() {assert.fail('No terminal observation selected');},
    setInterval() {return {unref() {}};}, clearInterval() {events.push('clear');},
    retainInstalledHostRuntimeFailure,
  };
  const execute = compileFunction('return '+source.slice(flights[0].start, flights[0].end), Object.keys(ports))(...Object.values(ports));
  return {execute, events, primary, cleanupFailure, held: () => held, preparing: () => preparing};
}

test('actual read-access resume retains its same captured Request through preparation and dispatch', async () => {
  const f = await capturedReadResumeFixture();await f.execute();
  assert.deepEqual(f.events.filter(value => value !== 'clear'),
    ['retain', 'prepare', 'adopt', 'attach', 'bind', 'definition', 'execute', ['finish', 'returned']]);
  assert.equal(f.held(), false);assert.equal(f.preparing(), 1);
});

test('actual read-access resume keeps thrown undefined and original failed-input retirement', async () => {
  const f = await capturedReadResumeFixture({rejectPrepare: true});
  let rejected = false;
  try {await f.execute();}
  catch (cause) {rejected = true;assert.strictEqual(cause, f.primary);}
  assert.equal(rejected, true);
  assert.deepEqual(f.events.filter(value => value !== 'clear'),
    ['retain', 'prepare', 'refuse', ['finish', 'failed']]);
  assert.equal(f.held(), false);assert.equal(f.preparing(), 1);
});

test('actual read-access resume retains the same input retirement retry without preparing again', async () => {
  const f = await capturedReadResumeFixture({failFinish: true});
  let failure;
  try {await f.execute();} catch (cause) {failure = cause;}
  assert.strictEqual(failure.primaryFailure, f.cleanupFailure);
  assert.strictEqual(failure.cause, f.cleanupFailure);assert.equal(f.held(), true);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(f.held(), false);assert.equal(f.preparing(), 1);
  assert.deepEqual(f.events.filter(Array.isArray),
    [['finish', 'returned'], ['finish', 'returned'], ['finish', 'returned']]);
});

test('actual read-access settlement observes undefined without replacing its original failure', async () => {
  const source = await readFile(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const selected = [];
  const walk = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.name === 'settlement' &&
        source.slice(node.init?.start, node.init?.end).includes("diagnostic('source_resume_failed'")) selected.push(node.init);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(selected.length, 1);
  const ref = {}, key = {}, view = {runId: 'same-run'};
  const flight = Promise.reject(undefined);
  const effectResumeFlights = new Map([[key, flight]]);
  const observed = [];
  const ports = {flight, ref, key, view, effectResumeFlights,
    diagnostic(name, detail) {observed.push({name, detail});},
    checkpoints: {journal: {getRunState() {return {status: 'resuming'};}},
      sweep() {assert.fail('An unresolved original claim must not be swept');}},
  };
  const settlement = compileFunction('return '+source.slice(selected[0].start, selected[0].end),
    Object.keys(ports))(...Object.values(ports));
  await settlement;
  let rejected = false;
  try {await flight;} catch (cause) {rejected = true;assert.strictEqual(cause, undefined);}
  assert.equal(rejected, true);
  assert.deepEqual(observed, [{name: 'source_resume_failed',
    detail: {ref, code: undefined, detail: undefined, cause: undefined, missingModule: undefined}}]);
  assert.equal(effectResumeFlights.size, 0);
});
