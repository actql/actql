import {checked} from '../../../host-common/runtime-result.mjs';
import {recoverRetainedSalesforceCatalog} from
  '../site/salesforce-catalog-recovery.mjs';
import {recoverNamedSalesforceObservation} from
  '../site/salesforce-named-describe.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Synchronous, bounded reconstruction only: the caller retains Run, cancellation,
// current authorization, response custody and physical send responsibilities.
// Rebuild provider request material from a recovered Preview and exact
// prepared Ledger claims. This does not restore apply or credential authority.
// The ordinary apply owner must repeat whole-set and current Site admission.
export function recoverPreparedSalesforceSingleRequests({
  moon, previewWire, runIdentityCid, authoringContextCid, members,
  previewLimits, bodyLimits, requestLimits, maxMembers, maxRows,
  maxIdentityBytes = 4096,
}) {
  const positive = value => Number.isSafeInteger(value) && value > 0;
  if (!moon || typeof previewWire !== 'string' ||
      typeof runIdentityCid !== 'string' ||
      typeof authoringContextCid !== 'string' ||
      !Array.isArray(members) || members.length === 0 ||
      !positive(maxMembers) || members.length > maxMembers ||
      !positive(maxRows) || maxRows > 100_000 ||
      !previewLimits || !bodyLimits || !requestLimits ||
      !positive(previewLimits.maxWireBytes) ||
      !positive(previewLimits.maxNodes) ||
      !positive(previewLimits.maxDepth) ||
      !positive(bodyLimits.maxBytes) ||
      !positive(bodyLimits.maxNodes) ||
      !positive(bodyLimits.maxDepth) ||
      !positive(requestLimits.maxPathBytes) ||
      !positive(requestLimits.maxTargetBytes) ||
      !positive(requestLimits.maxBodyBytes) ||
      !positive(maxIdentityBytes)) {
    fail('InvalidSalesforcePreparedRequestRecovery');
  }
  let totalRows = 0;
  for (const member of members) {
    if (!member?.projection || typeof member.apiVersion !== 'string' ||
        typeof member.resourceOrigin !== 'string' ||
        !Array.isArray(member.claims) || member.claims.length === 0) {
      fail('InvalidSalesforcePreparedRequestRecovery');
    }
    totalRows += member.claims.length;
    if (totalRows > maxRows) fail('InvalidSalesforcePreparedRequestRecovery');
  }
  const preview = checked(moon.salesforceAdmitRecoveryPreview(
    previewWire, runIdentityCid, authoringContextCid,
    previewLimits.maxWireBytes, previewLimits.maxNodes,
    previewLimits.maxDepth));
  if (moon.salesforceRecoveryPreviewMemberCount(preview) !==
      members.length) {
    fail('InvalidSalesforcePreparedRequestRecovery');
  }
  const requests = members.map((member, memberIndex) => {
    if (moon.salesforceRecoveryPreviewRowCount(preview, memberIndex) !==
        member.claims.length) {
      fail('InvalidSalesforcePreparedRequestRecovery');
    }
    return Object.freeze(member.claims.map((claim, rowIndex) => {
      if (typeof claim?.canonicalRequestCid !== 'string') {
        fail('InvalidSalesforcePreparedRequestRecovery');
      }
      return checked(moon.salesforceRecoverSingleWriteRequest(
        preview, memberIndex, rowIndex, member.projection,
        member.apiVersion, bodyLimits.maxBytes, bodyLimits.maxNodes,
        bodyLimits.maxDepth, requestLimits.maxPathBytes,
        requestLimits.maxTargetBytes, requestLimits.maxBodyBytes,
        maxIdentityBytes, member.resourceOrigin,
        claim.canonicalRequestCid));
    }));
  });
  return Object.freeze({preview, requests: Object.freeze(requests)});
}

