import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire, Module} from 'node:module';
import * as actual from './node-source-managed-installation.mjs';

type Production = typeof actual;
type PrepareSource = Production['prepareSourceManagedInstallation'];
type SelectedView = Extract<Awaited<ReturnType<PrepareSource>>,
  {prepareRun(prepared: unknown): unknown}>;
type SelectedProduction = Omit<Production, 'prepareSourceManagedInstallation'> & Readonly<{
  prepareSourceManagedInstallation(...args: Parameters<PrepareSource>): Promise<SelectedView>;
}>;
type Callback = (...values: unknown[]) => unknown;
type TestOwner = Record<string, Callback>;
type TestFailure = Error & {code?: string; cleanupHandle?: {
  retry(): Promise<{pending: boolean}>; status(): {pending: boolean};
}};

let fixtureId = 0;

// Evaluate the emitted module at its real path, with its real sibling modules.
// The explicit CJS receiver below is a test double for selected startup only.
function loadWithOwner(owner: TestOwner, selected: true): Promise<SelectedProduction>;
function loadWithOwner(owner: TestOwner, selected: false): Promise<Production>;
async function loadWithOwner(owner: TestOwner, selected: boolean): Promise<Production> {
  const require = createRequire(import.meta.url);
  const ownerPath = require.resolve('./infer-trusted-node-preload.cjs');
  const originalOwner = require.cache[ownerPath];
  const fixtureModule = new Module(ownerPath);
  fixtureModule.exports = owner;
  fixtureModule.loaded = true;
  const originalArgs = process.execArgv;
  const url = new URL('./node-source-managed-installation.mjs', import.meta.url);
  url.searchParams.set('fixture', String(++fixtureId));
  try {
    require.cache[ownerPath] = fixtureModule;
    if (selected) process.execArgv = [...originalArgs, '@actql/node/selected-infer-startup'];
    return await import(url.href);
  } finally {
    process.execArgv = originalArgs;
    if (originalOwner === undefined) delete require.cache[ownerPath];
    else require.cache[ownerPath] = originalOwner;
  }
}

test('the absent selected Source issuer refuses without observing caller originals', async () => {
  const selected = await loadWithOwner({}, true);
  let reads = 0;
  const raw = new Proxy({}, {get() {reads++;}, ownKeys() {reads++; return [];},
    getOwnPropertyDescriptor() {reads++; return undefined;}});
  await assert.rejects(selected.prepareSourceManagedInstallation(raw),
    {code: 'SourceManagedPreparationUnavailable'});
  assert.throws(() => selected.assertSourceManagedInstallationCurrent(raw, raw),
    {code: 'SourceManagedPreparationUnavailable'});
  assert.throws(() => selected.assertSourceManagedPreparationCurrent(raw, raw),
    {code: 'SourceManagedPreparationUnavailable'});
  assert.equal(reads, 0);
});

// Execute the exact consumer Source with an explicitly substituted CJS
// receiver. These test-only ports prove forwarding/custody, not a selected
// startup, Resource issuer, original Source capacity or real Host positive.
async function fixture() {
  const owner: TestOwner = {};
  const originals = Object.freeze({}), installation = Object.freeze({}), receipt = Object.freeze({});
  const s: {
    current: boolean; cause?: unknown; close: unknown; closes: number; calls: unknown[][];
    returnReceipt: unknown; bindingReturn?: unknown; intentCid: unknown;
    afterIntent?: () => void; afterRun?: () => void; afterRead?: () => void; run?: object; read?: object;
  } = {current: true, close: {pending: false}, closes: 0, calls: [], returnReceipt: receipt,
    bindingReturn: undefined, intentCid: 'sha256:' + 'a'.repeat(64), afterIntent: undefined};
  const callbacks: TestOwner = {
    prepareSourceManagedInstallation(value) {assert.equal(this, owner);assert.equal(value, originals);return installation;},
    assertSourceManagedInstallationCurrent(value, pair) {assert.equal(this, owner);assert.equal(value, installation);
      assert.equal(pair, originals);if (!s.current) throw s.cause;},
    beforeSourceSnapshot(value, pair, ...args) {assert.equal(this, owner);assert.equal(value, installation);
      assert.equal(pair, originals);s.calls.push(['before', ...args]);return s.returnReceipt;},
    bindSourceSnapshot(value, pair, r, body) {assert.equal(this, owner);assert.equal(value, installation);
      assert.equal(pair, originals);assert.equal(r, receipt);s.calls.push(['snapshot',body]);return s.bindingReturn;},
    bindSourceRequest(value, pair, r, body, request) {assert.equal(this, owner);assert.equal(value, installation);
      assert.equal(pair, originals);assert.equal(r, receipt);s.calls.push(['request',body,request]);},
    finishSourceProducer(value, pair, r, terminal) {assert.equal(this, owner);assert.equal(value, installation);
      assert.equal(pair, originals);assert.equal(r, receipt);s.calls.push(['finish',terminal]);},
    closeSourceManagedInstallation(value, pair) {assert.equal(this, owner);assert.equal(value, installation);
      assert.equal(pair, originals);s.closes++;return s.close;},
    sourceIntentCid(value, pair, r, body) {assert.equal(this, owner);assert.equal(value, installation);
      assert.equal(pair, originals);assert.equal(r, receipt);s.calls.push(['intent', body]);
      s.afterIntent?.();return s.intentCid;},
    prepareSourceManagedRun(value,pair,prepared) {assert.equal(this,owner);assert.equal(value,installation);
      assert.equal(pair,originals);s.calls.push(['run',prepared]);s.afterRun?.();return s.run;},
    prepareSourceManagedRead(value,pair,prepared,declaration,run) {assert.equal(this,owner);
      assert.equal(value,installation);assert.equal(pair,originals);
      s.calls.push(['read',prepared,declaration,run]);s.afterRead?.();return s.read;},
  };
  Object.assign(owner, callbacks);
  const consumer = await loadWithOwner(owner, true);
  return {s, consumer, owner, originals, installation, receipt};
}

