import {runtimeCore} from '../host-common/runtime-core.mjs';
import {snapshotEffectDispatchClaim,
  snapshotEffectDispatchClaims} from './effect-physical-dispatch.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Evidence access is separate from mutation admission. The common owner
// verifies the exact durable claim before exposing bytes to a provider
// projector; it never claims a new physical send or obtains a write grant.
export async function readAuthorizedEffectResponse({
  ledger,
  claims,
  commonMoon,
  expectedRequestCid,
  providerBinding = {},
  authorizeEvidenceRead,
  batch = false,
  invalidCode = 'InvalidEffectResponseRead',
  foreignCode = 'ForeignEffectResponse',
}) {
  const ownedClaims = batch && Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims)
    : !batch && claims ? Object.freeze([snapshotEffectDispatchClaim(claims)])
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
  const ownedProviderBinding = Object.create(null);
  for (const [key, value] of Object.entries(providerBinding)) {
    if (['logicalRequestScopeCid', 'logicalItemLocatorCid',
      'logicalItemLocatorCids', 'canonicalRequestCid'].includes(key) ||
        !['string', 'number', 'boolean'].includes(typeof value)) {
      fail(invalidCode);
    }
    ownedProviderBinding[key] = value;
  }
  const effect = runtimeCore(commonMoon).effectApplicationControl;
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
  const stored = batch ? read.call(ledger, ownedClaims)
    : read.call(ledger, ownedClaims[0]);
  return Object.freeze({stored, binding});
}

// Recovery owns the evidence-read sequence, while the provider supplies only
// its interpretation of the already stored observation. No write authority,
// credential use, or physical send is available on this path.
export async function recoverProjectedEffectResponse({
  projectStored,
  ...readOptions
}) {
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
export async function readAuthorizedEffectOutcomes(options) {
  const {ledger, claims, batch = false} = options;
  const ownedClaims = batch && Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims)
    : !batch && claims ? snapshotEffectDispatchClaim(claims) : undefined;
  const {stored, binding} = await readAuthorizedEffectResponse({
    ...options, claims: ownedClaims,
  });
  if (stored === undefined) return Object.freeze({outcomes: undefined,
    binding});
  const read = batch ? ledger.readClaimedBatchOutcomes
    : ledger.readClaimedOutcome;
  if (typeof read !== 'function') fail('InvalidEffectOutcomeRead');
  const outcomes = read.call(ledger, ownedClaims);
  return Object.freeze({outcomes, binding});
}

// Member aggregation consumes only terminal receipts re-admitted from the
// exact saved dispatch and response. An evidence-view grant is required even
// when the caller also holds current mutation authority.
export async function readAuthorizedEffectTerminalOutcome(options) {
  const {ledger, claims, batch = false, batchRowIndex, preview,
    memberIndex, previewRowIndex} = options;
  const ownedClaims = batch && Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims)
    : !batch && claims ? snapshotEffectDispatchClaim(claims) : undefined;
  const {stored, binding} = await readAuthorizedEffectResponse({
    ...options, claims: ownedClaims,
  });
  if (stored === undefined) return Object.freeze({receipt: undefined,
    binding});
  if (typeof ledger.readAdmittedTerminalOutcome !== 'function') {
    fail('InvalidEffectTerminalOutcomeRead');
  }
  const receipt = ledger.readAdmittedTerminalOutcome({
    ...(batch ? {claims: ownedClaims, batchRowIndex} : {
      claim: ownedClaims,
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
}) {
  if (!Array.isArray(rowOwners) || rowOwners.length === 0) {
    fail('InvalidEffectMemberReceiptEvidence');
  }
  const batches = new Map();
  const ownedOwners = rowOwners.map(owner => {
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
  const authorizedBatches = new Set();
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
}) {
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
}) {
  if (typeof ledger?.issueMemberReceiptFromRowPartition !== 'function') {
    fail('InvalidEffectMemberReceiptEvidence');
  }
  const ownedOwners = await authorizeMemberReceiptRows({ledger, rowOwners,
    commonMoon, authorizeEvidenceRead, providerBinding});
  return ledger.issueMemberReceiptFromRowPartition({
    preview, memberIndex, rowOwners: ownedOwners,
  });
}

// Set issuance reuses the physical evidence path of every member. The replay
// flags are explicit Host observations; neither row state nor a new Receipt
// proves whether an earlier terminal result was replayed without dispatch.
export async function issueAuthorizedEffectSetReceipt({
  ledger, members, preview, commonMoon, authorizeEvidenceRead,
  providerBinding = {}, limits,
}) {
  if (!Array.isArray(members) || members.length === 0 ||
      members.some(member => !Array.isArray(member?.rowOwners) ||
        typeof member.replayed !== 'boolean') ||
      !limits || !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
        Number.isSafeInteger(limits[key]) && limits[key] > 0)) {
    fail('InvalidEffectSetReceiptEvidence');
  }
  const issuedMembers = [];
  for (let memberIndex = 0; memberIndex < members.length; memberIndex++) {
    issuedMembers.push(await issueAuthorizedEffectMemberReceipt({
      ledger, rowOwners: members[memberIndex].rowOwners, preview,
      memberIndex, commonMoon, authorizeEvidenceRead, providerBinding,
    }));
  }
  const set = runtimeCore(commonMoon).effectApplicationControl
    .issueSetReceiptFromMembers(
      preview, issuedMembers.map(member => member.wire),
      members.map(member => member.replayed), limits.maxWireBytes,
      limits.maxNodes, limits.maxDepth);
  return Object.freeze({set, members: Object.freeze(issuedMembers)});
}
