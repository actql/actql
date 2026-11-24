import {approvedValue} from './installed-row-effect-commit.mjs';

import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {ControlWork} from './installed-effect-plan.mjs';
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';
import type {createInstalledRowEffectRequests} from './installed-row-effect-members.mjs';

type MemberKind = Parameters<typeof approvedValue>[0];
type MemberRef = Readonly<{kind: MemberKind; resource: string}>;
type PreviewRow = Readonly<{
  row_preview_cid: string;
  target_row_identity?: unknown;
  after?: Readonly<{value?: unknown}>;
  intended_changes?: Readonly<{value?: unknown}>;
}>;
type PreviewMember = Readonly<{changes: readonly PreviewRow[]; row_order: readonly string[]}>;
type ClaimMember = PreviewMember & Readonly<{
  effect_id: string;
  effect_member_preview_cid: string;
  capability_evidence_cid: string;
}>;
type ClaimEntry = Readonly<{request: unknown; requestCid: string}>;
type ClaimFacts<Member> = Readonly<{
  body: Readonly<{effects: readonly ClaimMember[]}>;
  keys: readonly (readonly unknown[])[];
  entries: readonly (readonly ClaimEntry[])[];
  requestScope: unknown;
  unit: Readonly<{programId: string; stageId: string}>;
  dispatches: readonly string[];
  unitCids: readonly string[];
  members: readonly Member[];
  retentionId: string;
}>;
type Effect = ReturnType<typeof effectApplicationControl>;
type ClaimControls<Member> = Readonly<{
  effect: Pick<Effect, 'logicalItemLocator' | 'dispatchKeyCorrelationWire' | 'dispatchKeyCid' | 'ledgerBasis'>;
  limits: Readonly<{locator: Readonly<{maxBytes: number}>; key: Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>}>;
  ownerOf(member: Member): Readonly<{owned: Readonly<{assertRequestFinalized?(request: unknown, keyCid: string): SynchronousRuntimeData}>}>;
  recoveryCid(member: Member, dispatch: string): string;
  fail(code: string): never;
}>;
type Recorded = Readonly<{members: readonly Readonly<{claims: readonly Pick<EffectDispatchClaim, 'canonicalRequestCid'>[]}>[]}>;
type RecoveredRows<Member> = Readonly<{
  members: readonly Member[];
  body: Readonly<{effects: readonly PreviewMember[]}>;
  recorded: Recorded;
}>;
type DurableRecovery = Readonly<{connectorRecovery?: readonly Readonly<{
  memberIndex: number; kind: string; wire: string; observationCid: string;
}>[]}>;
export type RecoveryInput<Member> = RecoveredRows<Member> & Readonly<{
  durable: DurableRecovery;
  maxRows?: number;
  previewWire: string;
  runInvocationCid: string;
  dispatches: readonly string[];
  requestTags?: readonly (readonly string[] | undefined)[];
  reserveRecoveryInput?: (memberIndex: number, metadata: unknown) => SynchronousRuntimeData;
  controlConstruction?: ControlWork;
}>;
type RecoveryFacts<Member> = Omit<RecoveryInput<Member>, 'controlConstruction'> & Readonly<{runOriginal?: object}>;
type MemberRecoveryFacts<Member> = RecoveryFacts<Member> & Readonly<{memberIndexes: readonly number[]}>;
type Rebuilt = Readonly<{
  requests?: readonly (readonly unknown[])[];
  currents?: readonly unknown[];
  then?: never;
}>;
type RecoveryMethod<Member, Facts extends RecoveryFacts<Member>> =
  (this: RecoveryDriver<Member>, facts: Facts) => Rebuilt | undefined;
