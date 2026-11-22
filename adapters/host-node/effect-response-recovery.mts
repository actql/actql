// @ts-expect-error The shared runtime facade is still authored in JavaScript.
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {retainIssuedEffectSetReceipt} from
  '../host-common/effect-receipt-custody.mjs';
import {snapshotEffectDispatchClaim,
  snapshotEffectDispatchClaims} from './effect-physical-dispatch.mjs';
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';
import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';

type ClaimInput = Parameters<typeof snapshotEffectDispatchClaim>[0];
type Claim = ReturnType<typeof snapshotEffectDispatchClaim>;
type ClaimGroup = Claim | readonly Claim[] | undefined;
type ReadLedger<Stored> = Readonly<{
  scopeCid: string;
  readClaimedResponse?(claim: Claim): Stored | undefined;
  readClaimedBatchResponse?(claims: readonly Claim[]): Stored | undefined;
}>;
type EvidenceBinding = Readonly<Record<string, string | number | boolean | readonly string[]>>;
type EvidenceAuthorization = (binding: EvidenceBinding) => boolean | PromiseLike<boolean>;
type ReadOptions<Stored> = Readonly<{
  ledger: ReadLedger<Stored>; claims: ClaimInput | readonly ClaimInput[];
  commonMoon: unknown; expectedRequestCid: string | undefined; providerBinding?: Readonly<Record<string, unknown>>;
  authorizeEvidenceRead: EvidenceAuthorization; batch?: boolean; invalidCode?: string; foreignCode?: string;
}>;
type ProjectOptions<Stored, Recovered> = ReadOptions<Stored> & Readonly<{projectStored(stored: Stored): Recovered}>;
type ReadOutcomes<Stored, Outcome> = ReadOptions<Stored> & Readonly<{
  ledger: ReadLedger<Stored> & Readonly<{
    readClaimedOutcome?(claim: Claim): Outcome | undefined;
    readClaimedBatchOutcomes?(claims: readonly Claim[]): readonly (Outcome | undefined)[] | undefined;
  }>;
}>;
type TerminalArguments = Readonly<{preview: unknown; memberIndex: number;
  previewRowIndex: number; batchRowIndex?: number}>;
type TerminalRead<Stored, Receipt> = ReadOptions<Stored> & TerminalArguments & Readonly<{
  ledger: ReadLedger<Stored> & Readonly<{
    readAdmittedTerminalOutcome?(options: TerminalArguments & Readonly<{
      claim?: Claim; claims?: readonly Claim[];
    }>): Receipt;
  }>;
}>;
type RowOwner = Readonly<{claim: EffectDispatchClaim; claims?: never; batchRowIndex?: never}> |
  Readonly<{claims: readonly EffectDispatchClaim[]; batchRowIndex: number; claim?: never}>;
type OwnedRowOwner = Readonly<{claim: Claim; claims?: never; batchRowIndex?: never}> |
  Readonly<{claims: readonly Claim[]; batchRowIndex: number; claim?: never}>;
type MemberOptions = Readonly<{
  ledger: ReadLedger<unknown>; rowOwners: readonly RowOwner[]; commonMoon: unknown;
  authorizeEvidenceRead: EvidenceAuthorization; providerBinding?: Readonly<Record<string, unknown>>;
}>;
type MemberPartition = Readonly<{preview: unknown; memberIndex: number; rowOwners: readonly OwnedRowOwner[]}>;
type MemberReceipt = Readonly<{wire: string}>;
type CheckMemberOptions = MemberOptions & Readonly<{
  preview: unknown; memberIndex: number; memberReceiptWire: string;
  ledger: ReadLedger<unknown> & Readonly<{
    checkMemberReceiptRowPartitionEvidence?(facts: MemberPartition & Readonly<{memberReceiptWire: string}>): unknown;
  }>;
}>;
type IssueMemberOptions = MemberOptions & Readonly<{
  preview: unknown; memberIndex: number;
  ledger: ReadLedger<unknown> & Readonly<{issueMemberReceiptFromRowPartition?(facts: MemberPartition): MemberReceipt}>;
}>;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type SetReceiptOptions = Omit<IssueMemberOptions, 'rowOwners' | 'memberIndex'> & Readonly<{
  members: readonly Readonly<{rowOwners: readonly RowOwner[]; replayed: boolean}>[];
  limits: Limits; publicationPreview?: unknown;
}>;
type EvidenceControl = Pick<ReturnType<typeof effectApplicationControl>, 'logicalRequestScopeCid' | 'logicalItemLocatorCid'>;
type EvidenceCore = Readonly<{
  effectApplicationControl: EvidenceControl & Pick<ReturnType<typeof effectApplicationControl>, 'issueSetReceiptFromMembers'>;
  publicationControl: Readonly<{
    issueEffectSetApplyReceiptFromMembers(preview: unknown, members: readonly MemberReceipt[],
      replayed: readonly boolean[], limits: Limits): Parameters<typeof retainIssuedEffectSetReceipt>[0]['set'];
  }>;
}>;

