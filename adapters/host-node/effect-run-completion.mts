import {applyCapturedEffectSet, applyRecoveredEffectSet} from
  './effect-run-apply.mjs';
import {issueAuthorizedEffectSetReceipt} from
  './effect-response-recovery.mjs';
import {publishCompletedEffectfulRun, transferCompletedEffectfulCaptureCustody} from
  '../host-common/completed-run-publication.mjs';
// @ts-expect-error The shared runtime facade is still authored in JavaScript.
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issuedEffectSetReceiptWires} from '../host-common/effect-receipt-custody.mjs';
import type {retainIssuedEffectSetReceipt} from '../host-common/effect-receipt-custody.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type Published = Parameters<typeof publishCompletedEffectfulRun>[0];
type IssuedSet = ReturnType<typeof retainIssuedEffectSetReceipt>;
type ReceiptOptions = Parameters<typeof issueAuthorizedEffectSetReceipt>[0];
type Ledger = ReceiptOptions['ledger'] & Readonly<{currentAdmitted(locator: string): unknown}>;
type ApplyOptions = Parameters<typeof applyCapturedEffectSet>[0] | Parameters<typeof applyRecoveredEffectSet>[0];
type ApplyRuntime = ApplyOptions['moon'] & Readonly<{
  strategyEffectPreviewSemanticCid(preview: unknown): unknown;
}>;
type ApplicationControl = Readonly<{
  logicalItemLocatorCid(locator: unknown): string;
  ledgerEntryStateCode(entry: unknown): number;
}>;
type DispatchRow = NonNullable<ApplyOptions['dispatchRow']>;
type DispatchInputs = Parameters<DispatchRow>[0];
type DispatchFacts = Parameters<NonNullable<ApplyOptions['bindDispatch']>>[0];
type Apply = ApplyOptions & Readonly<{
  moon: ApplyRuntime; ledger: Ledger; capturedInputs?: unknown;
  members?: readonly unknown[]; store?: unknown; publicationControl?: unknown;
  computation?: unknown; preview?: unknown;
}>;
type Receipt = Omit<ReceiptOptions, 'members'> & Readonly<{
  members: readonly Readonly<{replayed: boolean; rowOwners: readonly Readonly<{
    claim: Extract<ReceiptOptions['members'][number]['rowOwners'][number], {claim: object}>['claim'];
  }>[]}>[];
  publicationPreview: unknown;
}>;
type Publication = Omit<Published, 'ledger' | 'issuedSet' | 'signal' | 'control'> & Readonly<{
  ledger: unknown; control: Published['control'] & Readonly<{
    effectComputationPreviewSemanticCid(preview: unknown): unknown;
    effectSetReceiptRunDisposition(preview: Published['preview'],
      wires: ReturnType<typeof issuedEffectSetReceiptWires>, limits: Published['contractLimits']): number;
  }>;
}>;
type CompletionOptions = Readonly<{
  apply: Apply; receipt: Receipt; publication: Publication; signal?: AbortSignal;
  beforeDispatch?: () => SynchronousRuntimeData;
}>;
type Progress = Readonly<{status?: string; dispatched: number}> & Readonly<Record<string, unknown>>;
type ThenField = Readonly<{then?: unknown}>;
type EffectFailure = Readonly<{code?: unknown}>;

const fail: () => never = () => {
  throw Object.assign(new Error('InvalidCapturedEffectRunCompletion'), {
    code: 'InvalidCapturedEffectRunCompletion',
  });
};

