import assert from 'node:assert/strict';
import {mkdir, open, readFile, readdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {DatabaseSync} from 'node:sqlite';
import {createHostJournalDirectoryInspector} from '../host-node/host-journal-directory.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from '../host-node/client-request-journal.mjs';
import {openLocalPublicationStore, prepareLocalPublicationStoreOwnership,
  assertOriginalPreparedLocalPublicationStoreOwnership,
  closePreparedLocalPublicationStoreOwnership, captureOriginalLocalExecutionOwner} from './publication-store.mjs';

const bounds = Object.freeze({maxWireBytes: 16384, maxDirectoryEntries: 64});
async function fixture() {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'prepared-store-owner-', label: 'actual prepared Store ownership, explicit resource/control fixture'});
  const directory = join(scratch.path, 'publication');
  const configuration = {directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 100, maxContractDepth: 10};
  return {scratch, directory, configuration, control: createPublicationContractControlFixture()};
}
const adopt = (f, original, configuration = f.configuration) =>
  openLocalPublicationStore(configuration, f.control, undefined, undefined, original);

// Explicit directory operations test nominal forwarding/custody, not a native
// close ACK or an operational facility. The Root diagnostic separately uses
// the retained matching Darwin native artifact.
function selectedDirectory({names = [], outcome = 'closed', maxInspections = 8} = {}) {
  let opens = 0, closes = 0, next = 0;
  const handle = {};
  const native = {
    open() { opens++; next = 0; return handle; },
    next(original) { assert.strictEqual(original, handle);
      return next === names.length ? null : Buffer.from(names[next++]); },
    current(original) { assert.strictEqual(original, handle); },
    close(original) { assert.strictEqual(original, handle); closes++; return {outcome}; },
  };
  return {inspect: createHostJournalDirectoryInspector(native,
    {maxEntries: 64, maxNameBytes: 1024, maxWork: 65536, maxInspections}, () => {}),
    counts: () => ({opens, closes})};
}

test('selected Store preparation refuses a foreign or mismatched inspector before filesystem work', async () => {
  const f = await fixture();
  let calls = 0;
  await assert.rejects(prepareLocalPublicationStoreOwnership(f.directory, bounds, undefined,
    () => { calls++; return []; }), {code: 'HostJournalDirectoryUnavailable'});
  const selected = selectedDirectory();
  await assert.rejects(prepareLocalPublicationStoreOwnership(f.directory,
    {...bounds, maxDirectoryEntries: 63}, undefined, selected.inspect),
  {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(calls, 0);
  assert.deepEqual(selected.counts(), {opens: 0, closes: 0});
  await assert.rejects(readdir(f.directory), {code: 'ENOENT'});
  f.scratch.passed();
});

test('Store adoption retains the prepared native reader and does not refill its history', async () => {
  const f = await fixture(), selected = selectedDirectory({maxInspections: 1});
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds, undefined, selected.inspect);
  assert.deepEqual(selected.counts(), {opens: 1, closes: 1});
  await assert.rejects(adopt(f, original), {code: 'HostJournalDirectoryUnavailable'});
  assert.deepEqual(selected.counts(), {opens: 1, closes: 1});
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  f.scratch.passed();
});

test('Store preparation propagates the same native consumed-close Unknown without reopening or retrying close', async () => {
  const f = await fixture(), selected = selectedDirectory({outcome: 'unknown'});
  let failure;
  await assert.rejects(prepareLocalPublicationStoreOwnership(f.directory, bounds, undefined, selected.inspect),
    error => {failure = error; return error.code === 'HostJournalDirectoryCleanupPending';});
  for (let index = 0; index < 2; index++) assert.equal(failure.cleanupHandle.retry().pending, true);
  assert.deepEqual(selected.counts(), {opens: 1, closes: 1});
  assert.deepEqual(await readdir(f.directory), []);
  f.scratch.passed();
});

test('shared prepared exclusion survives Store cleanup until the same native Journal closes', async () => {
  const f = await fixture();
  const close = DatabaseSync.prototype.close;
  const cause = new Error('OriginalJournalClosePending');
  let permitted = false, journal;
  DatabaseSync.prototype.close = function (...args) {
    if (!permitted) throw cause;
    return Reflect.apply(close, this, args);
  };
  try {journal = openClientRequestJournal(join(f.scratch.path, 'requests'));}
  finally {DatabaseSync.prototype.close = close;}
  const dependency = Object.freeze({status() {
    assert.strictEqual(this, dependency);
    const observation = observeOriginalClientRequestJournalCustody(journal);
    return Object.freeze({pending: observation.databaseClosed !== true ||
      observation.observationDatabaseClosed !== true});
  }});
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds, dependency);
  const store = await adopt(f, original);
  const owner = await readFile(join(f.directory, 'owner', 'owner.json'));
  assert.throws(() => journal.close(), error => error === cause);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.deepEqual(await readFile(join(f.directory, 'owner', 'owner.json')), owner);
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, true);
  permitted = true;
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  assert.equal(await store.close(), true);
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  await assert.rejects(readFile(join(f.directory, 'owner', 'owner.json')), {code: 'ENOENT'});
  f.scratch.passed();
});

