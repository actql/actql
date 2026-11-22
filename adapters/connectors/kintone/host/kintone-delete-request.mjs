// Request DATA for the existing row Effect. Site and Effect owners retain
// physical reads, approval, dispatch, reconciliation and teardown.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const encode = value => canonicalJson(value, {dataKeys: true});
const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const isCid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const codec = 'actql-installed-kintone-delete-request/0.1';
const policyKeys = ['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth', 'maxFields',
  'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes', 'maxValueDepth',
  'maxValueTextBytes', 'maxIdentityBytes', 'maxComparisonWork', 'maxRecoveryBytes'];
const savedKeys = ['binding', 'identity', 'logicalCid', 'requestTag', 'targetBodyBase64',
  'targetBodyCid', 'body', 'requestCid'];

function ownData(value, names, code) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || nodeTypes.isProxy(value)) fail(code);
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== names.length ||
      names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail(code);
  return Object.fromEntries(names.map(name => [name, fields[name].value]));
}

export function createKintoneDeleteRequestAdapter({moon, mapping, declaration, origin, appId, connectorId,
  resource, siteBindingCid, generationCid, guestSpaceId, limits}) {
  if (typeof origin !== 'string' || !URL.canParse(origin) || new URL(origin).origin !== origin ||
      new URL(origin).protocol !== 'https:' ||
      typeof appId !== 'string' || !/^[1-9][0-9]*$/u.test(appId) || !isCid(siteBindingCid) || !isCid(generationCid) ||
      ![connectorId, resource].every(value => typeof value === 'string' && value.length > 0 && value.isWellFormed()) ||
      guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) fail('InvalidKintoneDeleteInstallation');
  const policy = ownData(limits, policyKeys, 'InvalidKintoneDeleteLimits');
  if (!Object.values(policy).every(positive)) fail('InvalidKintoneDeleteLimits');
  if (!moon || nodeTypes.isProxy(moon)) fail('KintoneDeleteRuntimeUnavailable');
  const native = Object.fromEntries([
    'DeleteMappingMatchesDeclaration', 'DeleteMappingMatchesRequest', 'DeleteMappingBody',
    'DeleteMappingRecheckForm', 'DeleteTargetReadBody', 'PrepareDeleteTargetRead',
    'DeletePreviewIdentity', 'DeletePreviewBefore', 'DeletePreviewVersionCid', 'DeleteApp', 'DeleteBody',
    'MutationLimits', 'PageLimits', 'ValueLimits', 'FormLimits',
  ].map(name => {
    const method = Object.getOwnPropertyDescriptor(moon, 'clientProgramKintone' + name)?.value;
    if (typeof method !== 'function' || nodeTypes.isProxy(method) || nodeTypes.isAsyncFunction(method)) {
      fail('KintoneDeleteRuntimeUnavailable');
    }
    return [name, (...args) => Reflect.apply(method, moon, args)];
  }));
  if (!native.DeleteMappingMatchesDeclaration(mapping, declaration)) fail('ForeignKintoneDeleteMapping');
  const {mapping_ref: mappingRef, mapping_contract_cid: mappingCid, target_ref: targetRef,
    primary_identity: primaryIdentity} = JSON.parse(native.DeleteMappingBody(mapping));
  if (typeof mappingRef !== 'string' || !isCid(mappingCid) || primaryIdentity !== '$id' ||
      targetRef !== `connector://${connectorId}/${resource}`) fail('ForeignKintoneDeleteMapping');
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const binding = Object.freeze({codec, origin, appId, connectorId, resource, siteBindingCid, generationCid,
    mappingRef, mappingCid, method: 'POST', override: 'DELETE', path: prefix + 'records.json'});
  const mutationLimits = maximum => native.MutationLimits(1, policy.maxIdentityBytes, policy.maxComparisonWork,
    maximum, policy.maxNodes, policy.maxDepth);
  const requestLimits = mutationLimits(policy.maxRequestBytes), beforeLimits = mutationLimits(policy.maxResponseBytes);
  const pageLimits = native.PageLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth, 1,
    policy.maxColumns, policy.maxCells, policy.maxTableRows);
  const valueLimits = native.ValueLimits(policy.maxColumns, policy.maxNameUnits,
    policy.maxValueNodes, policy.maxValueDepth, policy.maxValueTextBytes);
  const formLimits = native.FormLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth,
    policy.maxFields, policy.maxNameUnits);
  const originals = new WeakMap();
  const get = request => {
    const original = originals.get(request);
    if (original === undefined) fail('ForeignKintoneDeleteRequest');
    return original;
  };
  const observed = response => {
    if (response?.statusCode !== 200 || !(response.body instanceof Uint8Array) ||
        response.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneDeleteObservation');
    return response.body;
  };
  const readBody = identity => checked(native.DeleteTargetReadBody(mapping, identity, policy.maxFields, requestLimits));
  const logicalIdentity = identity => digest(encode({binding, identity}));
  const physicalIdentity = ({logicalCid, requestTag, targetBodyCid, body}) =>
    digest(encode({logicalCid, requestTag, targetBodyCid, body}));
  const project = (identity, bytes) => {
    const result = checked(native.PrepareDeleteTargetRead(mapping, identity, bytes, pageLimits, valueLimits, beforeLimits));
    const preview = runtimeField(result, 0), request = runtimeField(result, 1);
    if (native.DeletePreviewIdentity(preview) !== identity || native.DeleteApp(request) !== appId ||
        !native.DeleteMappingMatchesRequest(mapping, request)) fail('ForeignKintoneDeleteTarget');
    const body = native.DeleteBody(request), versionCid = native.DeletePreviewVersionCid(preview);
    if (!isCid(versionCid) || Buffer.byteLength(body) > policy.maxRequestBytes) fail('KintoneDeleteRequestLimit');
    return {native: request, body, versionCid, beforeWire: native.DeletePreviewBefore(preview)};
  };
  const final = request => {
    const original = get(request);
    if (original.requestCid === undefined) fail('KintoneDeleteRequestNotFinalized');
    return original;
  };
  const issueFinal = original => {
    const request = Object.freeze({logicalCid: original.logicalCid, requestCid: original.requestCid});
    originals.set(request, original);
    return Object.freeze({request, requestCid: original.requestCid});
  };
  return Object.freeze({mappingRef, mappingCid, binding, formBody: JSON.stringify({app: appId}),
    prepare({selector, value}) {
      if (typeof selector !== 'string' || value !== undefined) fail('InvalidKintoneDeleteSelector');
      const read = readBody(selector), logicalCid = logicalIdentity(selector);
      const request = Object.freeze({logicalCid});
      originals.set(request, {identity: selector, read, logicalCid});
      return Object.freeze({request, requestCid: logicalCid});
    },
    recheckForm(response) {return checked(native.DeleteMappingRecheckForm(mapping, observed(response), formLimits));},
    targetReadBody(request) {return get(request).read;},
    projectTarget(request, response) {
      const original = get(request), bytes = Buffer.from(observed(response));
      const target = project(original.identity, bytes);
      if (original.target === undefined) {
        original.target = target;
        original.targetBodyCid = digest(bytes);
        original.targetBodyBase64 = bytes.toString('base64');
      } else if (original.target.beforeWire !== target.beforeWire || original.target.versionCid !== target.versionCid) {
        fail('KintoneDeleteTargetChanged');
      }
      return Object.freeze({identity: original.identity, versionCid: target.versionCid, before: JSON.parse(target.beforeWire)});
    },
    finalize({request, requestTag}) {
      const original = get(request);
      if (original.target === undefined || original.finalized || original.requestCid !== undefined || !isCid(requestTag)) {
        fail('KintoneDeleteFinalizationUnavailable');
      }
      const next = {...original, requestTag, body: original.target.body};
      next.requestCid = physicalIdentity(next);
      original.finalized = true;
      return issueFinal(next);
    },
    requestFacts(request) {return Object.freeze({target: get(request).identity});},
    requestCid(request) {const original = get(request); return original.requestCid ?? original.logicalCid;},
    capabilityRequestCid(request) {return get(request).logicalCid;},
    assertFinalized(request, requestTag) {
      if (final(request).requestTag !== requestTag) fail('KintoneDeleteRequestTagMismatch');
    },
    nativeRequest(request) {return final(request).target.native;},
    requestBody(request) {return final(request).body;},
    savedWire(request) {
      const {identity, logicalCid, requestTag, targetBodyBase64, targetBodyCid, body, requestCid} = final(request);
      const wire = encode({binding, identity, logicalCid, requestTag, targetBodyBase64, targetBodyCid, body, requestCid});
      if (Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('KintoneDeleteRecoveryLimit');
      return wire;
    },
    restore({wire, requestTag}) {
      const invalid = 'ForeignKintoneDeleteRecovery';
      if (typeof wire !== 'string' || wire.length > policy.maxRecoveryBytes ||
          Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('KintoneDeleteRecoveryLimit');
      const saved = ownData(JSON.parse(wire), savedKeys, invalid);
      const storedBinding = ownData(saved.binding, Object.keys(binding), invalid);
      if (Object.keys(binding).some(name => storedBinding[name] !== binding[name]) ||
          !isCid(requestTag) || saved.requestTag !== requestTag ||
          !['logicalCid', 'targetBodyCid', 'requestCid'].every(name => isCid(saved[name])) ||
          typeof saved.identity !== 'string' || typeof saved.body !== 'string' ||
          Buffer.byteLength(saved.body) > policy.maxRequestBytes ||
          typeof saved.targetBodyBase64 !== 'string' ||
          saved.targetBodyBase64.length > Math.ceil(policy.maxResponseBytes / 3) * 4) fail(invalid);
      const read = readBody(saved.identity), bytes = Buffer.from(saved.targetBodyBase64, 'base64');
      if (bytes.length > policy.maxResponseBytes || bytes.toString('base64') !== saved.targetBodyBase64 ||
          encode(saved) !== wire || digest(bytes) !== saved.targetBodyCid ||
          logicalIdentity(saved.identity) !== saved.logicalCid || physicalIdentity(saved) !== saved.requestCid) fail(invalid);
      const target = project(saved.identity, bytes);
      if (target.body !== saved.body) fail(invalid);
      return issueFinal({...saved, read, target});
    },
  });
}
