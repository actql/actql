import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteTransferStoreJournal} from
  './sqlite-transfer-store-journal.mjs';

const control = runtimeCore(moon).remoteTransferControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

function request(attempt = 'transfer-a') {
  return control.prepare(Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    transferAttemptId: attempt,
    route: 'store',
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
      rowCount: 2,
      chunks: Object.freeze([
        Object.freeze({cid: cid('a'), byteLength: 5n, rowCount: 1}),
        Object.freeze({cid: cid('b'), byteLength: 7n, rowCount: 1}),
      ]),
    }),
    limits: Object.freeze({
      maxChunks: 2,
      maxManifestBytes: 4096,
      maxReferencedBytes: 12n,
    }),
    capacityBytes: 12n,
    expiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('4'),
    destinationGrantCid: cid('5'),
    routeCapabilityCid: cid('6'),
  }));
}

async function fixture(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-transfer-store-journal-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const open = () => openSqliteTransferStoreJournal(root, {
    maxChunks: 4,
    maxManifestBytes: 4096,
    maxReferencedBytes: 64n,
    ...options,
  });
  return Object.freeze({open});
}

test('Store use bytes and receipt survive restart', async t => {
  const {open} = await fixture(t);
  const journal = open();
  const transfer = request();
  const accepted = journal.accept(transfer, 'download-a', control);
  const useControl = control.storeUse;
  journal.advance(useControl.prepareStart(accepted.record), control);
  journal.advance(
    useControl.prepareProgress(accepted.record, 1, 5n),
    control,
  );
  journal.close();

  const reopened = open();
  t.after(() => reopened.close());
  const recovered = reopened.recover(control);
  assert.equal(recovered.length, 1);
  assert.deepEqual(useControl.recordProjection(recovered[0].record), [
    '2', '1', '0', '1', '5', '0', '',
  ]);
  reopened.advance(
    useControl.prepareProgress(recovered[0].record, 2, 12n),
    control,
  );
  const receipt = control.prepareDestinationReceipt(
    transfer,
    'destination-material-a',
  );
  reopened.advance(
    useControl.prepareComplete(recovered[0].record, receipt),
    control,
  );
  reopened.advance(
    useControl.prepareCleanup(recovered[0].record),
    control,
  );
  assert.deepEqual(
    reopened.inspect(recovered[0].storeUse, control).state,
    [
      '5',
      '2',
      '1',
      '2',
      '12',
      '1',
      control.destinationReceiptIdentity(receipt),
    ],
  );
});

test('Store use identity collision and capacity are transactional', async t => {
  const {open} = await fixture(t, {maxUses: 1});
  const first = open();
  const second = open();
  t.after(() => first.close());
  t.after(() => second.close());
  const transfer = request();
  first.accept(transfer, 'download-a', control);
  assert.deepEqual(
    control.storeUse.recordProjection(
      second.accept(transfer, 'download-a', control).record,
    ),
    ['0', '0', '0', '0', '0', '0', ''],
  );
  assert.throws(
    () => second.accept(request('transfer-b'), 'download-b', control),
    {code: 'RemoteTransferStoreJournalCapacityExceeded'},
  );
});