// The Host owns the ordering of common apply, durable outcome admission and
// publication. A provider may supply physical dispatch and current observation,
// but cannot substitute a Set Receipt or decide that unknown rows succeeded.
function validateCompletion({apply, receipt, publication, beforeDispatch}: CompletionOptions, recovered: boolean) {
  if (!apply || !receipt || !publication ||
      apply.moon !== receipt.commonMoon ||
      apply.ledger !== receipt.ledger ||
      apply.ledger !== publication.ledger ||
      publication.preview !== receipt.publicationPreview ||
      !Array.isArray(receipt.members) ||
      receipt.members.length === 0 ||
      (!recovered && receipt.members.length !== apply.members?.length) ||
      typeof receipt.authorizeEvidenceRead !== 'function' ||
      beforeDispatch !== undefined && typeof beforeDispatch !== 'function' ||
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

async function issueAndPublish({apply, receipt, publication, signal}: CompletionOptions,
  progress: Progress) {
  if (progress.status === 'waiting') {
    return Object.freeze({status: 'waiting', progress});
  }
  const issuedSet: IssuedSet = await issueAuthorizedEffectSetReceipt({
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
    if ((error as EffectFailure | null | undefined)?.code === 'EffectfulRunNeedsReconciliation') {
      return Object.freeze({status: 'needs_reconciliation', progress,
        issuedSet});
    }
    if ((error as EffectFailure | null | undefined)?.code === 'EffectfulRunFailed') {
      return Object.freeze({status: 'failed', progress, issuedSet});
    }
    throw error;
  }
}

async function complete(options: CompletionOptions, recovered: boolean) {
  // Own the invocation wrapper before the first await; opaque checked owners
  // keep their references, while the caller cannot replace the custody target
  // or dispatch binder during current-use authorization.
  options = Object.freeze({...options,
    apply: Object.freeze({...options?.apply}),
    receipt: Object.freeze({...options?.receipt}),
    publication: Object.freeze({...options?.publication})});
  validateCompletion(options, recovered);
  // Current admission and durable row intents are established by apply before
  // this wrapper is entered. Transfer cleanup custody before any provider can
  // send, and never interpret a missing reply as permission to reclaim it.
  let transferred = false;
  const wrap = (dispatch: DispatchRow | undefined) => typeof dispatch !== 'function' ? dispatch : async (row: DispatchInputs) => {
    if (!transferred) {
      await transferCompletedEffectfulCaptureCustody(options.publication);
      transferred = true;
    }
    options.signal?.throwIfAborted();
    const fenced = options.beforeDispatch?.();
    if (typeof (fenced as ThenField | undefined)?.then === 'function') {
      void Promise.resolve(fenced).catch(() => {});
      fail();
    }
    return dispatch(row);
  };
  const original = options.apply;
  const apply = {...original, ...(original.bindDispatch === undefined
    ? {dispatchRow: wrap(original.dispatchRow)}
    : {bindDispatch: (facts: DispatchFacts) => wrap(original.bindDispatch!(facts))}),
    signal: options.signal};
  const progress: Progress = recovered
    ? await applyRecoveredEffectSet(apply as Parameters<typeof applyRecoveredEffectSet>[0])
    : await applyCapturedEffectSet(apply as Parameters<typeof applyCapturedEffectSet>[0]);
  return issueAndPublish(options, progress);
}

// Once a physical send is durably claimed, an observation failure cannot
// reuse the consumed resume admission or turn the row into a fresh request.
// Any attempted row needs the common Set receipt, including an already
// Applied/Accepted row followed by a currently refused unattempted remainder.
// The issuer, not this Host, determines partial failure versus uncertainty.
export function completeInterruptedEffectRun(options: CompletionOptions, recovered: boolean) {
  validateCompletion(options, recovered);
  const {apply, receipt} = options;
  const control: ApplicationControl = runtimeCore(apply.moon).effectApplicationControl;
  const attempted = receipt.members.some(member =>
    member.rowOwners.some(owner => {
      const entry = apply.ledger.currentAdmitted(
        control.logicalItemLocatorCid(owner.claim.locator));
      return entry !== undefined &&
        control.ledgerEntryStateCode(entry) !== 0;
    }));
  if (!attempted) {
    throw Object.assign(new Error('EffectRunNoAttemptedSend'), {
      code: 'EffectRunNoAttemptedSend'});
  }
  return issueAndPublish(options, Object.freeze({status: 'interrupted',
    dispatched: 0}));
}

// A failed resume binding can retain a fenced observation claim, but no new
// execution or publication authority. Aggregate the exact historical rows
// through the existing issuer; neither refresh nor a dispatch port is called.
export async function settleRefusedEffectRun(options: CompletionOptions) {
  options = Object.freeze({...options,
    apply: Object.freeze({...options?.apply}),
    receipt: Object.freeze({...options?.receipt}),
    publication: Object.freeze({...options?.publication})});
  validateCompletion(options, true);
  const {apply, receipt, publication} = options;
  const issuedSet: IssuedSet = await issueAuthorizedEffectSetReceipt({...receipt,
    ledger: apply.ledger, commonMoon: apply.moon,
    publicationPreview: publication.preview});
  const wires = issuedEffectSetReceiptWires(issuedSet, apply.ledger,
    publication.preview);
  const disposition = publication.control.effectSetReceiptRunDisposition(
    publication.preview, wires, publication.contractLimits);
  if (![0, 1, 2].includes(disposition)) fail();
  // Even a completely observed historical Set is not a grant to publish
  // under a refused current binding. Its applied/accepted receipt is kept.
  return Object.freeze({status: disposition === 1 ? 'needs_reconciliation' : 'failed',
    progress: Object.freeze({status: 'refused', dispatched: 0}), issuedSet});
}

export function completeCapturedEffectRun(options: CompletionOptions) {
  return complete(options, false);
}

export function completeRecoveredEffectRun(options: CompletionOptions) {
  return complete(options, true);
}
