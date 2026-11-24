// Native proposal and request DATA. The existing installed Effect owns the
// read decision, Preview, claim, physical write and Unknown recovery.
import {createHash, type BinaryLike} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {freezeInput} from '../../../../packages/sdk/internal/private-source-preparation.mjs';
import {refusedEffectPreparation} from '../../../host-common/effect-preparation-result.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField, runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {KINTONE_RECORD_CREATE_OPERATION, KINTONE_RECORD_UPDATE_OPERATION} from '../site/kintone-record-write.mjs';

type Options = Readonly<{moon: unknown; mapping: unknown; declaration: unknown; origin: string; appId: string;
  connectorId: string; resource: string; siteBindingCid: string; generationCid: string;
  guestSpaceId?: string; limits: unknown}>;
type Observation = Readonly<{statusCode?: number; body?: unknown}>;
type PrepareInput = Readonly<{selector?: unknown; value?: unknown}>;
type FinalizeInput = Readonly<{request: unknown; requestTag: unknown}>;
type RestoreInput = Readonly<{wire: unknown; requestTag: unknown}>;
type Branch = 'create' | 'update';
type Original = {proposal: unknown; lookup: unknown; identity: string; value: unknown; valueWire: string; logicalCid: string;
  before?: unknown; beforeWire?: string; versionCid?: string; targetBodyBase64?: string; targetBodyCid?: string;
  requestTag?: string; native?: unknown; branch?: Branch; body?: string; requestCid?: string};
type IdentityInput = Readonly<{logicalCid: unknown; requestTag?: unknown; targetBodyCid?: unknown; branch?: unknown; body?: unknown}>;
type Finalized = Original & {branch: Branch; body: string; requestCid: string; requestTag: string};
type Bridge = Readonly<{
  KeyUpsertMappingMaterial(mapping: unknown, declaration: unknown): unknown;
  PrepareKeyUpsertProposal(mapping: unknown, selector: string, input: Uint8Array, maxBytes: number, write: unknown, lookup: unknown): unknown;
  KeyUpsertProposalLookup(proposal: unknown): unknown;
  KeyUpsertProposalValueWire(proposal: unknown): string;
  KeyUpsertProposalBefore(proposal: unknown, observed: unknown, values: unknown, limits: unknown): unknown;
  KeyUpsertBeforeIdentity(before: unknown): string;
  KeyUpsertBeforeWire(before: unknown): string | undefined;
  KeyUpsertBeforeVersionCid(before: unknown): string | undefined;
  FinalizeKeyUpsertRequest(proposal: unknown, before: unknown, write: unknown, limits: unknown): unknown;
  KeyUpsertExecutionMatches(proposal: unknown, before: unknown, request: unknown): boolean;
  KeyUpsertPhysicalRequest(request: unknown): unknown;
  RestoreKeyUpsertExecution(mapping: unknown, identity: string, input: Uint8Array, observed: Uint8Array,
    branch: Branch, body: string, maxBytes: number, lookup: unknown, pages: unknown, values: unknown,
    write: unknown, request: unknown, before: unknown): unknown;
  KeyUpsertResponse(request: unknown, status: number, body: Uint8Array, limits: unknown): unknown;
  KeyUpsertOutcome(request: unknown, response: unknown, limits: unknown): unknown;
  KeyUpsertOutcomeWire(outcome: unknown): string;
  KeyUpsertOutcomeUsesRequest(outcome: unknown, request: unknown): boolean;
  KeyUpsertOutcomeResponseSha256(outcome: unknown): string;
  LookupLimits(identity: number, cols: number, comparison: number, bytes: number, nodes: number, depth: number): unknown;
  LookupApp(lookup: unknown): string;
  LookupBody(lookup: unknown): string;
  LookupRecheckForm(lookup: unknown, observed: Uint8Array, forms: unknown): unknown;
  LookupResponse(lookup: unknown, status: number, observed: Uint8Array, pages: unknown): unknown;
  WriteLimits(fields: number, names: number, nodes: number, depth: number, text: number, bytes: number): unknown;
  MutationLimits(rows: number, identity: number, comparison: number, bytes: number, nodes: number, depth: number): unknown;
  PageLimits(bytes: number, nodes: number, depth: number, rows: number, cols: number, cells: number, tableRows: number): unknown;
  ValueLimits(cols: number, names: number, nodes: number, depth: number, text: number): unknown;
  FormLimits(bytes: number, nodes: number, depth: number, fields: number, names: number): unknown;
}>;
const fail: (code: string) => never = code => {throw Object.assign(new TypeError(code), {code});};
const encode = (value: unknown) => canonicalJson(value, {dataKeys: true});
const digest = (value: BinaryLike) => 'sha256:' + createHash('sha256').update(value).digest('hex');
const isCid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.isWellFormed();
const within = (value: unknown, max: number): value is string => text(value) && value.length <= max && Buffer.byteLength(value) <= max;
const recoveryVersion = 'actql-installed-kintone-key-upsert-request/0.1';
const limitNames = ['maxInputBytes', 'maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes',
  'maxValueDepth', 'maxValueTextBytes', 'maxIdentityBytes', 'maxComparisonWork', 'maxRecoveryBytes'] as const;
