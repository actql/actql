// Kintone protocol over the existing installed row Effect. The shared Host
// retains Preview, approval, claims, Unknown, physical funding and cleanup.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checkpointApprovalFacts} from '../../../host-common/checkpoint-approval.mjs';
import {ownHttpRequest} from '../../../host-common/http-exchange.mjs';
import {invocationScopeFields, invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {createKintoneUpdateRequestAdapter} from './kintone-update-request.mjs';
import {KINTONE_FORM_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {KINTONE_TARGET_READ_OPERATION} from '../site/kintone-record-delete.mjs';
import {KINTONE_RECORD_UPDATE_OPERATION} from '../site/kintone-record-write.mjs';

export const KINTONE_UPDATE_TARGET_VERSION = 'actql-installed-kintone-effect-target-read/0.1';
const recoveryKind = 'kintone-update-requests';
const recoveryVersion = 'actql-installed-kintone-update-recovery/0.1';
const fail = code => {throw Object.assign(new Error(code), {code});};
const encode = value => canonicalJson(value, {dataKeys: true});
const wireCid = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');
const cid = value => wireCid(encode(value));
const isCid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
// Match only this fixed original DATA envelope. Do not recursively serialize
// an unvalidated saved object merely to compare it with the bound original.
const sameRecord = (value, expected) => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === Object.keys(expected).length && Object.keys(expected).every(name =>
    Object.hasOwn(value, name) && (Array.isArray(expected[name])
      ? Array.isArray(value[name]) && value[name].length === expected[name].length &&
        expected[name].every((item, index) => value[name][index] === item)
      : value[name] === expected[name]));
const memberFacts = member => Object.freeze({effectId: member.effectId, memberIndex: member.memberIndex,
  kind: member.kind, resource: member.resource, mappingRef: member.mapping?.mappingRef,
  mappingCid: member.mapping?.mappingCid});
const capture = (receiver, name, asynchronous = false) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail('InvalidKintoneUpdateDriver');
  const field = Object.getOwnPropertyDescriptor(receiver, name), method = field?.value;
  if (!field || !Object.hasOwn(field, 'value') || typeof method !== 'function' || nodeTypes.isProxy(method) ||
      !asynchronous && nodeTypes.isAsyncFunction(method)) fail('InvalidKintoneUpdateDriver');
  return (...args) => Reflect.apply(method, receiver, args);
};

export class KintoneUpdateObservationFailure extends Error {
  constructor(cause, observations) {
    super('KintoneUpdateObservationFailed', {cause});
    this.code = cause?.code ?? 'KintoneUpdateObservationFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

export function kintoneUpdateDriver({moon, site, authorization, connection, origin, appId, connectorId,
  resource, formResource, fields, mapping, declaration, siteBindingCid, generationCid, guestSpaceId,
  limits, maxRows, maxMembers, maxRecoveryBytes}) {
  if (typeof connection !== 'string' || !connection || typeof formResource !== 'string' || !formResource ||
      formResource === resource || !positive(maxRows) || maxRows > 100 || !positive(maxMembers) ||
      !positive(maxRecoveryBytes) || !Array.isArray(fields) || nodeTypes.isProxy(fields) || fields.length < 1 ||
      fields.some((name, index) => typeof name !== 'string' || !name || name === '$id' || name === '$revision' ||
        index > 0 && name <= fields[index - 1])) fail('InvalidKintoneUpdateDriver');
  const beforeFields = Object.freeze(fields.slice());
  const requests = createKintoneUpdateRequestAdapter({moon, mapping, declaration, origin, appId, connectorId,
    resource, siteBindingCid, generationCid, guestSpaceId, limits});
  // These are immutable DATA bounds, not a borrowed mutable policy object.
  const maxRequestBytes = limits.maxRequestBytes, maxResponseBytes = limits.maxResponseBytes;
  const issueReadGrant = capture(site, 'issueReadGrant'),
    admitTarget = capture(site, 'admitCheckpointEffectTargetRead'), authorize = capture(authorization, 'authorize', true);
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const binding = Object.freeze({...requests.binding, formResource, fields: beforeFields});
  const currentFrames = new WeakMap();
  let occurrence = 0;
  const selected = member => {
    if (member?.kind !== 'update' || member.resource !== resource ||
        member.mapping?.mappingRef !== requests.mappingRef || member.mapping?.mappingCid !== requests.mappingCid) {
      fail('ForeignKintoneUpdateMapping');
    }
  };
  const frame = (member, current) => {
    selected(member);
    const original = currentFrames.get(current);
    if (!original || original.member !== member) fail('ForeignKintoneUpdateCurrent');
    return original;
  };
  const readScope = (options, observations) => {
    const {member, signal, runInvocationCid, dispatchRequestCid, controlConstruction, readChild,
      targetAuthorization} = options;
    selected(member);
    if (!isCid(runInvocationCid) || !isCid(dispatchRequestCid) || typeof readChild !== 'function') {
      fail('KintoneUpdateReadChildUnavailable');
    }
    const decision = async slot => {
      signal?.throwIfAborted();
      const result = await authorize('acquisition', {connection, resource: formResource, operation: 'read'}, {
        subjectCid: cid({binding, member: memberFacts(member), runInvocationCid, dispatchRequestCid, slot}), signal});
      signal?.throwIfAborted();
      if (result?.action !== 'dispatch') fail('KintoneFormReadDenied');
      return result;
    };
    const verify = async slot => {
      signal?.throwIfAborted();
      // Target uses its own original row grant/current child. Form decisions
      // cannot authorize target data or stand in for those physical fences.
      if (slot !== 'target') await decision(slot);
      signal?.throwIfAborted();
    };
    return async (slot, body, rowIndex, project) => {
      await verify(slot);
      let authorization, useId;
      const operation = slot === 'target' ? KINTONE_TARGET_READ_OPERATION : KINTONE_FORM_READ_OPERATION;
      if (slot === 'target') {
        if (typeof targetAuthorization !== 'function') fail('KintoneTargetAuthorizationUnavailable');
        authorization = await targetAuthorization(rowIndex); useId = authorization?.useId;
      } else {
        const facts = {operation, decision: await decision(slot), resource: formResource,
          runInvocationCid, dispatchRequestCid, maxUses: 3 * (2 * maxRows + 1)};
        authorization = controlConstruction === undefined ? issueReadGrant(facts)
          : controlConstruction(undefined, issueReadGrant, [facts]);
        if (occurrence >= Number.MAX_SAFE_INTEGER) fail('KintoneReadOccurrenceLimit');
        useId = dispatchRequestCid + '-kintone-form-' + occurrence++;
      }
      await verify(slot);
      if (!authorization || nodeTypes.isProxy(authorization) || slot !== 'target' && !Object.isFrozen(authorization) ||
          typeof useId !== 'string' || !useId || Buffer.byteLength(body) > maxRequestBytes) {
        fail('InvalidKintoneUpdateRead');
      }
      const http = ownHttpRequest({method: 'POST', path: prefix +
        (slot === 'target' ? 'records.json' : 'app/form/fields.json'), query: [],
        headers: [['accept', 'application/json'], ['x-http-method-override', 'GET']], body});
      const input = {grant: authorization.grant, useId,
        operations: new Map([[operation, Object.freeze({method: http.method, path: http.target,
          headers: http.headers, body: http.body})]]), maxRequestBytes, maxResponseBytes,
        returnRejectedResponse: true, signal, currentBeforeSend: () => verify(slot)};
      // Pass the SAME Site issuer object; useId is only the invocation input.
      const value = await readChild(authorization, input, rowIndex, slot, response => {
        observations.push(response);
        if (!response.accepted || response.statusCode !== 200) fail('KintoneUpdateReadRejected');
        return project(response);
      });
      await verify(slot);
      return value;
    };
  };
  const restore = ({durable, recorded, members, memberIndexes, body, requestTags}) => {
    if (!Array.isArray(members) || members.length < 1 || members.length > maxMembers ||
        !Array.isArray(durable?.connectorRecovery) || durable.connectorRecovery.length > members.length ||
        !Array.isArray(recorded?.members) || recorded.members.length !== members.length) fail('InvalidKintoneUpdateRecovery');
    const indexes = memberIndexes ?? members.map((_, index) => index);
    if (!Array.isArray(indexes) || indexes.length < 1 || indexes.length > members.length ||
        indexes.some((index, offset) => !Number.isSafeInteger(index) || index < 0 || index >= members.length ||
          offset > 0 && index <= indexes[offset - 1])) fail('InvalidKintoneUpdateRecovery');
    const byIndex = new Map();
    for (const entry of durable.connectorRecovery) {
      if (!Number.isSafeInteger(entry?.memberIndex) || entry.memberIndex < 0 || entry.memberIndex >= members.length ||
          byIndex.has(entry.memberIndex)) fail('InvalidKintoneUpdateRecovery');
      byIndex.set(entry.memberIndex, entry);
    }
    return Object.freeze({requests: Object.freeze(indexes.map(index => {
      const member = members[index]; selected(member);
      const saved = byIndex.get(index), changes = body?.effects?.[index]?.changes,
        claims = recorded.members[index]?.claims;
      if (saved?.kind !== recoveryKind || typeof saved.wire !== 'string' ||
          Buffer.byteLength(saved.wire) > maxRecoveryBytes || wireCid(saved.wire) !== saved.observationCid ||
          !Array.isArray(changes) || changes.length > maxRows || !Array.isArray(claims) ||
          claims.length !== changes.length) fail('InvalidKintoneUpdateRecovery');
      const value = JSON.parse(saved.wire);
      if (value === null || typeof value !== 'object' || Array.isArray(value) || value.version !== recoveryVersion ||
          Object.keys(value).sort().join(',') !== 'binding,member,requests,version' ||
          !sameRecord(value.binding, binding) || !sameRecord(value.member, memberFacts(member)) ||
          !Array.isArray(value.requests) || value.requests.length !== changes.length ||
          value.requests.some(wire => typeof wire !== 'string' || Buffer.byteLength(wire) > maxRecoveryBytes) ||
          encode(value) !== saved.wire) fail('InvalidKintoneUpdateRecovery');
      return Object.freeze(value.requests.map((wire, row) => {
        const rebuilt = requests.restore({wire, requestTag: requestTags?.[index]?.[row]});
        const facts = requests.requestFacts(rebuilt.request);
        if (rebuilt.requestCid !== claims[row].canonicalRequestCid ||
            encode(facts.value) !== encode(changes[row].after?.value) ||
            encode(facts.target) !== encode(changes[row].target_row_identity)) fail('ForeignKintoneUpdateRecovery');
        return rebuilt.request;
      }));
    }))});
  };
  return Object.freeze({
    kinds: Object.freeze(['update']), targetRead: Object.freeze({operation: KINTONE_TARGET_READ_OPERATION}),
    writeOperation: () => KINTONE_RECORD_UPDATE_OPERATION,
    requestFacts: requests.requestFacts, requestCid: requests.requestCid, capabilityRequestCid: requests.capabilityRequestCid,
    finalizeRequest: requests.finalize, assertRequestFinalized: requests.assertFinalized,
    async describe(options) {
      const observations = [];
      try {
        await readScope(options, observations)('schema', requests.formBody, 0, requests.recheckForm);
        const current = Object.freeze({});
        currentFrames.set(current, {member: options.member, runInvocationCid: options.runInvocationCid,
          dispatchRequestCid: options.dispatchRequestCid, controlConstruction: options.controlConstruction});
        return current;
      } catch (cause) {throw new KintoneUpdateObservationFailure(cause, observations);}
    },
    prepareRequest(options) {frame(options.member, options.current); return requests.prepare(options);},
    recheckRequests({member, entries, current}) {
      frame(member, current);
      if (!Array.isArray(entries) || entries.length > maxRows) fail('InvalidKintoneUpdateRequests');
      for (const entry of entries) {
        if (entry.requestCid !== requests.requestCid(entry.request)) fail('ForeignKintoneUpdateRequest');
        requests.nativeRequest(entry.request);
      }
    },
    async observeTargets(options) {
      const original = frame(options.member, options.current), observations = [];
      if (!Array.isArray(options.entries) || options.entries.length > maxRows) fail('InvalidKintoneUpdateRequests');
      try {
        const read = readScope({...original, readChild: options.readChild, signal: options.signal,
          targetAuthorization: options.authorizationForRow}, observations), rows = [];
        for (const [row, entry] of options.entries.entries()) {
          if (entry.requestCid !== requests.requestCid(entry.request)) fail('ForeignKintoneUpdateRequest');
          await read('schema-before', requests.formBody, row, requests.recheckForm);
          const observed = await read('target', requests.targetReadBody(entry.request), row,
            response => requests.projectTarget(entry.request, response));
          // The existing checked-page projection includes the exact API id
          // beside every declared before field. Keep it in the Preview.
          if (encode(Object.keys(observed.before).sort()) !== encode(['$id', ...beforeFields])) fail('ForeignKintoneBeforeFields');
          await read('schema-after', requests.formBody, row, requests.recheckForm);
          rows.push(observed);
        }
        return Object.freeze(rows);
      } catch (cause) {throw new KintoneUpdateObservationFailure(cause, observations);}
    },
    admitTargetReadApproval({member, decision}) {
      selected(member);
      const expected = {version: KINTONE_UPDATE_TARGET_VERSION, site_binding_cid: siteBindingCid,
        generation_cid: generationCid, effect_id: member.effectId, member_index: member.memberIndex,
        mapping_ref: requests.mappingRef, mapping_cid: requests.mappingCid, resource, effect_kind: 'update',
        key: '$id', fields: beforeFields};
      const matched = checkpointApprovalFacts(decision)?.physicalBindings?.find(value =>
        Object.entries(expected).every(([key, item]) => encode(value[key]) === encode(item)));
      if (!matched) fail('KintoneTargetReadApprovalNotAdmitted');
      return admitTarget(decision, matched, KINTONE_TARGET_READ_OPERATION);
    },
    footprint({member}) {
      selected(member);
      return Object.freeze({providerNamespace: 'kintone', resourceKind: 'app-record',
        boundaryCid: cid({origin, appId, guestSpaceId: guestSpaceId ?? null})});
    },
    recoveryEntry({member, entries}) {
      selected(member);
      if (!Array.isArray(entries) || entries.length > maxRows) fail('InvalidKintoneUpdateRecovery');
      const wires = entries.map(entry => {
        if (entry.requestCid !== requests.requestCid(entry.request)) fail('ForeignKintoneUpdateRequest');
        return requests.savedWire(entry.request);
      });
      const wire = encode({version: recoveryVersion, binding, member: memberFacts(member), requests: wires});
      if (Buffer.byteLength(wire) > maxRecoveryBytes) fail('KintoneUpdateRecoveryLimit');
      return Object.freeze({kind: recoveryKind, observationCid: wireCid(wire), wire});
    },
    recoverRequests: restore, recoverMemberRequests: restore,
    async send({member, request, current, authorization, credential, signal, callResource}) {
      frame(member, current);
      const scope = invocationScopeFields(authorization?.scope, credential?.control);
      if (scope?.resourceOrigin !== origin || scope.connectorRegistration !== 'kintone') fail('ForeignKintoneUpdateOrigin');
      const body = requests.requestBody(request);
      signal?.throwIfAborted();
      const response = await invokeScopedCredentialOperation({authorization, credential, callResource,
        operation: KINTONE_RECORD_UPDATE_OPERATION, method: 'PUT', path: prefix + 'records.json', query: [],
        headers: [['accept', 'application/json']], body, responseHeaders: [], maxRequestBytes, maxResponseBytes, signal});
      // No post-send abort exception may discard an observed response. Host
      // owns its custody and the original subsequent current/settlement fence.
      return Object.freeze({observation: Object.freeze({useCid: response.useCid,
        statusCode: response.statusCode, body: response.body})});
    },
    project({request, observation}) {return requests.projectResponse(request, observation);},
  });
}
