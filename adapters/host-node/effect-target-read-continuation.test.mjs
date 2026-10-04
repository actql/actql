import assert from 'node:assert/strict';
import test from 'node:test';
import {effectTargetReadContinuation} from './effect-target-read-continuation.mjs';
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
