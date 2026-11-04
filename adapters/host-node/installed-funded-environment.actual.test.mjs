import {composeInstalledEffects} from './installed-effect-inventory.mjs';
import {loadInstalledSources} from './installed-source.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {createInstalledHostServices, retireInstalledSourceInitialization}
  from './installed-host-services.mjs';
import {composeInstalledSourceEnvironment, composeInstalledInventoryEnvironment, releaseRetiredInstalledEnvironmentComposition} from './installed-funded-environment.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';

assert.ok(process.env.ACTQL_TEST_ENVIRONMENT_RUNTIME, 'Select the matching generated Environment bridge');
const native = await import(pathToFileURL(process.env.ACTQL_TEST_ENVIRONMENT_RUNTIME));
const baseWire = readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8').trimEnd();
const ok = value => ({$tag: 1, _0: value});
function document(name) {
  const body = JSON.parse(baseWire);withFixtureConnector(body, `connector://${name}/records`);
  delete body.evidence_bundle_cid;
  return canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
}

// Actual generated wire/Environment constructors and quantities, real nominal
// Host services. Resource reservation replies are explicit component fixtures:
// these tests establish ordering/identity, not actual Root/Ledger admission.
function fixture() {
  const input = {}, unit = {}, capacity = {}, initial = {}, events = [];
  const state = {reads: 0, from: 0, retire: 0, refuse: false, cause: undefined, current: true, retireReady: true, reconciled: [], zero: new Set(), delay: undefined};
  const moon = {...native};
  for (const name of ['ReconcileInstalledSourceConstruction', 'CompleteInstalledSourceMaterial',
    'BorrowInstalledSourceMaterial', 'BorrowedInstalledSourceEnvironment', 'ReturnInstalledSourceMaterial',
    'AbortUncontinuedSourceMaterial', 'BeginInstalledSourceIo', 'ChargeInstalledSourceIo',
    'MarkInstalledSourceIoTransferUncertain', 'FinishInstalledSourceIoAfterCleanup']) moon['clientProgram' + name] = () => ok();
  Object.assign(moon, {
    clientProgramInstalledSourceConstructionCapacity(...values) {
      const result = native.clientProgramInstalledSourceConstructionCapacity(...values);
      if (values.every(value => value === 0n)) state.zero.add(result._0);
      return result;
    },
    clientProgramReconcileInstalledSourceConstruction(value, original, quote) {
      assert.equal(value, capacity); assert.equal(original, input);
      state.reconciled.push([...quote.providers]); return ok();
    },
    clientProgramTakeHostInitializationSourceCapacity(value) {assert.equal(value, initial);return ok({_0: input, _1: unit});},
    clientProgramContinueInstalledSourceMaterial(value, original) {assert.equal(value, unit);assert.equal(original, input);return ok(capacity);},
    clientProgramComposeInstalledSourceConstructionCapacity: (original, providers) => ok({original, providers}),
    clientProgramReserveInstalledSourceConstruction(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);events.push('reserve');
      if (state.refuse) throw state.cause;return ok();
    },
    clientProgramRetireInstalledSourceMaterial(value, original) {
      assert.equal(value, capacity);assert.equal(original, input);state.retire++;return ok(state.retireReady);
    },
    clientProgramReadCheckEnvironmentWire(wire, cid) {
      assert.equal(events.at(-1), 'reserve');state.reads++;events.push('read');
      const value = native.clientProgramReadCheckEnvironmentWire(wire, cid);
      return state.delay?.(value) ?? value;
    },
    clientProgramCheckEnvironmentFromWire(value, ...flags) {
      assert.equal(events.at(-1), 'reserve');state.from++;events.push('from');
      return native.clientProgramCheckEnvironmentFromWire(value, ...flags);
    },
  });
  const services = createInstalledHostServices({root: '/component/environment', principalId: 'component', moon,
    initialPreparation: initial, assertCurrent() {state.onCurrent?.();if (!state.current) throw new Error('OriginalLost');}});
  return {moon, services, state, events, compose: (...inputs) => composeInstalledSourceEnvironment(services, moon, ...inputs),
    inventory: (previous, member, accept = () => false) => composeInstalledInventoryEnvironment(services, moon, baseWire, previous, member, accept),
    close: () => retireInstalledSourceInitialization(services)};
}