test('prepared dependency keeps its captured receiver and refuses ambiguous or failed close observations', async () => {
  const f = await fixture();
  const cause = new Error('OriginalDependencyObservationUnknown');
  let observation, failure = true, calls = 0;
  const dependency = {status() {
    assert.strictEqual(this, dependency);
    calls++;
    if (failure) throw cause;
    return observation;
  }};
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds, dependency);
  const owner = await readFile(join(f.directory, 'owner', 'owner.json'));
  dependency.status = () => ({pending: false});
  await assert.rejects(closePreparedLocalPublicationStoreOwnership(original), error => error === cause);
  failure = false;
  for (const value of [undefined, {}, true, {pending: true},
    Object.create({pending: false}), Object.defineProperty({}, 'pending', {
      get() {throw new Error('MustNotReadAccessor');},
    })]) {
    observation = value;
    await assert.rejects(closePreparedLocalPublicationStoreOwnership(original),
      {code: 'PublicationStoreCleanupPending'});
    assert.deepEqual(await readFile(join(f.directory, 'owner', 'owner.json')), owner);
  }
  observation = Object.freeze({pending: false});
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  assert.equal(calls, 8);
  f.scratch.passed();
});

// Physical ownership/format/custody only. No operational Resource issuer or
// new Store/key/Account authority follows from this explicit fixture.
test('fresh prepared owner remains nominal and ordinary owner-only format refusal stays unchanged', async () => {
  const f = await fixture();
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  assertOriginalPreparedLocalPublicationStoreOwnership(original, f.directory);
  assert.throws(() => assertOriginalPreparedLocalPublicationStoreOwnership({...original}, f.directory),
    {code: 'PublicationStoreOwnershipLost'});
  await assert.rejects(openLocalPublicationStore(f.configuration, f.control),
    {code: 'LegacyPublicationStoreFormat'});
  assert.deepEqual(await readdir(f.directory), ['owner']);
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  await assert.rejects(readFile(join(f.directory, 'owner', 'owner.json')), {code: 'ENOENT'});
  f.scratch.passed();
});

test('same original fresh owner is adopted once and only Store close releases it', async () => {
  const f = await fixture();
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  const owner = await readFile(join(f.directory, 'owner', 'owner.json'));
  const store = await adopt(f, original);
  const adoptedOwner = JSON.parse(await readFile(join(f.directory, 'owner', 'owner.json')));
  assert.deepEqual({...adoptedOwner, leaseAnchor: undefined}, {...JSON.parse(owner), leaseAnchor: undefined});
  const receipt = captureOriginalLocalExecutionOwner(original);
  assert.deepEqual(adoptedOwner.leaseAnchor, receipt?.anchor, 'unsupported delivery never invents an execution receipt');
  await assert.rejects(adopt(f, original), {code: 'PublicationStoreOwnershipLost'});
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, true);
  assert.deepEqual(JSON.parse(await readFile(join(f.directory, 'owner', 'owner.json'))), adoptedOwner);
  assert.equal(await store.close(), true);
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  await assert.rejects(adopt(f, original), {code: 'PublicationStoreOwnershipLost'});
  f.scratch.passed();
});

test('cold prepared owner preserves existing format and authority mismatch remains refused', async () => {
  const f = await fixture();
  await (await openLocalPublicationStore(f.configuration, f.control)).close();
  const wire = await readFile(join(f.directory, 'store.json'));
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  await assert.rejects(adopt(f, original, {...f.configuration, storeAuthorityCid: 'sha256:' + 'b'.repeat(64)}),
    {code: 'PublicationStoreAuthorityMismatch'});
  assert.deepEqual(await readFile(join(f.directory, 'store.json')), wire);
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  const next = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  await (await adopt(f, next)).close();
  assert.equal((await closePreparedLocalPublicationStoreOwnership(next)).pending, false);
  f.scratch.passed();
});

