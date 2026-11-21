import assert from 'node:assert/strict';
import test from 'node:test';
import {managedPreparationRetirementContinuation, bindManagedComputeRunObservation,
  managedComputeUsageReader} from './embedded-local-lifecycle.mjs';
import {ledgerLimitsFields, ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
type ManagedRun = Parameters<typeof managedPreparationRetirementContinuation>[0];
type Registry = Parameters<typeof managedPreparationRetirementContinuation>[1];
type RunReference = Parameters<typeof managedComputeUsageReader>[1];
type RuntimeFixture = {
  clientProgramInstalledManagedRunAccounting?: (value: unknown) => unknown;
  clientProgramInstalledManagedRunUsage?: () => readonly bigint[];
};

const ok = (value: unknown) => ({$tag: 1, _0: value});

// Actual Host observation/retirement consumers with explicit Core ports. No
// physical Run, Resource admission or cleanup acknowledgement is issued here.
function observationFixture() {
  const record = {} as Registry;
  return {record, bind(prepared: object, ref: RunReference) {
    bindManagedComputeRunObservation(record, prepared, ref,
      code => Object.assign(new Error(code), {code}));
  }, reader(ref: RunReference) {return managedComputeUsageReader(record, ref);}};
}

test('managed usage reader selects only the same admitted Run and releases its installation alias', () => {
  const runtime: RuntimeFixture = {}, f = observationFixture();
  const prepared = {}, value = {}, foreign = {}, first = {namespaceId:'n',authorityScopeCid:'a',runDefinitionCid:'r'};
  let reads = 0;
  const usage = [1n,2n,3n,4n,5n,6n,7n,8n,9n,10n,11n,12n,13n,14n,15n,16n];
  runtime.clientProgramInstalledManagedRunAccounting = function(actual: unknown) {
    assert.strictEqual(this,runtime); assert.strictEqual(actual,value); reads++; return ok(usage);
  };
  f.record.computeRuns = new Map([[prepared,{runtime,prepared,value,closed:false} as ManagedRun & {prepared: object}]]);
  assert.equal(f.reader(first),undefined);
  f.bind(foreign,first);
  assert.equal(f.reader(first),undefined);
  f.bind(prepared,first);
  const read = f.reader({...first})!;
  assert.equal(reads,0,'Capturing correlation does not sample or admit');
  assert.equal(f.reader({...first,authorityScopeCid:'foreign'}),undefined);
  assert.strictEqual(read(),usage); assert.equal(reads,1);
  runtime.clientProgramInstalledManagedRunAccounting=()=>{throw new Error('Replacement must not run');};
  assert.strictEqual(read(),usage); assert.equal(reads,2,'Same original callback and receiver');
  f.record.computeRunObservations=undefined;
  assert.equal(read(),undefined,'A retired installation bag retains no Core original');
  assert.equal(reads,2);
});

function finalAccountingFixture() {
  const runtime: RuntimeFixture = {}, f = observationFixture();
  const prepared = {}, value = {}, original = {}, ref = {namespaceId: 'n', authorityScopeCid: 'a', runDefinitionCid: 'r'};
  const first = [...ledgerLimitsFields, ...ledgerUsageFields].map((_, index) => BigInt(index + 1));
  let current = [...first], live = true, retireFailure: unknown, managerFailure: unknown, accountingFailure: unknown, malformed: unknown;
  let reads = 0, retires = 0, acknowledgements = 0;
  const retiredRead = new Error('OriginalLedgerRetired');
  runtime.clientProgramInstalledManagedRunAccounting = function(actual: unknown) {
    assert.strictEqual(this, runtime); assert.strictEqual(actual, value); reads++;
    if (!live) throw retiredRead;
    if (accountingFailure !== undefined) throw accountingFailure;
    return ok(malformed ?? [...current]);
  };
  const run: ManagedRun & {prepared: object} = {runtime, prepared, value, original, closed: false,
    retire(actual: unknown) {
      assert.strictEqual(this, runtime); assert.strictEqual(actual, value); retires++;
      if (retireFailure !== undefined) throw retireFailure;
      live = false; return ok(undefined);
    }, manager: {retireSeveredPreparation(actual: unknown) {
      assert.strictEqual(actual, original); assert.equal(live, false); acknowledgements++;
      if (managerFailure !== undefined) throw managerFailure;
    }}};
  f.record.computeRuns = new Map([[prepared, run]]);
  f.record.computeLiveRuns = new Set([run]);
  const continueRetirement = managedPreparationRetirementContinuation(run, f.record);
  return {...f, run, first, retiredRead,
    finish() {run.closed = true; return continueRetirement();},
    readCore: () => checked(Reflect.apply(runtime.clientProgramInstalledManagedRunAccounting!, runtime, [value])),
    bind() {f.bind(prepared, ref); return f.reader(ref)!;},
    change(values: readonly bigint[]) {current = [...values];}, failRetire(error: unknown) {retireFailure = error;},
    failManager(error: unknown) {managerFailure = error;}, failAccounting(error: unknown) {accountingFailure = error;},
    malformed(value: unknown) {malformed = value;},
    counts: () => ({reads, retires, acknowledgements})};
}

test('final managed accounting retains every original scalar after actual retirement and cuts Core aliases', () => {
  const f = finalAccountingFixture(), read = f.bind();
  assert.deepEqual(f.counts(), {reads: 0, retires: 0, acknowledgements: 0});
  f.finish();
  const observed = read();
  assert.deepEqual(observed, f.first); assert.equal(Object.isFrozen(observed), true);
  assert.equal(f.run.value, undefined); assert.equal(f.run.runtime, undefined); assert.equal(f.run.manager, undefined);
  assert.equal(f.record.computeLiveRuns.has(f.run), false);
  assert.deepEqual(f.counts(), {reads: 1, retires: 1, acknowledgements: 1});
  assert.throws(() => {(observed as bigint[])[0] = 0n;}, TypeError);
  f.record.computeRunObservations = undefined;
  assert.equal(read(), undefined, 'Escaped DATA cannot restore a retired installation or live Core owner');
});

test('pending final Core retirement keeps the same live usage and resamples only its successful retry', () => {
  const f = finalAccountingFixture(), read = f.bind(), primary = new Error('OriginalFinalRetirementPending');
  f.failRetire(primary); assert.throws(f.finish, error => error === primary);
  assert.equal(f.run.closed, true); assert.equal(f.run.finalAccounting, undefined);
  assert.equal(f.record.computeLiveRuns.has(f.run), true);
  assert.deepEqual(f.counts(), {reads: 1, retires: 1, acknowledgements: 0});
  const changed = f.first.map(value => value + 100n); f.change(changed);
  assert.equal(read(), undefined, 'The closing fence does not acknowledge physical retirement or publish old DATA');
  assert.deepEqual(f.readCore(), changed, 'The same still-live Core Ledger keeps its actual quantities');
  f.failRetire(undefined); f.finish(); assert.deepEqual(read(), changed);
  assert.deepEqual(f.counts(), {reads: 3, retires: 2, acknowledgements: 1});
});

test('failed manager retirement retains original custody and publishes final DATA only after the same retry', () => {
  const f = finalAccountingFixture(), read = f.bind(), primary = new Error('OriginalManagerRetirementPending');
  f.failManager(primary); assert.throws(f.finish, error => error === primary);
  assert.equal(f.run.closed, true); assert.equal(f.run.finalAccounting, undefined);
  assert.equal(f.record.computeLiveRuns.has(f.run), true);
  assert.equal(read(), undefined, 'Manager cleanup is still pending');
  assert.throws(f.readCore, error => error === f.retiredRead, 'No invented live Ledger after Core retirement');
  f.failManager(undefined); f.finish(); assert.deepEqual(read(), f.first);
  assert.deepEqual(f.counts(), {reads: 2, retires: 1, acknowledgements: 2});
});

test('failed optional accounting cannot replace cleanup or fabricate a final snapshot', () => {
  const f = finalAccountingFixture(), read = f.bind();
  f.failAccounting(new Error('OriginalAccountingUnavailable')); f.finish();
  assert.equal(read(), undefined); assert.equal(f.run.closed, true);
  assert.deepEqual(f.counts(), {reads: 1, retires: 1, acknowledgements: 1});
});

test('an unobserved managed retirement does not sample or retain accounting DATA', () => {
  const f = finalAccountingFixture(); f.finish();
  assert.equal(f.run.finalAccounting, undefined);
  assert.deepEqual(f.counts(), {reads: 0, retires: 1, acknowledgements: 1});
});

test('final accounting cannot retain a foreign object or extra alias from a malformed runtime port', () => {
  for (const extra of [false, true]) {
    const f = finalAccountingFixture(), read = f.bind(), values: unknown[] & {foreign?: object} = [...f.first];
    if (extra) values.foreign = {};
    else values[0] = {};
    f.malformed(values); f.finish();
    assert.equal(read(), undefined); assert.equal(f.run.finalAccounting, undefined);
    assert.equal(f.run.runtime, undefined); assert.equal(f.run.value, undefined);
  }
});

test('managed accounting refuses old Usage capability before any sample', () => {
  const runtime: RuntimeFixture = {}, f = observationFixture();
  const prepared = {}, value = {}, original = {namespaceId:'n',authorityScopeCid:'a',runDefinitionCid:'r'};
  let oldReads = 0;
  runtime.clientProgramInstalledManagedRunUsage = () => {oldReads++; return Array(19).fill(0n);};
  f.record.computeRuns = new Map([[prepared,{runtime,prepared,value,closed:false} as ManagedRun & {prepared: object}]]);
  f.bind(prepared,original);
  const read = f.reader(original);
  assert.equal(typeof read,'function');
  assert.equal(read!(),undefined,'An older same-size layout cannot be interpreted by the new capability');
  assert.equal(oldReads,0,'No legacy fallback or speculative second sample');
});
