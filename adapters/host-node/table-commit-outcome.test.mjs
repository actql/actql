// Selected physical projection is not another response, retry or Ledger Owner.
// Actual logical/physical admission is exercised by the MoonBit and real-Host
// tests; these cases isolate the common connection's dispatch obligations.
import test from 'node:test';
import assert from 'node:assert/strict';
import {settleSavedTableCommit} from './table-commit-outcome.mjs';

const limits = {maxWireBytes: 1024, maxNodes: 64, maxDepth: 8};
function fixture() {
  const claim = {canonicalRequestCid: 'original-request'};
  const physical = '{"opaque_backend":"non-Iceberg","committed":true}';
  const logical = '{"ok":true,"result":{"independent":"logical-receipt"}}';
  const tablePreview = Object.freeze({});
  const receipt = Object.freeze({terminalState: 'applied'});
  const saved = {responseBytes: Buffer.from(physical), statusCode: 200};
  const calls = [];
  const control = {
    tablePreviewLedgerBinding(preview) {
      assert.equal(preview, tablePreview);
      return {operationWire: '{"request_cid":"original-request"}',
        preview: 'checked-preview', memberIndex: 0};
    },
    tablePreviewCommitOutcome(preview, responseWire, statusCode, actualLimits) {
      assert.equal(preview, tablePreview);
      assert.equal(responseWire, logical);
      assert.equal(statusCode, 200);
      assert.equal(actualLimits, limits);
      calls.push('common-admission');
      return 'admitted-outcome';
    },
  };
  const ledger = {
    readClaimedResponse(actual) { assert.equal(actual, claim); return saved; },
    recordAdmittedRowOutcome({outcomeWire}) {
      assert.equal(outcomeWire, 'admitted-outcome');
      calls.push('record-outcome');
    },
    commitAdmittedRowOutcome() { calls.push('commit-outcome'); return {receipt}; },
  };
  const bridge = {projectCommitResponse({control: actualControl,
    responseWire, statusCode, limits: actualLimits}) {
    assert.equal(actualControl, control);
    assert.equal(responseWire, physical);
    assert.equal(statusCode, saved.statusCode);
    assert.equal(actualLimits, limits);
    calls.push('selected-connector');
    return logical;
  }};
  return {control, ledger, claim, tablePreview, bridge, limits,
    calls, saved, physical, receipt};
}

test('Table settlement selects its Connector projection without a Local fallback', () => {
  const f = fixture();
  assert.deepEqual(settleSavedTableCommit(f), {status: 'applied', receipt: f.receipt});
  assert.deepEqual(f.calls, ['selected-connector', 'common-admission',
    'record-outcome', 'commit-outcome']);
  assert.equal(f.saved.responseBytes.toString('utf8'), f.physical);
});

test('missing or rejected Table projection preserves the original response without settlement', () => {
  const f = fixture();
  assert.throws(() => settleSavedTableCommit({...f, bridge: {}}),
    {code: 'MissingTableCommitProjector'});
  const rejected = new Error('InvalidPhysicalContract');
  assert.throws(() => settleSavedTableCommit({...f,
    bridge: {projectCommitResponse() { throw rejected; }}}), error => error === rejected);
  assert.deepEqual(f.calls, []);
  assert.equal(f.saved.responseBytes.toString('utf8'), f.physical);
});

test('unknown Table response neither projects nor invents a terminal fact', () => {
  const f = fixture();
  assert.deepEqual(settleSavedTableCommit({...f,
    ledger: {...f.ledger, readClaimedResponse: () => undefined}}), {status: 'unknown'});
  assert.deepEqual(f.calls, []);
});