type RecoveryDriver<Member> = Readonly<{
  recoverRequests?: RecoveryMethod<Member, RecoveryFacts<Member>>;
  recoverMemberRequests?: RecoveryMethod<Member, MemberRecoveryFacts<Member>>;
  finalizeRequest?: (...args: never[]) => unknown;
  prepareRequest(facts: Readonly<{
    member: Member; value: unknown; selector: undefined; current: unknown; createRowIdentity?: unknown;
  }>): Readonly<{request?: unknown; requestCid?: string}> | undefined;
  requestCid(request: unknown): string;
}>;
type RecoveryOwner<Member> = Readonly<{owned: RecoveryDriver<Member>}>;
type Entry = ReturnType<ReturnType<typeof createInstalledRowEffectRequests>['entryOf']>;
type RecoveryControls<Member extends MemberRef, Owner extends RecoveryOwner<Member>> = Readonly<{
  owners: readonly Owner[];
  singular?: Owner;
  ownerOf(member: Member): Owner;
  orderedSourceIndexes(member: PreviewMember): readonly number[];
  resourceFields(member: Member): Readonly<{runOriginal?: object}>;
  entryOf(member: Member, request: unknown, requestCid: string | undefined): Entry;
  sameEffectValue(kind: MemberKind, left: unknown, right: unknown): boolean;
  sameValue(left: unknown, right: unknown): boolean;
  targeted(kind: MemberKind): boolean;
  fail(code: string): never;
}>;

export function createInstalledRowEffectClaims<Member>({
  effect, limits, ownerOf, recoveryCid, fail,
}: ClaimControls<Member>) {
  // Project original change positions from the Common-sealed dispatch order.
  // The Plan still verifies changes against the original source cursor; neither
  // source positions nor request/observation objects are rewritten to sort it.
  const orderedSourceIndexes = (member: PreviewMember) => {
    const positions = new Map(member.changes.map((row, index) => [row.row_preview_cid, index]));
    if (positions.size !== member.changes.length || member.row_order.length !== positions.size ||
        new Set(member.row_order).size !== positions.size) fail('InstalledRowEffectPreviewOrderMismatch');
    return Object.freeze(member.row_order.map(row => {
      if (!positions.has(row)) fail('InstalledRowEffectPreviewOrderMismatch');
      return positions.get(row)!;
    }));
  };

  // The Ledger claims of every row in the admitted dispatch order.
  // These three newly owned structural envelopes are final DATA for the
  // existing Ledger-family geometry. Keep original claim/opaque references;
  // do not freeze caller inputs or turn geometry into validation/currentness.
  const claimsOf = ({body, keys, entries, requestScope, unit, dispatches,
    unitCids, members, retentionId}: ClaimFacts<Member>) => Object.freeze(body.effects.map((member, memberIndex) => Object.freeze({
    claims: Object.freeze(orderedSourceIndexes(member).map(rowIndex => {
      const change = member.changes[rowIndex];
      const key = keys[memberIndex][rowIndex];
      const locator = effect.logicalItemLocator(requestScope,
        unit.programId, unit.stageId, member.effect_id,
        effect.dispatchKeyCorrelationWire(key), limits.locator.maxBytes,
        limits.key.maxBytes, limits.key.maxNodes, limits.key.maxDepth);
      const canonicalRequestCid = entries[memberIndex][rowIndex].requestCid;
      ownerOf(members[memberIndex]).owned.assertRequestFinalized?.(
        entries[memberIndex][rowIndex].request, effect.dispatchKeyCid(key));
      const basis = effect.ledgerBasis(requestScope, locator, key, unitCids[memberIndex],
        member.effect_member_preview_cid, change.row_preview_cid,
        canonicalRequestCid, recoveryCid(members[memberIndex], dispatches[memberIndex]),
        // A write without a provider idempotency key.
        'unavailable', member.capability_evidence_cid, retentionId);
      return {scope: requestScope, locator, key, basis,
        intentFingerprintCid: change.row_preview_cid, canonicalRequestCid};
    }))})));

  return {orderedSourceIndexes, claimsOf};
}