test('acquired managed Run reaches its same consumer before the post-factory current refusal',async ()=>{
  const f=await fixture(),view=await f.consumer.prepareSourceManagedInstallation(f.originals);
  const prepared=Object.freeze({}),run=Object.freeze({});f.s.run=run;
  f.s.cause=Object.freeze(new Error('OriginalRunChangedAfterFactory'));
  f.s.afterRun=()=>{f.s.current=false;};
  const retained=view.prepareRun(prepared);assert.strictEqual(retained,run);
  assert.throws(()=>view.assertCurrent(),error=>error===f.s.cause);
  assert.deepEqual(f.s.calls,[['run',prepared]]);
  await view.close();assert.equal(f.s.closes,1);
});

test('acquired Source child reaches its same cleanup consumer before the post-factory current refusal',async ()=>{
  const f=await fixture(),view=await f.consumer.prepareSourceManagedInstallation(f.originals);
  const prepared=Object.freeze({}),declaration=Object.freeze({}),run=Object.freeze({});
  let closes=0;const read=Object.freeze({close(){closes++;return {pending:false};}});f.s.read=read;
  f.s.cause=Object.freeze(new Error('OriginalSourceChangedAfterFactory'));
  f.s.afterRead=()=>{f.s.current=false;};
  const retained=view.prepareRead(prepared,declaration,run);assert.strictEqual(retained,read);
  const originalClose=(retained as typeof read).close;
  assert.throws(()=>view.assertCurrent(),error=>error===f.s.cause);
  assert.deepEqual(f.s.calls,[['read',prepared,declaration,run]]);
  assert.deepEqual(Reflect.apply(originalClose,retained,[]),{pending:false});
  assert.equal(closes,1);await view.close();assert.equal(f.s.closes,1);
});

test('ordinary Source refuses a foreign Host and never calls the selected preload receiver', async () => {
  assert.equal(process.execArgv.some(arg => arg === '@actql/node/selected-infer-startup' ||
    arg === '@actql/local-node/selected-infer-startup'), false);
  let selections = 0;
  const ordinary = await loadWithOwner({
    prepareSourceManagedInstallation() {selections++; assert.fail('MustNotBorrowPreloadReceiver');},
  }, false);
  const reads: PropertyKey[] = [];
  const raw = new Proxy({}, {
    get(_target, key) {reads.push(key);},
    ownKeys() {return assert.fail('Foreign Host keys must remain untouched');},
    getOwnPropertyDescriptor() {return assert.fail('Foreign Host descriptors must remain untouched');},
  });
  await assert.rejects(ordinary.prepareSourceManagedInstallation(raw), {code: 'InstalledHostPreparationChanged'});
  assert.throws(() => ordinary.assertSourceManagedInstallationCurrent(raw, raw), {code: 'ForeignInstalledSourcePreparation'});
  assert.deepEqual(reads, ['installation', 'supplier']);
  assert.equal(selections, 0);
});

test('partial Source metadata current checks the captured nominal original before a view exists', async () => {
  const f = await fixture();
  assert.equal(f.consumer.assertSourceManagedPreparationCurrent(f.installation, f.originals), undefined);
  f.owner.assertSourceManagedInstallationCurrent = () => {throw new Error('ReplacementMustNotRun');};
  assert.equal(f.consumer.assertSourceManagedPreparationCurrent(f.installation, f.originals), undefined);
  assert.throws(() => f.consumer.assertSourceManagedPreparationCurrent({...f.installation}, f.originals));
  assert.throws(() => f.consumer.assertSourceManagedPreparationCurrent(f.installation, {...f.originals}));
  assert.equal(f.s.closes, 0);
  assert.equal(f.s.calls.length, 0);
  f.s.current = false;
  f.s.cause = Object.freeze(new Error('OriginalPreparationRetired'));
  assert.throws(() => f.consumer.assertSourceManagedPreparationCurrent(f.installation, f.originals),
    cause => cause === f.s.cause);
});