test('foreign owner-only prefix and copied original never gain the fresh-prefix exception', async () => {
  const f = await fixture();
  await mkdir(join(f.directory, 'owner'), {recursive: true});
  const wire = Buffer.from(JSON.stringify({version: 'actql-local-publication-store-owner/0.1',
    pid: process.pid, token: 'foreign-original'}));
  await writeFile(join(f.directory, 'owner', 'owner.json'), wire);
  await assert.rejects(prepareLocalPublicationStoreOwnership(f.directory, bounds),
    {code: 'UnknownPublicationStoreFormat'});
  await assert.rejects(adopt(f, Object.freeze({})), {code: 'PublicationStoreOwnershipLost'});
  assert.deepEqual(await readFile(join(f.directory, 'owner', 'owner.json')), wire);
  f.scratch.passed();
});

test('extra material in a prepared fresh prefix is still rejected without format repair', async () => {
  const f = await fixture();
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  await writeFile(join(f.directory, 'unclassified'), 'retained-original');
  await assert.rejects(adopt(f, original), {code: 'LegacyPublicationStoreFormat'});
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  assert.equal(await readFile(join(f.directory, 'unclassified'), 'utf8'), 'retained-original');
  f.scratch.passed();
});

test('changed owner refuses before format construction and original cleanup alone can recover', async () => {
  const f = await fixture();
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  const path = join(f.directory, 'owner', 'owner.json');
  const wire = await readFile(path);
  await writeFile(path, JSON.stringify({...JSON.parse(wire), token: 'changed-original'}));
  await assert.rejects(adopt(f, original), {code: 'PublicationStoreOwnershipLost'});
  await assert.rejects(readFile(join(f.directory, 'store.json')), {code: 'ENOENT'});
  await assert.rejects(closePreparedLocalPublicationStoreOwnership(original), {code: 'PublicationStoreOwnershipLost'});
  // This disposable fixture restores only its own original token bytes for
  // original cleanup; it does not revive currentness or allow another adopt.
  await writeFile(path, wire);
  await assert.rejects(adopt(f, original), {code: 'PublicationStoreOwnershipLost'});
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  f.scratch.passed();
});

test('old pending durability retry never reads or removes a successor owner', async () => {
  const f = await fixture();
  const original = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  const probe = await open(f.directory, 'r');
  const prototype = Object.getPrototypeOf(probe), sync = prototype.sync;
  await probe.close();
  let injected = false;
  prototype.sync = async function(...args) {
    // No other operation is in flight: this first sync is the original
    // release's root-directory durability stage after owner removal.
    if (!injected) {
      injected = true; throw new Error('OriginalDirectorySyncPending');
    }
    return Reflect.apply(sync, this, args);
  };
  try { await assert.rejects(closePreparedLocalPublicationStoreOwnership(original), /OriginalDirectorySyncPending/); }
  finally { prototype.sync = sync; }
  assert.equal(injected, true);
  await assert.rejects(readFile(join(f.directory, 'owner', 'owner.json')), {code: 'ENOENT'});
  const successor = await prepareLocalPublicationStoreOwnership(f.directory, bounds);
  const wire = await readFile(join(f.directory, 'owner', 'owner.json'));
  assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  assert.deepEqual(await readFile(join(f.directory, 'owner', 'owner.json')), wire);
  assert.equal((await closePreparedLocalPublicationStoreOwnership(successor)).pending, false);
  f.scratch.passed();
});

test('metadata sync failure before prepare returns drains its same writer before retiring owner', async () => {
  const f = await fixture();
  await mkdir(f.directory, {recursive: true});
  const probe = await open(f.directory, 'r');
  const prototype = Object.getPrototypeOf(probe), sync = prototype.sync;
  await probe.close();
  const cause = new Error('OriginalOwnerMetadataSyncFailed');
  let writer;
  prototype.sync = async function(...args) {
    if (writer === undefined) {writer = this; throw cause;}
    return Reflect.apply(sync, this, args);
  };
  try { await assert.rejects(prepareLocalPublicationStoreOwnership(f.directory, bounds),
    error => error === cause); }
  finally { prototype.sync = sync; }
  assert.notEqual(writer, undefined);
  assert.equal(writer.fd, -1);
  assert.deepEqual(await readdir(f.directory), []);
  f.scratch.passed();
});
