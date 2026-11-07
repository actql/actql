// Provider meaning over the existing row Effect: complete Native request and
// target projection, separate metadata read authority and exactly one physical
// update. Preview, approval, durable claims, Unknown and cleanup stay in Host.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {checkpointApprovalFacts} from '../../../host-common/checkpoint-approval.mjs';
import {invocationScopeFields, invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {createHubSpotUpdateRequestAdapter} from './hubspot-update-request.mjs';
import {createHubSpotUpdateObservationAdapter} from './hubspot-update-observations.mjs';
import {projectHubSpotRecordWriteObservation} from '../site/hubspot-record-write.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_OBJECT_BATCH_READ_OPERATION} from '../site/hubspot-target-read.mjs';

export const HUBSPOT_INSTALLED_UPDATE_OPERATION = 'hubspot:objects:batch-update';
export const HUBSPOT_UPDATE_TARGET_VERSION = 'actql-installed-hubspot-effect-target-read/0.1';
const recoveryKind = 'hubspot-update-requests';
const recoveryVersion = 'actql-installed-hubspot-update-recovery/0.1';
const fail = code => {throw Object.assign(new Error(code), {code});};
const encode = value => canonicalJson(value, {dataKeys: true});
const wireCid = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');
const cid = value => wireCid(encode(value));
const isCid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const segment = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => '%' + unit.charCodeAt(0).toString(16).toUpperCase());
const memberFacts = member => Object.freeze({effectId: member.effectId, memberIndex: member.memberIndex,
  kind: member.kind, resource: member.resource, mappingRef: member.mapping?.mappingRef,
  mappingCid: member.mapping?.mappingCid});
const capture = (receiver, names) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail('InvalidHubSpotUpdateDriver');
  return Object.freeze(Object.fromEntries(names.map(name => {
    const field = Object.getOwnPropertyDescriptor(receiver, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
        nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) fail('InvalidHubSpotUpdateDriver');
    return [name, (...args) => Reflect.apply(field.value, receiver, args)];
  })));
};