test('generated Environment constructors are prefunded once and reuse exact same-owner originals', () => {
  const f = fixture();
  const first = f.compose(baseWire, undefined, document('first'));
  assert.equal(f.state.reads, 2);assert.equal(f.state.from, 2);
  const second = f.compose(baseWire, first, document('second'));
  assert.equal(f.state.reads, 4);assert.equal(f.state.from, 4);
  const reused = f.compose(baseWire, second);
  assert.equal(reused, second);assert.equal(f.state.reads, 4);assert.equal(f.state.from, 4);
  assert.deepEqual(second.body.connector_catalogs.map(v => v.connector_id).sort(), ['first', 'second']);
  assert.ok(Object.isFrozen(second.body) && Object.isFrozen(second.body.connector_catalogs));
  assert.equal(f.close(), true);assert.equal(f.state.retire, 1);
});

test('foreign and copied equal-wire Environment originals cannot substitute for the funded issuer', () => {
  const a = fixture(), b = fixture();const value = a.compose(baseWire);
  assert.throws(() => b.compose(baseWire, value), {code: 'ForeignInstalledEnvironmentOriginal'});
  assert.throws(() => a.compose(baseWire, {...value}), {code: 'ForeignInstalledEnvironmentOriginal'});
  a.close();b.close();
});

test('reservation refusal precedes generated read and failed undefined cause cannot revive construction', () => {
  const f = fixture();f.state.refuse = true;
  let failures = 0;
  for (let index = 0; index < 2; index++) try {f.compose(baseWire);assert.fail('Expected refusal');}
  catch (cause) {assert.equal(cause, undefined);failures++;}
  assert.equal(failures, 2);assert.equal(f.state.reads, 0);assert.equal(f.state.from, 0);
  f.state.refuse = false;assert.equal(f.close(), true);assert.equal(f.state.retire, 1);
});

test('currentness loss prevents reuse without starting another native admission', () => {
  const f = fixture();const value = f.compose(baseWire);const reads = f.state.reads;
  f.state.current = false;
  assert.throws(() => f.compose(value), /OriginalLost/);
  assert.equal(f.state.reads, reads);f.state.current = true;f.close();
});


test('only the same Source retirement ACK releases retained composition state', () => {
  const f = fixture();f.compose(baseWire);
  assert.throws(() => releaseRetiredInstalledEnvironmentComposition(f.services),
    {code: 'InstalledSourceRetirementPending'});
  f.state.refuse = true;
  try {f.compose(baseWire, undefined, document('failed'));assert.fail('Expected refusal');}
  catch (cause) {assert.equal(cause, undefined);}
  f.state.refuse = false;f.state.retireReady = false;
  assert.equal(f.close(), false);
  assert.throws(() => releaseRetiredInstalledEnvironmentComposition(f.services),
    {code: 'InstalledSourceRetirementPending'});
  try {f.compose(baseWire);assert.fail('Pending owner must retain its failure');}
  catch (cause) {assert.equal(cause, undefined);}
  f.state.retireReady = true;assert.equal(f.close(), true);
  // Retaining the closed services no longer retains the old construction
  // owner/failure/base. A new attempt observes the actual retired material.
  assert.throws(() => f.compose(baseWire), {code: 'ForeignInstalledSourceInitialization'});
});

test('installed aggregate composition requires original services before any load', async () => {
  let loads = 0;
  for (const installationServices of [undefined, {}, {...fixture().services}]) {
    await assert.rejects(composeInstalledEffects(['unused'], {moon: native, baseEnvironmentWire: baseWire,
      installationServices}, async () => {loads++;}), {code: 'ForeignInstalledHostServices'});
    await assert.rejects(loadInstalledSources(['unused'], {moon: native,
      installationServices}), {code: 'ForeignInstalledHostServices'});
  }
  let reads = 0;
  const options = {moon: native, baseEnvironmentWire: baseWire,
    get installationServices() {return reads++ === 0 ? undefined : fixture().services;}};
  await assert.rejects(composeInstalledEffects(['unused'], options, async () => {loads++;}),
    {code: 'ForeignInstalledHostServices'});
  assert.equal(reads, 1);
  assert.equal(loads, 0);
});

