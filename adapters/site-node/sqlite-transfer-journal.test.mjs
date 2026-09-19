import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteTransferJournal} from './sqlite-transfer-journal.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteTransferControl;

const request = (
  transferAttemptId = 'transfer-a',
  route = 'direct',
) => control.prepare(Object.freeze({
  coordinatorAuthority: 'coordinator-a',
  transferAttemptId,
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
}));

async function fixture(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-transfer-journal-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const open = () => openSqliteTransferJournal(root, {
    destinationSiteKey: 'destination-b',
    destinationSiteGeneration: 2,
    maxChunks: 2,
    maxManifestBytes: 4096,
    maxReferencedBytes: 16n,
    ...options,
  });
  return Object.freeze({root, open});
}

test('Transfer request and lifecycle recover from exact durable state',
  async t => {
    const {open} = await fixture(t);
    const journal = open();
    const transfer = request();
    const accepted = journal.accept(transfer, control);
    assert.deepEqual(
      control.recordProjection(accepted.record),
      [0, 0, 0, 0, 0, 0, 0, 1, 0],
    );
    journal.advance(control.prepareStart(accepted.record), control);
    assert.deepEqual(
      journal.inspect(transfer, control).state,
      [1, 1, 0, 0, 0, 0, 0, 1, 0],
    );
    journal.close();

    const reopened = open();
    t.after(() => reopened.close());
    const recovered = reopened.recover(control);
    assert.equal(recovered.length, 1);
    assert.equal(
      control.identity(recovered[0].request),
      control.identity(transfer),
    );
    assert.deepEqual(
      control.recordProjection(recovered[0].record),
      [1, 1, 0, 0, 0, 0, 0, 1, 0],
    );
    assert.deepEqual(
      control.recordProjection(reopened.accept(transfer, control).record),
      [1, 1, 0, 0, 0, 0, 0, 1, 0],
    );
    assert.throws(
      () => reopened.accept(request('transfer-a', 'store'), control),
      {code: 'RemoteTransferCollision'},
    );
  });

test('Transfer transition remains recoverable when control commit throws',
  async t => {
    const {open} = await fixture(t);
    const journal = open();
    t.after(() => journal.close());
    const accepted = journal.accept(request(), control);
    const transition = control.prepareStart(accepted.record);
    const failingControl = Object.freeze({
      ...control,
      commitTransition() {
        throw Object.assign(new Error('InjectedControlFailure'), {
          code: 'InjectedControlFailure',
        });
      },
    });
    assert.throws(
      () => journal.advance(transition, failingControl),
      {code: 'InjectedControlFailure'},
    );
    assert.deepEqual(
      journal.inspect(request(), control).state,
      [1, 1, 0, 0, 0, 0, 0, 1, 0],
    );
    const committed = journal.advance(transition, control);
    assert.deepEqual(
      control.recordProjection(committed),
      [1, 1, 0, 0, 0, 0, 0, 1, 0],
    );
  });

test('destination commit evidence is durable before lifecycle commit',
  async t => {
    const {open} = await fixture(t);
    const journal = open();
    const transfer = request('transfer-store', 'store');
    const accepted = journal.accept(transfer, control);
    journal.advance(control.prepareStart(accepted.record), control);
    journal.advance(
      control.prepareSourceSettled(accepted.record, true, true),
      control,
    );
    const receipt = control.prepareDestinationReceipt(
      transfer,
      'destination-material-a',
    );
    assert.deepEqual(
      control.destinationReceiptProjection(
        journal.commitDestinationReceipt(receipt, transfer, control),
      ),
      control.destinationReceiptProjection(receipt),
    );
    journal.close();

    const reopened = open();
    t.after(() => reopened.close());
    const restored = reopened.accept(transfer, control);
    assert.deepEqual(
      control.destinationReceiptProjection(
        reopened.inspectDestinationReceipt(transfer, control),
      ),
      control.destinationReceiptProjection(receipt),
    );
    reopened.advance(
      control.prepareDestinationCommit(restored.record),
      control,
    );
    assert.deepEqual(
      reopened.inspect(transfer, control).state,
      [3, 2, 3, 1, 0, 1, 1, 0, 1],
    );
  });

test('rejected integrity remains rejected after journal restart', async t => {
  const {open} = await fixture(t);
  const journal = open();
  const transfer = request('transfer-rejected');
  const accepted = journal.accept(transfer, control);
  journal.advance(control.prepareStart(accepted.record), control);
  journal.advance(
    control.prepareSourceSettled(accepted.record, false, false),
    control,
  );
  journal.close();

  const reopened = open();
  t.after(() => reopened.close());
  const restored = reopened.accept(transfer, control).record;
  assert.deepEqual(
    control.recordProjection(restored),
    [2, 1, 0, 2, 0, 1, 0, 1, 0],
  );
  assert.throws(() => control.prepareSourceSettled(restored, true, false));
  assert.throws(() => control.prepareDestinationCommit(restored));
  reopened.advance(control.prepareFailure(restored, false, true), control);
  reopened.advance(
    control.prepareCleanup(restored, true, true, true),
    control,
  );
  assert.deepEqual(
    reopened.inspect(transfer, control).state,
    [4, 3, 0, 2, 1, 1, 1, 1, 0],
  );
});

test('destination evidence collision cannot replace an accepted receipt',
  async t => {
    const {open} = await fixture(t);
    const journal = open();
    t.after(() => journal.close());
    const transfer = request('transfer-store', 'store');
    const accepted = journal.accept(transfer, control);
    journal.advance(control.prepareStart(accepted.record), control);
    journal.advance(
      control.prepareSourceSettled(accepted.record, true, true),
      control,
    );
    const first = control.prepareDestinationReceipt(transfer, 'material-a');
    const second = control.prepareDestinationReceipt(transfer, 'material-b');
    journal.commitDestinationReceipt(first, transfer, control);
    assert.throws(
      () => journal.commitDestinationReceipt(second, transfer, control),
      {code: 'RemoteTransferDestinationReceiptCollision'},
    );
    assert.deepEqual(
      control.destinationReceiptProjection(
        journal.inspectDestinationReceipt(transfer, control),
      ),
      control.destinationReceiptProjection(first),
    );
  });

test('concurrent journal handles share one atomic capacity authority',
  async t => {
    const {open} = await fixture(t, {maxTransfers: 1});
    const first = open();
    const second = open();
    t.after(() => first.close());
    t.after(() => second.close());
    first.accept(request('transfer-a'), control);
    assert.throws(
      () => second.accept(request('transfer-b'), control),
      {code: 'RemoteTransferJournalCapacityExceeded'},
    );
    assert.equal(second.recover(control).length, 1);
  });
