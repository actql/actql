import {refreshSalesforceEffectWriteCatalogs} from
  '../site/salesforce-effect-current-catalog.mjs';
import {observeSalesforceTargetSet} from
  '../site/salesforce-target-observation.mjs';
import {inspectSalesforceEffectCapability} from
  '../site/salesforce-effect-capability.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

const fail = () => {
  throw Object.assign(new Error('InvalidSalesforceEffectCurrentUse'), {
    code: 'InvalidSalesforceEffectCurrentUse',
  });
};

const positive = value => Number.isSafeInteger(value) && value > 0;

// Site transport observes current physical facts only. The common Effect
// owner authorizes the reads before calling refreshPreflight and re-admits
// the complete set before any row is dispatched.
export function installSalesforceEffectCurrentUse({moon, commonMoon, members,
  observedRows, maxMembers, maxRows, maxTotalResponseBytes}) {
  if (!moon || !Array.isArray(members) || members.length === 0 ||
      typeof moon.salesforceSingleWriteRequestMethod !== 'function' ||
      !Array.isArray(observedRows) || !positive(maxMembers) ||
      !positive(maxRows) || !positive(maxTotalResponseBytes) ||
      maxMembers > 1024 || maxRows > 100_000 ||
      maxTotalResponseBytes > 100_000_000 ||
      members.length > maxMembers) fail();
  let totalRows = 0;
  let guardedRows = 0;
  if (typeof commonMoon
      ?.clientProgramEffectApplyCapabilityFromCodes !== 'function' ||
      members.some(member => !member?.capability)) fail();
  const ownedMembers = Object.freeze(members.map(member => {
    if (!Array.isArray(member?.requests) || member.requests.length === 0 ||
        typeof member.refreshCatalog !== 'function') fail();
    totalRows += member.requests.length;
    if (totalRows > maxRows) fail();
    const requests = Object.freeze([...member.requests]);
    const target = member.target;
    for (const request of requests) {
      const method = moon.salesforceSingleWriteRequestMethod(request);
      if ((method !== 'POST' && method !== 'PATCH') ||
          (method === 'PATCH') !== (target !== undefined)) fail();
    }
    if (target !== undefined) {
      if (typeof target?.authorizationForRow !== 'function' ||
          !target.credential || !positive(target.limits?.maxResponseBytes) ||
          !positive(target.limits?.maxNodes) ||
          !positive(target.limits?.maxDepth) ||
          !positive(target.limits?.maxIdentityBytes) ||
          target.limits.maxResponseBytes > 1_000_000 ||
          target.limits.maxNodes > 100_000 ||
          target.limits.maxDepth > 64 ||
          target.limits.maxIdentityBytes > 1_000_000) fail();
      guardedRows += requests.length;
    }
    return Object.freeze({requests,
      capability: member.capability,
      collectionRequest: member.collectionRequest,
      refreshCatalog: member.refreshCatalog,
      target: target === undefined ? undefined : Object.freeze({
        authorizationForRow: target.authorizationForRow,
        credential: Object.freeze({...target.credential}),
        limits: Object.freeze({...target.limits}),
      })});
  }));
  if (observedRows.length !== guardedRows) fail();
  const rows = Object.freeze([...observedRows]);
  const catalogsByPreflight = new WeakMap();
  return Object.freeze({
    catalogAt(preflight, index) {
      const catalogs = catalogsByPreflight.get(preflight);
      if (!Number.isSafeInteger(index) || index < 0 ||
          index >= ownedMembers.length || catalogs === undefined) {
        fail();
      }
      return catalogs[index];
    },
    async refreshPreflight({signal, preflight} = {}) {
      if (preflight === null || typeof preflight !== 'object') fail();
      signal?.throwIfAborted();
      const catalogs = await refreshSalesforceEffectWriteCatalogs({
        moon, members: ownedMembers, maxMembers, maxRows, signal,
      });
      const targets = ownedMembers.flatMap((member, index) =>
        member.target === undefined ? [] : [{
          requests: member.requests,
          currentCatalog: catalogs[index],
          authorizationForRow: member.target.authorizationForRow,
          credential: member.target.credential,
          limits: member.target.limits,
        }]);
      const observed = targets.length === 0 ? [] :
        await observeSalesforceTargetSet({moon, members: targets,
          maxMembers, maxRows, maxTotalResponseBytes, signal});
      const guardVersions = observed.flatMap(member => member.map(row =>
        row.versionCid));
      if (guardVersions.length !== rows.length) fail();
      const capabilities = ownedMembers.map((member, index) =>
        inspectSalesforceEffectCapability(member.capability, member.requests,
          {currentObservation: catalogs[index],
            collection: member.collectionRequest !== undefined}));
      signal?.throwIfAborted();
      const current = Object.freeze({...preflight, observedRows: rows,
        guardVersions: Object.freeze(guardVersions),
        capabilities: Object.freeze(capabilities.map(value => value.identity)),
        routes: Object.freeze(capabilities.map(value => checked(
          commonMoon.clientProgramEffectApplyCapabilityFromCodes(
            value.identity, value.route, 0, 0, true,
            value.route === 0, 2, 1)))),
      });
      catalogsByPreflight.set(current, Object.freeze([...catalogs]));
      return current;
    },
  });
}
