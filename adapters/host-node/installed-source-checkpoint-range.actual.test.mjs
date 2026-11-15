import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import {sourceReadRangeActualFixture} from './installed-source-read-range.actual.test.mjs';
import {prepareInstalledSourceCheckpointInventory} from './installed-source.mjs';
import {captureSourceAliasConstruction} from './source-alias-construction.mjs';
import {completeInstalledSourceInitialization, borrowInstalledSourceInitialization,
  installedSourceConfigurationReader} from './installed-host-services.mjs';
import {sourceAliasPublication, sourceAliasPublicationOriginal} from './source-alias-publication.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

// Actual initial Resource, original RowSource, Account gates, encrypted Store
// and SQLite Checkpoint journal. This is not ordinary SDK/physical provider
// acceptance; no public request, provider send or business Run is issued here.
async function checkpointFixture(t) {
  const f = await sourceReadRangeActualFixture(t, {viewCount: 129, originalAuthorization: true});
  const construct = captureSourceAliasConstruction(installedSourceConfigurationReader(f.services), f.moon);
  const inventory = prepareInstalledSourceCheckpointInventory(f.adapter, construct);
  const publication = sourceAliasPublication(f.moon, f.environmentOriginal.admitted);
  const original = sourceAliasPublicationOriginal(f.moon, f.environmentOriginal.admitted, publication);
  assert.ok(original);
  completeInstalledSourceInitialization(f.services, f.sourceInputOriginal,
    original.preparedEnvironment, f.environmentOriginal.wire, f.environmentOriginal);
  inventory.custody.holder = borrowInstalledSourceInitialization(f.services,
    f.sourceInputOriginal, original.preparedEnvironment);
  const keys = generateKeyPairSync('ed25519');
  const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
  const options = {root: f.root, namespaceId: 'source-inventory-component',
    authorityScopeCid: `sha256:${'a'.repeat(64)}`, ownerPrincipal: 'operator',
    siteKey: 'fixture-site', realizationKey: 'installed-acquired',
    environmentCid: f.moon.clientProgramCheckingEnvironmentCid(f.environmentOriginal.admitted),
    contractControl: runtimeCore(f.moon).publicationControl,
    sources: inventory.sources, sourceInventory: inventory,
    authorization: {accountConfiguration: f.authorization.accountConfiguration,
      reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer', principalId: 'reviewer-principal', publicKey: pem(keys.publicKey)}],
      hostKey: {keyId: 'host-key', privateKey: pem(keys.privateKey)}, resumeAfterAnswer: false}};
  let checkpoints;
  t.after(async () => {
    if (checkpoints !== undefined) await checkpoints.close();
    assert.equal(inventory.custody.retire(), true);
    await f.close();
  });
  return {...f, inventory, options, async open(changes) {
    checkpoints = await installRemoteCheckpoints({...options, ...changes});
    return checkpoints;
  }};
}

test('completed Source inventory retains all129 real Checkpoint authorities until actual close', async t => {
  const f = await checkpointFixture(t);
  const checkpoints = await f.open();
  assert.equal(f.inventory.installedSources.length, 129);
  assert.ok(f.inventory.installedSources.every(entry => typeof entry.gate.authorize === 'function' &&
    typeof entry.resumeGate.authorize === 'function'));
  assert.equal(f.inventory.bindings.at(-1).source_ref,
    [...f.inventory.sources].sort((left, right) => left.sourceRef < right.sourceRef ? -1 : 1).at(-1).sourceRef);
  await f.adapter.close();
  assert.equal(f.retire(), false, 'the real Source body borrow still belongs to Checkpoints');
  const closed = await checkpoints.close();
  assert.equal(closed.pendingAuthorization, false);
  assert.equal(f.inventory.custody.holder, undefined);
  assert.equal(f.retire(), true);
  assert.deepEqual(f.counts(), {reads: 0, grants: 0});
});

test('completed Source inventory refuses a foreign copied authority array before Checkpoint construction', async t => {
  const f = await checkpointFixture(t);
  await assert.rejects(f.open({sources: [...f.inventory.sources]}), {code: 'InvalidRemoteHostSources'});
  assert.ok(f.inventory.custody.holder, 'the original initial owner still retains failed setup cleanup');
  assert.deepEqual(f.counts(), {reads: 0, grants: 0});
  assert.equal(f.inventory.custody.retire(), true);
  await f.close();
});

test('completed Source inventory quote refuses original-current loss before constructing authority slots', async t => {
  const f = await sourceReadRangeActualFixture(t, {viewCount: 129, originalAuthorization: true});
  const construct = captureSourceAliasConstruction(installedSourceConfigurationReader(f.services), f.moon);
  const fault = f.failCurrentBeforeNextConstruction();
  assert.throws(() => prepareInstalledSourceCheckpointInventory(f.adapter, construct),
    error => error.installedSourcePhase === 'ReserveInstalledSourceConstruction' &&
      /^[0-9]+$/u.test(error.installedSourceRetainedBytes) &&
      /^[0-9]+$/u.test(error.installedSourceExecutionBytes));
  assert.equal(fault.calls, 1);
  assert.deepEqual(f.counts(), {reads: 0, grants: 0});
  await f.close();
});

test('completed Source inventory refuses a copied Environment at the nominal completion join', async t => {
  const f = await sourceReadRangeActualFixture(t, {viewCount: 129, originalAuthorization: true});
  const publication = sourceAliasPublication(f.moon, f.environmentOriginal.admitted);
  const original = sourceAliasPublicationOriginal(f.moon, f.environmentOriginal.admitted, publication);
  assert.throws(() => completeInstalledSourceInitialization(f.services, f.sourceInputOriginal,
    original.preparedEnvironment, f.environmentOriginal.wire, {...f.environmentOriginal}),
  {code: 'ForeignInstalledEnvironmentOriginal'});
  assert.deepEqual(f.counts(), {reads: 0, grants: 0});
  await f.close();
});

test('completed Source inventory keeps its body until the real Checkpoint journal is closed', async t => {
  const f = await checkpointFixture(t);
  const checkpoints = await f.open();
  assert.equal(f.inventory.custody.retire(), false,
    'quiescent Account gates alone cannot acknowledge the journal consumer');
  assert.ok(f.inventory.custody.holder);
  await checkpoints.close();
  assert.equal(f.inventory.custody.holder, undefined);
  await f.close();
});
