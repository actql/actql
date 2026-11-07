// Pure adapter over HubSpot's original Mapping/Request/Marker constructors.
// The common row Effect supplies the final dispatch key; this module issues
// no claim, permission, provider property, send, retry or cleanup ACK.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeIsBoxedSome, runtimeField, runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';

const fail = code => {throw Object.assign(new TypeError(code), {code});};
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const encode = value => canonicalJson(value, {dataKeys: true});
const cid = value => 'sha256:' + createHash('sha256').update(encode(value)).digest('hex');
const own = (value, names) => {
  if (!value || typeof value !== 'object' || nodeTypes.isProxy(value)) fail('InvalidHubSpotUpdateRequest');
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== names.length || names.some(name =>
    !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidHubSpotUpdateRequest');
  return Object.fromEntries(names.map(name => [name, fields[name].value]));
};
const exact = wire => {
  if (typeof wire !== 'string') fail('InvalidHubSpotUpdateRequest');
  const value = JSON.parse(wire);
  if (JSON.stringify(value) !== wire) fail('LossyHubSpotUpdateRequest');
  return value;
};
const method = (receiver, name) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail('HubSpotUpdateRequestUnavailable');
  const field = Object.getOwnPropertyDescriptor(receiver, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) fail('HubSpotUpdateRequestUnavailable');
  return (...args) => Reflect.apply(field.value, receiver, args);
};

