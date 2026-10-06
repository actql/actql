import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
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