const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};

// Evidence access is separate from mutation admission. The common owner
// verifies the exact durable claim before exposing bytes to a provider
// projector; it never claims a new physical send or obtains a write grant.
export async function readAuthorizedEffectResponse<Stored>({
  ledger,
  claims,
  commonMoon,
  expectedRequestCid,
  providerBinding = {},
  authorizeEvidenceRead,
  batch = false,
  invalidCode = 'InvalidEffectResponseRead',
  foreignCode = 'ForeignEffectResponse',
}: ReadOptions<Stored>) {
  const ownedClaims = batch && Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims)
    : !batch && claims ? Object.freeze([snapshotEffectDispatchClaim(claims as ClaimInput)])
      : undefined;
  const read = batch ? ledger?.readClaimedBatchResponse
    : ledger?.readClaimedResponse;
  if (typeof read !== 'function' || typeof ledger.scopeCid !== 'string' ||
      !ownedClaims || ownedClaims.length === 0 || !commonMoon ||
      typeof expectedRequestCid !== 'string' ||
      typeof authorizeEvidenceRead !== 'function' ||
      !providerBinding || typeof providerBinding !== 'object' ||
      Array.isArray(providerBinding)) {
    fail(invalidCode);
  }
  const ownedProviderBinding = Object.create(null) as Record<string, string | number | boolean>;
  for (const [key, value] of Object.entries(providerBinding)) {
    if (['logicalRequestScopeCid', 'logicalItemLocatorCid',
      'logicalItemLocatorCids', 'canonicalRequestCid'].includes(key) ||
        !['string', 'number', 'boolean'].includes(typeof value)) {
      fail(invalidCode);
    }
    ownedProviderBinding[key] = value as string | number | boolean;
  }
  const effect: EvidenceControl = runtimeCore(commonMoon).effectApplicationControl;
  if (ownedClaims.some(claim =>
    effect.logicalRequestScopeCid(claim.scope) !== ledger.scopeCid ||
    claim.canonicalRequestCid !== expectedRequestCid)) {
    fail(foreignCode);
  }
  const locators = Object.freeze(ownedClaims.map(claim =>
    effect.logicalItemLocatorCid(claim.locator)));
  const binding = Object.freeze({
    logicalRequestScopeCid: ledger.scopeCid,
    ...(batch ? {logicalItemLocatorCids: locators} : {
      logicalItemLocatorCid: locators[0],
    }),
    canonicalRequestCid: expectedRequestCid,
    ...ownedProviderBinding,
  });
  if (await authorizeEvidenceRead(binding) !== true) {
    fail('EffectEvidenceAccessDenied');
  }
  const stored = batch ? (read as NonNullable<ReadLedger<Stored>['readClaimedBatchResponse']>).call(ledger, ownedClaims)
    : (read as NonNullable<ReadLedger<Stored>['readClaimedResponse']>).call(ledger, ownedClaims[0]);
  return Object.freeze({stored, binding});
}

