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
  const {stored, binding} = await readAuthorizedEffectResponse(options);
  if (stored === undefined) return Object.freeze({outcomes: undefined,
    binding});
  const read = batch ? ledger.readClaimedBatchOutcomes
    : ledger.readClaimedOutcome;
  if (typeof read !== 'function') fail('InvalidEffectOutcomeRead');
  const outcomes = read.call(ledger, claims);
  return Object.freeze({outcomes, binding});
}