export function createHubSpotUpdateRequestAdapter({moon, origin, portalId, connectorId, installedFor, limits}) {
  if (typeof origin !== 'string' || !URL.canParse(origin) || new URL(origin).origin !== origin ||
      !origin.startsWith('https://') || typeof portalId !== 'string' ||
      !/^[1-9][0-9]{0,10}$/u.test(portalId) || typeof connectorId !== 'string' ||
      typeof installedFor !== 'function' || nodeTypes.isProxy(installedFor) || nodeTypes.isAsyncFunction(installedFor)) {
    fail('InvalidHubSpotUpdateRequestAdapter');
  }
  const native = Object.fromEntries([
    'hubspotPrepareExecutionWriteBody', 'hubspotPrepareRecordTarget', 'hubspotTargetedRecordWriteInput',
    'hubspotPrepareRecordBatch', 'hubspotPrepareRecordRequestMarker', 'hubspotPrepareMarkedRecordBatch',
    'hubspotRecordBatchBody', 'hubspotRecordBatchObjectType', 'hubspotRecordBatchCount',
    'hubspotRecordBatchInputValueJson', 'hubspotRecordBatchInputTargetJson', 'hubspotRecordBatchMarkerFields',
  ].map(name => [name, method(moon, name)]));
  const policy = own(limits, ['maxProperties', 'body', 'request', 'maxRecoveryBytes']);
  const body = own(policy.body, ['maxInputBytes', 'maxNodes', 'maxDepth', 'maxFields', 'maxNameBytes',
    'maxValueNodes', 'maxValueTextBytes', 'maxComparisonWork', 'maxOutputBytes', 'maxOutputNodes', 'maxOutputDepth']);
  const request = own(policy.request, ['maxRows', 'maxProperties', 'maxTraceBytes', 'maxBodyBytes', 'maxBodyNodes', 'maxBodyDepth']);
  if (![policy.maxProperties, policy.maxRecoveryBytes, ...Object.values(body), ...Object.values(request)]
    .every(value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647) || request.maxRows > 100) {
    fail('InvalidHubSpotUpdateRequestLimits');
  }
  const bodyBounds = Object.freeze(Object.values(body)), requestBounds = Object.freeze(Object.values(request));
  const originals = new WeakMap();
  const get = request => {
    const value = originals.get(request);
    if (value === undefined) fail('ForeignHubSpotUpdateRequest');
    return value;
  };
  const installed = member => {
    if (member?.kind !== 'update' || typeof member.resource !== 'string') fail('InvalidHubSpotUpdateMember');
    const value = installedFor(member);
    if (!value || nodeTypes.isProxy(value) || !Object.isFrozen(value)) fail('ForeignHubSpotUpdateMapping');
    const fields = Object.getOwnPropertyDescriptors(value);
    if (['resource', 'mappingCid', 'mappingRef', 'markerProperty', 'catalog', 'mapping'].some(name =>
      !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('ForeignHubSpotUpdateMapping');
    if (value.resource !== member.resource || value.mappingCid !== member.mapping?.mappingCid ||
        value.mappingRef !== member.mapping?.mappingRef || typeof value.markerProperty !== 'string' ||
        !value.catalog || !value.mapping) fail('ForeignHubSpotUpdateMapping');
    return value;
  };
  const prepare = ({member, value, selector}) => {
    const selected = installed(member), valueWire = encode(value), selectorWire = encode(selector);
    if (Buffer.byteLength(valueWire) > body.maxInputBytes || Buffer.byteLength(selectorWire) > body.maxInputBytes) {
      fail('HubSpotUpdateRequestInputLimit');
    }
    const write = checked(native.hubspotPrepareExecutionWriteBody(selected.mapping, selected.catalog,
      Buffer.from(valueWire), policy.maxProperties, ...bodyBounds));
    const target = checked(native.hubspotPrepareRecordTarget(selected.catalog, 'id', Buffer.from(selectorWire), ...bodyBounds));
    const logical = Object.freeze({version: 'actql-installed-hubspot-update-request/0.1',
      connectorId, origin, portalId, resource: selected.resource,
      mappingRef: selected.mappingRef, mappingCid: selected.mappingCid,
      markerProperty: selected.markerProperty, valueWire, selectorWire});
    const logicalCid = cid(logical);
    const input = native.hubspotTargetedRecordWriteInput(write, target, logicalCid);
    const batch = checked(native.hubspotPrepareRecordBatch(selected.catalog, 1, 'id', [input], ...requestBounds));
    if (native.hubspotRecordBatchCount(batch) !== 1) fail('InvalidHubSpotUpdateRequest');
    const carrier = Object.freeze({logicalCid});
    originals.set(carrier, {selected, logical, logicalCid, input, batch, target});
    return Object.freeze({request: carrier, requestCid: logicalCid});
  };
  const finalize = ({request, requestTag}) => {
    const original = get(request);
    if (original.requestTag !== undefined || !cidPattern.test(requestTag ?? '')) fail('InvalidHubSpotUpdateRequestTag');
    const marker = checked(native.hubspotPrepareRecordRequestMarker(original.selected.catalog,
      original.selected.markerProperty, requestTag, ...bodyBounds));
    const batch = checked(native.hubspotPrepareMarkedRecordBatch(original.selected.catalog, 1, 'id',
      [original.input], marker, ...requestBounds));
    const wire = native.hubspotRecordBatchBody(batch);
    const requestCid = cid({logical: original.logical, logicalCid: original.logicalCid, requestTag, body: wire});
    const carrier = Object.freeze({logicalCid: original.logicalCid, requestCid});
    originals.set(carrier, {...original, batch, requestTag, requestCid, body: wire});
    return Object.freeze({request: carrier, requestCid});
  };
  const assertFinalized = (request, requestTag) => {
    const original = get(request), marker = native.hubspotRecordBatchMarkerFields(original.batch);
    if (original.requestTag !== requestTag || !cidPattern.test(requestTag ?? '') ||
        !runtimeIsBoxedSome(marker) || native.hubspotRecordBatchCount(original.batch) !== 1) {
      fail('HubSpotUpdateRequestNotFinalized');
    }
    const fields = runtimeField(marker, 0);
    if (!Array.isArray(fields) || fields.length !== 2 || fields[0] !== original.selected.markerProperty ||
        fields[1] !== requestTag || native.hubspotRecordBatchBody(original.batch) !== original.body) {
      fail('HubSpotUpdateRequestNotFinalized');
    }
  };
  const savedWire = request => {
    const original = get(request); assertFinalized(request, original.requestTag);
    const wire = encode({logical: original.logical, logicalCid: original.logicalCid,
      requestTag: original.requestTag, requestCid: original.requestCid, body: original.body});
    if (Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('HubSpotUpdateRecoveryLimit');
    return wire;
  };
  return Object.freeze({prepare, finalize, assertFinalized,
    requestCid: request => {const value = get(request); return value.requestCid ?? value.logicalCid;},
    capabilityRequestCid: request => get(request).logicalCid,
    requestFacts(request) {
      const original = get(request);
      if (native.hubspotRecordBatchCount(original.batch) !== 1) fail('InvalidHubSpotUpdateRequest');
      return Object.freeze({value: exact(runtimeUnboxedReferenceOption(native.hubspotRecordBatchInputValueJson(original.batch, 0))),
        target: exact(runtimeUnboxedReferenceOption(native.hubspotRecordBatchInputTargetJson(original.batch, 0)))});
    },
    nativeRequest: request => get(request).batch,
    nativeTarget: request => get(request).target,
    objectType: request => native.hubspotRecordBatchObjectType(get(request).batch),
    savedWire,
    restore({member, wire, requestTag}) {
      if (typeof wire !== 'string' || Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('HubSpotUpdateRecoveryLimit');
      const saved = own(exact(wire), ['logical', 'logicalCid', 'requestTag', 'requestCid', 'body']);
      const logical = own(saved.logical, ['version', 'connectorId', 'origin', 'portalId', 'resource',
        'mappingRef', 'mappingCid', 'markerProperty', 'valueWire', 'selectorWire']);
      if (saved.requestTag !== requestTag) fail('HubSpotUpdateRecoveryMismatch');
      const original = prepare({member, value: exact(logical.valueWire), selector: exact(logical.selectorWire)});
      if (encode(get(original.request).logical) !== encode(logical) || original.requestCid !== saved.logicalCid) {
        fail('HubSpotUpdateRecoveryMismatch');
      }
      const final = finalize({request: original.request, requestTag});
      assertFinalized(final.request, requestTag);
      if (final.requestCid !== saved.requestCid || savedWire(final.request) !== wire) fail('HubSpotUpdateRecoveryMismatch');
      return final;
    },
  });
}
