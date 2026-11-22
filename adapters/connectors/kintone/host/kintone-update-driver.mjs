// Kintone protocol over the existing installed row Effect. The shared Host
// retains Preview, approval, claims, Unknown, physical funding and cleanup.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {admitCheckpointPhysicalRead} from '../../../host-common/checkpoint-approval.mjs';
import {ownHttpRequest} from '../../../host-common/http-exchange.mjs';
import {invocationScopeFields, invokeScopedCredentialOperation, ownInvocationContext,
  rowUpdateTransportObservation} from '../../../host-common/owned-invocation-context.mjs';
import {assertInstalledRowUpdateClaim, installedRowUpdateRequestWires, packInstalledRowUpdateRecovery,
  restoreInstalledRowUpdateMembers, unpackInstalledRowUpdateRecovery} from '../../../host-common/installed-row-update-recovery.mjs';
import {createKintoneUpdateRequestAdapter} from './kintone-update-request.mjs';
import {createKintoneDeleteRequestAdapter} from './kintone-delete-request.mjs';
import {KINTONE_FORM_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {KintoneDeleteFailure, KINTONE_RECORD_DELETE_OPERATION, KINTONE_TARGET_READ_OPERATION}
  from '../site/kintone-record-delete.mjs';
import {KINTONE_RECORD_UPDATE_OPERATION} from '../site/kintone-record-write.mjs';

export const KINTONE_UPDATE_TARGET_VERSION = 'actql-installed-kintone-effect-target-read/0.1';
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
const capture = (receiver, name, invalid, asynchronous = false) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail(invalid);
  const field = Object.getOwnPropertyDescriptor(receiver, name), method = field?.value;
  if (!field || !Object.hasOwn(field, 'value') || typeof method !== 'function' || nodeTypes.isProxy(method) ||
      !asynchronous && nodeTypes.isAsyncFunction(method)) fail(invalid);
  return (...args) => Reflect.apply(method, receiver, args);
};

function credentialReadOperations(request, operation, limits) {
  const http = ownHttpRequest(request, limits);
  return new Map([[operation, Object.freeze({method: http.method, path: http.target,
    headers: http.headers, body: http.body})]]);
}

