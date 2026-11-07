import {checked} from '../../../host-common/runtime-result.mjs';
import {recoverRetainedSalesforceCatalog} from
  '../site/salesforce-catalog-recovery.mjs';
import {recoverNamedSalesforceObservation} from
  '../site/salesforce-named-describe.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Select original positions in the unchanged whole Preview. Read the caller's
// length and each selected index once, before invoking any Catalog decoder.
function selectedMemberIndexes(value, count, maximum, code) {
  if (!Number.isSafeInteger(maximum) || maximum < 1 ||
      !Number.isSafeInteger(count) || count < 1 || count > maximum) fail(code);
  if (value === undefined) return Array.from({length: count}, (_, index) => index);
  if (!Array.isArray(value)) fail(code);
  const length = value.length;
  if (!Number.isSafeInteger(length) || length < 1 || length > count) fail(code);
  const selected = [];
  let previous = -1;
  for (let index = 0; index < length; index++) {
    const memberIndex = value[index];
    if (!Number.isSafeInteger(memberIndex) || memberIndex <= previous ||
        memberIndex >= count) fail(code);
    selected.push(memberIndex);
    previous = memberIndex;
  }
  return Object.freeze(selected);
}

// Synchronous, bounded reconstruction only: the caller retains Run, cancellation,
// current authorization, response custody and physical send responsibilities.
// Rebuild provider request material from a recovered Preview and exact
// prepared Ledger claims. This does not restore apply or credential authority.
// The ordinary apply owner must repeat whole-set and current Site admission.
export function recoverPreparedSalesforceSingleRequests({
  moon, previewWire, runIdentityCid, authoringContextCid, members,
  previewLimits, bodyLimits, requestLimits, maxMembers, maxRows,
  maxIdentityBytes = 4096, memberIndexes,
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
  const selected = selectedMemberIndexes(memberIndexes,
    moon.salesforceRecoveryPreviewMemberCount(preview), maxMembers,
    'InvalidSalesforcePreparedRequestRecovery');
  if (selected.length !== members.length) {
    fail('InvalidSalesforcePreparedRequestRecovery');
  }
  const requests = members.map((member, selectedIndex) => {
    const memberIndex = selected[selectedIndex];
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
  maxMembers, maxRows, maxRetainedBytes, memberIndexes,
}) {
  if (!Array.isArray(recovered?.connectorRecovery) ||
      !Array.isArray(recorded?.members) ||
      (memberIndexes === undefined &&
        recovered.connectorRecovery.length !== recorded.members.length) ||
      recovered.connectorRecovery.length > maxMembers ||
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
  const selected = selectedMemberIndexes(memberIndexes,
    recorded.members.length, maxMembers, 'InvalidSalesforceCapturedRequestRecovery');
  const retainedByIndex = new Map();
  let originalPosition = 0;
  for (const entry of recovered.connectorRecovery) {
    const index = entry?.memberIndex;
    if (memberIndexes === undefined && index !== originalPosition) {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    originalPosition++;
    if (!Number.isSafeInteger(index) || index < 0 ||
        index >= recorded.members.length || retainedByIndex.has(index)) {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    retainedByIndex.set(index, entry);
  }
  const catalogs = [];
  const members = selected.map(memberIndex => {
    const entry = retainedByIndex.get(memberIndex);
    if (entry?.memberIndex !== memberIndex ||
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
  // No Catalog decoder or member-profile frame remains active. Drop this
  // duplicate JS Preview forest before the native identity constructor; only
  // the original wire and the retained Catalog/projection outputs continue.
  previewBody = undefined;
  const result = recoverPreparedSalesforceSingleRequests({moon, previewWire,
    runIdentityCid, authoringContextCid, members,
    previewLimits, bodyLimits, requestLimits, maxMembers, maxRows,
    memberIndexes: selected});
  return Object.freeze({...result, catalogs: Object.freeze(catalogs)});
}
