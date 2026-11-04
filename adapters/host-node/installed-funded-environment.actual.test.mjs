import {composeInstalledEffects} from './installed-effect-inventory.mjs';
import {loadInstalledSources} from './installed-source.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {createInstalledHostServices, retireInstalledSourceInitialization}
  from './installed-host-services.mjs';
import {composeInstalledSourceEnvironment, releaseRetiredInstalledEnvironmentComposition} from './installed-funded-environment.mjs';
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
  const state = {reads: 0, from: 0, retire: 0, refuse: false, cause: undefined, current: true, retireReady: true};
  const moon = {...native};
  for (const name of ['ReconcileInstalledSourceConstruction', 'CompleteInstalledSourceMaterial',
    'BorrowInstalledSourceMaterial', 'BorrowedInstalledSourceEnvironment', 'ReturnInstalledSourceMaterial',
    'AbortUncontinuedSourceMaterial', 'BeginInstalledSourceIo', 'ChargeInstalledSourceIo',
    'MarkInstalledSourceIoTransferUncertain', 'FinishInstalledSourceIoAfterCleanup']) moon['clientProgram' + name] = () => ok();
  Object.assign(moon, {
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
      return native.clientProgramReadCheckEnvironmentWire(wire, cid);
    },
    clientProgramCheckEnvironmentFromWire(value, ...flags) {
      assert.equal(events.at(-1), 'reserve');state.from++;events.push('from');
      return native.clientProgramCheckEnvironmentFromWire(value, ...flags);
    },
  });
  const services = createInstalledHostServices({root: '/component/environment', principalId: 'component', moon,
    initialPreparation: initial, assertCurrent() {if (!state.current) throw new Error('OriginalLost');}});
  return {moon, services, state, events, compose: (...inputs) => composeInstalledSourceEnvironment(services, moon, ...inputs),
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
