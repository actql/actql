import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {compileFunction} from 'node:vm';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {parse} from 'acorn';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {openLocalPublicationStore, prepareLocalPublicationStoreOwnership,
  assertOriginalPreparedLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership}
  from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const nodes = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  nodes.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
const helpers = ['hostJournalExclusion', 'closeHostRequestJournal',
  'closeHostPublicationOwnership', 'openHostRequestJournal'];
const declarations = helpers.map(name => nodes.find(node => node.type === 'FunctionDeclaration' &&
  node.id.name === name)).filter(Boolean);
const assignments = nodes.filter(node => node.type === 'AssignmentExpression' &&
  node.left.name === 'journal' && node.right.type === 'ConditionalExpression');
// Retain the actual old writer assignment for the original red. The repaired
// case executes the actual Host's complete opening/custody functions below.
const body = declarations.length === 0
  ? `${source.slice(assignments[0].start, assignments[0].end)};return journal;`
  : 'return openHostRequestJournal(journalOptions);';
const stores = nodes.filter(node => node.type === 'AssignmentExpression' &&
  node.left.name === 'store' && node.right.type === 'AwaitExpression' &&
  node.right.argument.callee?.name === 'openLocalPublicationStore');
assert.equal(stores.length, 1);
const storeTry = nodes.find(node => node.type === 'TryStatement' &&
  node.block.body.length === 1 && node.block.body[0].type === 'ExpressionStatement' &&
  node.block.body[0].expression === stores[0]);
const failureCalls = nodes.filter(node => node.type === 'CallExpression' &&
  node.callee.name === 'retainInstalledHostInitializationFailure' &&
  node.arguments[1]?.type === 'ObjectExpression' && node.arguments[1].properties.some(property =>
    property.key.name === 'closeInitializationJournal'));
const load = compileFunction(`
  let journal, originalJournalClose, publicationOwnership, publicationOpeningFailure, store;
  const checkpoints=undefined,dispatchOwner=undefined,sourceProfile=undefined,
    installedEffect=undefined,observation=undefined,ownerViews=undefined;
  let unselectedJournalAttempted=false, unselectedJournalFailure;
  const preparation=undefined, publicationDirectory=join(root,'publication');
  ${declarations.map(node => source.slice(node.start, node.end)).join('\n')}
  return {async open(journalOptions){${body}},
    async openStore(){${storeTry === undefined ? source.slice(stores[0].start, stores[0].end) + ';'
      : source.slice(storeTry.start, storeTry.end)}return store;},
    async failInitialization(cause){return retainInstalledHostInitializationFailure(cause,
      ${failureCalls.length === 0 ? '{journal,store}' : source.slice(
        failureCalls[0].arguments[1].start, failureCalls[0].arguments[1].end)});},
    get journal(){return journal;},get ownership(){return publicationOwnership;},
    async closeJournal(){${declarations.length === 0 ? 'journal?.close();' : 'return closeHostRequestJournal();'}},
    async closeOwnership(){${declarations.length === 0 ? '' : 'return closeHostPublicationOwnership();'}}};`,
['root', 'journalDirectory', 'openClientRequestJournal', 'observeOriginalClientRequestJournalCustody',
  'prepareLocalPublicationStoreOwnership', 'assertOriginalPreparedLocalPublicationStoreOwnership',
  'closePreparedLocalPublicationStoreOwnership', 'join', 'clientOperationError',
  'openLocalPublicationStore', 'control', 'storeAuthorityCid', 'localOutputLimits',
  'effectInstallation', 'effectEvidenceKey', 'retainInstalledHostInitializationFailure']);
const storeOptions = directory => ({directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
  capacityBytes: 1024 * 1024, maxObjectBytes: 4096, maxObjects: 16,
  maxContractNodes: 128, maxContractDepth: 16});
