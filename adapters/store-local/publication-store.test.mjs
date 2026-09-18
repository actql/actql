import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtemp,
  rm,
  writeFile,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {
  canonicalCid,
  sealPublicationContract,
} from '../host-common/run-publication-contracts.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;
const cids = Object.freeze({
  authority: digest('authority'),
  scope: digest('scope'),
  run: digest('run'),
  template: digest('template'),
  observations: digest('observations'),
  policy: digest('policy'),
  target: digest('target'),
  result: digest('result'),
  manifest: digest('manifest'),
  receipt: digest('receipt'),
  captured: digest('captured'),
  fence: digest('fence'),
});
const code = expected => error => error?.code === expected;

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-publication-store-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {
    directory,
    storeAuthorityCid: cids.authority,
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    ...options,
  };
  return {
    directory,
    configuration,
    store: await openLocalPublicationStore(configuration),
  };
}

function invocation() {
  return sealPublicationContract('run_invocation', {
    version: 'actql-run-invocation/0.1',
    invocation_template_cid: cids.template,
    observation_set_cid: cids.observations,
  });
}

function resultDefinition(name = 'answer') {
  return sealPublicationContract('result_definition', {
    version: 'actql-result-definition/0.1',
    program_definition_cid: cids.run,
    result_name: name,
  });
}

function publicationRequest(result = resultDefinition()) {
  return sealPublicationContract('publication_request', {
    version: 'actql-publication-request/0.1',
    tenant_id: 'tenant-a',
    authority_scope_cid: cids.scope,
    run_definition_cid: cids.run,
    inventory: [{
      result_name: result.result_name,
      result_definition_cid: result.result_definition_cid,
    }],
    publication_policy_cid: cids.policy,
    publication_target_cid: cids.target,
    requested_at: '2026-09-18T00:00:00.000Z',
  });
}

function publicationAttempt(request, attemptId = 'attempt-1') {
  return sealPublicationContract('publication_attempt', {
    version: 'actql-publication-attempt/0.1',
    publication_request_cid: request.publication_request_cid,
    run_definition_cid: cids.run,
    attempt_id: attemptId,
    fence_cid: cids.fence,
    started_at: '2026-09-18T00:00:01.000Z',
  });
}

function publicationRecord(attempt, sequence, state, prior, extra = {}) {
  return sealPublicationContract('publication_record', {
    version: 'actql-publication-record/0.1',
    publication_attempt_cid: attempt.publication_attempt_cid,
    ...(prior === undefined ? {} : {
      prior_record_cid: prior.publication_record_cid,
    }),
    sequence,
    state,
    observed_at: `2026-09-18T00:00:0${sequence + 2}.000Z`,
    cleanup_owner_cids: [],
    ...extra,
  });
}

function indexEntry(request, attempt, invocationValue, values = {}) {
  return sealPublicationContract('public_index_entry', {
    version: 'actql-public-index-entry/0.1',
    tenant_id: 'tenant-a',
    authority_scope_cid: cids.scope,
    run_definition_cid: cids.run,
    invocation_cid: invocationValue.invocation_cid,
    result_manifest_cid: cids.manifest,
    run_receipt_cid: cids.receipt,
    captured_run_cid: cids.captured,
    publication_request_cid: request.publication_request_cid,
    publication_attempt_cid: attempt.publication_attempt_cid,
    committed_at: '2026-09-18T00:00:09.000Z',
    ...values,
  });
}

const indexKey = Object.freeze({
  tenantId: 'tenant-a',
  authorityScopeCid: cids.scope,
  runDefinitionCid: cids.run,
});

async function prepareCommit(store, request, attempt, invocationValue) {
  const semantic = [
    [invocationValue, invocationValue.invocation_cid],
    [{version: 'manifest'}, cids.manifest],
    [{version: 'receipt'}, cids.receipt],
    [{version: 'captured'}, cids.captured],
  ];
  for (const [value, cid] of semantic) await store.putSemantic(value, cid);
  await store.putPublicationContract('publication_request', request);
  await store.createAttempt(attempt);
  const preparing = publicationRecord(attempt, 0, 'preparing');
  await store.appendRecord(preparing, {uncommittedConfirmed: false});
  const committing = publicationRecord(attempt, 1, 'committing', preparing);
  await store.appendRecord(committing, {uncommittedConfirmed: false});
  return {
    preparing,
    committing,
    required: [
      invocationValue.invocation_cid,
      cids.manifest,
      cids.receipt,
      cids.captured,
      request.publication_request_cid,
      attempt.publication_attempt_cid,
    ],
  };
}

test('bounded object writes are durable, streamed, and physically addressed',
  async t => {
    const {store, configuration} = await fixture(t);
    const writer = store.createObjectWriter(6);
    await writer.append('abc');
    await writer.append(Buffer.from('def'));
    await assert.rejects(writer.append('g'), code('PublicationObjectLimit'));
    const stored = await writer.seal(digest('abcdef'));
    assert.deepEqual(stored, {
      cid: digest('abcdef'), bytes: 6, created: true,
    });
    assert.equal(store.status().reservedBytes, 0);
    const chunks = [];
    await store.consumeObject(stored.cid, chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(chunks).toString('utf8'), 'abcdef');
    store.close();
    const reopened = await openLocalPublicationStore(configuration);
    assert.deepEqual(await reopened.verifyObject(stored.cid), {
      cid: stored.cid, bytes: 6,
    });
    assert.equal(reopened.status().storedBytes, 6);
  });

