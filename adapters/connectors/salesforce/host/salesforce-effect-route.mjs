import {installSalesforceEffectCurrentUse} from
  './salesforce-effect-current-use.mjs';
import {installSalesforceEffectDispatch} from
  './salesforce-effect-dispatch.mjs';

const fail = () => {
  throw Object.assign(new Error('InvalidSalesforceEffectRoute'), {
    code: 'InvalidSalesforceEffectRoute',
  });
};

// One provider route supplies current-use observations and physical calls to
// the common Effect owner. Both stages use the same member request inventory;
// neither stage decides row admission, retry, or completion.
export function installSalesforceEffectRoute({commonMoon, moon, ledger,
  admittedPreview, observedRows, members, maxMembers, maxRows,
  maxTotalResponseBytes}) {
  if (!commonMoon || !moon || !ledger || !admittedPreview ||
      !Array.isArray(members) || members.length === 0 ||
      typeof commonMoon.strategyEffectPreviewSemanticCid !== 'function') {
    fail();
  }
  const subjectCid = commonMoon.strategyEffectPreviewSemanticCid(
    admittedPreview);
  if (typeof subjectCid !== 'string') fail();
  const owned = Object.freeze(members.map(member => {
    if (!Array.isArray(member?.requests) ||
        typeof member.authorizationForRow !== 'function' ||
        !member.credential || !member.limits ||
        typeof member.refreshCatalog !== 'function' ||
        (member.target !== undefined &&
          (typeof member.target?.authorizationForRow !== 'function' ||
            !member.target.credential || !member.target.limits)) ||
        (member.collection !== undefined &&
          (!member.collection?.request ||
            typeof member.collection.authorization !== 'function' ||
            !member.collection.limits))) fail();
    const target = member.target === undefined ? undefined : Object.freeze({
      authorizationForRow: member.target.authorizationForRow,
      credential: Object.freeze({...member.target.credential}),
      limits: Object.freeze({...member.target.limits}),
    });
    const collection = member.collection === undefined ? undefined :
      Object.freeze({
        request: member.collection.request,
        authorization: member.collection.authorization,
        limits: Object.freeze({...member.collection.limits}),
      });
    return Object.freeze({
      requests: Object.freeze([...member.requests]),
      capability: member.capability,
      refreshCatalog: member.refreshCatalog,
      target,
      authorizationForRow: member.authorizationForRow,
      credential: Object.freeze({...member.credential}),
      limits: Object.freeze({...member.limits}),
      collection,
    });
  }));
  const currentUse = installSalesforceEffectCurrentUse({moon, commonMoon,
    observedRows, members: owned.map(member => ({
      requests: member.requests,
      capability: member.capability,
      refreshCatalog: member.refreshCatalog,
      target: member.target,
      credential: member.credential,
      collectionRequest: member.collection?.request,
    })), maxMembers, maxRows, maxTotalResponseBytes});
  return Object.freeze({
    refreshPreflight: currentUse.refreshPreflight,
    bindDispatch({members: activeMembers, subjectCid: activeSubject,
      signal}) {
      if (activeSubject !== subjectCid ||
          !Array.isArray(activeMembers) ||
          activeMembers.length !== owned.length) fail();
      return installSalesforceEffectDispatch({commonMoon, moon, ledger,
        admittedPreview, currentUse, signal,
        members: owned.map((member, index) => ({
          requests: member.requests,
          claims: activeMembers[index].claims,
          authorizationForRow: member.authorizationForRow,
          credential: member.credential,
          limits: member.limits,
          collection: member.collection,
        }))});
    },
  });
}
