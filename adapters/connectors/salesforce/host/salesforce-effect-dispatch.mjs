import {captureSalesforceCollectionEffectWrite,
  captureSalesforceSingleEffectWrite} from './salesforce-effect-write.mjs';
import {snapshotEffectDispatchClaims} from
  '../../../host-node/effect-physical-dispatch.mjs';

const fail = () => {
  throw Object.assign(new Error('InvalidSalesforceEffectDispatch'), {
    code: 'InvalidSalesforceEffectDispatch',
  });
};

// Bind one installed physical route to the common Effect frontier. The
// frontier owns row admission and progress; this adapter only executes the
// selected Salesforce request against that apply's refreshed Catalog.
export function installSalesforceEffectDispatch({commonMoon, moon, ledger,
  admittedPreview, currentUse, members, signal}) {
  if (!commonMoon || !moon || !ledger || !admittedPreview ||
      typeof currentUse?.catalogAt !== 'function' ||
      typeof commonMoon.strategyEffectPreviewOrderedRowCid !== 'function' ||
      !Array.isArray(members) || members.length === 0 ||
      members.length > 1024) fail();
  let totalRows = 0;
  const owned = Object.freeze(members.map(member => {
    if (!Array.isArray(member?.requests) ||
        !Array.isArray(member.claims) ||
        member.requests.length === 0 ||
        member.requests.length !== member.claims.length ||
        typeof member.authorizationForRow !== 'function' ||
        !member.credential || !member.limits) fail();
    totalRows += member.requests.length;
    if (totalRows > 100_000) fail();
    const collection = member.collection;
    if (collection !== undefined &&
        (!collection.request ||
          typeof collection.authorization !== 'function' ||
          !collection.limits)) fail();
    return Object.freeze({requests: Object.freeze([...member.requests]),
      claims: snapshotEffectDispatchClaims(member.claims),
      authorizationForRow: member.authorizationForRow,
      credential: Object.freeze({...member.credential}),
      limits: Object.freeze({...member.limits}),
      collection: collection === undefined ? undefined : Object.freeze({
        request: collection.request,
        authorization: collection.authorization,
        limits: Object.freeze({...collection.limits}),
      })});
  }));
  return async ({memberIndex, rowIndex, claim, currentPreflight}) => {
    if (!Number.isSafeInteger(memberIndex) ||
        !Number.isSafeInteger(rowIndex) ||
        memberIndex < 0 || memberIndex >= owned.length ||
        rowIndex < 0 || rowIndex >= owned[memberIndex].requests.length ||
        !claim) fail();
    const member = owned[memberIndex];
    const expected = member.claims[rowIndex];
    if (!expected ||
        ['scope', 'locator', 'key', 'basis', 'intentFingerprintCid',
          'canonicalRequestCid'].some(field =>
          expected[field] === undefined || expected[field] !== claim[field])) {
      fail();
    }
    signal?.throwIfAborted();
    const currentObservation = currentUse.catalogAt(currentPreflight,
      memberIndex);
    if (member.collection !== undefined) {
      if (rowIndex !== 0) fail();
      const authorization = await member.collection.authorization();
      signal?.throwIfAborted();
      return captureSalesforceCollectionEffectWrite({
        ledger, claims: member.claims, admittedPreview, memberIndex,
        firstRow: rowIndex, commonMoon, moon,
        request: member.collection.request, currentObservation,
        authorization, credential: member.credential,
        limits: member.collection.limits, signal,
      });
    }
    const rowPreviewCid = commonMoon.strategyEffectPreviewOrderedRowCid(
      admittedPreview, memberIndex, rowIndex);
    if (typeof rowPreviewCid !== 'string') fail();
    const authorization = await member.authorizationForRow(rowIndex);
    signal?.throwIfAborted();
    return captureSalesforceSingleEffectWrite({
      ledger, commonMoon, admittedPreview, memberIndex, rowIndex,
      rowPreviewCid, claim, moon, request: member.requests[rowIndex],
      currentObservation, authorization, credential: member.credential,
      limits: member.limits, signal,
    });
  };
}
