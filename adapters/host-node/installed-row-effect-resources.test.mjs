import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import {canonicalJson} from './local-account-config.mjs';

// The real row factory and its preparation entrances, with explicit Core and
// resource ports. Stopping before the capture Store is not physical Run or
// dispatch acceptance; the same-Host integration supplies those originals.
const cid = digit => `sha256:${digit.repeat(64)}`;
async function fixture(t, variant = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-run-resources-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const calls = [], original = Object.freeze({}), prepared = {}, compilation = {};
  const next = new Error('StopBeforeCaptureStoreOrLedger');
  const refusal = new Error('OriginalEffectRunNotCurrent');
  let current = true, expectedFacts;
  const resourcePort = {
    bindRunOriginal(facts) {
      assert.strictEqual(this, resourcePort);
      assert.strictEqual(facts, expectedFacts);
      calls.push('bind'); return original;
    },
    assertCurrent(value) {
      assert.strictEqual(this, resourcePort);
      assert.strictEqual(value, original);
      calls.push('current'); if (!current) throw refusal;
    },
    limits(value) {assert.strictEqual(value, original); return Object.freeze({});},
  };
  const unused = () => assert.fail('No physical target, authorization or dispatch');
  const moon = {
    ...variant.moon,
    strategyRemoteManagedOutputEvidenceKind: () => 'test-unused-kind',
    clientProgramEffectMemberDescriptor(value) {
      assert.strictEqual(value, prepared);
      return {$tag: 1, _0: runtimeTupleFromFields({0: 0, 1: 'effect', 2: 'create',
        3: 'connector://fixture/records', 4: 'mapping:fixture/records', 5: cid('a'), 6: {}})};
    },
    clientProgramEffectRequestScope() {calls.push('request-scope'); throw next;},
  };
  const effect = await createInstalledRowEffect({moon, environmentWire: '{}',
    connectorId: 'fixture', connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    connection: 'fixture', runtimeBundleCid: cid('b'), bindingCid: cid('c'), ledgerRoot: root,
    mappings: [{resource: 'records', mappingRef: 'mapping:fixture/records', mappingCid: cid('a'),
      body: JSON.stringify({mapping_contract_cid: cid('a'), target_ref: 'connector://fixture/records',
        minimum_approval: 'required', permission_rules: [{effect_kind: 'create', permissions: ['write']}]})}],
    site: {issueReadGrant: unused, issueEffectGrant: unused}, authorization: {authorize: unused},
    driver: {kinds: ['create'], prepareRequest: unused, requestFacts: unused,
      writeOperation: unused, send: unused, project: unused, footprint: unused},
    limits: variant.limits,
    effectResources: Object.hasOwn(variant, 'port') ? variant.port : resourcePort,
  });
  const captured = {moon, prepared, compilation, definition: {}, identity: {},
    execution: {}, checkedHost: {}, store: {}, control: {},
    previewContext: {}, unit: {stageIndex: 0, effectIds: ['effect']},
    plan: {invocation: {identity: cid('d')}}};
  const dispatch = `sha256:${createHash('sha256').update(canonicalJson({
    version: 'actql-installed-row-effect-dispatch/0.1', run_invocation_cid: cid('d'),
    effect_id: 'effect'})).digest('hex')}`;
  const recovered = {moon, recovered: {computation: {preview: {}}},
    continuation: {version: 'actql-installed-row-effect-continuation/0.1', binding_cid: cid('c'),
      program_id: 'program', stage_id: 'stage', members: [{effect_id: 'effect',
        mapping_cid: cid('a'), dispatch_request_cid: dispatch}]},
    control: {effectComputationPreviewWire: () => JSON.stringify({invocation_cid: cid('d'),
      effects: [{effect_id: 'effect', effect_kind: 'create', target: 'connector://fixture/records',
        mapping: 'mapping:fixture/records', resolved_mapping_contract_cid: cid('a')}]}),
    effectComputationPreviewLedgerIdentity() {calls.push('preview-identity'); throw next;}}};
  return {effect, moon, calls, original, next, refusal, resourcePort, captured, recovered,
    expect(value) {expectedFacts = value;}, revoke() {current = false;}};
}

