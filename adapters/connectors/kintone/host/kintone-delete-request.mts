// Request DATA for the existing row Effect. Site and Effect owners retain
// physical reads, approval, dispatch, reconciliation and teardown.
import {createHash, type BinaryLike} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';

type Options = Readonly<{moon: unknown; mapping: unknown; declaration: unknown; origin: string; appId: string;
  connectorId: string; resource: string; siteBindingCid: string; generationCid: string;
  guestSpaceId?: string; limits: unknown}>;
type Observation = Readonly<{statusCode?: number; body?: unknown}>;
type PrepareInput = Readonly<{selector?: unknown; value?: unknown}>;
type FinalizeInput = Readonly<{request: unknown; requestTag: unknown}>;
type RestoreInput = Readonly<{wire: unknown; requestTag: unknown}>;
type MappingWire = Readonly<{mapping_ref?: unknown; mapping_contract_cid?: unknown; target_ref?: unknown; primary_identity?: unknown}>;
type Target = Readonly<{native: unknown; preview: unknown; body: string; versionCid: string; beforeWire: string}>;
type IdentityInput = Readonly<{logicalCid: unknown; requestTag?: unknown; targetBodyCid?: unknown; body?: unknown}>;
type Original = {identity: string; read: string; logicalCid: string; target?: Target; targetBodyCid?: string;
  targetBodyBase64?: string; requestTag?: string; body?: string; requestCid?: string; finalized?: boolean};
type Finalized = Original & {target: Target; body: string; requestCid: string; requestTag: string;
  targetBodyBase64: string; targetBodyCid: string};
type Bridge = Readonly<{
  DeleteMappingMatchesDeclaration(mapping: unknown, declaration: unknown): boolean;
  DeleteMappingMatchesRequest(mapping: unknown, request: unknown): boolean;
  DeleteMappingBody(mapping: unknown): string;
  DeleteMappingRecheckForm(mapping: unknown, body: Uint8Array, limits: unknown): unknown;
  DeleteTargetReadBody(mapping: unknown, identity: string, fields: number, limits: unknown): unknown;
  PrepareDeleteTargetRead(mapping: unknown, identity: string, bytes: Uint8Array, pages: unknown, values: unknown, limits: unknown): unknown;
  DeletePreviewIdentity(preview: unknown): string;
  DeletePreviewBefore(preview: unknown): string;
  DeletePreviewVersionCid(preview: unknown): string;
  DeleteApp(request: unknown): string;
  DeleteBody(request: unknown): string;
  DeleteObservedOutcome(mapping: unknown, request: unknown, original: unknown, status: number, bytes: Uint8Array,
    preview: unknown, memberIndex: number, rowIndex: number, limits: unknown): unknown;
  DeletePreviewOutcomeMatches(outcome: unknown, mapping: unknown, request: unknown, preview: unknown,
    memberIndex: number, rowIndex: number): boolean;
  DeletePreviewOutcomeWire(outcome: unknown): string;
  DeletePreviewOutcomeResponseSha256(outcome: unknown): string;
  DeletePreviewOutcomeRowCid(outcome: unknown): string;
  MutationLimits(rows: number, identity: number, comparison: number, bytes: number, nodes: number, depth: number): unknown;
  PageLimits(bytes: number, nodes: number, depth: number, rows: number, cols: number, cells: number, tableRows: number): unknown;
  ValueLimits(cols: number, names: number, nodes: number, depth: number, text: number): unknown;
  FormLimits(bytes: number, nodes: number, depth: number, fields: number, names: number): unknown;
}>;
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const encode = (value: unknown) => canonicalJson(value, {dataKeys: true});
const digest = (value: BinaryLike) => 'sha256:' + createHash('sha256').update(value).digest('hex');
const isCid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2147483647;
const codec = 'actql-installed-kintone-delete-request/0.1';
const policyKeys = ['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth', 'maxFields',
  'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes', 'maxValueDepth',
  'maxValueTextBytes', 'maxIdentityBytes', 'maxComparisonWork', 'maxRecoveryBytes'] as const;
const savedKeys = ['binding', 'identity', 'logicalCid', 'requestTag', 'targetBodyBase64',
  'targetBodyCid', 'body', 'requestCid'] as const;

function ownData<Name extends string>(value: unknown, names: readonly Name[], code: string): Record<Name, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || nodeTypes.isProxy(value)) fail(code);
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(fields).length !== names.length ||
      names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail(code);
  return Object.fromEntries(names.map(name => [name, fields[name].value])) as Record<Name, unknown>;
}

