// Settle only the response already retained by the existing send-once Ledger.
// This is not an installer/approval gate or a send/retry path. A lost or invalid
// reply remains uncertain; only the original Catalog receipt can supply the
// typed terminal projection. Current table head is never inspected here.
export function settleSavedTableCommit({control, ledger, tablePreview, claim,
  limits}) {
  const binding = control.tablePreviewLedgerBinding(tablePreview);
  const operation = JSON.parse(binding.operationWire);
  if (claim?.canonicalRequestCid !== operation.request_cid) {
    throw Object.assign(new Error('ForeignTableDispatchRequest'),
      {code: 'ForeignTableDispatchRequest'});
  }
  // The Ledger separately checks scope, immutable basis, durable dispatch and
  // exact saved-response ownership. Never project a supplied body/status pair.
  const saved = ledger.readClaimedResponse(claim);
  if (saved === undefined) return Object.freeze({status: 'unknown'});
  if (!Number.isSafeInteger(limits?.maxWireBytes) || limits.maxWireBytes < 1 ||
      saved.responseBytes.byteLength > limits.maxWireBytes) {
    throw Object.assign(new Error('TableCommitResponseLimit'),
      {code: 'TableCommitResponseLimit'});
  }
  const wire = new TextDecoder('utf-8', {fatal: true}).decode(saved.responseBytes);
  const outcomeWire = control.tablePreviewCommitOutcome(tablePreview, wire,
    saved.statusCode, limits);
  const options = {claim, preview: binding.preview,
    memberIndex: binding.memberIndex, previewRowIndex: 0};
  ledger.recordAdmittedRowOutcome({...options, outcomeWire});
  const terminal = ledger.commitAdmittedRowOutcome(options);
  return Object.freeze({status: 'applied', receipt: terminal.receipt});
}
