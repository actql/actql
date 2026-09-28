import {applyCapturedEffectSet, applyRecoveredEffectSet} from
  './effect-run-apply.mjs';
import {issueAuthorizedEffectSetReceipt} from
  './effect-response-recovery.mjs';
import {publishCompletedEffectfulRun} from
  '../host-common/completed-run-publication.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const fail = () => {
  throw Object.assign(new Error('InvalidCapturedEffectRunCompletion'), {
    code: 'InvalidCapturedEffectRunCompletion',
  });
};

// The Host owns the ordering of common apply, durable outcome admission and
// publication. A provider may supply physical dispatch and current observation,
// but cannot substitute a Set Receipt or decide that unknown rows succeeded.
function validateCompletion({apply, receipt, publication}, recovered) {
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
}

async function issueAndPublish({apply, receipt, publication, signal},
  progress) {
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

async function complete(options, recovered) {
  validateCompletion(options, recovered);
  const progress = recovered
    ? await applyRecoveredEffectSet({...options.apply, signal: options.signal})
    : await applyCapturedEffectSet({...options.apply, signal: options.signal});
  return issueAndPublish(options, progress);
}

// Once a physical send is durably claimed, an observation failure cannot
// reuse the consumed resume admission or turn the row into a fresh request.
// A dispatching/unknown head is sufficient to issue the Set's uncertainty
// receipt; it is not evidence that any external mutation succeeded.
export function completeInterruptedEffectRun(options, recovered) {
  validateCompletion(options, recovered);
  const {apply, receipt} = options;
  const control = runtimeCore(apply.moon).effectApplicationControl;
  const uncertain = receipt.members.some(member =>
    member.rowOwners.some(owner => {
      const entry = apply.ledger.currentAdmitted(
        control.logicalItemLocatorCid(owner.claim.locator));
      return entry !== undefined &&
        [1, 5].includes(control.ledgerEntryStateCode(entry));
    }));
  if (!uncertain) {
    throw Object.assign(new Error('EffectRunNoUncertainSend'), {
      code: 'EffectRunNoUncertainSend'});
  }
  return issueAndPublish(options, Object.freeze({status: 'interrupted',
    dispatched: 0}));
}

export function completeCapturedEffectRun(options) {
  return complete(options, false);
}

export function completeRecoveredEffectRun(options) {
  return complete(options, true);
}
