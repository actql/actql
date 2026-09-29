import {checkedSalesforceCatalogPreparation} from
  './salesforce-effect-preparation-result.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Refresh every selected member before the first Effect mutation. MoonBit
// rechecks the exact request against its current Catalog observation.
export async function refreshSalesforceEffectWriteCatalogs({
  moon, members, maxMembers, maxRows, signal,
}) {
  if (!moon || !Array.isArray(members) || members.length === 0 ||
      !Number.isSafeInteger(maxMembers) || maxMembers < 1 ||
      maxMembers > 1024 || members.length > maxMembers ||
      !Number.isSafeInteger(maxRows) || maxRows < 1 ||
      maxRows > 100_000) {
    fail('InvalidSalesforceEffectCatalogRefresh');
  }
  let rowCount = 0;
  const owned = members.map(member => {
    if (!Array.isArray(member?.requests) || member.requests.length === 0 ||
        typeof member.refreshCatalog !== 'function') {
      fail('InvalidSalesforceEffectCatalogRefresh');
    }
    rowCount += member.requests.length;
    if (rowCount > maxRows) fail('InvalidSalesforceEffectCatalogRefresh');
    return Object.freeze({requests: Object.freeze([...member.requests]),
      collectionRequest: member.collectionRequest,
      refreshCatalog: member.refreshCatalog});
  });
  const observations = [];
  for (const member of owned) {
    signal?.throwIfAborted();
    const catalog = await member.refreshCatalog({signal});
    if (!catalog?.observation) fail('InvalidSalesforceEffectCatalogRefresh');
    for (const request of member.requests) {
      signal?.throwIfAborted();
      checkedSalesforceCatalogPreparation(moon.salesforceRecheckSingleWriteRequest(
        request, catalog.observation), moon, catalog.observation);
    }
    if (member.collectionRequest !== undefined) {
      checkedSalesforceCatalogPreparation(moon.salesforceRecheckCollectionWriteRequest(
        member.collectionRequest, catalog.observation), moon, catalog.observation);
    }
    observations.push(catalog.observation);
  }
  return Object.freeze(observations);
}
