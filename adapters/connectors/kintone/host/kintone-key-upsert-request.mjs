// Native proposal and request DATA. The existing installed Effect owns the
// read decision, Preview, claim, physical write and Unknown recovery.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {freezeInput} from '../../../../packages/sdk/internal/data.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField, runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {KINTONE_RECORD_CREATE_OPERATION, KINTONE_RECORD_UPDATE_OPERATION} from '../site/kintone-record-write.mjs';

const fail = code => {throw Object.assign(new TypeError(code), {code});};
const encode = value => canonicalJson(value, {dataKeys: true});
const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const isCid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' && value.length > 0 && value.isWellFormed();
const within = (value, max) => text(value) && value.length <= max && Buffer.byteLength(value) <= max;
const recoveryVersion = 'actql-installed-kintone-key-upsert-request/0.1';
const limitNames = ['maxInputBytes', 'maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes',
  'maxValueDepth', 'maxValueTextBytes', 'maxIdentityBytes', 'maxComparisonWork', 'maxRecoveryBytes'];
const savedNames = ['version', 'binding', 'identity', 'valueWire', 'targetBodyBase64',
  'targetBodyCid', 'branch', 'body', 'requestTag', 'logicalCid', 'requestCid'];

function closed(value, names) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || nodeTypes.isProxy(value)) {
    fail('InvalidKintoneKeyUpsertMaterial');
  }
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== names.length ||
      names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidKintoneKeyUpsertMaterial');
  return Object.freeze(Object.fromEntries(names.map(name => [name, fields[name].value])));
}

function capture(moon, name) {
  const field = moon && !nodeTypes.isProxy(moon)
    ? Object.getOwnPropertyDescriptor(moon, 'clientProgramKintone' + name) : undefined;
  const method = field?.value;
  if (typeof method !== 'function' || nodeTypes.isProxy(method) || nodeTypes.isAsyncFunction(method)) {
    fail('KintoneKeyUpsertRuntimeUnavailable');
  }
  return (...args) => Reflect.apply(method, moon, args);
}

