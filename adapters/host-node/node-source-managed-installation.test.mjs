import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import * as actual from './node-source-managed-installation.mjs';

test('the actual absent Source issuer refuses without observing caller originals', async () => {
  let reads = 0;
  const raw = new Proxy({}, {get() {reads++;}, ownKeys() {reads++;},
    getOwnPropertyDescriptor() {reads++;}});
  await assert.rejects(actual.prepareSourceManagedInstallation(raw),
    {code: 'SourceManagedPreparationUnavailable'});
  assert.throws(() => actual.assertSourceManagedInstallationCurrent(raw, raw),
    {code: 'SourceManagedPreparationUnavailable'});
  assert.throws(() => actual.assertSourceManagedPreparationCurrent(raw, raw),
    {code: 'SourceManagedPreparationUnavailable'});
  assert.equal(reads, 0);
});

// Execute the exact consumer Source with an explicitly substituted CJS
// receiver. These test-only ports prove forwarding/custody, not a selected
// startup, Resource issuer, original Source capacity or real Host positive.
async function fixture(t, {ordinaryAbsent = false} = {}) {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  await mkdir(join(root, '_build'), {recursive:true});
  const scratch = {path: await mkdtemp(join(root, '_build/source-forward-controls-'))};
  await writeFile(join(scratch.path, 'infer-trusted-node-preload.cjs'), ordinaryAbsent
    ? "module.exports={prepareSourceManagedInstallation(){throw new Error('MustNotBorrowPreloadReceiver');}};\n"
    : 'module.exports={};\n');
  await writeFile(join(scratch.path, 'node-public-initial-control-bootstrap.cjs'), ordinaryAbsent
    ? 'module.exports={};\n' : "module.exports=require('./infer-trusted-node-preload.cjs');\n");
  const owner = createRequire(import.meta.url)(join(scratch.path, 'infer-trusted-node-preload.cjs'));
  const originals = Object.freeze({}), installation = Object.freeze({}), receipt = Object.freeze({});
  const s = {current: true, close: {pending: false}, closes: 0, calls: [], returnReceipt: receipt,
    bindingReturn: undefined, intentCid: 'sha256:' + 'a'.repeat(64), afterIntent: undefined};
  Object.assign(owner, {
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
  });
  await writeFile(join(scratch.path, 'consumer.mjs'), await readFile(new URL('./node-source-managed-installation.mjs', import.meta.url)));
  const consumer = await import(pathToFileURL(join(scratch.path, 'consumer.mjs')));
  // Keep these tiny explicit-port fixtures; no automatic test-failure cleanup
  // can be mistaken for an original Source/physical acknowledgement.
  return {s, consumer, owner, originals, installation, receipt, path: scratch.path};
}

test('acquired managed Run reaches its same consumer before the post-factory current refusal',async t=>{
  const f=await fixture(t),view=await f.consumer.prepareSourceManagedInstallation(f.originals);
  const prepared=Object.freeze({}),run=Object.freeze({});f.s.run=run;
  f.s.cause=Object.freeze(new Error('OriginalRunChangedAfterFactory'));
  f.s.afterRun=()=>{f.s.current=false;};
  const retained=view.prepareRun(prepared);assert.strictEqual(retained,run);
  assert.throws(()=>view.assertCurrent(),error=>error===f.s.cause);
  assert.deepEqual(f.s.calls,[['run',prepared]]);
  await view.close();assert.equal(f.s.closes,1);
});

test('acquired Source child reaches its same cleanup consumer before the post-factory current refusal',async t=>{
  const f=await fixture(t),view=await f.consumer.prepareSourceManagedInstallation(f.originals);
  const prepared=Object.freeze({}),declaration=Object.freeze({}),run=Object.freeze({});
  let closes=0;const read=Object.freeze({close(){closes++;return {pending:false};}});f.s.read=read;
  f.s.cause=Object.freeze(new Error('OriginalSourceChangedAfterFactory'));
  f.s.afterRead=()=>{f.s.current=false;};
  const retained=view.prepareRead(prepared,declaration,run);assert.strictEqual(retained,read);
  const originalClose=retained.close;
  assert.throws(()=>view.assertCurrent(),error=>error===f.s.cause);
  assert.deepEqual(f.s.calls,[['read',prepared,declaration,run]]);
  assert.deepEqual(Reflect.apply(originalClose,retained,[]),{pending:false});
  assert.equal(closes,1);await view.close();assert.equal(f.s.closes,1);
});