test('capture binds its original Run before capture Store or target work', async t => {
  const f = await fixture(t); f.expect(f.captured);
  await assert.rejects(f.effect.prepareCaptured(f.captured), cause => cause === f.next);
  assert.deepEqual(f.calls, ['bind', 'current', 'request-scope']);
});

test('capture current refusal never reaches capture Store or request scope', async t => {
  const f = await fixture(t); f.expect(f.captured); f.revoke();
  await assert.rejects(f.effect.prepareCaptured(f.captured), cause => cause === f.refusal);
  assert.deepEqual(f.calls, ['bind', 'current']);
});

test('recovery binds the validated recovered original before Ledger work', async t => {
  const f = await fixture(t); f.expect(f.recovered);
  assert.throws(() => f.effect.prepareRecovered(f.recovered), cause => cause === f.next);
  assert.deepEqual(f.calls, ['bind', 'current', 'preview-identity']);
  f.calls.length = 0; f.revoke();
  assert.throws(() => f.effect.prepareRecovered(f.recovered), cause => cause === f.refusal);
  assert.deepEqual(f.calls, ['bind', 'current']);
});

test('resource methods retain their original receiver and successful capture', async t => {
  const f = await fixture(t); f.expect(f.captured);
  f.resourcePort.bindRunOriginal = () => assert.fail('Replacement bind');
  f.resourcePort.assertCurrent = () => assert.fail('Replacement current');
  await assert.rejects(f.effect.prepareCaptured(f.captured), cause => cause === f.next);
  assert.deepEqual(f.calls, ['bind', 'current', 'request-scope']);
});

test('a resource accessor is not invoked or silently treated as an absent service', async t => {
  let reads = 0;
  const port = {get bindRunOriginal() {reads++; return () => ({});},
    assertCurrent() {}, limits() {return {};}};
  await assert.rejects(fixture(t, {port}), {code: 'InstalledEffectResourcesUnavailable'});
  assert.equal(reads, 0);
});


test('managed recovery derives its shared row ceiling from the same current Plan, preserving explicit tighter bounds', async t => {
  for (const [rows, supplied, expected, members = 1] of [[101, undefined, 101], [501, undefined, 501],
    [101, 100, 100], [0, undefined, 0], [60, undefined, 120, 2],
    [2147483647, undefined, 2147483647, 2]]) {
    const plan = {}, value = {}, prepared = {}, request = {}, events = [];
    let active = false;
    const f = await fixture(t, {limits: supplied === undefined ? {} : {maxRows: supplied}, moon: {
      clientProgramInstalledEffectManagedPlanShape(selected) {
        assert.strictEqual(this, f.moon); assert.strictEqual(selected, plan); assert.equal(active, false);
        events.push('shape'); return runtimeTupleFromFields({0: rows, 1: members, 2: 1});
      },
      clientProgramInstalledEffectManagedOperationPlan() {events.push('current'); return {$tag: 1, _0: plan};},
      clientProgramInstalledEffectManagedPlanHasHostInput() {return false;},
      clientProgramInstalledEffectOperationControlConstructionBegin(p, original, identity, selected) {
        assert.deepEqual([p, original, identity, selected], [value, prepared, request, plan]);
        assert.equal(active, false); active = true; events.push('begin'); return {$tag: 1, _0: undefined};
      },
      clientProgramInstalledEffectOperationControlConstructionComplete() {
        assert.equal(active, true); active = false; events.push('complete'); return {$tag: 1, _0: undefined};
      },
      strategyEffectRecoveredPreviewKeys(_preview, _scope, _members, actualRows, work) {
        assert.equal(actualRows, expected); assert.equal(work, 10000);
        assert.equal(active, false); throw f.next;
      },
    }});
    const managed = {runtime: f.moon, value, prepared, request, operationPlan: plan,
      readPlan: f.moon.clientProgramInstalledEffectManagedOperationPlan, closed: false, selecting: false};
    const work = prepareInstalledEffectControlConstruction(managed);
    managed.controlConstruction = work; managed.retireControlConstruction = work.retire;
    f.recovered.managedEffect = managed;
    f.recovered.control.effectComputationPreviewLedgerIdentity = () => ({});
    f.expect(f.recovered);
    assert.throws(() => f.effect.prepareRecovered(f.recovered), error => error === f.next);
    assert.deepEqual(events, ['current', 'shape', 'current']);
    assert.equal(work.retire(), true);
  }
});