// Re-admit the original bounded Catalog projection from the encrypted Run
// capture, then rebuild each exact prepared request from its Preview row and
// durable claim. A fresh Catalog and mutation grant are still required before
// sending any reconstructed request. A member's recovery entry is either a
// retained Catalog sync (`salesforce-catalog`) or the retained describe of
// exactly its Resource (`salesforce-named-catalog`).
export function recoverCapturedSalesforceSingleRequests({
  moon, recovered, recorded, previewWire, runIdentityCid,
  authoringContextCid, previewLimits, bodyLimits, requestLimits,
  maxMembers, maxRows, maxRetainedBytes,
}) {
  if (!Array.isArray(recovered?.connectorRecovery) ||
      !Array.isArray(recorded?.members) ||
      recovered.connectorRecovery.length !== recorded.members.length ||
      typeof previewWire !== 'string' ||
      !Number.isSafeInteger(maxRetainedBytes) ||
      maxRetainedBytes < 1) {
    fail('InvalidSalesforceCapturedRequestRecovery');
  }
  let previewBody;
  try { previewBody = JSON.parse(previewWire); }
  catch { fail('InvalidSalesforceCapturedRequestRecovery'); }
  if (!Array.isArray(previewBody.effects) ||
      previewBody.effects.length !== recorded.members.length) {
    fail('InvalidSalesforceCapturedRequestRecovery');
  }
  const catalogs = [];
  const members = recovered.connectorRecovery.map((entry, memberIndex) => {
    if (entry.memberIndex !== memberIndex ||
        !['salesforce-catalog', 'salesforce-named-catalog']
          .includes(entry.kind) ||
        typeof entry.wire !== 'string') {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    let profile;
    try { profile = JSON.parse(entry.wire); }
    catch { fail('InvalidSalesforceCapturedRequestRecovery'); }
    const operation = new Map([
      ['create', 0], ['update', 1], ['upsert', 2],
    ]).get(profile.operation);
    if (operation === undefined ||
        previewBody.effects[memberIndex].effect_kind !== profile.operation ||
        previewBody.effects[memberIndex].write_footprint?.resource_kind !==
          profile.resourceName ||
        typeof profile.apiVersion !== 'string' ||
        typeof profile.resourceOrigin !== 'string' ||
        typeof profile.externalTargetField !== 'string' ||
        !Array.isArray(profile.fieldNames) ||
        profile.fieldNames.length === 0 ||
        !profile.fieldNames.every(name => typeof name === 'string')) {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    const named = entry.kind === 'salesforce-named-catalog';
    const retained = named ? profile.evidence : profile.catalog;
    // Retained describe bytes are base64 inside the saved wire.
    if (typeof retained?.observationJson !== 'string' ||
        (named && Buffer.byteLength(entry.wire, 'utf8') >
          2 * maxRetainedBytes)) {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    const catalog = named ? {observation: recoverNamedSalesforceObservation({
      moon, evidence: retained, expectedObservationCid: entry.observationCid})}
      : recoverRetainedSalesforceCatalog({moon, retained,
        expectedObservationCid: entry.observationCid, maxRetainedBytes});
    const binding = JSON.parse(retained.observationJson).binding;
    if (binding.resource_origin !== profile.resourceOrigin ||
        binding.run_invocation_cid !== previewBody.invocation_cid) {
      fail('ForeignSalesforceCapturedRequestRecovery');
    }
    const projection = checked(moon.salesforcePrepareWriteProjection(
      catalog.observation, binding.namespace_id, binding.principal,
      binding.environment, binding.connection_revision, binding.org_id,
      binding.site_key, binding.site_generation,
      binding.connector_registration, binding.connector_revision,
      binding.resource_origin, binding.run_invocation_cid,
      binding.dispatch_request_cid, binding.sync_occurrence,
      profile.resourceName, operation, profile.externalTargetField,
      profile.fieldNames, profile.fieldNames.length));
    catalogs.push(catalog.observation);
    return Object.freeze({projection, apiVersion: profile.apiVersion,
      resourceOrigin: profile.resourceOrigin,
      claims: recorded.members[memberIndex].claims});
  });
  const result = recoverPreparedSalesforceSingleRequests({moon, previewWire,
    runIdentityCid, authoringContextCid, members,
    previewLimits, bodyLimits, requestLimits, maxMembers, maxRows});
  return Object.freeze({...result, catalogs: Object.freeze(catalogs)});
}

