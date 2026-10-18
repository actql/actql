import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody,
  assertOriginalClientRequestJournalFacilityCurrent}
  from './client-request-journal.mjs';

const source = readFileSync(new URL('./node-public-initial-control-bootstrap.cjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'script'});
const names = ['journalOriginal', 'journalFailure', 'journalCurrent', 'journalStatus',
  'journalCleanup', 'journalAcknowledged', 'closeJournal', 'journalCarrier',
  'prepareJournal', 'openJournal'];
const bodies = names.map(name => {
  const nodes = ast.body.filter(node => node.type === 'FunctionDeclaration' && node.id.name === name);
  assert.equal(nodes.length, 1);
  return source.slice(nodes[0].start, nodes[0].end);
}).join('\n');
const make = compileFunction(`
  let journalInstallation;
  const apply=Reflect.apply,descriptor=Object.getOwnPropertyDescriptor;
  const own=Object.hasOwn,freeze=Object.freeze;
  const journalPromise=Promise,journalPromiseResolve=Promise.resolve;
  const journalPromiseThen=Promise.prototype.then;
  const journalUnavailable=()=>{throw Object.assign(new Error('HostJournalPreparationUnavailable'),
    {code:'HostJournalPreparationUnavailable'});};
  const field=(value,name)=>{const property=descriptor(value,name);
    if(property===undefined||!own(property,'value'))journalUnavailable();return property.value;};
  ${bodies}
  return {prepare:prepareJournal,open:openJournal,current:journalCurrent,
    close:(original,held)=>closeJournal(journalOriginal(original,held,true))};`,
['state', 'assertSamePreparation']);

async function fixture({covered = true, open, read, current, nativeCurrent} = {}) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-root-custody-', label: 'same Root Journal custody diagnostic',
  });
  const originals = Object.freeze({host: {}, installation: {}, generation: {}});
  const directory = join(scratch.path, 'requests');
  const subject = Object.freeze({journalDirectory: directory, assertCurrent() { current?.(); }});
  const namespace = {};
  const state = {namespace, journalNative: Object.freeze({DatabaseSync, StatementSync}),
    journalDisposition: covered ? Object.freeze({
    argumentsForOriginalJournal(actual, options) {
      assert.strictEqual(actual, subject); return options;
    },
  }) : undefined, journal: Object.freeze({
    read(actual) {assert.strictEqual(this, namespace); assert.strictEqual(actual, originals);
      read?.(); return subject;},
    open(path, options) {assert.strictEqual(this, namespace);
      return open === undefined ? openClientRequestJournal(path, options) : open(path, options);},
    observe: observeOriginalClientRequestJournalCustody,
    current(database, statement) {
      assert.strictEqual(this, namespace);
      assert.strictEqual(database, DatabaseSync);
      assert.strictEqual(statement, StatementSync);
      assertOriginalClientRequestJournalFacilityCurrent(database, statement);
      nativeCurrent?.();
    },
  })};
  const root = make(state, actual => assert.strictEqual(actual, originals));
  return {scratch, originals, directory, root, state};
}

// Actual production Root statements and actual SQLite/FS Journal, but with
// an explicit unaccounted Host/disposition fixture. This is custody/ordering
// evidence, not the missing production native supplier or normal Host credit.
test('Root refuses missing disposition before subject read or native constructor', async () => {
  let reads = 0, opens = 0;
  const f = await fixture({covered: false, read() {reads++;}, open() {opens++;}});
  assert.throws(() => f.root.prepare(f.originals), {code: 'HostJournalPreparationUnavailable'});
  assert.equal(reads, 0); assert.equal(opens, 0); f.scratch.passed();
});

test('Root native facility refusal precedes subject read and native constructor', async () => {
  let reads = 0, opens = 0, fences = 0;
  const cause = new Error('OriginalNativeFacilityChanged');
  const f = await fixture({read() {reads++;}, open() {opens++;},
    nativeCurrent() {fences++; throw cause;}});
  let failure;
  assert.throws(() => f.root.prepare(f.originals), error => {
    failure = error; return error.cause === cause;
  });
  assert.equal(fences, 1); assert.equal(reads, 0); assert.equal(opens, 0);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  f.scratch.passed();
});

test('Root post-constructor native refusal retains acquired child and permits original close', async () => {
  let acquired, changed = false;
  const cause = new Error('OriginalNativeFacilityChangedAfterOpen');
  const f = await fixture({nativeCurrent() {if (changed) throw cause;},
    open(path, options) {acquired = openClientRequestJournal(path, options); changed = true; return acquired;}});
  const original = f.root.prepare(f.originals);
  let failure;
  assert.throws(() => f.root.open(original, f.originals, f.directory, {}), error => {
    failure = error; return error.cause === cause;
  });
  assert.equal(observeOriginalClientRequestJournalCustody(acquired).databaseClosed, false);
  assert.equal(failure.cleanupHandle.status().nativePending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(observeOriginalClientRequestJournalCustody(acquired).databaseClosed, true);
  f.scratch.passed();
});

test('Root retains one original actual Journal through native close, not a copied pair', async () => {
  const f = await fixture();
  const original = f.root.prepare(f.originals);
  for (const [token, pair] of [[{}, f.originals], [original, {...f.originals}]]) {
    assert.throws(() => f.root.current(token, pair), {code: 'HostJournalPreparationUnavailable'});
  }
  const journal = f.root.open(original, f.originals, f.directory, {});
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, false);
  assert.throws(() => f.root.open(original, f.originals, f.directory, {}),
    {code: 'HostJournalPreparationUnavailable'});
  const closed = await f.root.close(original, f.originals);
  assert.equal(closed.pending, false);
  assert.equal(closed.physicalBackingReleased, false);
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  f.scratch.passed();
});