async function fixture({openStore = openLocalPublicationStore} = {}) {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'host-writer-exclusion-', label: 'actual same-root Host writer ordering'});
  const directory = join(scratch.path, 'requests');
  const host = load(scratch.path, directory, openClientRequestJournal,
    observeOriginalClientRequestJournalCustody, prepareLocalPublicationStoreOwnership,
    assertOriginalPreparedLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership,
    join, code => Object.assign(new Error(code), {code}), openStore,
    createPublicationContractControlFixture(), 'sha256:' + 'a'.repeat(64),
    {maxWireBytes: 4096}, undefined, undefined, retainInstalledHostInitializationFailure);
  return {scratch, host, directory};
}

test('an unselected same-root Host refuses the live Store owner before native Journal work', async () => {
  const {scratch, host} = await fixture();
  const store = await openLocalPublicationStore(storeOptions(join(scratch.path, 'publication')),
    createPublicationContractControlFixture());
  const original = DatabaseSync.prototype.open;
  let opens = 0;
  DatabaseSync.prototype.open = function (...args) {
    opens++;
    return Reflect.apply(original, this, args);
  };
  try {
    await assert.rejects(host.open({}));
    assert.equal(opens, 0);
  } finally {
    DatabaseSync.prototype.open = original;
    await host.closeJournal();
    assert.equal(await store.close(), true);
    await host.closeOwnership();
  }
  scratch.passed();
});

test('ordinary Host adopts its exact pre-Journal owner and retains it through independent close failure', async () => {
  const {scratch, host} = await fixture();
  const open = DatabaseSync.prototype.open, close = DatabaseSync.prototype.close;
  let database, allowed = false;
  DatabaseSync.prototype.open = function (...args) {
    assert.equal(typeof JSON.parse(readFileSync(join(scratch.path,
      'publication/owner/owner.json'), 'utf8')).token, 'string');
    database = this;
    return Reflect.apply(open, this, args);
  };
  DatabaseSync.prototype.close = function (...args) {
    if (this === database && !allowed) throw new Error('OriginalWriterClosePending');
    return Reflect.apply(close, this, args);
  };
  try { await host.open({}); }
  finally { DatabaseSync.prototype.open = open; DatabaseSync.prototype.close = close; }
  const ownerPath = join(scratch.path, 'publication/owner/owner.json');
  const original = readFileSync(ownerPath);
  let store;
  try {
    store = await host.openStore();
    assert.deepEqual(readFileSync(ownerPath), original);
    await assert.rejects(host.closeJournal(), /OriginalWriterClosePending/u);
    await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
    assert.deepEqual(readFileSync(ownerPath), original);
    await assert.rejects(host.closeOwnership());
    allowed = true;
    await host.closeJournal();
    assert.equal(await store.close(), true);
    await host.closeOwnership();
    assert.equal(existsSync(ownerPath), false);
  } finally {
    allowed = true;
    await host.closeJournal();
    await store?.close();
    await host.closeOwnership();
  }
  assert.equal(database.isOpen, false);
  scratch.passed();
});

test('Host close retries the original secondary ACK before returning the shared exclusion', async () => {
  const {scratch, host} = await fixture();
  await host.open({});
  const open = DatabaseSync.prototype.open, close = DatabaseSync.prototype.close;
  let secondary, allowed = false;
  DatabaseSync.prototype.open = function (...args) {
    secondary = this;
    return Reflect.apply(open, this, args);
  };
  DatabaseSync.prototype.close = function (...args) {
    if (this === secondary && !allowed) throw new Error('OriginalSecondaryClosePending');
    return Reflect.apply(close, this, args);
  };
  try { host.journal.observationStorage(); }
  finally { DatabaseSync.prototype.open = open; DatabaseSync.prototype.close = close; }
  let store;
  try {
    store = await host.openStore();
    await assert.rejects(host.closeJournal(), {code: 'InstalledHostJournalCleanupPending'});
    assert.equal(observeOriginalClientRequestJournalCustody(host.journal).databaseClosed, true);
    assert.equal(secondary.isOpen, true);
    await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
    assert.equal(existsSync(join(scratch.path, 'publication/owner/owner.json')), true);
    allowed = true;
    await host.closeJournal();
    assert.equal(secondary.isOpen, false);
    assert.equal(await store.close(), true);
    await host.closeOwnership();
  } finally {
    allowed = true;
    await host.closeJournal();
    await store?.close();
    await host.closeOwnership();
  }
  scratch.passed();
});