// Recovery owns the evidence-read sequence, while the provider supplies only
// its interpretation of the already stored observation. No write authority,
// credential use, or physical send is available on this path.
export async function recoverProjectedEffectResponse<Stored, Recovered>({
  projectStored,
  ...readOptions
}: ProjectOptions<Stored, Recovered>) {
  if (typeof projectStored !== 'function') {
    fail('InvalidEffectResponseProjection');
  }
  const {stored} = await readAuthorizedEffectResponse(readOptions);
  return Object.freeze({
    recovered: stored === undefined ? undefined : projectStored(stored),
  });
}

// Evidence viewing precedes exact physical outcome access. The returned
// record is custody of a prior projection, not semantic admission or a
// terminal Effect fact; no write credential or new send is available here.
export async function readAuthorizedEffectOutcomes<Stored, Outcome>(options: ReadOutcomes<Stored, Outcome>) {
  const {ledger, claims, batch = false} = options;
  const ownedClaims = batch && Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims)
    : !batch && claims ? snapshotEffectDispatchClaim(claims as ClaimInput) : undefined;
  const {stored, binding} = await readAuthorizedEffectResponse({
    ...options, claims: ownedClaims,
  });
  if (stored === undefined) return Object.freeze({outcomes: undefined,
    binding});
  const read = batch ? ledger.readClaimedBatchOutcomes
    : ledger.readClaimedOutcome;
  if (typeof read !== 'function') fail('InvalidEffectOutcomeRead');
  const outcomes = (read as (claims: ClaimGroup) => Outcome | readonly (Outcome | undefined)[] | undefined).call(ledger, ownedClaims);
  return Object.freeze({outcomes, binding});
}

// Member aggregation consumes only terminal receipts re-admitted from the
// exact saved dispatch and response. An evidence-view grant is required even
// when the caller also holds current mutation authority.
export async function readAuthorizedEffectTerminalOutcome<Stored, Receipt>(options: TerminalRead<Stored, Receipt>) {
  const {ledger, claims, batch = false, batchRowIndex, preview,
    memberIndex, previewRowIndex} = options;
  const ownedClaims = batch && Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims)
    : !batch && claims ? snapshotEffectDispatchClaim(claims as ClaimInput) : undefined;
  const {stored, binding} = await readAuthorizedEffectResponse({
    ...options, claims: ownedClaims,
  });
  if (stored === undefined) return Object.freeze({receipt: undefined,
    binding});
  if (typeof ledger.readAdmittedTerminalOutcome !== 'function') {
    fail('InvalidEffectTerminalOutcomeRead');
  }
  const receipt = ledger.readAdmittedTerminalOutcome({
    ...(batch ? {claims: ownedClaims as readonly Claim[] | undefined, batchRowIndex} : {
      claim: ownedClaims as Claim | undefined,
    }),
    preview, memberIndex, previewRowIndex,
  });
  return Object.freeze({receipt, binding});
}

// A member Receipt is not evidence by itself. Authorize the exact retained
// dispatches first, then compare its row partition with one durable Store
// snapshot and re-admit every terminal row Receipt from saved response bytes.
async function authorizeMemberReceiptRows({
  ledger,
  rowOwners,
  commonMoon,
  authorizeEvidenceRead,
  providerBinding = {},
}: MemberOptions) {
  if (!Array.isArray(rowOwners) || rowOwners.length === 0) {
    fail('InvalidEffectMemberReceiptEvidence');
  }
  const batches = new Map<readonly ClaimInput[], readonly Claim[]>();
  const ownedOwners: OwnedRowOwner[] = rowOwners.map((owner: RowOwner) => {
    if (owner?.claims === undefined) {
      return Object.freeze({claim: snapshotEffectDispatchClaim(owner?.claim)});
    }
    if (!Array.isArray(owner.claims) ||
        !Number.isSafeInteger(owner.batchRowIndex) ||
        owner.batchRowIndex < 0 || owner.batchRowIndex >= owner.claims.length) {
      fail('InvalidEffectMemberReceiptEvidence');
    }
    let claims = batches.get(owner.claims);
    if (claims === undefined) {
      claims = snapshotEffectDispatchClaims(owner.claims);
      batches.set(owner.claims, claims);
    }
    return Object.freeze({claims, batchRowIndex: owner.batchRowIndex});
  });
  const authorizedBatches = new Set<readonly Claim[]>();
  for (const owner of ownedOwners) {
    if (owner.claim !== undefined) {
      await readAuthorizedEffectResponse({ledger, claims: owner.claim,
        commonMoon, expectedRequestCid: owner.claim.canonicalRequestCid,
        providerBinding, authorizeEvidenceRead});
    } else if (!authorizedBatches.has(owner.claims)) {
      await readAuthorizedEffectResponse({ledger, claims: owner.claims,
        commonMoon,
        expectedRequestCid: owner.claims[0].canonicalRequestCid,
        providerBinding, authorizeEvidenceRead, batch: true});
      authorizedBatches.add(owner.claims);
    }
  }
  return ownedOwners;
}

