import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteTransferControl;

const request = route => Object.freeze({
  coordinatorAuthority: 'coordinator-a',
  transferAttemptId: 'transfer-a',
  route,
  sourceSite: 'source-a',
  sourceSiteGeneration: 1,
  destinationSite: 'destination-b',
  destinationSiteGeneration: 2,
  sourceMaterialGeneration: 'material-a',
  physicalManifest: Object.freeze({
    version: 'actql-managed-physical-manifest/0.1',
    schemaContractCid: cid('1'),
    viewContractCid: cid('2'),
    codecContractCid: cid('3'),
    rowCount: 1,
    chunks: Object.freeze([
      Object.freeze({cid: cid('a'), byteLength: 5n, rowCount: 1}),
    ]),
  }),
  limits: Object.freeze({
    maxChunks: 1,
    maxManifestBytes: 4096,
    maxReferencedBytes: 5n,
  }),
  capacityBytes: 5n,
  expiresAtMilliseconds: 2_000_000_000_000n,
  sourceGrantCid: cid('4'),
  destinationGrantCid: cid('5'),
  routeCapabilityCid: cid('6'),
});

const commit = transition => control.commitTransition(transition, true);

test('Remote Transfer control binds route without adapter-owned identity', () => {
  const direct = control.prepare(request('direct'));
  const store = control.prepare(request('store'));
  assert.notEqual(control.identity(direct), control.identity(store));
  assert.equal(control.requestProjection(direct)[1], 'direct');
  assert.equal(control.requestProjection(store)[1], 'store');
  assert.equal(
    JSON.parse(control.requestJson(direct)).physical_manifest_cid,
    control.requestProjection(direct)[7],
  );
});

test('Remote Transfer canonical wire is admitted by common control', () => {
  const original = control.prepare(request('direct'));
  const wire = control.requestJson(original);
  const manifest = control.manifestJson(original);
  const restored = control.admitJson(
    wire,
    manifest,
    control.identity(original),
    control.requestProjection(original)[7],
    request('direct').limits,
  );
  assert.equal(control.identity(restored), control.identity(original));
  assert.equal(control.requestJson(restored), wire);
  assert.equal(control.manifestJson(restored), manifest);
  assert.deepEqual(control.chunks(restored), [
    {cid: cid('a'), byteLength: 5n, rowCount: 1},
  ]);
  assert.equal(control.activeAt(restored, 1_999_999_999_999n), true);
  assert.equal(control.activeAt(restored, 2_000_000_000_000n), false);
  assert.throws(() => control.admitJson(
    `${wire} `,
    manifest,
    control.identity(original),
    control.requestProjection(original)[7],
    request('direct').limits,
  ));
});

test('Remote Transfer durable state is restored by common control', () => {
  const requestValue = control.prepare(request('direct'));
  const record = control.open(requestValue);
  commit(control.prepareStart(record));
  const restored = control.restore(
    requestValue,
    control.recordProjection(record),
  );
  assert.deepEqual(
    control.recordProjection(restored),
    control.recordProjection(record),
  );
  assert.equal(control.revision(restored), 1);
  assert.deepEqual(
    control.journalKey(requestValue),
    ['coordinator-a', 'destination-b', '2', 'transfer-a'],
  );
  assert.throws(() => control.restore(
    requestValue,
    [1, 2, 0, 1, 0, 1, 1, 1, 1],
  ));
});

test('destination receipt is canonical evidence for the exact Store request',
  () => {
    const requestValue = control.prepare(request('store'));
    const receipt = control.prepareDestinationReceipt(
      requestValue,
      'destination-material-a',
    );
    const wire = control.destinationReceiptJson(receipt);
    const identity = control.destinationReceiptIdentity(receipt);
    const restored = control.admitDestinationReceiptJson(
      wire,
      requestValue,
      identity,
    );
    assert.deepEqual(
      control.destinationReceiptProjection(restored),
      control.destinationReceiptProjection(receipt),
    );
    assert.throws(() => control.admitDestinationReceiptJson(
      wire,
      control.prepare(request('direct')),
      identity,
    ));
    assert.throws(() => control.admitDestinationReceiptJson(
      `${wire} `,
      requestValue,
      identity,
    ));
  });

test('Store use state keeps reader stop separate from destination receipt',
  () => {
    const requestValue = control.prepare(request('store'));
    const storeUse = control.storeUse.prepare(requestValue, 'download-a');
    assert.deepEqual(control.storeUse.projection(storeUse), [
      control.storeUse.identity(storeUse),
      control.identity(requestValue),
      'download-a',
      'destination-b',
      '2',
      cid('5'),
    ]);
    const record = control.storeUse.open(storeUse);
    const commit = transition => control.storeUse.commitTransition(
      transition,
      true,
    );
    commit(control.storeUse.prepareStart(record));
    commit(control.storeUse.prepareProgress(record, 1, 5n));
    const receipt = control.prepareDestinationReceipt(
      requestValue,
      'destination-material-a',
    );
    commit(control.storeUse.prepareComplete(record, receipt));
    assert.deepEqual(control.storeUse.recordProjection(record), [
      '3',
      '2',
      '0',
      '1',
      '5',
      '1',
      control.destinationReceiptIdentity(receipt),
    ]);
    const restored = control.storeUse.restore(
      storeUse,
      control.storeUse.recordProjection(record),
    );
    assert.deepEqual(
      control.storeUse.recordProjection(restored),
      control.storeUse.recordProjection(record),
    );
    commit(control.storeUse.prepareCleanup(record));
    assert.equal(control.storeUse.recordProjection(record)[2], '1');
  });

test('direct Transfer commits only after durable stop and integrity', () => {
  const record = control.open(control.prepare(request('direct')));
  commit(control.prepareStart(record));
  assert.throws(() => control.prepareDestinationCommit(record));
  commit(control.prepareSourceSettled(record, true, false));
  const completion = control.prepareDestinationCommit(record);
  const [expected, next] = control.transitionProjection(completion);
  assert.deepEqual(expected, [2, 1, 0, 1, 0, 1, 0, 1, 0]);
  assert.deepEqual(next, [3, 2, 0, 1, 0, 1, 1, 1, 1]);
  assert.throws(() => control.commitTransition(completion, false));
  assert.deepEqual(control.recordProjection(record), expected);
  commit(completion);
  commit(control.prepareCleanup(record, false, false, false));
  assert.deepEqual(
    control.recordProjection(record),
    [4, 2, 0, 1, 1, 1, 1, 1, 1],
  );
});

test('Store failure separates source stop from destination cleanup', () => {
  const record = control.open(control.prepare(request('store')));
  commit(control.prepareStart(record));
  commit(control.prepareFailure(record, false, true));
  assert.throws(() => control.prepareCleanup(record, false, true, false));
  commit(control.prepareCleanup(record, false, true, true));
  assert.deepEqual(
    control.recordProjection(record),
    [3, 3, 2, 0, 1, 1, 1, 1, 0],
  );
});

test('Transfer admission rejects unbounded adapter projections', () => {
  assert.throws(
    () => control.prepare({
      ...request('direct'),
      limits: {...request('direct').limits, maxChunks: 0},
    }),
    {name: 'TypeError'},
  );
  assert.throws(
    () => control.prepare({...request('direct'), capacityBytes: 4n}),
  );
});