export function createInstalledRowEffectRecoveryEntries<Member extends MemberRef, Owner extends RecoveryOwner<Member>>({
  owners, singular, ownerOf, orderedSourceIndexes, resourceFields, entryOf, sameEffectValue, sameValue, targeted, fail,
}: RecoveryControls<Member, Owner>) {
  const reject: RecoveryControls<Member, Owner>['fail'] = fail;
  // Repeatable checked DATA comparison, never a request constructor or send
  // admission. Hot observation must recheck the actual current Ledger claims
  // against the SAME still-backed requests and approved original Preview.
  const validateRecoveredEntries = ({members, body, recorded}: RecoveredRows<Member>, entries: readonly (readonly Entry[])[]) => {
    if (!Array.isArray(entries) || entries.length !== members.length) reject('InstalledEffectContinuationMismatch');
    members.forEach((member, index) => {
      const changes = body.effects[index].changes, claims = recorded.members[index]?.claims ?? [];
      const rows = entries[index], sourceIndexes = orderedSourceIndexes(body.effects[index]);
      const claimBySource = new Map(sourceIndexes.map((sourceIndex, dispatchIndex) =>
        [sourceIndex, claims[dispatchIndex]]));
      if (!Array.isArray(rows) || rows.length !== changes.length || claims.length !== changes.length) {
        reject('InstalledEffectContinuationMismatch');
      }
      rows.forEach((entry, row) => {
        if (entry.requestCid !== claimBySource.get(row)?.canonicalRequestCid ||
            !sameEffectValue(member.kind, entry.value, approvedValue(member.kind, changes[row])) ||
            (targeted(member.kind) && !sameValue(entry.target, changes[row].target_row_identity))) {
          reject('ForeignInstalledRowEffectRequest');
        }
      });
    });
  };

  // Each recovered row's request, rebuilt from its approved Preview row (a
  // create) or from the provider's retained data (an update), and held to
  // exactly the request its durable claim names, the value the Preview
  // approved and, for an update, the Preview's target.
  const recoveredEntries = ({members, body, durable, recorded, maxRows,
    previewWire, runInvocationCid, dispatches, requestTags, controlConstruction, reserveRecoveryInput}: RecoveryInput<Member>) => {
    const restore = <Facts extends RecoveryFacts<Member>>(
      owned: RecoveryDriver<Member>, method: RecoveryMethod<Member, Facts>, facts: Facts,
    ) => controlConstruction === undefined || owned.finalizeRequest === undefined
      ? Reflect.apply(method, owned, [facts]) : controlConstruction(owned, method, [facts]);
    const rebuilt = singular?.owned.recoverRequests === undefined ? undefined :
      restore(singular.owned, singular.owned.recoverRequests, {durable, recorded, previewWire, body, maxRows,
        members, runInvocationCid, dispatches, requestTags, reserveRecoveryInput,
        ...resourceFields(members[0])});
    const requests = members.map((_, index) => rebuilt?.requests?.[index]);
    const usesRecovery = members.map(() => rebuilt !== undefined);
    const currents = members.map((_, index) => rebuilt?.currents?.[index]);
    if (singular === undefined) {
      for (const owner of owners) {
        if (owner.owned.recoverMemberRequests === undefined) continue;
        const memberIndexes = Object.freeze(members.flatMap((member, index) =>
          ownerOf(member) === owner ? [index] : []));
        if (memberIndexes.length === 0) continue;
        const recovered = restore(owner.owned, owner.owned.recoverMemberRequests, {durable, recorded, maxRows,
          previewWire, body, memberIndexes, members, runInvocationCid, dispatches, requestTags, reserveRecoveryInput,
          ...resourceFields(members[memberIndexes[0]])});
        if (!Array.isArray(recovered?.requests) ||
            recovered.requests.length !== memberIndexes.length ||
            (recovered.currents !== undefined &&
              (!Array.isArray(recovered.currents) ||
                recovered.currents.length !== memberIndexes.length))) {
          reject('InstalledEffectContinuationMismatch');
        }
        memberIndexes.forEach((index, selectedIndex) => {
          if (!Array.isArray(recovered.requests![selectedIndex])) {
            reject('InstalledEffectContinuationMismatch');
          }
          usesRecovery[index] = true;
          requests[index] = recovered.requests![selectedIndex];
          currents[index] = recovered.currents?.[selectedIndex];
        });
      }
    }
    const entries = members.map((member, index) => {
      const {owned} = ownerOf(member);
      const changes = body.effects[index].changes;
      const rows = !usesRecovery[index]
        ? changes.map(change => {
          const prepared = owned.prepareRequest({member,
            ...(member.kind === 'create' ? {createRowIdentity: Object.freeze(change.target_row_identity)} : {}),
            value: change.after?.value, selector: undefined,
            current: currents[index], ...resourceFields(member)});
          return entryOf(member, prepared?.request, prepared?.requestCid);
        })
        : (requests[index] ?? []).map(request =>
          entryOf(member, request, owned.requestCid(request)));
      return Object.freeze(rows);
    });
    validateRecoveredEntries({members, body, recorded}, entries);
    return {entries: Object.freeze(entries), currents: Object.freeze(currents)};
  };

  return {validateRecoveredEntries, recoveredEntries};
}