export async function checkAuthorizedEffectMemberReceiptRowPartition({
  ledger, rowOwners, preview, memberIndex, memberReceiptWire, commonMoon,
  authorizeEvidenceRead, providerBinding = {},
}: CheckMemberOptions) {
  if (typeof ledger?.checkMemberReceiptRowPartitionEvidence !== 'function') {
    fail('InvalidEffectMemberReceiptEvidence');
  }
  const ownedOwners = await authorizeMemberReceiptRows({ledger, rowOwners,
    commonMoon, authorizeEvidenceRead, providerBinding});
  return ledger.checkMemberReceiptRowPartitionEvidence({
    preview, memberIndex, rowOwners: ownedOwners, memberReceiptWire,
  });
}

// Only the common owner issues a member Receipt. Authorization precedes the
// durable head snapshot; the issuer then re-admits every terminal row fact.
export async function issueAuthorizedEffectMemberReceipt({
  ledger, rowOwners, preview, memberIndex, commonMoon,
  authorizeEvidenceRead, providerBinding = {},
}: IssueMemberOptions) {
  if (typeof ledger?.issueMemberReceiptFromRowPartition !== 'function') {
    fail('InvalidEffectMemberReceiptEvidence');
  }
  const ownedOwners = await authorizeMemberReceiptRows({ledger, rowOwners,
    commonMoon, authorizeEvidenceRead, providerBinding});
  return ledger.issueMemberReceiptFromRowPartition({
    preview, memberIndex, rowOwners: ownedOwners,
  });
}

// Set issuance reuses the physical evidence path of every member. For final
// publication, MoonBit rechecks those rows against the separately owned
// publication Preview before the exact Ledger/Preview pair is retained.
// Replay flags remain explicit Host observations, not inferred row facts.
export async function issueAuthorizedEffectSetReceipt({
  ledger, members, preview, commonMoon, authorizeEvidenceRead,
  providerBinding = {}, limits, publicationPreview,
}: SetReceiptOptions) {
  if (!Array.isArray(members) || members.length === 0 ||
      members.some((member: SetReceiptOptions['members'][number]) => !Array.isArray(member?.rowOwners) ||
        typeof member.replayed !== 'boolean') ||
      !limits || !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
        Number.isSafeInteger(limits[key as keyof Limits]) && limits[key as keyof Limits] > 0)) {
    fail('InvalidEffectSetReceiptEvidence');
  }
  const core: EvidenceCore = runtimeCore(commonMoon);
  const issuedMembers: MemberReceipt[] = [];
  for (let memberIndex = 0; memberIndex < members.length; memberIndex++) {
    issuedMembers.push(await issueAuthorizedEffectMemberReceipt({
      ledger, rowOwners: members[memberIndex].rowOwners, preview,
      memberIndex, commonMoon, authorizeEvidenceRead, providerBinding,
    }));
  }
  const set = publicationPreview === undefined
    ? core.effectApplicationControl
      .issueSetReceiptFromMembers(
        preview, issuedMembers.map(member => member.wire),
        members.map(member => member.replayed), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth)
    : core.publicationControl.issueEffectSetApplyReceiptFromMembers(
      publicationPreview, issuedMembers,
      members.map(member => member.replayed), limits);
  return retainIssuedEffectSetReceipt({set, members: issuedMembers,
    ledger, preview: publicationPreview ?? preview});
}
