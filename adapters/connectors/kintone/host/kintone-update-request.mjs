// Same-runtime native proposal/observed target/request DATA. The existing Row
// Effect owns authorization, physical reads, Preview, claim, send and cleanup.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';

const fail = code => {throw Object.assign(new TypeError(code), {code});};
const encode = value => canonicalJson(value, {dataKeys: true});
const wireCid = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const cid = value => wireCid(encode(value));
const isCid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed();
const own = (value, names) => {
  if (!value || typeof value !== 'object' || nodeTypes.isProxy(value) || Array.isArray(value)) fail('InvalidKintoneUpdateMaterial');
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== names.length || names.some(name =>
    !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidKintoneUpdateMaterial');
  return Object.freeze(Object.fromEntries(names.map(name => [name, fields[name].value])));
};
const method = (receiver, name) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail('KintoneUpdateRuntimeUnavailable');
  const field = Object.getOwnPropertyDescriptor(receiver, name), fn = field?.value;
  if (!field || !Object.hasOwn(field, 'value') || typeof fn !== 'function' ||
      nodeTypes.isProxy(fn) || nodeTypes.isAsyncFunction(fn)) fail('KintoneUpdateRuntimeUnavailable');
  return (...args) => Reflect.apply(fn, receiver, args);
};
const limitNames = ['maxInputBytes', 'maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes',
  'maxValueDepth', 'maxValueTextBytes', 'maxIdentityBytes', 'maxComparisonWork', 'maxRecoveryBytes'];
const recoveryKeys = ['version', 'binding', 'identity', 'valueWire', 'targetBodyBase64', 'body',
  'targetBodyCid', 'requestTag', 'logicalCid', 'requestCid'];
const recoveryVersion = 'actql-installed-kintone-update-request/0.1';

