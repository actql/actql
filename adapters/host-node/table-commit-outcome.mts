// Settle only the response already retained by the existing send-once Ledger.
// This is not an installer/approval gate or a send/retry path. A lost or invalid
// reply remains uncertain; only the original Catalog receipt can supply the
// typed terminal projection. Current table head is never inspected here.
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';

type ClaimIdentity = Pick<EffectDispatchClaim, 'canonicalRequestCid'>;
type UnknownOutcome = Readonly<{status: 'unknown'; receipt?: never}>;
type ReceiptState = Readonly<{terminalState: string | undefined}>;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Binding = Readonly<{operationWire: string; preview: unknown; memberIndex: number}>;
type Control = Readonly<{
  localTableCommitResponse?(responseWire: string, statusCode: number, limits: unknown): unknown;
  tablePreviewLedgerBinding(preview: object): Binding;
  tablePreviewCommitOutcome(preview: object, responseWire: unknown, statusCode: number, limits: Limits): string;
}>;
type StoredResponse = Readonly<{responseBytes: Uint8Array; statusCode: number}>;
type OutcomeOwner<Claim> = Readonly<{claim: Claim; preview: unknown; memberIndex: number; previewRowIndex: number}>;
type Ledger<Claim, Receipt> = Readonly<{
  readClaimedResponse(claim: Claim): StoredResponse | undefined;
  recordAdmittedRowOutcome(options: OutcomeOwner<Claim> & Readonly<{outcomeWire: string}>): unknown;
  commitAdmittedRowOutcome(options: OutcomeOwner<Claim>): Readonly<{receipt: Receipt}>;
}>;
type CommitOptions<Claim, Receipt> = Readonly<{
  control: Control; ledger: Ledger<Claim, Receipt>; tablePreview: object; claim: Claim; limits: Limits;
  bridge: Readonly<{projectCommitResponse?(input: Readonly<{
    control: Control; responseWire: string; statusCode: number; limits: Limits;
  }>): unknown}>;
}>;

export function settleSavedTableCommit<Claim extends ClaimIdentity, Receipt extends ReceiptState>(
  {control, ledger, tablePreview, claim, bridge, limits}: CommitOptions<Claim, Receipt>) {
  const binding = control.tablePreviewLedgerBinding(tablePreview);
  const operation = JSON.parse(binding.operationWire) as Readonly<{request_cid: string}>;
  if (claim?.canonicalRequestCid !== operation.request_cid) {
    throw Object.assign(new Error('ForeignTableDispatchRequest'),
      {code: 'ForeignTableDispatchRequest'});
  }
  // The Ledger separately checks scope, immutable basis, durable dispatch and
  // exact saved-response ownership. Never project a supplied body/status pair.
  const saved = ledger.readClaimedResponse(claim);
  if (saved === undefined) return Object.freeze({status: 'unknown'}) as UnknownOutcome;
  if (!Number.isSafeInteger(limits?.maxWireBytes) || limits.maxWireBytes < 1 ||
      saved.responseBytes.byteLength > limits.maxWireBytes) {
    throw Object.assign(new Error('TableCommitResponseLimit'),
      {code: 'TableCommitResponseLimit'});
  }
  const wire = new TextDecoder('utf-8', {fatal: true}).decode(saved.responseBytes);
  if (typeof bridge?.projectCommitResponse !== 'function') {
    throw Object.assign(new Error('MissingTableCommitProjector'),
      {code: 'MissingTableCommitProjector'});
  }
  const logicalWire = bridge.projectCommitResponse({control, responseWire: wire,
    statusCode: saved.statusCode, limits});
  const outcomeWire = control.tablePreviewCommitOutcome(tablePreview, logicalWire,
    saved.statusCode, limits);
  const options = {claim, preview: binding.preview,
    memberIndex: binding.memberIndex, previewRowIndex: 0};
  ledger.recordAdmittedRowOutcome({...options, outcomeWire});
  const terminal = ledger.commitAdmittedRowOutcome(options);
  return Object.freeze({status: terminal.receipt.terminalState, receipt: terminal.receipt});
}