test('partial original Journal construction retains the same owner until constructor cleanup ACK', async () => {
  const {scratch, host} = await fixture();
  const open = DatabaseSync.prototype.open, close = DatabaseSync.prototype.close;
  let database, allowed = false, failure;
  DatabaseSync.prototype.open = function (...args) {
    database = this;
    Reflect.apply(open, this, args);
    throw new Error('OriginalPostOpenFailure');
  };
  DatabaseSync.prototype.close = function (...args) {
    if (!allowed) throw new Error('OriginalConstructorClosePending');
    return Reflect.apply(close, this, args);
  };
  try { await host.open({}); }
  catch (cause) { failure = cause; }
  finally { DatabaseSync.prototype.open = open; DatabaseSync.prototype.close = close; }
  try {
    assert.equal(failure.code, 'SqliteJournalInitializationCleanupPending');
    assert.equal(failure.cleanupHandle.status().pending, true);
    await assert.rejects(host.closeOwnership());
    assert.equal(existsSync(join(scratch.path, 'publication/owner/owner.json')), true);
    allowed = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    await host.closeOwnership();
    assert.equal(database.isOpen, false);
    assert.equal(existsSync(join(scratch.path, 'publication/owner/owner.json')), false);
  } finally {
    allowed = true;
    await failure?.cleanupHandle?.retry();
    await host.closeOwnership();
  }
  scratch.passed();
});

test('actual Store-opening failure drains its already acquired Journal independently of the dependent child', async () => {
  const stagingFailure = new Error('OriginalStoreStagingSyncFailure');
  let openings = 0;
  const {scratch, host} = await fixture({openStore(options, control, unused, bootstrap, original) {
    openings++;
    return openLocalPublicationStore(options, control, {async syncDirectory(directory) {
      if (directory.endsWith('/staging')) throw stagingFailure;
    }}, bootstrap, original);
  }});
  const close = DatabaseSync.prototype.close;
  let allowed = false, closes = 0;
  DatabaseSync.prototype.close = function (...args) {
    closes++;
    if (!allowed) throw new Error('SameJournalNativeClosePending');
    return Reflect.apply(close, this, args);
  };
  try { await host.open({}); }
  finally { DatabaseSync.prototype.close = close; }
  let openingFailure, retained;
  try {
    await assert.rejects(host.openStore(), cause => {
      openingFailure = cause;
      assert.strictEqual(cause.primaryFailure, stagingFailure);
      return cause.cleanupHandle.status().pending === true;
    });
    assert.equal(closes, 0);
    retained = await host.failInitialization(openingFailure);
    assert.equal(closes, 1, 'The same Journal must not wait behind the Store child it blocks');
    assert.equal(retained.cleanupHandle.status().pending, true);
    assert.equal(openingFailure.cleanupHandle.status().pending, true);
    assert.equal(existsSync(join(scratch.path, 'publication/owner/owner.json')), true);
    allowed = true;
    assert.equal((await retained.cleanupHandle.retry()).pending, false);
    assert.equal(openingFailure.cleanupHandle.status().pending, false);
    assert.equal(existsSync(join(scratch.path, 'publication/owner/owner.json')), false);
    assert.equal(openings, 1);
    assert.equal(closes, 2);
  } finally {
    allowed = true;
    if (retained !== undefined) await retained.cleanupHandle.retry();
    else {
      await host.closeJournal();
      await openingFailure?.cleanupHandle?.retry();
      await host.closeOwnership();
    }
  }
  scratch.passed();
});