export function createKintoneDeleteRequestAdapter({moon, mapping, declaration, origin, appId, connectorId,
  resource, siteBindingCid, generationCid, guestSpaceId, limits}: Options) {
  if (typeof origin !== 'string' || !URL.canParse(origin) || new URL(origin).origin !== origin ||
      new URL(origin).protocol !== 'https:' ||
      typeof appId !== 'string' || !/^[1-9][0-9]*$/u.test(appId) || !isCid(siteBindingCid) || !isCid(generationCid) ||
      ![connectorId, resource].every(value => typeof value === 'string' && value.length > 0 && value.isWellFormed()) ||
      guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) fail('InvalidKintoneDeleteInstallation');
  const policy = ownData(limits, policyKeys, 'InvalidKintoneDeleteLimits') as Record<(typeof policyKeys)[number], number>;
  if (!Object.values(policy).every(positive)) fail('InvalidKintoneDeleteLimits');
  if (!moon || nodeTypes.isProxy(moon)) fail('KintoneDeleteRuntimeUnavailable');
  const native = Object.fromEntries([
    'DeleteMappingMatchesDeclaration', 'DeleteMappingMatchesRequest', 'DeleteMappingBody',
    'DeleteMappingRecheckForm', 'DeleteTargetReadBody', 'PrepareDeleteTargetRead',
    'DeletePreviewIdentity', 'DeletePreviewBefore', 'DeletePreviewVersionCid', 'DeleteApp', 'DeleteBody',
    'DeleteObservedOutcome', 'DeletePreviewOutcomeMatches', 'DeletePreviewOutcomeWire',
    'DeletePreviewOutcomeResponseSha256', 'DeletePreviewOutcomeRowCid',
    'MutationLimits', 'PageLimits', 'ValueLimits', 'FormLimits',
  ].map(name => {
    const method = Object.getOwnPropertyDescriptor(moon, 'clientProgramKintone' + name)?.value;
    if (typeof method !== 'function' || nodeTypes.isProxy(method) || nodeTypes.isAsyncFunction(method)) {
      fail('KintoneDeleteRuntimeUnavailable');
    }
    return [name, (...args: unknown[]) => Reflect.apply(method, moon, args)];
  })) as Bridge;
  if (!native.DeleteMappingMatchesDeclaration(mapping, declaration)) fail('ForeignKintoneDeleteMapping');
  const {mapping_ref: mappingRef, mapping_contract_cid: mappingCid, target_ref: targetRef,
    primary_identity: primaryIdentity} = JSON.parse(native.DeleteMappingBody(mapping)) as MappingWire;
  if (typeof mappingRef !== 'string' || !isCid(mappingCid) || primaryIdentity !== '$id' ||
      targetRef !== `connector://${connectorId}/${resource}`) fail('ForeignKintoneDeleteMapping');
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const binding = Object.freeze({codec, origin, appId, connectorId, resource, siteBindingCid, generationCid,
    mappingRef, mappingCid, method: 'POST', override: 'DELETE', path: prefix + 'records.json'});
  const mutationLimits = (maximum: number) => native.MutationLimits(1, policy.maxIdentityBytes, policy.maxComparisonWork,
    maximum, policy.maxNodes, policy.maxDepth);
  const requestLimits = mutationLimits(policy.maxRequestBytes), beforeLimits = mutationLimits(policy.maxResponseBytes);
  const pageLimits = native.PageLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth, 1,
    policy.maxColumns, policy.maxCells, policy.maxTableRows);
  const valueLimits = native.ValueLimits(policy.maxColumns, policy.maxNameUnits,
    policy.maxValueNodes, policy.maxValueDepth, policy.maxValueTextBytes);
  const formLimits = native.FormLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth,
    policy.maxFields, policy.maxNameUnits);
  const originals = new WeakMap<object, Original>();
  const get = (request: unknown) => {
    const original = originals.get(request as object);
    if (original === undefined) fail('ForeignKintoneDeleteRequest');
    return original;
  };
  const observed = (response: Observation) => {
    if (response?.statusCode !== 200 || !(response.body instanceof Uint8Array) ||
        response.body.byteLength > policy.maxResponseBytes) fail('InvalidKintoneDeleteObservation');
    return response.body;
  };
  const readBody = (identity: string) => checked(native.DeleteTargetReadBody(mapping, identity, policy.maxFields, requestLimits)) as string;
  const logicalIdentity = (identity: string) => digest(encode({binding, identity}));
  const physicalIdentity = ({logicalCid, requestTag, targetBodyCid, body}: IdentityInput) =>
    digest(encode({logicalCid, requestTag, targetBodyCid, body}));
  const project = (identity: string, bytes: Uint8Array): Target => {
    const result = checked(native.PrepareDeleteTargetRead(mapping, identity, bytes, pageLimits, valueLimits, beforeLimits));
    const preview = runtimeField(result, 0), request = runtimeField(result, 1);
    if (native.DeletePreviewIdentity(preview) !== identity || native.DeleteApp(request) !== appId ||
        !native.DeleteMappingMatchesRequest(mapping, request)) fail('ForeignKintoneDeleteTarget');
    const body = native.DeleteBody(request), versionCid = native.DeletePreviewVersionCid(preview);
    if (!isCid(versionCid) || Buffer.byteLength(body) > policy.maxRequestBytes) fail('KintoneDeleteRequestLimit');
    return {native: request, preview, body, versionCid, beforeWire: native.DeletePreviewBefore(preview)};
  };
  const final = (request: unknown): Finalized => {
    const original = get(request);
    if (original.requestCid === undefined) fail('KintoneDeleteRequestNotFinalized');
    return original as Finalized;
  };
  const issueFinal = (original: Finalized) => {
    const request = Object.freeze({logicalCid: original.logicalCid, requestCid: original.requestCid});
    originals.set(request, original);
    return Object.freeze({request, requestCid: original.requestCid});
  };
  return Object.freeze({mappingRef, mappingCid, binding, formBody: JSON.stringify({app: appId}),
    prepare({selector, value}: PrepareInput) {
      if (typeof selector !== 'string' || value !== undefined) fail('InvalidKintoneDeleteSelector');
      const read = readBody(selector), logicalCid = logicalIdentity(selector);
      const request = Object.freeze({logicalCid});
      originals.set(request, {identity: selector, read, logicalCid});
      return Object.freeze({request, requestCid: logicalCid});
    },
    recheckForm(response: Observation) {return checked(native.DeleteMappingRecheckForm(mapping, observed(response), formLimits));},
    targetReadBody(request: unknown) {return get(request).read;},
    projectTarget(request: unknown, response: Observation) {
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
    finalize({request, requestTag}: FinalizeInput) {
      const original = get(request);
      if (original.target === undefined || original.finalized || original.requestCid !== undefined || !isCid(requestTag)) {
        fail('KintoneDeleteFinalizationUnavailable');
      }
      const next: Original = {...original, requestTag, body: original.target.body};
      next.requestCid = physicalIdentity(next);
      original.finalized = true;
      return issueFinal(next as Finalized);
    },
    requestFacts(request: unknown) {return Object.freeze({target: get(request).identity});},
    requestCid(request: unknown) {const original = get(request); return original.requestCid ?? original.logicalCid;},
    capabilityRequestCid(request: unknown) {return get(request).logicalCid;},
    assertFinalized(request: unknown, requestTag: unknown) {
      if (final(request).requestTag !== requestTag) fail('KintoneDeleteRequestTagMismatch');
    },
    nativeRequest(request: unknown) {return final(request).target.native;},
    requestBody(request: unknown) {return final(request).body;},
    projectResponse({request, observation, preview, memberIndex, rowIndex}:
      Readonly<{request: unknown; observation: Observation; preview: unknown; memberIndex: number; rowIndex: number}>) {
      const original = final(request).target;
      if (!Number.isInteger(observation?.statusCode) || !(observation.body instanceof Uint8Array) ||
          observation.body.byteLength > policy.maxResponseBytes ||
          ![memberIndex, rowIndex].every(value => Number.isInteger(value) && value >= 0 && value <= 2147483647)) {
        fail('InvalidKintoneDeleteObservation');
      }
      try {
        const projected = checked(native.DeleteObservedOutcome(mapping, original.native, original.preview,
          observation.statusCode!, observation.body, preview, memberIndex, rowIndex, beforeLimits));
        const responseSha256 = native.DeletePreviewOutcomeResponseSha256(projected);
        if (!native.DeletePreviewOutcomeMatches(projected, mapping, original.native, preview, memberIndex, rowIndex) ||
            'sha256:' + responseSha256 !== digest(observation.body)) fail('ForeignKintoneDeleteObservation');
        return Object.freeze({kind: 'typed-success-response', projected, responseSha256,
          rowPreviewCid: native.DeletePreviewOutcomeRowCid(projected),
          outcome: JSON.parse(native.DeletePreviewOutcomeWire(projected))});
      } catch (cause) {
        return Object.freeze({kind: 'unclassified-response', observation, cause});
      }
    },
    savedWire(request: unknown) {
      const {identity, logicalCid, requestTag, targetBodyBase64, targetBodyCid, body, requestCid} = final(request);
      const wire = encode({binding, identity, logicalCid, requestTag, targetBodyBase64, targetBodyCid, body, requestCid});
      if (Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('KintoneDeleteRecoveryLimit');
      return wire;
    },
    restore({wire, requestTag}: RestoreInput) {
      const invalid = 'ForeignKintoneDeleteRecovery';
      if (typeof wire !== 'string' || wire.length > policy.maxRecoveryBytes ||
          Buffer.byteLength(wire) > policy.maxRecoveryBytes) fail('KintoneDeleteRecoveryLimit');
      const saved = ownData(JSON.parse(wire), savedKeys, invalid);
      const storedBinding = ownData(saved.binding, Object.keys(binding), invalid);
      if (Object.keys(binding).some(name => storedBinding[name] !== binding[name as keyof typeof binding]) ||
          !isCid(requestTag) || saved.requestTag !== requestTag ||
          !(['logicalCid', 'targetBodyCid', 'requestCid'] as const).every(name => isCid(saved[name])) ||
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
      return issueFinal({...saved, read, target} as Finalized);
    },
  });
}