export class KintoneUpdateObservationFailure extends Error {
  constructor(cause, observations) {
    super('KintoneUpdateObservationFailed', {cause});
    this.code = cause?.code ?? 'KintoneUpdateObservationFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

export function kintoneUpdateDriver(options) {
  return kintoneRecordMutationDriver('update', options);
}

export function kintoneDeleteDriver(options) {
  return kintoneRecordMutationDriver('delete', options);
}

function kintoneRecordMutationDriver(kind, {moon, site, authorization, connection, origin, appId, connectorId,
  resource, formResource, fields, mapping, declaration, siteBindingCid, generationCid, guestSpaceId,
  limits, maxMembers, maxRecoveryBytes}) {
  const updating = kind === 'update';
  const subject = updating ? 'KintoneUpdate' : 'KintoneDelete';
  const invalidDriver = 'Invalid' + subject + 'Driver';
  const invalidRequests = 'Invalid' + subject + 'Requests';
  const invalidRecovery = 'Invalid' + subject + 'Recovery';
  const foreignRequest = 'Foreign' + subject + 'Request';
  const recoveryKind = `kintone-${kind}-requests`;
  const recoveryVersion = `actql-installed-kintone-${kind}-recovery/0.1`;
  const observationFailure = (cause, observations, phase) => updating
    ? new KintoneUpdateObservationFailure(cause, observations)
    : new KintoneDeleteFailure(cause, observations, phase);
  if (typeof connection !== 'string' || !connection || typeof formResource !== 'string' || !formResource ||
      formResource === resource || !positive(maxMembers) ||
      !positive(maxRecoveryBytes) || !Array.isArray(fields) || nodeTypes.isProxy(fields) || fields.length < 1 ||
      fields.some((name, index) => typeof name !== 'string' || !name || name === '$id' || name === '$revision' ||
        index > 0 && name <= fields[index - 1])) fail(invalidDriver);
  const beforeFields = Object.freeze(fields.slice());
  const createRequests = updating ? createKintoneUpdateRequestAdapter : createKintoneDeleteRequestAdapter;
  const requests = createRequests({moon, mapping, declaration, origin, appId, connectorId,
    resource, siteBindingCid, generationCid, guestSpaceId, limits});
  // These are immutable DATA bounds, not a borrowed mutable policy object.
  const maxRequestBytes = limits.maxRequestBytes, maxResponseBytes = limits.maxResponseBytes;
  const issueReadGrant = capture(site, 'issueReadGrant', invalidDriver),
    admitTarget = capture(site, 'admitCheckpointEffectTargetRead', invalidDriver),
    authorize = capture(authorization, 'authorize', invalidDriver, true);
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const binding = Object.freeze({...requests.binding, formResource, fields: beforeFields});
  const currentFrames = new WeakMap();
  let occurrence = 0;
  const selected = member => {
    if (member?.kind !== kind || member.resource !== resource ||
        member.mapping?.mappingRef !== requests.mappingRef || member.mapping?.mappingCid !== requests.mappingCid) {
      fail('Foreign' + subject + 'Mapping');
    }
  };
  const frame = (member, current) => {
    selected(member);
    const original = currentFrames.get(current);
    if (!original || original.member !== member) fail('Foreign' + subject + 'Current');
    return original;
  };
  const readScope = (options, observations) => {
    const {member, signal, runInvocationCid, dispatchRequestCid, controlConstruction, readChild, readTarget,
      targetAuthorization} = options;
    selected(member);
    if (!isCid(runInvocationCid) || !isCid(dispatchRequestCid) || typeof readChild !== 'function') {
      fail(subject + 'ReadChildUnavailable');
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
      const request = {method: 'POST', path: prefix +
        (slot === 'target' ? 'records.json' : 'app/form/fields.json'), query: [],
        headers: [['accept', 'application/json'], ['x-http-method-override', 'GET']], body};
      const consume = response => {
        observations.push(response);
        if (!response.accepted || response.statusCode !== 200) fail(subject + 'ReadRejected');
        return project(response);
      };
      if (slot === 'target' && readTarget !== undefined) {
        const value = await readTarget(rowIndex, request, consume, () => verify(slot));
        await verify(slot);
        return value;
      }
      let authorization, useId;
      const operation = slot === 'target' ? KINTONE_TARGET_READ_OPERATION : KINTONE_FORM_READ_OPERATION;
      if (slot === 'target') {
        if (typeof targetAuthorization !== 'function') fail('KintoneTargetAuthorizationUnavailable');
        authorization = await targetAuthorization(rowIndex); useId = authorization?.useId;
      } else {
        const facts = {operation, decision: await decision(slot), resource: formResource,
          runInvocationCid, dispatchRequestCid, maxUses: 1};
        authorization = controlConstruction === undefined ? issueReadGrant(facts)
          : controlConstruction(undefined, issueReadGrant, [facts]);
        if (occurrence >= Number.MAX_SAFE_INTEGER) fail('KintoneReadOccurrenceLimit');
        useId = dispatchRequestCid + '-kintone-form-' + occurrence++;
      }
      await verify(slot);
      if (!authorization || nodeTypes.isProxy(authorization) || slot !== 'target' && !Object.isFrozen(authorization) ||
          typeof useId !== 'string' || !useId || Buffer.byteLength(body) > maxRequestBytes) {
        fail('Invalid' + subject + 'Read');
      }
      const prepareOperations = !updating && slot === 'target' ? () =>
        credentialReadOperations(request, operation, {maxTargetBytes: requests.binding.path.length}) : undefined;
      const input = {grant: authorization.grant, useId,
        ...(prepareOperations === undefined ? {operations: credentialReadOperations(request, operation)} : {}),
        maxRequestBytes, maxResponseBytes,
        returnRejectedResponse: true, signal, currentBeforeSend: () => verify(slot)};
      // Pass the SAME Site issuer object; useId is only the invocation input.
      const value = prepareOperations !== undefined
        ? await readChild(authorization, input, rowIndex, slot, consume, prepareOperations)
        : await readChild(authorization, input, rowIndex, slot, consume);
      await verify(slot);
      return value;
    };
  };
  const restore = context => {
    const {maxRows} = context;
    if (!Number.isSafeInteger(maxRows) || maxRows < 0 || maxRows > 2147483647) {
      fail(invalidRecovery);
    }
    return restoreInstalledRowUpdateMembers(context, maxMembers,
      invalidRecovery, ({recorded, members, body, requestTags}, index, saved) => {
        const member = members[index]; selected(member);
        const changes = body?.effects?.[index]?.changes,
          claims = recorded.members[index]?.claims;
        const value = unpackInstalledRowUpdateRecovery(saved, recoveryKind, maxRecoveryBytes,
          changes, claims, maxRows, invalidRecovery);
        if (value === null || typeof value !== 'object' || Array.isArray(value) || value.version !== recoveryVersion ||
            Object.keys(value).sort().join(',') !== 'binding,member,requests,version' ||
            !sameRecord(value.binding, binding) || !sameRecord(value.member, memberFacts(member)) ||
            !Array.isArray(value.requests) || value.requests.length !== changes.length ||
            value.requests.some(wire => typeof wire !== 'string' || Buffer.byteLength(wire) > maxRecoveryBytes) ||
            encode(value) !== saved.wire) fail(invalidRecovery);
        return Object.freeze(value.requests.map((wire, row) => {
          const rebuilt = requests.restore({wire, requestTag: requestTags?.[index]?.[row]});
          const facts = requests.requestFacts(rebuilt.request);
          if (updating) {
            assertInstalledRowUpdateClaim(rebuilt, facts, claims, changes, row, 'ForeignKintoneUpdateRecovery');
          } else if (rebuilt.requestCid !== claims[row]?.canonicalRequestCid ||
              changes[row]?.after?.state !== 'absent' || facts.target !== changes[row]?.target_row_identity) {
            fail('ForeignKintoneDeleteRecovery');
          }
          return rebuilt.request;
        }));
      });
  };

  const write = updating ? {
    kind, operation: KINTONE_RECORD_UPDATE_OPERATION,
    prepareUpdateWrite(member, request, current, resourceOrigin, registration, signal) {
      frame(member, current);
      if (resourceOrigin !== origin || registration !== 'kintone') fail('ForeignKintoneUpdateOrigin');
      const body = requests.requestBody(request);
      signal?.throwIfAborted();
      return {method: 'PUT', path: prefix + 'records.json', query: [],
        headers: [['accept', 'application/json']], body, responseHeaders: []};
    },
    project({request, observation}) {return requests.projectResponse(request, observation);},
  } : {
    kinds: Object.freeze([kind]),
    writeOperation(member) {selected(member); return KINTONE_RECORD_DELETE_OPERATION;},
    async send({member, request, current, authorization, credential, callResource, signal}) {
      frame(member, current);
      const context = ownInvocationContext({authorization, credential,
        limits: {maxRequestBytes, maxResponseBytes}, callbacks: {callResource}});
      const scope = invocationScopeFields(context.scope, context.credential.control);
      if (scope.resourceOrigin !== origin || scope.connectorRegistration !== 'kintone' ||
          scope.operation !== KINTONE_RECORD_DELETE_OPERATION) fail('ForeignKintoneDeleteOrigin');
      const body = requests.requestBody(request);
      signal?.throwIfAborted();
      const response = await invokeScopedCredentialOperation({authorization: context.authorization,
        credential: context.credential, callResource: context.callbacks.callResource,
        operation: KINTONE_RECORD_DELETE_OPERATION, method: 'POST', path: prefix + 'records.json', body,
        headers: [['accept', 'application/json'], ['x-http-method-override', 'DELETE']],
        maxRequestBytes, maxResponseBytes, signal});
      return rowUpdateTransportObservation(response);
    },
    project: requests.projectResponse,
  };
  return Object.freeze({
    ...write, targetRead: Object.freeze({operation: KINTONE_TARGET_READ_OPERATION}),
    requestFacts: requests.requestFacts, requestCid: requests.requestCid, capabilityRequestCid: requests.capabilityRequestCid,
    finalizeRequest: requests.finalize, assertRequestFinalized: requests.assertFinalized,
    async describe(options) {
      const observations = [];
      try {
        if (!Number.isSafeInteger(options.maxRows) || options.maxRows < 0 || options.maxRows > 2147483647) {
          fail(invalidRequests);
        }
        await readScope(options, observations)('schema', requests.formBody, 0, requests.recheckForm);
        const current = Object.freeze({});
        currentFrames.set(current, {member: options.member, runInvocationCid: options.runInvocationCid,
          dispatchRequestCid: options.dispatchRequestCid, controlConstruction: options.controlConstruction, maxRows: options.maxRows});
        return current;
      } catch (cause) {throw observationFailure(cause, observations, 'form');}
    },
    prepareRequest(options) {frame(options.member, options.current); return requests.prepare(options);},
    recheckRequests({member, entries, current}) {
      const original = frame(member, current);
      if (!Array.isArray(entries) || entries.length > original.maxRows) fail(invalidRequests);
      for (const entry of entries) {
        if (entry.requestCid !== requests.requestCid(entry.request)) fail(foreignRequest);
        requests.nativeRequest(entry.request);
      }
    },
    async observeTargets(options) {
      const original = frame(options.member, options.current), observations = [];
      if (!Array.isArray(options.entries) || options.entries.length > original.maxRows) fail(invalidRequests);
      try {
        const read = readScope({...original, readChild: options.readChild, readTarget: options.readTarget, signal: options.signal,
          targetAuthorization: options.authorizationForRow}, observations), rows = [];
        for (const [row, entry] of options.entries.entries()) {
          if (entry.requestCid !== requests.requestCid(entry.request)) fail(foreignRequest);
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
      } catch (cause) {throw observationFailure(cause, observations, 'target');}
    },
    admitTargetReadApproval({member, decision}) {
      selected(member);
      const expected = {version: KINTONE_UPDATE_TARGET_VERSION, site_binding_cid: siteBindingCid,
        generation_cid: generationCid, effect_id: member.effectId, member_index: member.memberIndex,
        mapping_ref: requests.mappingRef, mapping_cid: requests.mappingCid, resource, effect_kind: kind,
        key: '$id', fields: beforeFields};
      return admitCheckpointPhysicalRead(decision, expected, KINTONE_TARGET_READ_OPERATION,
        admitTarget, 'KintoneTargetReadApprovalNotAdmitted');
    },
    footprint({member}) {
      selected(member);
      return Object.freeze({providerNamespace: 'kintone', resourceKind: 'app-record',
        boundaryCid: cid({origin, appId, guestSpaceId: guestSpaceId ?? null})});
    },
    recoveryEntry({member, current, entries}) {
      const original = frame(member, current);
      const wires = installedRowUpdateRequestWires(entries, original.maxRows, requests,
        invalidRecovery, foreignRequest);
      return packInstalledRowUpdateRecovery(recoveryKind, {version: recoveryVersion, binding,
        member: memberFacts(member), requests: wires}, maxRecoveryBytes, subject + 'RecoveryLimit');
    },
    recoverRequests: restore, recoverMemberRequests: restore,
  });
}