export function createKintoneKeyUpsertRequestAdapter({moon, mapping, declaration, origin, appId,
  connectorId, resource, siteBindingCid, generationCid, guestSpaceId, limits}) {
  if (!text(origin) || !URL.canParse(origin) || new URL(origin).protocol !== 'https:' || new URL(origin).origin !== origin ||
      !text(appId) || !/^[1-9][0-9]*$/u.test(appId) || !text(connectorId) || !text(resource) ||
      !isCid(siteBindingCid) || !isCid(generationCid) ||
      (guestSpaceId !== undefined && (!text(guestSpaceId) || !/^[1-9][0-9]*$/u.test(guestSpaceId)))) {
    fail('InvalidKintoneKeyUpsertInstallation');
  }
  const policy = closed(limits, limitNames);
  if (!Object.values(policy).every(value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) {
    fail('InvalidKintoneKeyUpsertLimits');
  }
  const native = Object.freeze(Object.fromEntries([
    'KeyUpsertMappingBody', 'PrepareKeyUpsertProposal', 'KeyUpsertProposalLookup',
    'KeyUpsertProposalValueWire', 'KeyUpsertProposalBefore', 'KeyUpsertBeforeIdentity',
    'KeyUpsertBeforeWire', 'KeyUpsertBeforeVersionCid', 'FinalizeKeyUpsertRequest',
    'KeyUpsertExecutionMatches', 'KeyUpsertPhysicalRequest', 'RestoreKeyUpsertExecution',
    'KeyUpsertResponse', 'KeyUpsertOutcome', 'KeyUpsertOutcomeWire',
    'KeyUpsertOutcomeUsesRequest', 'KeyUpsertOutcomeResponseSha256',
    'LookupLimits', 'LookupApp', 'LookupBody', 'LookupRecheckForm', 'LookupResponse',
    'MutationLimits', 'PageLimits', 'ValueLimits', 'WriteLimits', 'FormLimits',
  ].map(name => [name, capture(moon, name)])));
  const body = JSON.parse(checked(native.KeyUpsertMappingBody(mapping, declaration)));
  const {mapping_ref: mappingRef, mapping_contract_cid: mappingCid, primary_identity: key} = body;
  if (!text(mappingRef) || !isCid(mappingCid) || !text(key) ||
      body.target_ref !== 'connector://' + connectorId + '/' + resource) fail('ForeignKintoneKeyUpsertMapping');
  const prefix = guestSpaceId === undefined ? '/k/v1/' : '/k/guest/' + guestSpaceId + '/v1/';
  const binding = Object.freeze({connectorId, origin, appId, resource, siteBindingCid, generationCid,
    mappingRef, mappingCid, key, path: prefix + 'records.json', codec: recoveryVersion});
  const mutation = bytes => native.MutationLimits(1, policy.maxIdentityBytes, policy.maxComparisonWork,
    bytes, policy.maxNodes, policy.maxDepth);
  const requestLimits = mutation(policy.maxRequestBytes), beforeLimits = mutation(policy.maxResponseBytes);
  const lookupLimits = native.LookupLimits(policy.maxIdentityBytes, policy.maxColumns,
    policy.maxComparisonWork, policy.maxRequestBytes, policy.maxNodes, policy.maxDepth);
  const pages = native.PageLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth, 2,
    policy.maxColumns, policy.maxCells, policy.maxTableRows);
  const values = native.ValueLimits(policy.maxColumns, policy.maxNameUnits,
    policy.maxValueNodes, policy.maxValueDepth, policy.maxValueTextBytes);
  const write = native.WriteLimits(policy.maxFields, policy.maxNameUnits, policy.maxValueNodes,
    policy.maxValueDepth, policy.maxValueTextBytes, policy.maxRequestBytes);
  const forms = native.FormLimits(policy.maxResponseBytes, policy.maxNodes,
    policy.maxDepth, policy.maxFields, policy.maxNameUnits);
  const originals = new WeakMap();
  const get = request => {
    const original = originals.get(request);
    if (original === undefined) fail('ForeignKintoneKeyUpsertRequest');
    return original;
  };
  const logicalIdentity = (identity, valueWire) => digest(encode({binding, identity, valueWire}));
  const physicalIdentity = original => digest(encode({binding, logicalCid: original.logicalCid,
    requestTag: original.requestTag, targetBodyCid: original.targetBodyCid,
    branch: original.branch, body: original.body}));
  const publish = original => {
    const request = Object.freeze({logicalCid: original.logicalCid,
      ...(original.requestCid === undefined ? {} : {requestCid: original.requestCid})});
    originals.set(request, original);
    return Object.freeze({request, requestCid: original.requestCid ?? original.logicalCid});
  };
  const lookupOf = proposal => {
    const lookup = native.KeyUpsertProposalLookup(proposal);
    if (native.LookupApp(lookup) !== appId) fail('ForeignKintoneKeyUpsertApp');
    return lookup;
  };
  const responseBytes = observation => {
    if (observation?.statusCode !== 200 || !(observation.body instanceof Uint8Array) ||
        observation.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneKeyUpsertObservation');
    return observation.body;
  };
  const target = (before, identity) => {
    const beforeWire = runtimeUnboxedReferenceOption(native.KeyUpsertBeforeWire(before));
    const versionCid = runtimeUnboxedReferenceOption(native.KeyUpsertBeforeVersionCid(before));
    if (native.KeyUpsertBeforeIdentity(before) !== identity ||
        (beforeWire === undefined ? versionCid !== undefined : !text(beforeWire) || !isCid(versionCid))) {
      fail('ForeignKintoneKeyUpsertTarget');
    }
    return {beforeWire, versionCid};
  };
  const physical = (original, request) => {
    if (!native.KeyUpsertExecutionMatches(original.proposal, original.before, request)) {
      fail('ForeignKintoneKeyUpsertExecution');
    }
    const selected = checked(native.KeyUpsertPhysicalRequest(request));
    const branch = runtimeField(selected, 0), body = runtimeField(selected, 1);
    if (branch !== (original.versionCid === undefined ? 'create' : 'update') ||
        !within(body, policy.maxRequestBytes)) fail('ForeignKintoneKeyUpsertExecution');
    return {branch, body};
  };
  const finalized = request => {
    const original = get(request);
    if (original.native === undefined || !isCid(original.requestTag)) fail('KintoneKeyUpsertRequestNotFinalized');
    const selected = physical(original, original.native);
    if (selected.branch !== original.branch || selected.body !== original.body ||
        physicalIdentity(original) !== original.requestCid) fail('ForeignKintoneKeyUpsertExecution');
    return original;
  };
  return Object.freeze({mappingRef, mappingCid, key, binding,
    formBody: JSON.stringify({app: appId}),
    prepare({value, selector}) {
      const valueWire = encode(value);
      if (!within(selector, policy.maxIdentityBytes) || !within(valueWire, policy.maxInputBytes)) {
        fail('InvalidKintoneKeyUpsertInput');
      }
      const proposal = checked(native.PrepareKeyUpsertProposal(mapping, selector, Buffer.from(valueWire),
        policy.maxInputBytes, write, lookupLimits));
      if (native.KeyUpsertProposalValueWire(proposal) !== valueWire) fail('ForeignKintoneKeyUpsertValue');
      return publish({proposal, lookup: lookupOf(proposal), identity: selector, value: freezeInput(JSON.parse(valueWire)), valueWire,
        logicalCid: logicalIdentity(selector, valueWire)});
    },
    targetReadBody(request) {return native.LookupBody(get(request).lookup);},
    recheckForm(request, response) {return checked(native.LookupRecheckForm(get(request).lookup, responseBytes(response), forms));},
    projectTarget(request, observation) {
      const original = get(request), bytes = responseBytes(observation);
      const observed = checked(native.LookupResponse(original.lookup, 200, bytes, pages));
      const before = checked(native.KeyUpsertProposalBefore(original.proposal, observed, values, beforeLimits));
      const current = target(before, original.identity);
      if (original.before === undefined) {
        Object.assign(original, current, {before,
          targetBodyBase64: Buffer.from(bytes).toString('base64'), targetBodyCid: digest(bytes)});
      } else if (current.beforeWire !== original.beforeWire || current.versionCid !== original.versionCid) {
        fail('KintoneKeyUpsertTargetChanged');
      }
      return Object.freeze(current.versionCid === undefined ? {identity: original.identity, state: 'absent'}
        : {identity: original.identity, state: 'present', versionCid: current.versionCid, before: JSON.parse(current.beforeWire)});
    },
    finalize({request, requestTag}) {
      const original = get(request);
      if (original.before === undefined || original.requestTag !== undefined || !isCid(requestTag)) {
        fail('KintoneKeyUpsertFinalizationUnavailable');
      }
      const built = checked(native.FinalizeKeyUpsertRequest(original.proposal, original.before, write, requestLimits));
      const admitted = {...original, ...physical(original, built), requestTag, native: built};
      admitted.requestCid = physicalIdentity(admitted);
      original.requestTag = requestTag;
      return publish(admitted);
    },
    requestFacts(request) {const original = get(request); return Object.freeze({value: original.value, target: original.identity});},
    requestCid(request) {const original = get(request); return original.requestCid ?? original.logicalCid;},
    capabilityRequestCid(request) {return get(request).logicalCid;},
    assertFinalized(request, requestTag) {
      if (finalized(request).requestTag !== requestTag) fail('KintoneKeyUpsertRequestTagMismatch');
    },
    writeRequest(request) {
      const original = finalized(request), insert = original.branch === 'create';
      return Object.freeze({operation: insert ? KINTONE_RECORD_CREATE_OPERATION : KINTONE_RECORD_UPDATE_OPERATION,
        method: insert ? 'POST' : 'PUT', path: binding.path, body: original.body});
    },
    projectResponse(request, observation) {
      const original = finalized(request);
      if (!Number.isInteger(observation?.statusCode) || !(observation.body instanceof Uint8Array) ||
          observation.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneKeyUpsertObservation');
      try {
        const response = checked(native.KeyUpsertResponse(original.native, observation.statusCode,
          observation.body, beforeLimits));
        const projected = checked(native.KeyUpsertOutcome(original.native, response, beforeLimits));
        if (!native.KeyUpsertOutcomeUsesRequest(projected, original.native) ||
            'sha256:' + native.KeyUpsertOutcomeResponseSha256(projected) !== digest(observation.body)) {
          fail('ForeignKintoneKeyUpsertResponse');
        }
        return Object.freeze({kind: 'typed-success-response', projected,
          outcome: JSON.parse(native.KeyUpsertOutcomeWire(projected))});
      } catch (cause) {
        return Object.freeze({kind: 'unclassified-response', observation, cause});
      }
    },
    savedWire(request) {
      const original = finalized(request);
      const wire = encode({version: recoveryVersion, binding, identity: original.identity,
        valueWire: original.valueWire, targetBodyBase64: original.targetBodyBase64, targetBodyCid: original.targetBodyCid,
        branch: original.branch, body: original.body, requestTag: original.requestTag,
        logicalCid: original.logicalCid, requestCid: original.requestCid});
      if (!within(wire, policy.maxRecoveryBytes)) fail('KintoneKeyUpsertRecoveryLimit');
      return wire;
    },
    restore({wire, requestTag}) {
      if (!within(wire, policy.maxRecoveryBytes)) fail('KintoneKeyUpsertRecoveryLimit');
      const saved = closed(JSON.parse(wire), savedNames), savedBinding = closed(saved.binding, Object.keys(binding));
      if (saved.version !== recoveryVersion || Object.keys(binding).some(name => savedBinding[name] !== binding[name]) ||
          !isCid(requestTag) || saved.requestTag !== requestTag || !isCid(saved.logicalCid) ||
          !isCid(saved.requestCid) || !isCid(saved.targetBodyCid) || !within(saved.identity, policy.maxIdentityBytes) ||
          !within(saved.valueWire, policy.maxInputBytes) || !within(saved.body, policy.maxRequestBytes) ||
          (saved.branch !== 'create' && saved.branch !== 'update') ||
          !text(saved.targetBodyBase64) || saved.targetBodyBase64.length > 4 * Math.ceil(policy.maxResponseBytes / 3)) {
        fail('ForeignKintoneKeyUpsertRecovery');
      }
      const observed = Buffer.from(saved.targetBodyBase64, 'base64');
      if (observed.byteLength > policy.maxResponseBytes || observed.toString('base64') !== saved.targetBodyBase64 ||
          digest(observed) !== saved.targetBodyCid || encode(saved) !== wire ||
          logicalIdentity(saved.identity, saved.valueWire) !== saved.logicalCid || physicalIdentity(saved) !== saved.requestCid) {
        fail('ForeignKintoneKeyUpsertRecovery');
      }
      const restored = checked(native.RestoreKeyUpsertExecution(mapping, saved.identity,
        Buffer.from(saved.valueWire), observed, saved.branch, saved.body, policy.maxInputBytes,
        lookupLimits, pages, values, write, requestLimits, beforeLimits));
      const proposal = runtimeField(restored, 0), before = runtimeField(restored, 1), request = runtimeField(restored, 2);
      if (native.KeyUpsertProposalValueWire(proposal) !== saved.valueWire) fail('ForeignKintoneKeyUpsertRecovery');
      const original = {...saved, proposal, before, native: request, lookup: lookupOf(proposal),
        value: freezeInput(JSON.parse(saved.valueWire)), ...target(before, saved.identity)};
      const selected = physical(original, request);
      if (selected.branch !== saved.branch || selected.body !== saved.body) fail('ForeignKintoneKeyUpsertRecovery');
      return publish(original);
    },
  });
}