test('post-constructor current refusal retains the same native child behind original cleanup', async () => {
  let journal, changed = false;
  const originalFailure = new Error('OriginalAfterNativeCurrentChanged');
  const f = await fixture({current() {if (changed) throw originalFailure;},
    open(path, options) {journal = openClientRequestJournal(path, options); changed = true; return journal;}});
  const original = f.root.prepare(f.originals);
  let failure;
  assert.throws(() => f.root.open(original, f.originals, f.directory, {}), error => {
    failure = error; return error.cause === originalFailure;
  });
  assert.equal(failure.cleanupHandle.status().nativePending, true);
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, false);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  f.scratch.passed();
});

test('constructor cleanup is retained before fallible current and close reentry shares original flight', async () => {
  let f, reentry, retries = 0, permitted = false, failure;
  const cleanup = Object.freeze({status() {return {pending: !permitted};},
    retry() {retries++; reentry = failure.cleanupHandle.retry(); return {pending: !permitted};}});
  const cause = Object.assign(new Error('OriginalConstructorCleanupPending'), {cleanupHandle: cleanup});
  f = await fixture({open() {throw cause;}});
  const original = f.root.prepare(f.originals);
  assert.throws(() => f.root.open(original, f.originals, f.directory, {}), error => {
    failure = error; return error.cause === cause;
  });
  const first = failure.cleanupHandle.retry();
  assert.equal((await first).pending, true);
  assert.strictEqual(reentry, first); assert.equal(retries, 1);
  permitted = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retries, 1); f.scratch.passed();
});

test('Root closes the same optional observation child without erasing its attempt history', async () => {
  const f = await fixture();
  const original = f.root.prepare(f.originals);
  const journal = f.root.open(original, f.originals, f.directory, {});
  journal.observationStorage();
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).observationAttempted, true);
  assert.equal((await f.root.close(original, f.originals)).pending, false);
  f.scratch.passed();
});

test('secondary native close failure stays pending and retries the same captured receiver', async () => {
  const originalClose = DatabaseSync.prototype.close;
  let secondary, journal, permitted = false, calls = 0;
  const f = await fixture();
  const original = f.root.prepare(f.originals);
  journal = f.root.open(original, f.originals, f.directory, {});
  DatabaseSync.prototype.close = function () {
    secondary ??= this;
    assert.strictEqual(this, secondary);
    calls++;
    if (!permitted) throw new Error('OriginalSecondaryClosePending');
    return Reflect.apply(originalClose, this, []);
  };
  try {
    journal.observationStorage();
    assert.equal((await f.root.close(original, f.originals)).pending, true);
    assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
    assert.equal(observeOriginalClientRequestJournalCustody(journal).observationDatabaseClosed, false);
    assert.equal(secondary.isOpen, true);
    DatabaseSync.prototype.close = () => { throw new Error('ReplacementMustNotRun'); };
    assert.equal((await f.root.close(original, f.originals)).pending, true);
    permitted = true;
    assert.equal((await f.root.close(original, f.originals)).pending, false);
    assert.equal(secondary.isOpen, false);
    assert.equal(calls, 3);
    assert.equal(observeOriginalClientRequestJournalCustody(journal).observationAttempted, true);
  } finally {
    permitted = true;
    DatabaseSync.prototype.close = originalClose;
    journal.close();
  }
  f.scratch.passed();
});

test('secondary open failure retains its original wrapper for close without opening a replacement', async () => {
  const originalOpen = DatabaseSync.prototype.open;
  const f = await fixture();
  const original = f.root.prepare(f.originals);
  const journal = f.root.open(original, f.originals, f.directory, {});
  let secondary, opens = 0;
  DatabaseSync.prototype.open = function () {
    secondary = this; opens++;
    Reflect.apply(originalOpen, this, []);
    throw new Error('OriginalSecondaryOpenFailedAfterAcquisition');
  };
  try {
    assert.throws(() => journal.observationStorage(), /OriginalSecondaryOpenFailedAfterAcquisition/);
    assert.equal(secondary.isOpen, true);
    assert.equal(observeOriginalClientRequestJournalCustody(journal).observationDatabaseClosed, false);
    assert.equal((await f.root.close(original, f.originals)).pending, false);
    assert.equal(secondary.isOpen, false);
    assert.equal(opens, 1);
    assert.equal(observeOriginalClientRequestJournalCustody(journal).observationAttempted, true);
  } finally {
    DatabaseSync.prototype.open = originalOpen;
    journal.close();
  }
  f.scratch.passed();
});