test('selected Source intent hash retains its receipt/body and checks original current after the Common callback', async () => {
  const f = await fixture(), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  const body = Object.freeze({original: 'body'});
  view.bindSourceSnapshot(f.receipt, body);
  f.owner.sourceIntentCid = () => {throw new Error('ReplacementMustNotRun');};
  assert.equal(view.intentCid(f.receipt, body), f.s.intentCid);
  assert.deepEqual(f.s.calls, [['snapshot', body], ['intent', body]]);
  assert.throws(() => view.intentCid({...f.receipt}, body));
  f.s.cause = Object.freeze(new Error('OriginalChangedDuringIntent'));
  f.s.afterIntent = () => {f.s.current = false;};
  assert.throws(() => view.intentCid(f.receipt, body), cause => cause === f.s.cause);
  // The original producer/close remains owned; a callback failure does not
  // acknowledge a physical child or issue another hashing attempt.
  view.finishSourceProducer(f.receipt, 'failed');
  await view.close();
  assert.equal(f.s.closes, 1);
});

test('selected Source rejects an unexpected hash protocol without native fallback or a replacement receipt', async () => {
  const f = await fixture(), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  const pending = Promise.resolve(f.s.intentCid);
  f.s.intentCid = pending;
  let originalFailure: unknown;
  assert.throws(() => view.intentCid(f.receipt, Object.freeze({})), cause => {
    originalFailure = cause;
    return (cause as TestFailure).code === 'SourceManagedSynchronousProtocolChanged' && (cause as TestFailure).cause === pending;
  });
  assert.throws(() => view.beforeSourceSnapshot('aql', 'unchanged', {}), cause => cause === originalFailure);
  assert.equal(f.s.calls.length, 1);
  view.finishSourceProducer(f.receipt, 'failed');
  await view.close();
  assert.equal(f.s.closes, 1);
});

test('four producer calls synchronously forward exact originals to the captured receiver', async () => {
  const f = await fixture(), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  const input = {}, options = {}, body = {}, request = {}, terminal = {};
  f.owner.beforeSourceSnapshot = () => {throw new Error('ReplacementMustNotRun');};
  assert.equal(view.beforeSourceSnapshot('aql', input, options), f.receipt);
  assert.equal(view.bindSourceSnapshot(f.receipt, body), undefined);
  assert.equal(view.bindSourceRequest(f.receipt, body, request), undefined);
  assert.equal(view.finishSourceProducer(f.receipt, terminal), undefined);
  assert.deepEqual(f.s.calls, [['before','aql',input,options],['snapshot',body],
    ['request',body,request],['finish',terminal]]);
  assert.throws(() => f.consumer.assertSourceManagedInstallationCurrent({...view}, f.originals));
  assert.throws(() => f.consumer.assertSourceManagedInstallationCurrent(view, {...f.originals}));
});

test('an async producer receipt refuses synchronously and remains sticky without snapshot fallback', async () => {
  const f = await fixture(), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  f.s.returnReceipt = Promise.resolve(f.receipt);
  let failure: TestFailure | undefined;
  assert.throws(() => view.beforeSourceSnapshot('aql', {}, {}), cause => {
    failure = cause as TestFailure;return (cause as TestFailure).code === 'SourceManagedSynchronousProtocolChanged';});
  assert.equal(failure!.cause, f.s.returnReceipt);
  assert.throws(() => view.beforeSourceSnapshot('aql', {}, {}), cause => cause === failure);
  assert.equal(f.s.calls.length, 1);
  await view.close();assert.equal(f.s.closes, 1);
});

test('post-acquisition current failure preserves the exact cause and original cleanup through pending', async () => {
  const f = await fixture();f.s.current = false;f.s.cause = Object.freeze(new Error('OriginalCurrent'));
  let failure: TestFailure | undefined;
  await assert.rejects(f.consumer.prepareSourceManagedInstallation(f.originals), cause => {
    failure = cause as TestFailure;return (cause as TestFailure).code === 'SourceManagedInstallationCleanupPending';});
  assert.equal(failure!.cause, f.s.cause);
  f.owner.closeSourceManagedInstallation = () => {throw new Error('ReplacementMustNotRun');};
  f.s.close = {pending: true};assert.equal((await failure!.cleanupHandle!.retry()).pending, true);
  assert.equal(failure!.cleanupHandle!.status().pending, true);
  f.s.close = {pending: false};assert.equal((await failure!.cleanupHandle!.retry()).pending, false);
  assert.equal(failure!.cleanupHandle!.status().pending, false);assert.equal(f.s.closes, 2);
});

test('same original close is single-flight and only own DATA pending false retires aliases', async () => {
  const f = await fixture(), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  let resolve!: (value: {pending: boolean}) => void;f.s.close = new Promise<{pending: boolean}>(done => {resolve = done;});
  const first = view.close(), second = view.close();assert.equal(f.s.closes, 1);
  resolve({pending: true});await first;await second;
  for (const observation of [undefined, true, {}, Object.create({pending:false})]) {
    f.s.close = observation;await view.close();view.assertCurrent();
  }
  let reads = 0;f.s.close = {get pending(){reads++;return false;}};
  await view.close();assert.equal(reads, 0);view.assertCurrent();
  f.s.close = {pending:false};await view.close();const count=f.s.closes;
  assert.throws(() => view.assertCurrent());await view.close();assert.equal(f.s.closes,count);
});
