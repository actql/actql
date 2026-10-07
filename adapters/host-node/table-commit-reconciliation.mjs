// Readonly original-operation recovery under the existing Effect evidence,
// Ledger and typed Table outcome owners. This path never claims or sends a write.
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {readAuthorizedEffectResponse} from './effect-response-recovery.mjs';
import {snapshotEffectDispatchClaim} from './effect-physical-dispatch.mjs';
import {settleSavedTableCommit} from './table-commit-outcome.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const unknown = () => Object.freeze({status: 'unknown'});

export async function reconcileOriginalTableCommit({control, commonMoon, ledger,
  tablePreview, claim, bridge, authorizeEvidenceRead, credentialUseCid,
  maxRevisions, entryLimits, limits, signal}) {
  if (typeof bridge?.reconcileOperation !== 'function' || !cid(credentialUseCid) ||
      !Number.isSafeInteger(maxRevisions) || maxRevisions < 1 ||
      !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
        Number.isSafeInteger(limits?.[key]) && limits[key] > 0 &&
        Number.isSafeInteger(entryLimits?.[key]) && entryLimits[key] > 0)) {
    fail('InvalidTableCommitReconciliation');
  }
  const ownedClaim = snapshotEffectDispatchClaim(claim);
  const binding = control.tablePreviewLedgerBinding(tablePreview);
  const operation = JSON.parse(binding.operationWire);
  if (ownedClaim.canonicalRequestCid !== operation.request_cid ||
      ownedClaim.intentFingerprintCid !== binding.rowPreviewCid) {
    fail('ForeignTableDispatchRequest');
  }
  const effect = runtimeCore(commonMoon).effectApplicationControl;
  effect.admitMemberRow(binding.preview, binding.memberIndex, 0,
    effect.previewMemberKind(binding.preview, binding.memberIndex),
    ownedClaim.scope, binding.rowPreviewCid, ownedClaim.locator, ownedClaim.key);
  const read = () => readAuthorizedEffectResponse({ledger, claims: ownedClaim,
    commonMoon, expectedRequestCid: operation.request_cid,
    providerBinding: {catalogIdentityCid: operation.catalog_identity_cid},
    authorizeEvidenceRead, invalidCode: 'InvalidTableCommitEvidenceRead',
    foreignCode: 'ForeignTableDispatchRequest'});
  const settle = () => settleSavedTableCommit({control, ledger, tablePreview,
    claim: ownedClaim, limits});
  signal?.throwIfAborted();
  const initial = await read();
  signal?.throwIfAborted();
  if (initial.stored !== undefined) return settle();

  // The validated complete history must contain the original possible dispatch.
  // Prepared/missing intent is not permission to query-and-manufacture a send.
  // The common Ledger verifies its chain; common admission verifies its basis.
  let dispatching;
  for (const row of ledger.history(effect.logicalItemLocatorCid(ownedClaim.locator),
    maxRevisions)) {
    const entry = effect.admitLedgerEntry(row.entryJson, entryLimits.maxWireBytes,
      entryLimits.maxNodes, entryLimits.maxDepth);
    if (!effect.ledgerEntryMatchesBasis(entry, ownedClaim.basis)) {
      fail('ForeignTableDispatchRequest');
    }
    if (effect.ledgerEntryStateCode(entry) !== 1) continue;
    if (dispatching !== undefined || !effect.ledgerEntryAdmitsDispatch(entry,
      ownedClaim.scope, ownedClaim.locator, ownedClaim.key,
      ownedClaim.canonicalRequestCid)) fail('ForeignTableDispatchRequest');
    dispatching = entry;
  }
  if (dispatching === undefined) return unknown();

  const result = await bridge.reconcileOperation(operation, signal);
  signal?.throwIfAborted();
  // Snapshot before the next authorization await. This is a Catalog lookup
  // observation, not an invented reconstruction of the lost transport reply.
  const responseBytes = Buffer.from(JSON.stringify(result));
  if (responseBytes.byteLength > limits.maxWireBytes) fail('TableCommitResponseLimit');
  // Recheck current evidence access and consume a concurrent observer's saved
  // response rather than replacing its bytes, credential use or revision.
  const afterLookup = await read();
  signal?.throwIfAborted();
  if (afterLookup.stored !== undefined) return settle();
  const observed = JSON.parse(responseBytes.toString('utf8'));
  if (observed?.ok !== true || observed.result === null) return unknown();
  // Validate the original request, schema/mapping, expected UUID and immutable
  // row count before adding evidence. No current-head success inference.
  control.tablePreviewCommitOutcome(tablePreview,
    responseBytes.toString('utf8'), 200, limits);
  try {
    ledger.recordResponse({dispatching, scope: ownedClaim.scope,
      locator: ownedClaim.locator, key: ownedClaim.key,
      canonicalRequestCid: operation.request_cid, credentialUseCid,
      statusCode: 200, responseBytes});
  } catch (error) {
    // Another process can win the response CAS after our read. Its exact
    // durable bytes remain authoritative; an unrelated failure stays a failure.
    if (error?.code !== 'EffectPhysicalResponseCollision' ||
        ledger.readClaimedResponse(ownedClaim) === undefined) throw error;
  }
  // Only the response durably owned by the original dispatch can issue the
  // existing outcome Receipt and terminal Ledger transition.
  return settle();
}