const savedNames = ['version', 'binding', 'identity', 'valueWire', 'targetBodyBase64',
  'targetBodyCid', 'branch', 'body', 'requestTag', 'logicalCid', 'requestCid'] as const;

function closed<Name extends string>(value: unknown, names: readonly Name[]): Readonly<Record<Name, unknown>> {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || nodeTypes.isProxy(value)) {
    fail('InvalidKintoneKeyUpsertMaterial');
  }
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== names.length ||
      names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidKintoneKeyUpsertMaterial');
  return Object.freeze(Object.fromEntries(names.map(name => [name, fields[name].value]))) as Readonly<Record<Name, unknown>>;
}

function capture(moon: unknown, name: string) {
  const field = moon && !nodeTypes.isProxy(moon)
    ? Object.getOwnPropertyDescriptor(moon, 'clientProgramKintone' + name) : undefined;
  const method = field?.value;
  if (typeof method !== 'function' || nodeTypes.isProxy(method) || nodeTypes.isAsyncFunction(method)) {
    fail('KintoneKeyUpsertRuntimeUnavailable');
  }
  return (...args: unknown[]): unknown => Reflect.apply(method, moon, args);
}

export function createKintoneKeyUpsertRequestAdapter({moon, mapping, declaration, origin, appId,
  connectorId, resource, siteBindingCid, generationCid, guestSpaceId, limits}: Options) {
  if (!text(origin) || !URL.canParse(origin) || new URL(origin).protocol !== 'https:' || new URL(origin).origin !== origin ||
      !text(appId) || !/^[1-9][0-9]*$/u.test(appId) || !text(connectorId) || !text(resource) ||
      !isCid(siteBindingCid) || !isCid(generationCid) ||
      (guestSpaceId !== undefined && (!text(guestSpaceId) || !/^[1-9][0-9]*$/u.test(guestSpaceId)))) {
    fail('InvalidKintoneKeyUpsertInstallation');
  }
  const policy = closed(limits, limitNames) as Readonly<Record<(typeof limitNames)[number], number>>;
  if (!Object.values(policy).every(value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) {
    fail('InvalidKintoneKeyUpsertLimits');
  }
  const native = Object.freeze(Object.fromEntries([
    'KeyUpsertMappingMaterial', 'PrepareKeyUpsertProposal', 'KeyUpsertProposalLookup',
    'KeyUpsertProposalValueWire', 'KeyUpsertProposalBefore', 'KeyUpsertBeforeIdentity',
    'KeyUpsertBeforeWire', 'KeyUpsertBeforeVersionCid', 'FinalizeKeyUpsertRequest',
    'KeyUpsertExecutionMatches', 'KeyUpsertPhysicalRequest', 'RestoreKeyUpsertExecution',
    'KeyUpsertResponse', 'KeyUpsertOutcome', 'KeyUpsertOutcomeWire',
    'KeyUpsertOutcomeUsesRequest', 'KeyUpsertOutcomeResponseSha256',
    'LookupLimits', 'LookupApp', 'LookupBody', 'LookupRecheckForm', 'LookupResponse',
    'MutationLimits', 'PageLimits', 'ValueLimits', 'WriteLimits', 'FormLimits',
  ].map(name => [name, capture(moon, name)]))) as Bridge;
  const originalMapping = checked(native.KeyUpsertMappingMaterial(mapping, declaration));
  const mappingRef = runtimeField(originalMapping, 1), mappingCid = runtimeField(originalMapping, 2),
    key = runtimeField(originalMapping, 3);
  if (!text(mappingRef) || !isCid(mappingCid) || !text(key) ||
      runtimeField(originalMapping, 4) !== connectorId || runtimeField(originalMapping, 5) !== resource) {
    fail('ForeignKintoneKeyUpsertMapping');
  }
  const prefix = guestSpaceId === undefined ? '/k/v1/' : '/k/guest/' + guestSpaceId + '/v1/';
  const binding = Object.freeze({connectorId, origin, appId, resource, siteBindingCid, generationCid,
    mappingRef, mappingCid, key, path: prefix + 'records.json', codec: recoveryVersion});
  const mutation = (bytes: number) => native.MutationLimits(1, policy.maxIdentityBytes, policy.maxComparisonWork,
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
  const originals = new WeakMap<object, Original>();
  const get = (request: unknown) => {
    const original = originals.get(request as object);
    if (original === undefined) fail('ForeignKintoneKeyUpsertRequest');
    return original;
  };
  const logicalIdentity = (identity: string, valueWire: string) => digest(encode({binding, identity, valueWire}));
  const physicalIdentity = (original: IdentityInput) => digest(encode({binding, logicalCid: original.logicalCid,
    requestTag: original.requestTag, targetBodyCid: original.targetBodyCid,
    branch: original.branch, body: original.body}));
  const publish = (original: Original) => {
    const request = Object.freeze({logicalCid: original.logicalCid,
      ...(original.requestCid === undefined ? {} : {requestCid: original.requestCid})});
    originals.set(request, original);
    return Object.freeze({request, requestCid: original.requestCid ?? original.logicalCid});
  };
  const lookupOf = (proposal: unknown) => {
    const lookup = native.KeyUpsertProposalLookup(proposal);
    if (native.LookupApp(lookup) !== appId) fail('ForeignKintoneKeyUpsertApp');
    return lookup;
  };
  const responseBytes = (observation: Observation) => {
    if (observation?.statusCode !== 200 || !(observation.body instanceof Uint8Array) ||
        observation.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneKeyUpsertObservation');
    return observation.body;
  };
  const target = (before: unknown, identity: string) => {
    const beforeWire = runtimeUnboxedReferenceOption(native.KeyUpsertBeforeWire(before));
    const versionCid = runtimeUnboxedReferenceOption(native.KeyUpsertBeforeVersionCid(before));
    if (native.KeyUpsertBeforeIdentity(before) !== identity ||
        (beforeWire === undefined ? versionCid !== undefined : !text(beforeWire) || !isCid(versionCid))) {
      fail('ForeignKintoneKeyUpsertTarget');
    }
    return {beforeWire, versionCid};
  };
  const physical = (original: Original, request: unknown): Readonly<{branch: Branch; body: string}> => {
    if (!native.KeyUpsertExecutionMatches(original.proposal, original.before, request)) {
      fail('ForeignKintoneKeyUpsertExecution');
    }
    const selected = checked(native.KeyUpsertPhysicalRequest(request));
    const branch = runtimeField(selected, 0), body = runtimeField(selected, 1);
    if (branch !== (original.versionCid === undefined ? 'create' : 'update') ||
        !within(body, policy.maxRequestBytes)) fail('ForeignKintoneKeyUpsertExecution');
    return {branch: branch as Branch, body};
  };
  const finalized = (request: unknown): Finalized => {
    const original = get(request);
    if (original.native === undefined || !isCid(original.requestTag)) fail('KintoneKeyUpsertRequestNotFinalized');
    const selected = physical(original, original.native);
    if (selected.branch !== original.branch || selected.body !== original.body ||
        physicalIdentity(original) !== original.requestCid) fail('ForeignKintoneKeyUpsertExecution');
    return original as Finalized;
  };
  return Object.freeze({mappingRef, mappingCid, key, binding,
    formBody: JSON.stringify({app: appId}),
    prepare({value, selector}: PrepareInput) {
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
    targetReadBody(request: unknown) {return native.LookupBody(get(request).lookup);},
    recheckForm(request: unknown, response: Observation) {return checked(native.LookupRecheckForm(get(request).lookup, responseBytes(response), forms));},
    projectTarget(request: unknown, observation: Observation) {
      const original = get(request), bytes = responseBytes(observation);
      const observed = checked(native.LookupResponse(original.lookup, 200, bytes, pages));
      const before = checked(native.KeyUpsertProposalBefore(original.proposal, observed, values, beforeLimits));
      const current = target(before, original.identity);
      if (original.before === undefined) {
        Object.assign(original, current, {before,
          targetBodyBase64: Buffer.from(bytes).toString('base64'), targetBodyCid: digest(bytes)});
      } else if (current.beforeWire !== original.beforeWire || current.versionCid !== original.versionCid) {
        throw refusedEffectPreparation(Object.assign(new TypeError('KintoneKeyUpsertTargetChanged'),
          {code: 'KintoneKeyUpsertTargetChanged'}));
      }
      return Object.freeze(current.versionCid === undefined ? {identity: original.identity, state: 'absent'}
        : {identity: original.identity, state: 'present', versionCid: current.versionCid, before: JSON.parse(current.beforeWire!)});
    },
    finalize({request, requestTag}: FinalizeInput) {
      const original = get(request);
      if (original.before === undefined || original.requestTag !== undefined || !isCid(requestTag)) {
        fail('KintoneKeyUpsertFinalizationUnavailable');
      }
      const built = checked(native.FinalizeKeyUpsertRequest(original.proposal, original.before, write, requestLimits));
      const admitted: Original = {...original, ...physical(original, built), requestTag, native: built};
      admitted.requestCid = physicalIdentity(admitted);
      original.requestTag = requestTag;
      return publish(admitted);
    },
    requestFacts(request: unknown) {const original = get(request); return Object.freeze({value: original.value, target: original.identity});},
    requestCid(request: unknown) {const original = get(request); return original.requestCid ?? original.logicalCid;},
    capabilityRequestCid(request: unknown) {return get(request).logicalCid;},
    assertFinalized(request: unknown, requestTag: unknown) {
      if (finalized(request).requestTag !== requestTag) fail('KintoneKeyUpsertRequestTagMismatch');
    },
    writeRequest(request: unknown) {
      const original = finalized(request), insert = original.branch === 'create';
      return Object.freeze({operation: insert ? KINTONE_RECORD_CREATE_OPERATION : KINTONE_RECORD_UPDATE_OPERATION,
        method: (insert ? 'POST' : 'PUT') as 'POST' | 'PUT', path: binding.path, body: original.body});
    },
    projectResponse(request: unknown, observation: Observation) {
      const original = finalized(request);
      if (!Number.isInteger(observation?.statusCode) || !(observation.body instanceof Uint8Array) ||
          observation.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneKeyUpsertObservation');
      try {
        const response = checked(native.KeyUpsertResponse(original.native, observation.statusCode!,
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
    savedWire(request: unknown) {
      const original = finalized(request);
      const wire = encode({version: recoveryVersion, binding, identity: original.identity,
        valueWire: original.valueWire, targetBodyBase64: original.targetBodyBase64, targetBodyCid: original.targetBodyCid,
        branch: original.branch, body: original.body, requestTag: original.requestTag,
        logicalCid: original.logicalCid, requestCid: original.requestCid});
      if (!within(wire, policy.maxRecoveryBytes)) fail('KintoneKeyUpsertRecoveryLimit');
      return wire;
    },
    restore({wire, requestTag}: RestoreInput) {
      if (!within(wire, policy.maxRecoveryBytes)) fail('KintoneKeyUpsertRecoveryLimit');
      const saved = closed(JSON.parse(wire), savedNames), savedBinding = closed(saved.binding, Object.keys(binding));
      if (saved.version !== recoveryVersion || Object.keys(binding).some(name => savedBinding[name] !== binding[name as keyof typeof binding]) ||
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
        value: freezeInput(JSON.parse(saved.valueWire)), ...target(before, saved.identity)} as Original;
      const selected = physical(original, request);
      if (selected.branch !== saved.branch || selected.body !== saved.body) fail('ForeignKintoneKeyUpsertRecovery');
      return publish(original);
    },
  });
}