const releasedSlots = f => f.state.reconciled.at(-1).filter(value => f.state.zero.has(value)).length;
test('inventory replacement releases only its prior shallow prefix and keeps member originals', () => {
  const f = fixture();
  const member = f.inventory(undefined, document('member'));
  const prefix = f.inventory(member, document('second'));
  const before = releasedSlots(f);
  const final = f.inventory(prefix, document('third'), () => true);
  assert.equal(releasedSlots(f) - before, 3); // JS merge, wire read, native Environment.
  assert.throws(() => f.inventory(prefix, document('fourth')), {code: 'ForeignInstalledEnvironmentOriginal'});
  // This failed call latches the same owner; the earlier completed output
  // still contains the same member leaves, without a second parse or refund.
  assert.equal(final.body.connector_catalogs.find(value => value.connector_id === 'member'), member.body.connector_catalogs[0]);
  assert.equal(releasedSlots(f) - before, 3);
  f.close();
});

test('escaped and normally borrowed inventory prefixes retain their original custody', () => {
  for (const escaped of [false, true]) {
    const f = fixture(), member = f.inventory(undefined, document('member'));
    const prefix = f.inventory(member, document('second'), () => escaped);
    if (!escaped) assert.equal(f.compose(baseWire, prefix), prefix);
    const before = releasedSlots(f);
    f.inventory(prefix, document('third'), () => true);
    assert.equal(releasedSlots(f), before);
    f.close();
  }
});

test('failed acceptance and lost currentness keep the previous inventory prefix funded', () => {
  for (const loss of [false, true]) {
    const f = fixture(), member = f.inventory(undefined, document('member'));
    const prefix = f.inventory(member, document('second'));
    const before = releasedSlots(f), original = new Error('OriginalAcceptanceRefusal');
    assert.throws(() => f.inventory(prefix, document('third'), () => {
      if (loss) {f.state.current = false; return false;}
      throw original;
    }), loss ? /OriginalLost/ : value => value === original);
    assert.equal(releasedSlots(f), before);
    f.state.current = true;f.close();
  }
});

test('failed asynchronous successor preserves prefix and Source borrow until its actual settle', async () => {
  const f = fixture(), member = f.inventory(undefined, document('member'));
  const prefix = f.inventory(member, document('second'));
  const before = releasedSlots(f);
  let settle;
  f.state.delay = value => f.state.reads === 6 ? new Promise(resolve => {settle = () => resolve(value);}) : value;
  assert.throws(() => f.inventory(prefix, document('third')), {code: 'InstalledSourceConstructorNotSynchronous'});
  assert.equal(releasedSlots(f), before);
  assert.equal(f.close(), false);
  settle(); await Promise.resolve(); await Promise.resolve();
  assert.equal(f.close(), true);
});

test('Environment owner refuses reentry even during its first nominal reader lookup', () => {
  const f = fixture(); let reentries = 0;
  f.state.onCurrent = () => {
    f.state.onCurrent = undefined;
    assert.throws(() => f.compose(baseWire), {code: 'InstalledEnvironmentConstructionReentry'});
    reentries++;
  };
  f.compose(baseWire);
  assert.equal(reentries, 1);
  f.close();
});

test('one-sided manifest borrowing retains the actual earlier prefix envelope', () => {
  const f = fixture(), member = f.inventory(undefined, document('member'));
  const prefix = f.inventory(member, document('second'));
  const before = releasedSlots(f);
  const final = f.inventory(prefix, baseWire, () => true);
  assert.equal(final.body.connector_manifest, prefix.body.connector_manifest);
  assert.equal(releasedSlots(f), before);
  f.close();
});
