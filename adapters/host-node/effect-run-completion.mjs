import {applyCapturedEffectSet, applyRecoveredEffectSet} from
  './effect-run-apply.mjs';
import {issueAuthorizedEffectSetReceipt} from
  './effect-response-recovery.mjs';
import {publishCompletedEffectfulRun} from
  '../host-common/completed-run-publication.mjs';

const fail = () => {
  throw Object.assign(new Error('InvalidCapturedEffectRunCompletion'), {
    code: 'InvalidCapturedEffectRunCompletion',
  });
};

// The Host owns the ordering of common apply, durable outcome admission and
// publication. A provider may supply physical dispatch and current observation,
// but cannot substitute a Set Receipt or decide that unknown rows succeeded.
async function complete({apply, receipt, publication, signal}, recovered) {
  if (!apply || !receipt || !publication ||
      apply.moon !== receipt.commonMoon ||
      apply.ledger !== receipt.ledger ||
      apply.ledger !== publication.ledger ||
      publication.preview !== receipt.publicationPreview ||
      !Array.isArray(receipt.members) ||
      receipt.members.length === 0 ||
      (!recovered && receipt.members.length !== apply.members?.length) ||
      typeof receipt.authorizeEvidenceRead !== 'function' ||
      (recovered && (apply.store !== publication.store ||
        apply.publicationControl !== publication.control ||
        apply.computation !== publication.computation ||
        apply.preview !== publication.preview))) fail();
  const subjectCid = recovered
    ? publication.control.effectComputationPreviewSemanticCid(apply.preview)
    : apply.moon.clientProgramEffectApplySubjectCid(apply.capturedInputs);
  const publicationCid = publication.control
    .effectComputationPreviewSemanticCid(publication.preview);
  const receiptCid = apply.moon.strategyEffectPreviewSemanticCid(
    receipt.preview);
  if (typeof subjectCid !== 'string' || subjectCid !== publicationCid ||
      receiptCid !== publicationCid) fail();
  const progress = recovered
    ? await applyRecoveredEffectSet({...apply, signal})
    : await applyCapturedEffectSet({...apply, signal});
  if (progress.status === 'waiting') {
    return Object.freeze({status: 'waiting', progress});
  }
  const issuedSet = await issueAuthorizedEffectSetReceipt({
    ...receipt,
    ledger: apply.ledger,
    commonMoon: apply.moon,
    publicationPreview: publication.preview,
  });
  try {
    const completed = await publishCompletedEffectfulRun({
      ...publication, ledger: apply.ledger, issuedSet, signal,
    });
    return Object.freeze({status: 'published', progress, issuedSet,
      completed});
  } catch (error) {
    if (error?.code === 'EffectfulRunNeedsReconciliation') {
      return Object.freeze({status: 'needs_reconciliation', progress,
        issuedSet});
    }
    if (error?.code === 'EffectfulRunFailed') {
      return Object.freeze({status: 'failed', progress, issuedSet});
    }
    throw error;
  }
}

export function completeCapturedEffectRun(options) {
  return complete(options, false);
}

export function completeRecoveredEffectRun(options) {
  return complete(options, true);
}
