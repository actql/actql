import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {snapshotEffectDispatchClaim} from './effect-physical-dispatch.mjs';

import type {requireAuthorizedDispatch} from '../host-common/authorization-gate.mjs';
import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';
import type {openEffectLedger} from './effect-ledger.mjs';

type Decision = Awaited<ReturnType<typeof requireAuthorizedDispatch>>;
type ApprovalDecision = Pick<Decision, 'basis' | 'checkpointCid' | 'resolutionCid'>;
type MappingApproval = Readonly<{mapping: Readonly<{approval?: string}>}>;
type ApprovalMember =
  | (MappingApproval & Readonly<{kind: 'create' | 'update' | 'upsert' | 'delete'}>)
  | Readonly<{kind: 'command'}>;
type MemberRef = Readonly<{kind: ApprovalMember['kind']; resource: string}>;
type Row = Readonly<{
  target_row_identity?: unknown;
  intended_changes?: Readonly<{value?: unknown}>;
  after?: Readonly<{value?: unknown}>;
}>;
type EffectControl = ReturnType<typeof effectApplicationControl>;
type Ledger = ReturnType<typeof openEffectLedger>;
type Preview = Parameters<EffectControl['admitMemberRow']>[0];
type SettleInput = Readonly<{
  ledger: Pick<Ledger, 'recordAdmittedRowOutcome' | 'commitAdmittedRowOutcome'>;
  claim: EffectDispatchClaim;
  applyPreview: Preview;
  memberIndex: number;
  rowIndex: number;
  projected?: Readonly<{kind?: string; outcome?: Readonly<{state?: string}>}>;
}>;
type Admission<Member> = Readonly<{
  applyPreview: Preview;
  memberIndex: number;
  rowIndex: number;
  claim: EffectDispatchClaim;
  member: Member;
  entry: Readonly<{request: unknown; requestCid: string; value?: unknown; target?: unknown}>;
  previewRow: Row;
}>;
type CommitControls<Member extends MemberRef> = Readonly<{
  moon: Readonly<{strategyEffectPreviewOrderedRowCid: EffectControl['previewOrderedRowCid']}>;
  effect: Pick<EffectControl, 'admitMemberRow' | 'dispatchKeyCid'>;
  ownerOf(member: Member): Readonly<{
    connection: string;
    owned: Readonly<{assertRequestFinalized?(request: unknown, keyCid: string): unknown}>;
  }>;
  sameEffectValue(kind: Member['kind'], left: unknown, right: unknown): boolean;
  sameValue(left: unknown, right: unknown): boolean;
  targeted(kind: Member['kind']): boolean;
  fail(code: string): never;
}>;

// Command has no contract minimum. Only legacy Mapping DATA uses this reader.
export const approvalOf = (member: MappingApproval) => member.mapping.approval;
export const approvedValue = (kind: ApprovalMember['kind'], row: Row) => kind === 'delete' ? undefined : kind === 'command'
  ? row.intended_changes?.value : row.after?.value;

export function createInstalledRowEffectApproval(text: (value: unknown) => boolean) {
  // A Mapping that requires approval is written only under a commit the Host
  // resumed from a resolved Checkpoint of this sealed Set; an account allow
  // alone is not an approval. Decided from the commit decision before the
  // row's claim, so the Set's prepared intents show nothing was sent.
  const requireApproval = (member: ApprovalMember, decision: ApprovalDecision | undefined) => {
    if (member.kind !== 'command' && approvalOf(member) === 'required' &&
        (decision?.basis !== 'resumed' || !text(decision.checkpointCid) ||
          !text(decision.resolutionCid))) {
      throw refusedEffectPreparation(Object.assign(
        new Error('InstalledRowEffectApprovalRequired'),
        {code: 'InstalledRowEffectApprovalRequired'}));
    }
  };
  return requireApproval;
}

export function createInstalledRowEffectCommit<Member extends MemberRef>({
  moon, effect, ownerOf, sameEffectValue, sameValue, targeted, fail,
}: CommitControls<Member>) {
  const reject: CommitControls<Member>['fail'] = fail;
  const scopeKey = (member: Member) => JSON.stringify([ownerOf(member).connection, member.resource]);
  // A resource name alone cannot identify a decision across installations.
  const commitDecisions = (decisions: readonly (Decision | undefined)[] | undefined,
    subjectCid: string, members: readonly Member[]) => {
    const byScope = new Map<string, Decision>();
    const required = new Set(members.map(scopeKey));
    for (const decision of decisions ?? []) {
      const tuple = decision?.tuple;
      const key = JSON.stringify([tuple?.connection ?? null, tuple?.resource ?? null]);
      if (decision?.action !== 'dispatch' || decision.boundary !== 'effect_commit' ||
          decision.subjectCid !== subjectCid || tuple?.operation !== 'effect' ||
          !required.has(key) || byScope.has(key)) reject('InstalledRowEffectCommitNotAuthorized');
      byScope.set(key, decision);
    }
    for (const key of required) if (!byScope.has(key)) reject('InstalledRowEffectCommitNotAuthorized');
    return byScope;
  };

  // Settle one row from a typed provider outcome. Anything else leaves the
  // row's possible dispatch unknown; it is never resent.
  const settle = ({ledger, claim, applyPreview, memberIndex, rowIndex,
    projected}: SettleInput) => {
    if (projected?.kind !== 'typed-success-response' &&
        projected?.kind !== 'typed-failure-response') return undefined;
    const outcome = projected.outcome;
    if (!['applied', 'failed'].includes(outcome?.state as string)) {
      reject('InvalidInstalledRowEffectOutcome');
    }
    const recorded = ledger.recordAdmittedRowOutcome({claim,
      preview: applyPreview, memberIndex, previewRowIndex: rowIndex,
      outcomeWire: canonicalValueJson(outcome, {dataKeys: true})});
    const terminal = ledger.commitAdmittedRowOutcome({claim,
      preview: applyPreview, memberIndex, previewRowIndex: rowIndex});
    return Object.freeze({outcomeReceipt: recorded.receipt,
      terminal: terminal.transition});
  };

  // Bind a row's request to its admitted Preview row: the request must write
  // exactly the approved value to exactly the approved target, under its
  // claim.
  const admitRow = ({applyPreview, memberIndex, rowIndex, claim, member,
    entry, previewRow}: Admission<Member>) => {
    ownerOf(member).owned.assertRequestFinalized?.(entry.request, effect.dispatchKeyCid(claim.key));
    if (claim.canonicalRequestCid !== entry.requestCid ||
        !sameEffectValue(member.kind, entry.value, approvedValue(member.kind, previewRow)) ||
        (targeted(member.kind) &&
          !sameValue(entry.target, previewRow.target_row_identity))) {
      reject('ForeignInstalledRowEffectRequest');
    }
    const rowPreviewCid = moon.strategyEffectPreviewOrderedRowCid(
      applyPreview, memberIndex, rowIndex);
    if (typeof rowPreviewCid !== 'string') {
      reject('InvalidInstalledRowEffectDispatch');
    }
    const ownedClaim = snapshotEffectDispatchClaim(claim);
    effect.admitMemberRow(applyPreview, memberIndex, rowIndex, member.kind,
      ownedClaim.scope, rowPreviewCid, ownedClaim.locator, ownedClaim.key);
    return ownedClaim;
  };

  return {scopeKey, commitDecisions, settle, admitRow};
}