test('semantic contract identity remains distinct from physical body digest',
  async t => {
    const {store} = await fixture(t);
    const value = resultDefinition();
    const stored = await store.putPublicationContract(
      'result_definition', value,
    );
    assert.equal(stored.semanticCid, value.result_definition_cid);
    assert.notEqual(stored.physical.cid, stored.semanticCid);
    assert.deepEqual(await store.readJsonObject(
      value.result_definition_cid, 'result_definition',
    ), value);
    await assert.rejects(store.putSemantic(
      {...value, result_name: 'different'}, value.result_definition_cid,
    ), code('PublicationSemanticIdentityConflict'));
  });

test('publication records are append-only and sequence creation is CAS',
  async t => {
    const {store} = await fixture(t);
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    await store.putPublicationContract('publication_request', request);
    await store.createAttempt(attempt);
    const first = publicationRecord(attempt, 0, 'preparing');
    await store.appendRecord(first, {uncommittedConfirmed: false});
    const committing = publicationRecord(attempt, 1, 'committing', first);
    const cancelled = publicationRecord(attempt, 1, 'cancelled', first);
    const results = await Promise.allSettled([
      store.appendRecord(committing, {uncommittedConfirmed: false}),
      store.appendRecord(cancelled, {uncommittedConfirmed: false}),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    assert.equal(results.filter(result => result.status === 'rejected').length, 1);
    const latest = await store.latestRecord(attempt.publication_attempt_cid);
    assert.equal(latest.sequence, 1);
    assert.ok(['committing', 'cancelled'].includes(latest.state));
  });

test('unknown publication cannot become failed without confirmed non-commit',
  async t => {
    const {store} = await fixture(t);
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    await store.putPublicationContract('publication_request', request);
    await store.createAttempt(attempt);
    const first = publicationRecord(attempt, 0, 'preparing');
    const second = publicationRecord(attempt, 1, 'committing', first);
    const unknown = publicationRecord(attempt, 2, 'publication_unknown', second);
    for (const record of [first, second, unknown]) {
      await store.appendRecord(record, {uncommittedConfirmed: false});
    }
    const failed = publicationRecord(attempt, 3, 'failed', unknown, {
      failure_cid: digest('failure'),
    });
    await assert.rejects(store.appendRecord(
      failed, {uncommittedConfirmed: false},
    ), code('InvalidPublicationRecordTransition'));
    await store.appendRecord(failed, {uncommittedConfirmed: true});
  });

test('public index is invisible before commit and survives a lost response',
  async t => {
    const {store, configuration} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    assert.equal(await store.inspectCommittedIndex(indexKey), undefined);
    const entry = indexEntry(request, attempt, invocationValue);
    const committed = await store.commitIndex(entry, prepared.required);
    assert.equal(committed.committed, true);
    // Simulate losing the response after the durable commit by closing without
    // appending the terminal attempt record, then reconcile after restart.
    store.close();
    const reopened = await openLocalPublicationStore(configuration);
    assert.deepEqual(await reopened.inspectCommittedIndex(indexKey), entry);
    const succeeded = publicationRecord(attempt, 2, 'succeeded',
      prepared.committing, {public_index_entry_cid: entry.public_index_entry_cid});
    await reopened.appendRecord(succeeded, {uncommittedConfirmed: false});
    assert.equal((await reopened.latestRecord(
      attempt.publication_attempt_cid,
    )).state, 'succeeded');
  });

test('same intent is idempotent while conflicting commit is rejected',
  async t => {
    const {store} = await fixture(t);
    const invocationValue = invocation();
    const request = publicationRequest();
    const attempt = publicationAttempt(request);
    const prepared = await prepareCommit(
      store, request, attempt, invocationValue,
    );
    const entry = indexEntry(request, attempt, invocationValue);
    await store.commitIndex(entry, prepared.required);

    const retryAttempt = publicationAttempt(request, 'attempt-2');
    const retry = await prepareCommit(
      store, request, retryAttempt, invocationValue,
    );
    const retryEntry = indexEntry(request, retryAttempt, invocationValue, {
      committed_at: '2026-09-18T00:01:00.000Z',
    });
    const idempotent = await store.commitIndex(retryEntry, retry.required);
    assert.equal(idempotent.committed, false);
    assert.equal(idempotent.idempotent, true);
    assert.deepEqual(idempotent.entry, entry);

    const conflictingRequest = publicationRequest(resultDefinition('other'));
    const conflictAttempt = publicationAttempt(
      conflictingRequest, 'attempt-3',
    );
    const conflict = await prepareCommit(
      store, conflictingRequest, conflictAttempt, invocationValue,
    );
    const conflictingEntry = indexEntry(
      conflictingRequest, conflictAttempt, invocationValue,
    );
    await assert.rejects(store.commitIndex(
      conflictingEntry, conflict.required,
    ), code('PublicationCommitConflict'));
  });

test('lookup hides absence and verifies current authorization', async t => {
  const {store} = await fixture(t);
  await assert.rejects(store.lookupCommittedIndex(indexKey, () => false),
    code('PublicationLookupDenied'));
  await assert.rejects(store.lookupCommittedIndex(indexKey, () => true),
    code('PublicationLookupDenied'));
  let calls = 0;
  await assert.rejects(store.lookupCommittedIndex(indexKey, value => {
    calls++;
    return !Object.hasOwn(value, 'entry');
  }), code('PublicationLookupDenied'));
  assert.equal(calls, 1);
});

test('physical mutation is rejected after restart', async t => {
  const {store, directory} = await fixture(t);
  const stored = await store.putBytes(Buffer.from('original'));
  await writeFile(join(
    directory, 'objects', stored.cid.slice('sha256:'.length),
  ), 'mutated!');
  await assert.rejects(store.verifyObject(stored.cid),
    code('PublicationObjectCorrupt'));
});