test('ordinary Source absence cannot borrow the explicit preload receiver or observe caller originals', async t => {
  const f = await fixture(t, {ordinaryAbsent: true});
  // Node's test child has test-runner execArgv. Exercise the actual ordinary
  // selector in a fresh plain child, not by changing its production predicate.
  const entry = join(f.path, 'ordinary-absence.mjs');
  await writeFile(entry, "import assert from'node:assert/strict';import{prepareSourceManagedInstallation}from'./consumer.mjs';" +
    "assert.deepEqual(process.execArgv,[]);let observed=0;const raw=new Proxy({},{get(){observed++;},ownKeys(){observed++;},getOwnPropertyDescriptor(){observed++;}});" +
    "await assert.rejects(prepareSourceManagedInstallation(raw),{code:'SourceManagedPreparationUnavailable'});assert.equal(observed,0);");
  const result = spawnSync(process.execPath, [entry], {encoding: 'utf8', timeout: 10000});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
});

test('partial Source metadata current checks the captured nominal original before a view exists', async t => {
  const f = await fixture(t);
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

test('selected Source intent hash retains its receipt/body and checks original current after the Common callback', async t => {
  const f = await fixture(t), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
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

test('selected Source rejects an unexpected hash protocol without native fallback or a replacement receipt', async t => {
  const f = await fixture(t), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  const pending = Promise.resolve(f.s.intentCid);
  f.s.intentCid = pending;
  let originalFailure;
  assert.throws(() => view.intentCid(f.receipt, Object.freeze({})), cause => {
    originalFailure = cause;
    return cause.code === 'SourceManagedSynchronousProtocolChanged' && cause.cause === pending;
  });
  assert.throws(() => view.beforeSourceSnapshot('aql', 'unchanged', {}), cause => cause === originalFailure);
  assert.equal(f.s.calls.length, 1);
  view.finishSourceProducer(f.receipt, 'failed');
  await view.close();
  assert.equal(f.s.closes, 1);
});

test('four producer calls synchronously forward exact originals to the captured receiver', async t => {
  const f = await fixture(t), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
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

test('an async producer receipt refuses synchronously and remains sticky without snapshot fallback', async t => {
  const f = await fixture(t), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  f.s.returnReceipt = Promise.resolve(f.receipt);
  let failure;
  assert.throws(() => view.beforeSourceSnapshot('aql', {}, {}), cause => {
    failure = cause;return cause.code === 'SourceManagedSynchronousProtocolChanged';});
  assert.equal(failure.cause, f.s.returnReceipt);
  assert.throws(() => view.beforeSourceSnapshot('aql', {}, {}), cause => cause === failure);
  assert.equal(f.s.calls.length, 1);
  await view.close();assert.equal(f.s.closes, 1);
});

test('post-acquisition current failure preserves the exact cause and original cleanup through pending', async t => {
  const f = await fixture(t);f.s.current = false;f.s.cause = Object.freeze(new Error('OriginalCurrent'));
  let failure;
  await assert.rejects(f.consumer.prepareSourceManagedInstallation(f.originals), cause => {
    failure = cause;return cause.code === 'SourceManagedInstallationCleanupPending';});
  assert.equal(failure.cause, f.s.cause);
  f.owner.closeSourceManagedInstallation = () => {throw new Error('ReplacementMustNotRun');};
  f.s.close = {pending: true};assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(failure.cleanupHandle.status().pending, true);
  f.s.close = {pending: false};assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(failure.cleanupHandle.status().pending, false);assert.equal(f.s.closes, 2);
});

test('same original close is single-flight and only own DATA pending false retires aliases', async t => {
  const f = await fixture(t), view = await f.consumer.prepareSourceManagedInstallation(f.originals);
  let resolve;f.s.close = new Promise(done => {resolve = done;});
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
