// Actual installed Content cleanup composition and real physical Store. The
// portable computation is a finite transport fixture, not public execution.
// Withhold only the same prepared handle's release ACK, never invent custody
// or a publication. The real Store remains unable to close while it is held.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {installNodeContentRun} from './installed-content-run.mjs';
import {localOutputLimits} from './local-values-plan.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

test('installed Content cleanup retains a real prepared object until the same release ACK', async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'content-cleanup-ack-', label: 'installed Content prepared release ACK'});
  const bytes = 'independent Content cleanup bytes\n';
  const contentCid = cid(bytes);
  const authority = cid('independent Store authority');
  const store = await openLocalPublicationStore({directory: join(scratch.path, 'store'),
    // Match the current installed writer's declared ceiling; this does not
    // allocate that capacity or change any product resource limit/profile.
    storeAuthorityCid: authority, capacityBytes: 2 * localOutputLimits.maxWireBytes,
    maxObjectBytes: localOutputLimits.maxWireBytes,
    maxObjects: 16, maxContractNodes: 256, maxContractDepth: 32},
  createPublicationContractControlFixture());
  let releaseAllowed = false, actualPrepared, execution;
  let starts = 0, seals = 0, releaseCalls = 0, commitCalls = 0, stops = 0, prefixWork = 0n;
  let ledgerPreparations = 0, managedPreparations = 0;
  const request = {}, managed = {value: {}, serialization: {}, closed: false};
  const originalFailure = new Error('IndependentPhysicalCommitNotStarted');
  const ledger = Object.freeze({fixture: 'original Pure acquisition ledger'});
  const compiled = Object.freeze({fixture: 'checked compilation'});
  const preparedProgram = Object.freeze({fixture: 'prepared Program'});
  const definition = {wire: JSON.stringify({valid_until: '2099-01-01T00:00:00.000Z'}),
    identity: cid('independent definition')};
  const policy = {cid: cid('independent policy'), wire: '{"classification":"internal"}'};
  t.after(async () => {
    // This same original diagnostic handle owns cleanup even after a failed
    // assertion. Do not erase an environment whose release remains pending.
    releaseAllowed = true;
    if (actualPrepared?.status().pending) await actualPrepared.release();
    await store.close();
  });
  const control = {
    workspaceCapacity: () => ({retainedBytes: 1n, executionBytes: 1n}),
    prefixCapacity() {assert.fail('Do not rebuild the selected Request provider');},
    requestPrefixCapacity: value => {assert.equal(value, managed.serialization);return {retainedBytes: 1n, executionBytes: 1n};},
    startRequestPrefix(value, program, selected) {
      assert.equal(value, managed.value);assert.equal(program, preparedProgram);assert.equal(selected, managed.serialization);
      starts++; return Object.freeze({fixture: 'original prefix'});
    },
    prefixWork: () => prefixWork,
    prefixAdvance() { prefixWork++; return {work: 1n, stopped: false, output: {fixture: 'completed output'}}; },
    prefixCancel() {},
    cleanupRequestPrefix(value, selected) {assert.equal(value, managed.value);assert.equal(selected, managed.serialization);stops++; return true;},
    prepare: () => ({fixture: 'serialization barrier'}),
    encoder: () => ({fixture: 'encoder'}),
    bindInput: () => ({fixture: 'bound input'}),
    inputRows: () => 0,
    inputAdvance: () => ({work: 1, ready: true, piece: bytes}),
    inputFinish: () => ({contentCid}),
    inputCancel() {},
    inputIdentityStart: () => ({fixture: 'identity cursor'}),
    inputIdentityAdvance: () => ({work: 1n, ready: true}),
    inputIdentityFinish: () => ({fixture: 'input evidence'}),
    inputIdentityCancel() {},
    candidate: () => ({fixture: 'candidate'}),
    inspect: () => ({identity: cid('independent candidate')}),
  };
  const physical = {...store,
    createPreparedObjectWriter(maxBytes) {
      const writer = store.createPreparedObjectWriter(maxBytes);
      return Object.freeze({...writer, async seal(expected) {
        seals++;
        const sealed = await writer.seal(expected);
        actualPrepared = sealed.prepared;
        return Object.freeze({...sealed, prepared: Object.freeze({
          ...actualPrepared,
          release() {
            releaseCalls++;
            return releaseAllowed ? actualPrepared.release() : Promise.resolve(false);
          },
        })});
      }});
    },
    async commitPhysicalHolding() { commitCalls++; throw originalFailure; },
  };
  const publications = {
    checkedClientSerializationGenerationLimits(value, graph) {
      assert.equal(value, compiled); assert.deepEqual(graph, {task: 0, step: 1});
      return {maxRows: localOutputLimits.maxRows, maxBytes: localOutputLimits.maxWireBytes};
    },
    checkClientCompiledRunOwner(run, prepared) {
      assert.equal(run, compiled); assert.equal(prepared, preparedProgram);
    },
    compiledSerializationPolicy: () => policy,
    checkedClientSerializationByteHoldingCid: () => cid('independent byte holding'),
  };
  const run = installNodeContentRun({
    moon: {clientProgramAcquisitionLedger: () => {ledgerPreparations++; return {$tag: 1, _0: ledger};},
      clientProgramAcquisitionCount: () => 0,
      clientProgramInstalledManagedRunAccounting: owner => {assert.equal(owner, managed.value); return {$tag: 1, _0: Array(13).fill(0n)};}},
    core: {contentGenerationControl: control, publicationControl: publications},
    registry: '{}', values: '{}', fragment: undefined, ordered: undefined,
    namespaceId: 'fixture', authorityScopeCid: cid('independent scope'), storeAuthorityCid: authority,
    ownerPrincipal: 'fixture', now: () => '2026-10-13T00:00:00.000Z', authorize: () => true,
    prepareSerializationManagedRun(program, identity, plan) {assert.equal(program, preparedProgram);assert.equal(identity, request);assert.equal(plan.compiled, compiled);managedPreparations++;return managed;},
    preparedRunRequired: true, assertRunCurrent: () => assert.equal(store.status().closed, false),
  });
  const plan = Object.freeze({kind: 'serialization', compiled,
    runDefinition: definition, serializationGraph: {task: 0, step: 1}});
  await assert.rejects(run({preparedProgram, plan, store: physical, principalId: 'fixture',
    retainExecution() {assert.fail('Unprepared Run cannot acquire cleanup custody');}}),
  {message: 'InstalledContentRunPreparationUnavailable'});
  assert.equal(ledgerPreparations, 0);
  assert.equal(starts, 0);
  run.prepareRun({preparedProgram, plan, request});
  run.prepareRun({preparedProgram, plan, request});
  assert.equal(ledgerPreparations, 0, 'terminal Content cannot create a scalar Ledger');
  assert.equal(managedPreparations, 1, 'one original Request preparation before dispatch');
  assert.throws(() => run.prepareRun({preparedProgram, plan: {...plan}, request}),
    {message: 'ForeignInstalledContentRun'});
  await assert.rejects(run({preparedProgram, plan,
  store: physical, principalId: 'fixture', retainExecution: value => { execution = value; }}),
  error => error === originalFailure);
  assert.throws(() => run.prepareRun({preparedProgram, plan, request}), {message: 'ForeignInstalledContentRun'});
  assert.equal(actualPrepared.status().pending, true);
  assert.deepEqual(await readFile(join(scratch.path, 'store', 'objects', contentCid.slice(7))), Buffer.from(bytes));
  const firstCleanup = await execution.cleanup();
  assert.equal(actualPrepared.status().pending, true);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(store.status().closed, false);
  t.diagnostic(JSON.stringify({firstCleanup, preparedPending: actualPrepared.status().pending,
    storeClosed: store.status().closed, releaseCalls, stops}));
  assert.equal(firstCleanup, false, 'requesting release is not the same as its ACK');
  assert.equal(execution.cleanupPending(), true);
  assert.equal(stops, 0, 'do not settle prefix custody before physical child ACK');
  assert.equal(await execution.cleanup(), false);
  assert.equal(actualPrepared.status().pending, true);
  assert.equal(releaseCalls, 2, 'retry the same original handle, not generation');
  releaseAllowed = true;
  const first = execution.cleanup();
  assert.equal(execution.close(), first, 'existing cleanup remains single-flight');
  assert.equal(await first, true);
  assert.equal(execution.cleanupPending(), false);
  assert.equal(actualPrepared.status().pending, false);
  assert.equal(releaseCalls, 3);
  assert.equal(stops, 1);
  assert.equal(await execution.cleanup(), true);
  assert.equal(releaseCalls, 3, 'confirmed cleanup never releases twice');
  assert.equal(starts, 1);
  assert.equal(ledgerPreparations, 0);
  assert.equal(managedPreparations, 1);
  assert.equal(seals, 1);
  assert.equal(commitCalls, 1, 'cleanup retry never retries the failed commit');
  await assert.rejects(readFile(join(scratch.path, 'store', 'objects', contentCid.slice(7))), {code: 'ENOENT'});
  await writeFile(join(scratch.path, 'observations.json'), JSON.stringify({contentCid,
    starts, seals, releaseCalls, commitCalls, stops, prefixWork: String(prefixWork)}));
  await store.close();
  scratch.passed();
});
