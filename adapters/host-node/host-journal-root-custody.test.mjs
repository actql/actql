import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
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

async function fixture({covered = true, open, read, current} = {}) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-root-custody-', label: 'same Root Journal custody diagnostic',
  });
  const originals = Object.freeze({host: {}, installation: {}, generation: {}});
  const directory = join(scratch.path, 'requests');
  const subject = Object.freeze({journalDirectory: directory, assertCurrent() { current?.(); }});
  const namespace = {};
  const state = {namespace, journalDisposition: covered ? Object.freeze({
    argumentsForOriginalJournal(actual, options) {
      assert.strictEqual(actual, subject); return options;
    },
  }) : undefined, journal: Object.freeze({
    read(actual) {assert.strictEqual(this, namespace); assert.strictEqual(actual, originals);
      read?.(); return subject;},
    open(path, options) {assert.strictEqual(this, namespace);
      return open === undefined ? openClientRequestJournal(path, options) : open(path, options);},
    observe: observeOriginalClientRequestJournalCustody,
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
