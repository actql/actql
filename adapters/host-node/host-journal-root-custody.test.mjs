import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import fs from 'node:fs';
import crypto from 'node:crypto';
import journalFacilityFields from './host-journal-facility-fields.cjs';
import {parse} from 'acorn';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody,
  assertOriginalClientRequestJournalFacilityCurrent}
  from './client-request-journal.mjs';
import {prepareLocalPublicationStoreOwnership, assertOriginalPreparedLocalPublicationStoreOwnership,
  closePreparedLocalPublicationStoreOwnership, openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const source = readFileSync(new URL('./node-public-initial-control-bootstrap.cjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'script'});
const names = ['journalOriginal', 'journalFailure', 'journalCurrent', 'journalStatus',
  'journalCleanup', 'journalAcknowledged', 'journalExclusionDependency', 'closeJournal', 'journalCarrier',
  'prepareJournal', 'captureJournalNativeBindings', 'openJournal', 'journalPublicationOwnership'];
const bodies = names.map(name => {
  const nodes = ast.body.filter(node => node.type === 'FunctionDeclaration' && node.id.name === name);
  assert.equal(nodes.length, 1);
  return source.slice(nodes[0].start, nodes[0].end);
}).join('\n');
const table = ast.body.filter(node => node.type === 'VariableDeclaration')
  .flatMap(node => node.declarations).find(node => node.id.name === 'table').init.right;
const journalNames = ['prepareHostJournalInstallation', 'assertHostJournalInstallationCurrent',
  'closeHostJournalInstallation', 'openHostJournalRequestJournal', 'originalHostPublicationOwnership'];
const journalProperties = table.properties.filter(node => journalNames.includes(node.key.name));
assert.equal(journalProperties.length, 5);
const originalOwner = journalProperties.map(node => source.slice(node.start, node.end)).join(',');
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
    captureNative:captureJournalNativeBindings,
    ownership:journalPublicationOwnership,owner:{${originalOwner}},
    close:(original,held)=>closeJournal(journalOriginal(original,held,true))};`,
['state', 'assertSamePreparation', 'join', 'journalFacilityFields']);

// Execute the actual adapter and Host forwarding/Store assignment, not a
// fixture-only ownership accessor or a manual fifth-argument substitution.
const adapterSource = readFileSync(new URL('./node-host-journal-installation.mjs', import.meta.url), 'utf8');
const adapter = compileFunction(adapterSource.replace("import {createRequire} from 'node:module';", '')
  .replace('createRequire(import.meta.url)', 'selectedRequire')
  .replace('export async function ', 'async function ') + '\nreturn prepareHostJournalInstallation;',
['selectedRequire', 'process']);
const hostSource = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const hostNodes = [];
function collectHost(node) {
  if (node === null || typeof node !== 'object') return;
  hostNodes.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collectHost);
    else if (value !== null && typeof value === 'object') collectHost(value);
  }
}
collectHost(parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'}));
const hostMethod = name => {
  const matches = hostNodes.filter(node => node.type === 'Property' && node.method && node.key.name === name);
  assert.equal(matches.length, 1);
  return hostSource.slice(matches[0].start, matches[0].end);
};
const hostPreparation = compileFunction(`
  let hostJournal,hostJournalClose,hostJournalOpen,hostJournalOwnership,hostJournalFlight;
  let hostJournalOpenAttempted=false;const record={};
  return {${hostMethod('prepareHostJournal')},${hostMethod('openRequestJournal')},
    ${hostMethod('publicationOwnership')}};`,
['originals', 'prepareHostJournalInstallation', 'assertInitialControlHostPreparation', 'clientOperationError']);
const storeAssignments = hostNodes.filter(node => node.type === 'AssignmentExpression' &&
  node.left.name === 'store' && node.right.type === 'AwaitExpression' &&
  node.right.argument.callee?.name === 'openLocalPublicationStore');
assert.equal(storeAssignments.length, 1);
const actualHostStore = compileFunction(`return (async()=>{let store;
  ${hostSource.slice(storeAssignments[0].start, storeAssignments[0].end)};return store;})();`,
['root', 'storeAuthorityCid', 'localOutputLimits', 'effectInstallation', 'effectEvidenceKey',
  'control', 'preparation', 'openLocalPublicationStore', 'join', 'publicationOwnership']);
const hostStore = (f, preparation, ownership) => actualHostStore(f.scratch.path, 'sha256:' + 'a'.repeat(64),
  {maxWireBytes: 4096}, undefined, undefined, createPublicationContractControlFixture(),
  preparation, openLocalPublicationStore, join, ownership);
function connectedHostPreparation(f) {
  const prepare = adapter(name => {
    assert.equal(name, './node-public-initial-control-bootstrap.cjs');
    return f.root.owner;
  }, {execArgv: [], env: {}});
  return hostPreparation(f.originals, prepare, actual => assert.strictEqual(actual, f.originals),
    code => Object.assign(new Error(code), {code}));
}

async function fixture({covered = true, open, read, current, nativeCurrent,
  prepareOwnership = prepareLocalPublicationStoreOwnership} = {}) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-root-custody-', label: 'same Root Journal custody diagnostic',
  });
  const originals = Object.freeze({host: {}, installation: {}, generation: {}});
  const directory = join(scratch.path, 'requests');
  const subject = Object.freeze({root: scratch.path, journalDirectory: directory,
    assertCurrent() { current?.(); }});
  const namespace = {};
  const state = {namespace, journalNative: Object.freeze({DatabaseSync, StatementSync}),
    journalDisposition: covered ? Object.freeze({
    ownershipBounds: Object.freeze({maxWireBytes: 16384, maxDirectoryEntries: 64}),
    argumentsForOriginalJournal(actual, options) {
      assert.strictEqual(actual, subject); return options;
    },
  }) : undefined, journal: Object.freeze({
    read(actual) {assert.strictEqual(this, namespace); assert.strictEqual(actual, originals);
      read?.(); return subject;},
    open(path, options) {assert.strictEqual(this, namespace);
      return open === undefined ? openClientRequestJournal(path, options) : open(path, options);},
    observe: observeOriginalClientRequestJournalCustody,
    ownershipPrepare: prepareOwnership,
    ownershipCurrent: assertOriginalPreparedLocalPublicationStoreOwnership,
    ownershipClose: closePreparedLocalPublicationStoreOwnership,
    current(database, statement, bindings) {
      assert.strictEqual(this, namespace);
      assert.strictEqual(database, DatabaseSync);
      assert.strictEqual(statement, StatementSync);
      assert.strictEqual(bindings,state.journalNative.bindings);
      assertOriginalClientRequestJournalFacilityCurrent(database, statement, bindings);
      nativeCurrent?.();
    },
  })};
  const root = make(state, actual => assert.strictEqual(actual, originals), join, journalFacilityFields);
  state.journalNative = Object.freeze({DatabaseSync,StatementSync,
    bindings:root.captureNative(fs,crypto)});
  return {scratch, originals, directory, root, state};
}

test('Root forwards earlier native bindings and rejects a foreign filesystem operation before subject acquisition', async () => {
  let subjects = 0;
  const f = await fixture({read(){subjects++;}});
  const original = f.state.journalNative;
  f.state.journalNative = Object.freeze({...original,bindings:Object.freeze({
    ...original.bindings,fs:Object.freeze({...original.bindings.fs,
      opendirSync(){assert.fail('Foreign operation must not run');}}),
  })});
  let failure;
  assert.throws(()=>f.root.prepare(f.originals), cause => {
    failure=cause;
    return cause.cause?.code==='ClientRequestJournalFacilityUnavailable';
  });
  assert.equal(subjects,0);
  assert.equal(failure.cleanupHandle.status().nativePending,false);
  assert.equal((await failure.cleanupHandle.retry()).pending,false);
  f.scratch.passed();
});

test('actual captured Root adapter and Host Store call adopt the same ownership and keep both ACKs', async () => {
  const nativeClose = DatabaseSync.prototype.close;
  let permitted = false;
  const f = await fixture({open(path, options) {
    DatabaseSync.prototype.close = function (...args) {
      if (!permitted) throw new Error('OriginalConnectedJournalClosePending');
      return Reflect.apply(nativeClose, this, args);
    };
    try {return openClientRequestJournal(path, options);}
    finally {DatabaseSync.prototype.close = nativeClose;}
  }});
  const preparation = connectedHostPreparation(f);
  const view = await preparation.prepareHostJournal();
  assert.throws(() => preparation.publicationOwnership(), {code: 'HostJournalPreparationUnavailable'});
  await preparation.openRequestJournal(f.directory, {});
  f.root.owner.originalHostPublicationOwnership = () => assert.fail('Captured original must be used');
  const directory = join(f.scratch.path, 'publication');
  const owner = readFileSync(join(directory, 'owner', 'owner.json'));
  const store = await hostStore(f, preparation);
  assert.deepEqual(readFileSync(join(directory, 'owner', 'owner.json')), owner);
  assert.throws(() => preparation.publicationOwnership(), {code: 'HostJournalPreparationUnavailable'});
  assert.equal((await view.close()).pending, true);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.deepEqual(readFileSync(join(directory, 'owner', 'owner.json')), owner);
  permitted = true;
  assert.equal((await view.close()).pending, true);
  assert.equal(await store.close(), true);
  assert.equal((await view.close()).pending, false);
  assert.throws(() => preparation.publicationOwnership(), {code: 'HostJournalPreparationUnavailable'});
  f.scratch.passed();
});

test('actual unselected Host Store call adopts its same earlier ordinary ownership', async () => {
  const f = await fixture();
  const ownership = await prepareLocalPublicationStoreOwnership(join(f.scratch.path, 'publication'));
  const store = await hostStore(f, undefined, ownership);
  assert.equal(await store.close(), true);
  assert.equal((await closePreparedLocalPublicationStoreOwnership(ownership)).pending, false);
  f.scratch.passed();
});

test('actual Host Store adoption refuses changed currentness before Store work and retains original cleanup', async () => {
  let changed = false;
  const cause = new Error('OriginalHostChangedBeforeStore');
  const f = await fixture({current() {if (changed) throw cause;}});
  const preparation = connectedHostPreparation(f);
  const view = await preparation.prepareHostJournal();
  await preparation.openRequestJournal(f.directory, {});
  changed = true;
  await assert.rejects(hostStore(f, preparation), error => error === cause);
  assert.throws(() => readFileSync(join(f.scratch.path, 'publication', 'store.json')),
    {code: 'ENOENT'});
  assert.equal(typeof JSON.parse(readFileSync(join(f.scratch.path,
    'publication', 'owner', 'owner.json'), 'utf8')).token, 'string');
  assert.equal((await view.close()).pending, false);
  f.scratch.passed();
});

test('Root preparation creates no owner; awaited ownership precedes the same native Journal', async () => {
  let opened = 0;
  const f = await fixture({open(path, options) {
    assert.equal(typeof JSON.parse(readFileSync(join(f.scratch.path,
      'publication', 'owner', 'owner.json'), 'utf8')).token, 'string');
    opened++;
    return openClientRequestJournal(path, options);
  }});
  const original = f.root.prepare(f.originals);
  assert.throws(() => readFileSync(join(f.scratch.path, 'publication')), {code: 'ENOENT'});
  await f.root.open(original, f.originals, f.directory, {});
  assert.equal(opened, 1);
  assert.equal((await f.root.close(original, f.originals)).pending, false);
  assert.throws(() => readFileSync(join(f.scratch.path, 'publication', 'owner', 'owner.json')),
    {code: 'ENOENT'});
  f.scratch.passed();
});

test('Root retains awaited ownership before post-acquisition current refusal and native work', async () => {
  let changed = false, opens = 0;
  const cause = new Error('OriginalChangedAfterOwnership');
  const f = await fixture({current() {if (changed) throw cause;},
    async prepareOwnership(...args) {
      const original = await prepareLocalPublicationStoreOwnership(...args);
      changed = true;
      return original;
    }, open() {opens++;}});
  const original = f.root.prepare(f.originals);
  let failure;
  await assert.rejects(f.root.open(original, f.originals, f.directory, {}), error => {
    failure = error; return error.cause === cause;
  });
  assert.equal(opens, 0);
  assert.equal(failure.cleanupHandle.status().ownershipPending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.throws(() => readFileSync(join(f.scratch.path, 'publication', 'owner', 'owner.json')),
    {code: 'ENOENT'});
  f.scratch.passed();
});

test('Root close awaits its original ownership flight and never starts a native child afterwards', async () => {
  let release, acquired, opens = 0;
  const acquiredPromise = new Promise(resolve => {acquired = resolve;});
  const f = await fixture({async prepareOwnership(...args) {
    const original = await prepareLocalPublicationStoreOwnership(...args);
    acquired();
    await new Promise(resolve => {release = resolve;});
    return original;
  }, open() {opens++;}});
  const original = f.root.prepare(f.originals);
  const opening = f.root.open(original, f.originals, f.directory, {});
  const rejected = assert.rejects(opening, {code: 'HostJournalInstallationCleanupPending'});
  await acquiredPromise;
  let settled = false;
  const closing = f.root.close(original, f.originals).then(value => {settled = true; return value;});
  await Promise.resolve();
  assert.equal(settled, false);
  release();
  await rejected;
  assert.equal((await closing).pending, false);
  assert.equal(opens, 0);
  f.scratch.passed();
});

test('Root and adopted Store keep the same exclusion until both original physical duties acknowledge', async () => {
  const nativeClose = DatabaseSync.prototype.close;
  let permitted = false;
  const cause = new Error('OriginalSharedJournalClosePending');
  const f = await fixture({open(path, options) {
    DatabaseSync.prototype.close = function (...args) {
      if (!permitted) throw cause;
      return Reflect.apply(nativeClose, this, args);
    };
    try {return openClientRequestJournal(path, options);}
    finally {DatabaseSync.prototype.close = nativeClose;}
  }});
  const original = f.root.prepare(f.originals);
  await f.root.open(original, f.originals, f.directory, {});
  const directory = join(f.scratch.path, 'publication');
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: 'sha256:' + 'a'.repeat(64), capacityBytes: 65536,
    maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 100, maxContractDepth: 10},
  createPublicationContractControlFixture(), undefined, undefined,
  f.root.ownership(original, f.originals));
  const owner = readFileSync(join(directory, 'owner', 'owner.json'));
  assert.equal((await f.root.close(original, f.originals)).pending, true);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.deepEqual(readFileSync(join(directory, 'owner', 'owner.json')), owner);
  permitted = true;
  // Journal ACK cannot stand in for the adopted Store's payload/release ACK.
  assert.equal((await f.root.close(original, f.originals)).pending, true);
  assert.deepEqual(readFileSync(join(directory, 'owner', 'owner.json')), owner);
  assert.equal(await store.close(), true);
  assert.equal((await f.root.close(original, f.originals)).pending, false);
  f.scratch.passed();
});

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
  await assert.rejects(f.root.open(original, f.originals, f.directory, {}), error => {
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
    assert.throws(() => f.root.ownership(token, pair), {code: 'HostJournalPreparationUnavailable'});
  }
  const journal = await f.root.open(original, f.originals, f.directory, {});
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
  await assert.rejects(f.root.open(original, f.originals, f.directory, {}), error => {
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
  await assert.rejects(f.root.open(original, f.originals, f.directory, {}), error => {
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
  const journal = await f.root.open(original, f.originals, f.directory, {});
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
  journal = await f.root.open(original, f.originals, f.directory, {});
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
  const journal = await f.root.open(original, f.originals, f.directory, {});
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