export function hubspotUpdateDriver({moon, site, authorization, connection, origin, portalId, connectorId,
  siteBindingCid, generationCid, installedFor, metadataResources, requestLimits, readLimits, writeLimits,
  maxRows, maxMembers, maxRecoveryBytes}) {
  if (typeof connection !== 'string' || !connection || !isCid(siteBindingCid) || !isCid(generationCid) ||
      !positive(maxRows) || maxRows > 100 || !positive(maxMembers) || !positive(maxRecoveryBytes) ||
      typeof installedFor !== 'function' || !metadataResources || nodeTypes.isProxy(metadataResources)) {
    fail('InvalidHubSpotUpdateDriver');
  }
  const resources = {};
  for (const key of ['account', 'properties']) {
    const field = Object.getOwnPropertyDescriptor(metadataResources, key);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string' || !field.value) {
      fail('InvalidHubSpotUpdateDriver');
    }
    resources[key] = field.value;
  }
  if (resources.account === resources.properties) fail('InvalidHubSpotUpdateDriver');
  Object.freeze(resources);
  const physical = capture(site, ['issueReadGrant', 'admitCheckpointEffectTargetRead']);
  // Authorization is asynchronous by contract; capture the original receiver
  // rather than treating its pending result as a synchronous native resource.
  const gate = Object.getOwnPropertyDescriptor(authorization ?? {}, 'authorize');
  if (!gate || !Object.hasOwn(gate, 'value') || typeof gate.value !== 'function' ||
      nodeTypes.isProxy(gate.value)) fail('InvalidHubSpotUpdateDriver');
  const authorize = (...args) => Reflect.apply(gate.value, authorization, args);
  const native = capture(moon, ['hubspotRecheckRecordBatch', 'hubspotRecordBatchBody',
    'hubspotPropertyCatalogObjectType', 'hubspotProjectRecordWriteSuccess', 'hubspotRecordWriteResponseRows']);
  const responsePolicy = Object.freeze(Object.fromEntries(['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows', 'maxRequestBytes']
    .map(name => [name, Object.getOwnPropertyDescriptor(writeLimits ?? {}, name)?.value])));
  if (!Object.values(responsePolicy).every(positive) || responsePolicy.maxRows !== 1) fail('InvalidHubSpotUpdateDriver');
  const maxProperties = Object.getOwnPropertyDescriptor(requestLimits ?? {}, 'maxProperties')?.value;
  if (!positive(maxProperties)) fail('InvalidHubSpotUpdateDriver');
  const requests = createHubSpotUpdateRequestAdapter({moon, origin, portalId, connectorId, installedFor, limits: requestLimits});
  const observations = createHubSpotUpdateObservationAdapter({moon, portalId, installedFor, requests,
    limits: readLimits, maxRows});
  const targetReadLimits = Object.freeze(Object.fromEntries(
    ['maxColumns', 'maxRequestBytes', 'maxRequestNodes', 'maxRequestDepth'].map(name =>
      [name, Object.getOwnPropertyDescriptor(readLimits, name)?.value])));
  const currentFrames = new WeakMap();
  const binding = Object.freeze({connectorId, origin, portalId, siteBindingCid, generationCid});
  let occurrence = 0;
  const selected = member => {
    const original = installedFor(member);
    if (!original || nodeTypes.isProxy(original) || !Object.isFrozen(original) || member?.kind !== 'update' ||
        original.resource !== member.resource || original.mappingRef !== member.mapping?.mappingRef ||
        original.mappingCid !== member.mapping?.mappingCid || !Array.isArray(original.fields) ||
        !Object.isFrozen(original.fields) || resources.account === member.resource || resources.properties === member.resource) {
      fail('ForeignHubSpotUpdateMapping');
    }
    return original;
  };
  const frame = (member, current) => {
    const value = currentFrames.get(current);
    if (!value || value.original !== selected(member) || value.member !== member) fail('ForeignHubSpotUpdateCurrent');
    return value;
  };
  const metadataReader = ({member, runInvocationCid, dispatchRequestCid, signal, controlConstruction,
    targetAuthorization}) => {
    if (!isCid(runInvocationCid) || !isCid(dispatchRequestCid)) fail('InvalidHubSpotUpdateReadScope');
    const resourceFor = slot => slot === 'account' ? resources.account
      : ['schema', 'schema-before', 'schema-after'].includes(slot) ? resources.properties
      : fail('ForeignHubSpotUpdateReadSlot');
    const decision = async slot => {
      signal?.throwIfAborted();
      const result = await authorize('acquisition', {connection, resource: resourceFor(slot), operation: 'read'}, {
        subjectCid: cid({binding, member: memberFacts(member), runInvocationCid, dispatchRequestCid, slot}), signal});
      signal?.throwIfAborted();
      if (result?.action !== 'dispatch') fail('HubSpotMetadataReadDenied');
      return result;
    };
    return Object.freeze({
      async verify(slot) {
        signal?.throwIfAborted();
        // Target authority is the original same-row grant and physical child's
        // retained current/Checkpoint entry fences, never a metadata decision.
        if (slot !== 'target') await decision(slot);
        signal?.throwIfAborted();
      },
      async authorizationFor(slot, rowIndex) {
        if (slot === 'target') {
          if (typeof targetAuthorization !== 'function') fail('HubSpotTargetAuthorizationUnavailable');
          return targetAuthorization(rowIndex);
        }
        const granted = await decision(slot), operation = slot === 'account'
          ? HUBSPOT_ACCOUNT_DETAILS_OPERATION : HUBSPOT_PROPERTIES_READ_OPERATION;
        // Same signed scope may recur within a clock tick. Its durable use
        // inventory is never refilled. Bound the three existing phases' actual
        // metadata occurrences; each physical use still has its own original.
        const facts = {operation, decision: granted, resource: resourceFor(slot), runInvocationCid,
          dispatchRequestCid, maxUses: 3 * (slot === 'account' ? maxRows + 1 : 2 * maxRows + 1)};
        const original = controlConstruction === undefined ? physical.issueReadGrant(facts)
          : controlConstruction(undefined, physical.issueReadGrant, [facts]);
        if (occurrence >= Number.MAX_SAFE_INTEGER) fail('HubSpotReadOccurrenceLimit');
        // Keep the actual issuer original for the shared physical child's
        // purpose/provenance check. A useId envelope is not that original.
        return Object.freeze({originalAuthorization: original,
          useId: dispatchRequestCid + '-hubspot-read-' + occurrence++});
      },
    });
  };
  const restore = ({durable, recorded, members, memberIndexes, body, requestTags}) => {
    if (!Array.isArray(members) || members.length < 1 || members.length > maxMembers ||
        !Array.isArray(durable?.connectorRecovery) || durable.connectorRecovery.length > members.length ||
        !Array.isArray(recorded?.members) || recorded.members.length !== members.length) fail('InvalidHubSpotUpdateRecovery');
    const indexes = memberIndexes ?? members.map((_, index) => index);
    if (!Array.isArray(indexes) || indexes.length < 1 || indexes.length > members.length ||
        indexes.some((index, offset) => !Number.isSafeInteger(index) || index < 0 || index >= members.length ||
          offset > 0 && index <= indexes[offset - 1])) fail('InvalidHubSpotUpdateRecovery');
    const byIndex = new Map();
    for (const entry of durable.connectorRecovery) {
      if (!Number.isSafeInteger(entry?.memberIndex) || entry.memberIndex < 0 || entry.memberIndex >= members.length ||
          byIndex.has(entry.memberIndex)) fail('InvalidHubSpotUpdateRecovery');
      byIndex.set(entry.memberIndex, entry);
    }
    return Object.freeze({requests: Object.freeze(indexes.map(index => {
      const member = members[index]; selected(member);
      const saved = byIndex.get(index), changes = body?.effects?.[index]?.changes,
        claims = recorded.members[index]?.claims;
      if (saved?.kind !== recoveryKind || typeof saved.wire !== 'string' ||
          Buffer.byteLength(saved.wire) > maxRecoveryBytes || wireCid(saved.wire) !== saved.observationCid ||
          !Array.isArray(changes) || changes.length > maxRows || !Array.isArray(claims) ||
          claims.length !== changes.length) fail('InvalidHubSpotUpdateRecovery');
      const value = JSON.parse(saved.wire);
      if (encode(value) !== saved.wire || value.version !== recoveryVersion ||
          Object.keys(value).sort().join(',') !== 'binding,member,requests,version' ||
          encode(value.binding) !== encode(binding) || encode(value.member) !== encode(memberFacts(member)) ||
          !Array.isArray(value.requests) || value.requests.length !== changes.length) fail('InvalidHubSpotUpdateRecovery');
      return Object.freeze(value.requests.map((wire, row) => {
        const rebuilt = requests.restore({member, wire, requestTag: requestTags?.[index]?.[row]});
        const facts = requests.requestFacts(rebuilt.request);
        if (rebuilt.requestCid !== claims[row].canonicalRequestCid ||
            encode(facts.value) !== encode(changes[row].after?.value) ||
            encode(facts.target) !== encode(changes[row].target_row_identity)) fail('ForeignHubSpotUpdateRecovery');
        requests.prepareTargetRead(rebuilt.request, targetReadLimits);
        return rebuilt.request;
      }));
    }))});
  };
  return Object.freeze({
    kinds: Object.freeze(['update']), targetRead: Object.freeze({operation: HUBSPOT_OBJECT_BATCH_READ_OPERATION}),
    writeOperation: () => HUBSPOT_INSTALLED_UPDATE_OPERATION,
    requestFacts: requests.requestFacts, requestCid: requests.requestCid, capabilityRequestCid: requests.capabilityRequestCid,
    finalizeRequest: requests.finalize, assertRequestFinalized: requests.assertFinalized,
    async describe(options) {
      const original = selected(options.member), read = metadataReader(options);
      const current = await observations.describe({...options, ...read});
      // Retain only the original scope and control callback needed by later
      // target reads, not Describe's completed physical read closure/signal.
      currentFrames.set(current, {original, member: options.member,
        runInvocationCid: options.runInvocationCid, dispatchRequestCid: options.dispatchRequestCid,
        controlConstruction: options.controlConstruction});
      return current;
    },
    prepareRequest(options) {
      frame(options.member, options.current);
      const prepared = requests.prepare(options);
      requests.prepareTargetRead(prepared.request, targetReadLimits);
      return prepared;
    },
    recheckRequests({member, entries, current, controlConstruction}) {
      frame(member, current);
      const check = () => {for (const entry of entries) checked(native.hubspotRecheckRecordBatch(
        requests.nativeRequest(entry.request), current.catalog, maxProperties));};
      return controlConstruction === undefined ? check() : controlConstruction(undefined, check, []);
    },
    observeTargets(options) {
      const original = frame(options.member, options.current);
      const read = metadataReader({...original, signal: options.signal, targetAuthorization: options.authorizationForRow});
      return observations.observeTargets({...options, ...read});
    },
    admitTargetReadApproval({member, decision}) {
      const original = selected(member), expected = {version: HUBSPOT_UPDATE_TARGET_VERSION,
        site_binding_cid: siteBindingCid, generation_cid: generationCid, effect_id: member.effectId,
        member_index: member.memberIndex, mapping_ref: original.mappingRef, mapping_cid: original.mappingCid,
        resource: original.resource, effect_kind: 'update', key: 'id', fields: original.fields};
      const matched = checkpointApprovalFacts(decision)?.physicalBindings?.find(value =>
        Object.entries(expected).every(([key, item]) => encode(value[key]) === encode(item)));
      if (!matched) fail('HubSpotTargetReadApprovalNotAdmitted');
      return physical.admitCheckpointEffectTargetRead(decision, matched, HUBSPOT_OBJECT_BATCH_READ_OPERATION);
    },
    footprint({member}) {
      const original = selected(member);
      return Object.freeze({providerNamespace: 'hubspot', resourceKind: 'object',
        boundaryCid: cid({origin, portalId, objectType: native.hubspotPropertyCatalogObjectType(original.catalog)})});
    },
    recoveryEntry({member, entries}) {
      selected(member);
      if (!Array.isArray(entries) || entries.length > maxRows) fail('InvalidHubSpotUpdateRecovery');
      const wires = entries.map(entry => {
        if (entry.requestCid !== requests.requestCid(entry.request)) fail('ForeignHubSpotUpdateRequest');
        return requests.savedWire(entry.request);
      });
      const wire = encode({version: recoveryVersion, binding, member: memberFacts(member), requests: wires});
      if (Buffer.byteLength(wire) > maxRecoveryBytes) fail('HubSpotUpdateRecoveryLimit');
      return Object.freeze({kind: recoveryKind, observationCid: wireCid(wire), wire});
    },
    recoverRequests: restore, recoverMemberRequests: restore,
    async send({member, request, current, authorization, credential, signal, callResource}) {
      frame(member, current);
      if (invocationScopeFields(authorization?.scope, credential?.control)?.resourceOrigin !== origin) {
        fail('ForeignHubSpotUpdateOrigin');
      }
      checked(native.hubspotRecheckRecordBatch(requests.nativeRequest(request), current.catalog, maxProperties));
      const body = native.hubspotRecordBatchBody(requests.nativeRequest(request));
      if (Buffer.byteLength(body) > responsePolicy.maxRequestBytes) fail('HubSpotUpdateRequestLimit');
      signal?.throwIfAborted();
      const response = await invokeScopedCredentialOperation({authorization, credential, callResource,
        operation: HUBSPOT_INSTALLED_UPDATE_OPERATION, method: 'POST',
        path: '/crm/v3/objects/' + segment(requests.objectType(request)) + '/batch/update',
        query: [], headers: [['accept', 'application/json']], body, responseHeaders: [],
        maxRequestBytes: responsePolicy.maxRequestBytes, maxResponseBytes: responsePolicy.maxResponseBytes, signal});
      return Object.freeze({observation: Object.freeze({useCid: response.useCid,
        statusCode: response.statusCode, body: response.body})});
    },
    project({request, observation}) {
      const result = projectHubSpotRecordWriteObservation({moon: native,
        request: requests.nativeRequest(request), observation, limits: responsePolicy});
      if (result.kind !== 'typed-success-response') return Object.freeze({kind: result.kind});
      const rows = native.hubspotRecordWriteResponseRows(result.response), target = requests.requestFacts(request).target;
      if (!Array.isArray(rows) || rows.length !== 1 || rows[0][0] !== target || rows[0][1] !== 'updated') {
        fail('ForeignHubSpotUpdateResponse');
      }
      return Object.freeze({kind: 'typed-success-response', outcome: Object.freeze({state: 'applied',
        action: 'updated', result: Object.freeze({id: target})})});
    },
  });
}