export function createKintoneUpdateRequestAdapter({moon, mapping, declaration, origin, appId, connectorId,
  resource, siteBindingCid, generationCid, guestSpaceId, limits}) {
  if (!text(origin) || !URL.canParse(origin) || new URL(origin).protocol !== 'https:' ||
      new URL(origin).origin !== origin || !text(appId) || !text(connectorId) || !text(resource) ||
      !isCid(siteBindingCid) || !isCid(generationCid) ||
      guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) fail('InvalidKintoneUpdateInstallation');
  const policy = own(limits, limitNames);
  if (!Object.values(policy).every(positive)) fail('InvalidKintoneUpdateLimits');
  const native = Object.freeze(Object.fromEntries([
    'UpdateMappingMatchesDeclaration', 'UpdateMappingBody', 'UpdateMappingRef', 'UpdateMappingCid',
    'PrepareUpdateProposal', 'UpdateProposalIdentity', 'UpdateProposalValueWire', 'UpdateProposalApp',
    'UpdateTargetReadBody', 'PrepareUpdatePreview', 'UpdatePreviewIdentity', 'UpdatePreviewBeforeWire',
    'UpdatePreviewVersionCid', 'FinalizeUpdateRequest', 'UpdateExecutionMatches', 'RestoreUpdateExecution',
    'UpdateBody', 'MutationLimits', 'PageLimits', 'ValueLimits', 'WriteLimits', 'FormLimits',
    'UpdateMappingRecheckForm', 'UpdateResponse', 'UpdateEffectOutcome', 'UpdateEffectOutcomeWire',
    'UpdateEffectOutcomeMatchesRequest', 'UpdateEffectOutcomeResponseSha256',
  ].map(name => [name, method(moon, 'clientProgramKintone' + name)])));
  if (!native.UpdateMappingMatchesDeclaration(mapping, declaration)) fail('ForeignKintoneUpdateMapping');
  const mappingRef = checked(native.UpdateMappingRef(mapping)), mappingCid = checked(native.UpdateMappingCid(mapping));
  const body = JSON.parse(checked(native.UpdateMappingBody(mapping)));
  if (!text(mappingRef) || !isCid(mappingCid) || body.mapping_ref !== mappingRef ||
      body.mapping_contract_cid !== mappingCid ||
      body.target_ref !== 'connector://' + connectorId + '/' + resource || body.primary_identity !== '$id') {
    fail('ForeignKintoneUpdateMapping');
  }
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const binding = Object.freeze({connectorId, origin, appId, resource, siteBindingCid, generationCid,
    mappingRef, mappingCid, method: 'PUT', path: prefix + 'records.json', codec: recoveryVersion});
  const requestLimits = native.MutationLimits(1, policy.maxIdentityBytes, policy.maxComparisonWork,
    policy.maxRequestBytes, policy.maxNodes, policy.maxDepth);
  const beforeLimits = native.MutationLimits(1, policy.maxIdentityBytes, policy.maxComparisonWork,
    policy.maxResponseBytes, policy.maxNodes, policy.maxDepth);
  const pageLimits = native.PageLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth, 1,
    policy.maxColumns, policy.maxCells, policy.maxTableRows);
  const valueLimits = native.ValueLimits(policy.maxColumns, policy.maxNameUnits,
    policy.maxValueNodes, policy.maxValueDepth, policy.maxValueTextBytes);
  const writeLimits = native.WriteLimits(policy.maxFields, policy.maxNameUnits, policy.maxValueNodes,
    policy.maxValueDepth, policy.maxValueTextBytes, policy.maxRequestBytes);
  const formLimits = native.FormLimits(policy.maxResponseBytes, policy.maxNodes,
    policy.maxDepth, policy.maxFields, policy.maxNameUnits);
  const originals = new WeakMap();
  const get = request => {
    const original = originals.get(request);
    if (!original) fail('ForeignKintoneUpdateRequest');
    return original;
  };
  const valueBytes = wire => {
    if (typeof wire !== 'string' || !wire.isWellFormed() || wire.length > policy.maxInputBytes ||
        Buffer.byteLength(wire) > policy.maxInputBytes) fail('KintoneUpdateValueLimit');
    return Buffer.from(wire, 'utf8');
  };
  const targetBytes = text => {
    if (typeof text !== 'string' || text.length > Math.ceil(policy.maxResponseBytes / 3) * 4 ||
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(text)) {
      fail('KintoneUpdateTargetLimit');
    }
    const bytes = Buffer.from(text, 'base64');
    if (bytes.byteLength > policy.maxResponseBytes || bytes.toString('base64') !== text) fail('KintoneUpdateTargetLimit');
    return bytes;
  };
  const logicalIdentity = (identity, valueWire) => cid({binding, identity, valueWire});
  const physicalIdentity = original => cid({binding, logicalCid: original.logicalCid,
    requestTag: original.requestTag, targetBodyCid: original.targetBodyCid, body: original.body});
  const finalized = request => {
    const original = get(request);
    if (!isCid(original.requestTag) || !original.native ||
        !native.UpdateExecutionMatches(original.proposal, original.preview, original.native) ||
        native.UpdateBody(original.native) !== original.body || physicalIdentity(original) !== original.requestCid) {
      fail('KintoneUpdateRequestNotFinalized');
    }
    return original;
  };
  const observed = observation => {
    if (observation?.statusCode !== 200 || !(observation.body instanceof Uint8Array) ||
        observation.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneTargetObservation');
    return observation.body;
  };
  return Object.freeze({mappingRef, mappingCid, binding,
    prepare({value, selector}) {
      if (typeof selector !== 'string') fail('InvalidKintoneUpdateSelector');
      const proposal = checked(native.PrepareUpdateProposal(mapping, selector, valueBytes(encode(value)),
        policy.maxInputBytes, writeLimits, requestLimits));
      if (native.UpdateProposalApp(proposal) !== appId) fail('ForeignKintoneUpdateApp');
      const identity = native.UpdateProposalIdentity(proposal), valueWire = native.UpdateProposalValueWire(proposal);
      const logicalCid = logicalIdentity(identity, valueWire), request = Object.freeze({logicalCid});
      originals.set(request, {proposal, identity, valueWire, value: JSON.parse(valueWire), logicalCid,
        readBody: checked(native.UpdateTargetReadBody(proposal, policy.maxFields,
          policy.maxRequestBytes, policy.maxNodes, policy.maxDepth))});
      return Object.freeze({request, requestCid: logicalCid});
    },
    formBody: JSON.stringify({app: appId}),
    recheckForm(observation) {return checked(native.UpdateMappingRecheckForm(mapping, observed(observation), formLimits));},
    targetReadBody(request) {return get(request).readBody;},
    projectTarget(request, observation) {
      const original = get(request), bytes = observed(observation);
      const preview = checked(native.PrepareUpdatePreview(original.proposal, bytes, pageLimits, valueLimits, beforeLimits));
      const identity = native.UpdatePreviewIdentity(preview), beforeWire = native.UpdatePreviewBeforeWire(preview),
        versionCid = native.UpdatePreviewVersionCid(preview);
      if (identity !== original.identity || !isCid(versionCid)) fail('ForeignKintoneUpdateTarget');
      if (original.preview === undefined) {
        original.preview = preview; original.beforeWire = beforeWire; original.versionCid = versionCid;
        original.targetBodyBase64 = Buffer.from(bytes).toString('base64');
        original.targetBodyCid = wireCid(bytes);
      } else if (beforeWire !== original.beforeWire || versionCid !== original.versionCid) {
        fail('KintoneUpdateTargetChanged');
      }
      return Object.freeze({identity, versionCid, before: JSON.parse(beforeWire)});
    },
    finalize({request, requestTag}) {
      const original = get(request);
      if (original.preview === undefined || original.requestTag !== undefined || !isCid(requestTag)) {
        fail('KintoneUpdateFinalizationUnavailable');
      }
      const built = checked(native.FinalizeUpdateRequest(original.proposal, original.preview, requestLimits));
      const body = native.UpdateBody(built);
      if (Buffer.byteLength(body) > policy.maxRequestBytes) fail('KintoneUpdateRequestLimit');
      const physical = {...original, native: built, body, requestTag};
      physical.requestCid = physicalIdentity(physical);
      const carrier = Object.freeze({logicalCid: original.logicalCid, requestCid: physical.requestCid});
      // The original logical carrier cannot issue a second finalization.
      original.requestTag = requestTag; originals.set(carrier, physical);
      return Object.freeze({request: carrier, requestCid: physical.requestCid});
    },
    requestFacts(request) {const value = get(request); return Object.freeze({value: value.value, target: value.identity});},
    requestCid(request) {const value = get(request); return value.requestCid ?? value.logicalCid;},
    capabilityRequestCid(request) {return get(request).logicalCid;},
    assertFinalized(request, requestTag) {
      if (finalized(request).requestTag !== requestTag) fail('KintoneUpdateRequestTagMismatch');
    },
    nativeRequest(request) {return finalized(request).native;},
    requestBody(request) {return finalized(request).body;},
    projectResponse(request, observation) {
      const original = finalized(request);
      if (!Number.isInteger(observation?.statusCode) || !(observation.body instanceof Uint8Array) ||
          observation.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneUpdateObservation');
      try {
        const response = checked(native.UpdateResponse(original.native, observation.statusCode,
          observation.body, beforeLimits));
        const projected = checked(native.UpdateEffectOutcome(original.native, response, beforeLimits));
        if (!native.UpdateEffectOutcomeMatchesRequest(projected, original.native) ||
            'sha256:' + native.UpdateEffectOutcomeResponseSha256(projected) !== wireCid(observation.body)) {
          fail('ForeignKintoneUpdateResponse');
        }
        return Object.freeze({kind: 'typed-success-response', projected,
          outcome: JSON.parse(native.UpdateEffectOutcomeWire(projected))});
      } catch (cause) {
        // A rejected or malformed provider response never supplies absence,
        // known nonacceptance, a retry or a successful Effect outcome.
        return Object.freeze({kind: 'unclassified-response', observation, cause});
      }
    },
    savedWire(request) {
      const original = finalized(request);
      const wire = encode({version: recoveryVersion, binding, identity: original.identity,
        valueWire: original.valueWire, targetBodyBase64: original.targetBodyBase64, body: original.body,
        targetBodyCid: original.targetBodyCid, requestTag: original.requestTag, logicalCid: original.logicalCid, requestCid: original.requestCid});
      if (Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('KintoneUpdateRecoveryLimit');
      return wire;
    },
    restore({wire, requestTag}) {
      if (typeof wire !== 'string' || wire.length > policy.maxRecoveryBytes ||
          Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('KintoneUpdateRecoveryLimit');
      const saved = own(JSON.parse(wire), recoveryKeys);
      const savedBinding = own(saved.binding, Object.keys(binding));
      if (saved.version !== recoveryVersion || Object.keys(binding).some(name => savedBinding[name] !== binding[name]) ||
          saved.requestTag !== requestTag || !isCid(requestTag) || typeof saved.identity !== 'string' ||
          !isCid(saved.logicalCid) || !isCid(saved.requestCid) || !isCid(saved.targetBodyCid) || typeof saved.body !== 'string' ||
          Buffer.byteLength(saved.body) > policy.maxRequestBytes) fail('ForeignKintoneUpdateRecovery');
      const inputBytes = valueBytes(saved.valueWire), observedBytes = targetBytes(saved.targetBodyBase64);
      // Check the closed primitive envelope before canonical recursion. Full
      // native value/target admission precedes Host's decoded value projection.
      if (encode(saved) !== wire || logicalIdentity(saved.identity, saved.valueWire) !== saved.logicalCid ||
          physicalIdentity(saved) !== saved.requestCid || wireCid(observedBytes) !== saved.targetBodyCid) fail('ForeignKintoneUpdateRecovery');
      const result = checked(native.RestoreUpdateExecution(mapping, saved.identity, inputBytes,
        observedBytes, saved.body, policy.maxInputBytes, pageLimits, valueLimits,
        writeLimits, requestLimits, beforeLimits));
      const proposal = runtimeField(result, 0), preview = runtimeField(result, 1), rebuilt = runtimeField(result, 2);
      if (native.UpdateProposalApp(proposal) !== appId || native.UpdateProposalValueWire(proposal) !== saved.valueWire ||
          !native.UpdateExecutionMatches(proposal, preview, rebuilt)) fail('ForeignKintoneUpdateRecovery');
      const value = JSON.parse(saved.valueWire);
      if (encode(value) !== saved.valueWire) fail('ForeignKintoneUpdateRecovery');
      const original = {...saved, value, proposal, preview, native: rebuilt,
        beforeWire: native.UpdatePreviewBeforeWire(preview), versionCid: native.UpdatePreviewVersionCid(preview),
        readBody: checked(native.UpdateTargetReadBody(proposal, policy.maxFields,
          policy.maxRequestBytes, policy.maxNodes, policy.maxDepth))};
      const request = Object.freeze({logicalCid: original.logicalCid, requestCid: original.requestCid});
      originals.set(request, original);
      return Object.freeze({request, requestCid: original.requestCid});
    },
  });
}
