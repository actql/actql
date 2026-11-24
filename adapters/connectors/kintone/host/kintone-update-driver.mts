// Kintone protocol over the existing installed row Effect. The shared Host
// retains Preview, approval, claims, Unknown, physical funding and cleanup.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {admitCheckpointPhysicalRead} from '../../../host-common/checkpoint-approval.mjs';
import {isEffectPreparationRefusal, refusedEffectPreparation} from '../../../host-common/effect-preparation-result.mjs';
import {ownHttpRequest} from '../../../host-common/http-exchange.mjs';
import {invocationScopeFields, invokeScopedCredentialOperation, ownInvocationContext,
  rowUpdateTransportObservation} from '../../../host-common/owned-invocation-context.mjs';
import {assertInstalledRowUpdateClaim, installedRowUpdateRequestWires, packInstalledRowUpdateRecovery,
  restoreInstalledRowUpdateMembers, unpackInstalledRowUpdateRecovery} from '../../../host-common/installed-row-update-recovery.mjs';
import {createKintoneKeyUpsertRequestAdapter} from './kintone-key-upsert-request.mjs';
import {createKintoneUpdateRequestAdapter} from './kintone-update-request.mjs';
import {createKintoneDeleteRequestAdapter} from './kintone-delete-request.mjs';
import {KINTONE_FORM_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {KintoneDeleteFailure, KINTONE_RECORD_DELETE_OPERATION, KINTONE_TARGET_READ_OPERATION}
  from '../site/kintone-record-delete.mjs';
import {KINTONE_RECORD_UPDATE_OPERATION} from '../site/kintone-record-write.mjs';

import type {BinaryLike} from 'node:crypto';
import type {RowEffectKind, RowEffectMember} from '../../../../packages/local-node/connector-installation.js';
import type {KintoneResponse} from '../site/kintone-record-read.mjs';

type RequestOptions = Parameters<typeof createKintoneUpdateRequestAdapter>[0];
type Requests = ReturnType<typeof createKintoneUpdateRequestAdapter>;
type DeleteRequests = ReturnType<typeof createKintoneDeleteRequestAdapter>;
type UpsertRequests = ReturnType<typeof createKintoneKeyUpsertRequestAdapter>;
type Kind = 'update' | 'upsert' | 'delete';
type Target = Readonly<{state?: 'present' | 'absent'; before?: object; identity: string; versionCid?: string}>;
type Send = Current & Readonly<{request: object;
  authorization?: Readonly<{scope?: unknown}>; credential?: Readonly<{control?: unknown}>;
  callResource: unknown; signal?: AbortSignal}>;
type ProjectResponse = Readonly<{request: object; observation: Parameters<Requests['projectResponse']>[1]}>;
type ScopeFields = Readonly<{resourceOrigin?: unknown; connectorRegistration?: unknown; operation?: unknown}>;
type PhysicalObservation = Parameters<typeof rowUpdateTransportObservation>[0];
type PhysicalBinding = Parameters<typeof admitCheckpointPhysicalRead>[1];
type Member = RowEffectMember<RowEffectKind>;
type Grant = Readonly<{grant?: unknown; useId?: unknown}>;
type Site = Readonly<{
  issueReadGrant(facts: Readonly<{operation: string; decision: unknown; resource: string;
    runInvocationCid: string; dispatchRequestCid: string; maxUses: number}>): Grant;
  admitCheckpointEffectTargetRead(decision: unknown, binding: PhysicalBinding, operation: string): unknown;
}>;
type Authorize = (kind: 'acquisition', input: Readonly<{connection: string; resource: string; operation: 'read'}>,
  current: Readonly<{subjectCid: string; signal?: AbortSignal}>) =>
  Readonly<{action?: unknown}> | PromiseLike<Readonly<{action?: unknown}> | undefined> | undefined;
type DriverOptions = RequestOptions & Readonly<{kind?: Kind; site: unknown; authorization: unknown; connection: string;
  formResource: string; fields: readonly string[]; limits: Readonly<{maxRequestBytes: number; maxResponseBytes: number}>;
  maxMembers: number; maxRecoveryBytes: number}>;
type Slot = 'target' | 'schema' | 'schema-before' | 'schema-after';
type Control = <Args extends readonly unknown[], Result>(receiver: unknown, project: (...args: Args) => Result,
  args: Args) => Result;
type CurrentFrame = Readonly<{member: Member; runInvocationCid: string; dispatchRequestCid: string;
  controlConstruction?: Control; maxRows: number}>;
type Project<Value> = (response: KintoneResponse) => Value;
type ReadChildInput = Readonly<{grant?: unknown; useId: string; operations?: ReadonlyMap<string, unknown>;
  maxRequestBytes: number; maxResponseBytes: number; returnRejectedResponse: boolean; signal?: AbortSignal;
  currentBeforeSend(): unknown}>;
type Transport = Readonly<{signal?: AbortSignal;
  readChild<Value>(authorization: Grant, input: ReadChildInput, row: number, slot: Slot,
    project: Project<Value>, prepareOperations?: () => ReadonlyMap<string, unknown>): Value | PromiseLike<Value>;
  readTarget?<Value>(row: number, request: Parameters<typeof ownHttpRequest>[0], project: Project<Value>,
    currentBeforeSend: () => unknown): Value | PromiseLike<Value>}>;
type Scope = CurrentFrame & Transport & Readonly<{targetAuthorization?(row: number): Grant | PromiseLike<Grant | undefined> | undefined}>;
type Entry = Readonly<{request: object; requestCid: string}>;
type Current = Readonly<{member: Member; current: object}>;
type Entries = Current & Readonly<{entries: readonly Entry[]}>;
type Observe = Entries & Transport & Readonly<{authorizationForRow: NonNullable<Scope['targetAuthorization']>}>;
type Claims = Parameters<typeof assertInstalledRowUpdateClaim>[2];
type Changes = readonly (Parameters<typeof assertInstalledRowUpdateClaim>[3][number] &
  Readonly<{after?: Readonly<{state?: unknown; value?: unknown}>}> )[];
type Saved = NonNullable<Parameters<typeof unpackInstalledRowUpdateRecovery>[0]> & Readonly<{memberIndex: number}>;
type RecoveryContext = Readonly<{members: readonly Member[]; maxRows: number;
  recorded: Readonly<{members: readonly Readonly<{claims?: Claims}>[]}>;
  durable: Readonly<{connectorRecovery: readonly Saved[]}>; memberIndexes?: readonly number[];
  body?: Readonly<{effects?: readonly Readonly<{changes?: Changes}>[]}>;
  requestTags?: readonly (readonly string[])[]}>;
type Recovery = Readonly<{version?: unknown; binding?: unknown; member?: unknown; requests?: unknown}>;

export const KINTONE_UPDATE_TARGET_VERSION = 'actql-installed-kintone-effect-target-read/0.1';
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const encode = (value: unknown) => canonicalJson(value, {dataKeys: true});
const wireCid = (wire: BinaryLike) => 'sha256:' + createHash('sha256').update(wire).digest('hex');
const cid = (value: unknown) => wireCid(encode(value));
const isCid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2147483647;
// Match only this fixed original DATA envelope. Do not recursively serialize
// an unvalidated saved object merely to compare it with the bound original.
const sameRecord = (value: unknown, expected: Readonly<Record<string, unknown>>) => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === Object.keys(expected).length && Object.keys(expected).every(name =>
    Object.hasOwn(value, name) && (Array.isArray(expected[name])
      ? Array.isArray((value as Record<string, unknown>)[name]) && (value as Record<string, unknown[]>)[name].length === (expected[name] as unknown[]).length &&
        (expected[name] as unknown[]).every((item, index) => (value as Record<string, unknown[]>)[name][index] === item)
      : (value as Record<string, unknown>)[name] === expected[name]));
const memberFacts = (member: Member) => Object.freeze({effectId: member.effectId, memberIndex: member.memberIndex,
  kind: member.kind, resource: member.resource, mappingRef: (member as RowEffectMember<'update'>).mapping?.mappingRef,
  mappingCid: (member as RowEffectMember<'update'>).mapping?.mappingCid});
const capture = <Args extends readonly unknown[], Value>(receiver: unknown, name: string, invalid: string, asynchronous = false) => {
  if (!receiver || nodeTypes.isProxy(receiver)) fail(invalid);
  const field = Object.getOwnPropertyDescriptor(receiver, name), method = field?.value;
  if (!field || !Object.hasOwn(field, 'value') || typeof method !== 'function' || nodeTypes.isProxy(method) ||
      !asynchronous && nodeTypes.isAsyncFunction(method)) fail(invalid);
  return (...args: Args): Value => Reflect.apply(method, receiver, args);
};

function credentialReadOperations(request: Parameters<typeof ownHttpRequest>[0], operation: string, limits?: Parameters<typeof ownHttpRequest>[1]) {
  const http = ownHttpRequest(request, limits);
  return new Map([[operation, Object.freeze({method: http.method, path: http.target,
    headers: http.headers, body: http.body})]]);
}

export class KintoneUpdateObservationFailure extends Error {
  declare readonly code: unknown;
  declare readonly observations: readonly KintoneResponse[];

  constructor(cause: unknown, observations: readonly KintoneResponse[]) {
    super('KintoneUpdateObservationFailed', {cause});
    this.code = (cause as {code?: unknown} | null | undefined)?.code ?? 'KintoneUpdateObservationFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

export function kintoneUpdateDriver(options: DriverOptions) {
  const kind = options?.kind ?? 'update';
  if (kind !== 'update' && kind !== 'upsert') fail('InvalidKintoneUpdateDriver');
  return kintoneRecordMutationDriver(kind, options);
}

export function kintoneDeleteDriver(options: DriverOptions) {
  return kintoneRecordMutationDriver('delete', options);
}

function kintoneRecordMutationDriver(kind: Kind, {moon, site, authorization, connection, origin, appId, connectorId,
  resource, formResource, fields, mapping, declaration, siteBindingCid, generationCid, guestSpaceId,
  limits, maxMembers, maxRecoveryBytes}: DriverOptions) {
  const updating = kind === 'update', upsert = kind === 'upsert', deleting = kind === 'delete';
  const subject = deleting ? 'KintoneDelete' : 'KintoneUpdate';
  const invalidDriver = 'Invalid' + subject + 'Driver';
  const invalidRequests = 'Invalid' + subject + 'Requests';
  const invalidRecovery = 'Invalid' + subject + 'Recovery';
  const foreignRequest = 'Foreign' + subject + 'Request';
  const family = upsert ? 'key-upsert' : kind;
  const recoveryKind = `kintone-${family}-requests`;
  const recoveryVersion = `actql-installed-kintone-${family}-recovery/0.1`;
  const observationFailure = (cause: unknown, observations: readonly KintoneResponse[], phase: ConstructorParameters<typeof KintoneDeleteFailure>[2]) => !deleting
    ? new KintoneUpdateObservationFailure(cause, observations)
    : new KintoneDeleteFailure(cause as ConstructorParameters<typeof KintoneDeleteFailure>[0], observations, phase);
  if (typeof connection !== 'string' || !connection || typeof formResource !== 'string' || !formResource ||
      formResource === resource || !positive(maxMembers) ||
      !positive(maxRecoveryBytes) || !Array.isArray(fields) || nodeTypes.isProxy(fields) || fields.length < 1 ||
      fields.some((name, index) => typeof name !== 'string' || !name || name === '$id' || name === '$revision' ||
        index > 0 && name <= fields[index - 1])) fail(invalidDriver);
  const beforeFields = Object.freeze(fields.slice());
  const createRequests = upsert ? createKintoneKeyUpsertRequestAdapter
    : deleting ? createKintoneDeleteRequestAdapter : createKintoneUpdateRequestAdapter;
  const requests = createRequests({moon, mapping, declaration, origin, appId, connectorId,
    resource, siteBindingCid, generationCid, guestSpaceId, limits});
  const recheckForm = upsert ? (request: object) => (response: KintoneResponse) => (requests as UpsertRequests).recheckForm(request, response)
    : () => (requests as Requests | DeleteRequests).recheckForm;
  // These are immutable DATA bounds, not a borrowed mutable policy object.
  const maxRequestBytes = limits.maxRequestBytes, maxResponseBytes = limits.maxResponseBytes;
  const issueReadGrant = capture<Parameters<Site['issueReadGrant']>, ReturnType<Site['issueReadGrant']>>(site, 'issueReadGrant', invalidDriver),
    admitTarget = capture<Parameters<Site['admitCheckpointEffectTargetRead']>, unknown>(site, 'admitCheckpointEffectTargetRead', invalidDriver),
    authorize = capture<Parameters<Authorize>, ReturnType<Authorize>>(authorization, 'authorize', invalidDriver, true);
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const binding = Object.freeze({...requests.binding, formResource, fields: beforeFields});
  const currentFrames = new WeakMap<object, CurrentFrame>();
  let occurrence = 0;
  const selected = (member: Member) => {
    if (member?.kind !== kind || member.resource !== resource ||
        member.mapping?.mappingRef !== requests.mappingRef || member.mapping?.mappingCid !== requests.mappingCid) {
      fail('Foreign' + subject + 'Mapping');
    }
  };
  const frame = (member: Member, current: object) => {
    selected(member);
    const original = currentFrames.get(current);
    if (!original || original.member !== member) fail('Foreign' + subject + 'Current');
    return original;
  };
  const assertReadOriginal = ({member, runInvocationCid, dispatchRequestCid}: Pick<CurrentFrame, 'member' | 'runInvocationCid' | 'dispatchRequestCid'>) => {
    selected(member);
    if (!isCid(runInvocationCid) || !isCid(dispatchRequestCid)) fail(subject + 'ReadChildUnavailable');
  };
  const readScope = (options: Scope, observations: KintoneResponse[]) => {
    const {member, signal, runInvocationCid, dispatchRequestCid, controlConstruction, readChild, readTarget,
      targetAuthorization} = options;
    assertReadOriginal(options);
    if (typeof readChild !== 'function') fail(subject + 'ReadChildUnavailable');
    const decision = async (slot: Slot) => {
      signal?.throwIfAborted();
      const result = await authorize('acquisition', {connection, resource: formResource, operation: 'read'}, {
        subjectCid: cid({binding, member: memberFacts(member), runInvocationCid, dispatchRequestCid, slot}), signal});
      signal?.throwIfAborted();
      if (result?.action !== 'dispatch') fail('KintoneFormReadDenied');
      return result;
    };
    const verify = async (slot: Slot) => {
      signal?.throwIfAborted();
      // Target uses its own original row grant/current child. Form decisions
      // cannot authorize target data or stand in for those physical fences.
      if (slot !== 'target') await decision(slot);
      signal?.throwIfAborted();
    };
    return async <Value,>(slot: Slot, body: string, rowIndex: number, project: Project<Value>) => {
      await verify(slot);
      const request = {method: 'POST', path: prefix +
        (slot === 'target' ? 'records.json' : 'app/form/fields.json'), query: [],
        headers: [['accept', 'application/json'], ['x-http-method-override', 'GET']], body};
      const consume = (response: KintoneResponse) => {
        observations.push(response);
        if (!response.accepted || response.statusCode !== 200) fail(subject + 'ReadRejected');
        return project(response);
      };
      if (slot === 'target' && readTarget !== undefined) {
        const value = await readTarget(rowIndex, request, consume, () => verify(slot));
        await verify(slot);
        return value;
      }
      let authorization: Grant | undefined, useId: unknown;
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
      const prepareOperations = deleting && slot === 'target' ? () =>
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
  const restore = (context: RecoveryContext) => {
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
          changes, claims, maxRows, invalidRecovery) as Recovery | null;
        if (value === null || typeof value !== 'object' || Array.isArray(value) || value.version !== recoveryVersion ||
            Object.keys(value).sort().join(',') !== 'binding,member,requests,version' ||
            !sameRecord(value.binding, binding) || !sameRecord(value.member, memberFacts(member)) ||
            !Array.isArray(value.requests) || value.requests.length !== changes!.length ||
            value.requests.some(wire => typeof wire !== 'string' || Buffer.byteLength(wire) > maxRecoveryBytes) ||
            encode(value) !== saved!.wire) fail(invalidRecovery);
        return Object.freeze(value.requests.map((wire: unknown, row: number) => {
          const rebuilt = requests.restore({wire, requestTag: requestTags?.[index]?.[row]});
          const facts = requests.requestFacts(rebuilt.request);
          if (!deleting) {
            assertInstalledRowUpdateClaim(rebuilt as {requestCid: string}, facts as {value: unknown; target: unknown}, claims!, changes!, row, 'ForeignKintoneUpdateRecovery');
          } else if (rebuilt.requestCid !== claims![row]?.canonicalRequestCid ||
              changes![row]?.after?.state !== 'absent' || facts.target !== changes![row]?.target_row_identity) {
            fail('ForeignKintoneDeleteRecovery');
          }
          return rebuilt.request;
        }));
      });
  };

  const write = upsert ? {
    kind: kind as 'upsert',
    kinds: Object.freeze(['upsert']),
    writeOperation() {fail('KintoneKeyUpsertWriteBranchUnavailable');},
    async send({member, request, current, authorization, credential, callResource, signal}: Send) {
      frame(member, current);
      const scope = invocationScopeFields(authorization?.scope, credential?.control) as ScopeFields | undefined;
      const write = (requests as UpsertRequests).writeRequest(request);
      if (scope?.resourceOrigin !== origin || scope.connectorRegistration !== 'kintone' ||
          scope.operation !== write.operation) fail('ForeignKintoneKeyUpsertWriteScope');
      signal?.throwIfAborted();
      return rowUpdateTransportObservation(await invokeScopedCredentialOperation({
        ...write, authorization, credential, callResource, signal, maxRequestBytes, maxResponseBytes,
        headers: [['accept', 'application/json']], responseHeaders: [],
      }) as PhysicalObservation);
    },
    project({request, observation}: ProjectResponse) {return (requests as UpsertRequests).projectResponse(request, observation);},
  } : updating ? {
    kind: kind as 'update', operation: KINTONE_RECORD_UPDATE_OPERATION,
    prepareUpdateWrite(member: Member, request: object, current: object, resourceOrigin: unknown, registration: unknown, signal?: AbortSignal) {
      frame(member, current);
      if (resourceOrigin !== origin || registration !== 'kintone') fail('ForeignKintoneUpdateOrigin');
      const body = (requests as Requests | DeleteRequests).requestBody(request);
      signal?.throwIfAborted();
      return {method: 'PUT', path: prefix + 'records.json', query: [],
        headers: [['accept', 'application/json']], body, responseHeaders: []};
    },
    project({request, observation}: ProjectResponse) {return (requests as Requests).projectResponse(request, observation);},
  } : {
    kinds: Object.freeze([kind]),
    writeOperation(member: Member) {selected(member); return KINTONE_RECORD_DELETE_OPERATION;},
    async send({member, request, current, authorization, credential, callResource, signal}: Send) {
      frame(member, current);
      const context = ownInvocationContext({authorization, credential,
        limits: {maxRequestBytes, maxResponseBytes}, callbacks: {callResource}});
      const scope = invocationScopeFields(context.scope, context.credential.control) as ScopeFields;
      if (scope.resourceOrigin !== origin || scope.connectorRegistration !== 'kintone' ||
          scope.operation !== KINTONE_RECORD_DELETE_OPERATION) fail('ForeignKintoneDeleteOrigin');
      const body = (requests as Requests | DeleteRequests).requestBody(request);
      signal?.throwIfAborted();
      const response = await invokeScopedCredentialOperation({authorization: context.authorization,
        credential: context.credential, callResource: context.callbacks.callResource,
        operation: KINTONE_RECORD_DELETE_OPERATION, method: 'POST', path: prefix + 'records.json', body,
        headers: [['accept', 'application/json'], ['x-http-method-override', 'DELETE']],
        maxRequestBytes, maxResponseBytes, signal});
      return rowUpdateTransportObservation(response as PhysicalObservation);
    },
    project: (requests as DeleteRequests).projectResponse,
  };
  return Object.freeze({
    ...write, targetRead: Object.freeze({operation: KINTONE_TARGET_READ_OPERATION}),
    requestFacts: requests.requestFacts, requestCid: requests.requestCid, capabilityRequestCid: requests.capabilityRequestCid,
    finalizeRequest: requests.finalize, assertRequestFinalized: requests.assertFinalized,
    async describe(options: Scope) {
      const observations: KintoneResponse[] = [];
      try {
        if (!Number.isSafeInteger(options.maxRows) || options.maxRows < 0 || options.maxRows > 2147483647) {
          fail(invalidRequests);
        }
        // UPSERT validates Form under the exact row's target-read children,
        // after the logical request identifies the selected key.
        if (upsert) assertReadOriginal(options);
        else await readScope(options, observations)('schema', requests.formBody, 0, (requests as Requests | DeleteRequests).recheckForm);
        const current = Object.freeze({});
        currentFrames.set(current, {member: options.member, runInvocationCid: options.runInvocationCid,
          dispatchRequestCid: options.dispatchRequestCid, controlConstruction: options.controlConstruction, maxRows: options.maxRows});
        return current;
      } catch (cause) {throw observationFailure(cause, observations, 'form');}
    },
    prepareRequest(options: Current & Parameters<Requests['prepare']>[0]) {frame(options.member, options.current); return requests.prepare(options);},
    recheckRequests({member, entries, current}: Entries) {
      const original = frame(member, current);
      if (!Array.isArray(entries) || entries.length > original.maxRows) fail(invalidRequests);
      for (const entry of entries) {
        if (entry.requestCid !== requests.requestCid(entry.request)) fail(foreignRequest);
        if (!upsert) (requests as Requests | DeleteRequests).nativeRequest(entry.request);
      }
    },
    async observeTargets(options: Observe) {
      const original = frame(options.member, options.current), observations: KintoneResponse[] = [];
      if (!Array.isArray(options.entries) || options.entries.length > original.maxRows) fail(invalidRequests);
      try {
        const read = readScope({...original, readChild: options.readChild, readTarget: options.readTarget, signal: options.signal,
          targetAuthorization: options.authorizationForRow}, observations), rows = [];
        for (const [row, entry] of options.entries.entries()) {
          if (entry.requestCid !== requests.requestCid(entry.request)) fail(foreignRequest);
          const verifyForm = recheckForm(entry.request);
          await read('schema-before', requests.formBody, row, verifyForm);
          const observed: Target = await read('target', requests.targetReadBody(entry.request), row,
            response => requests.projectTarget(entry.request, response));
          // The existing checked-page projection includes the exact API id
          // beside every declared before field. Keep it in the Preview.
          if (observed.state !== 'absent' &&
              encode(Object.keys(observed.before!).sort()) !== encode(['$id', ...beforeFields])) fail('ForeignKintoneBeforeFields');
          await read('schema-after', requests.formBody, row, verifyForm);
          rows.push(observed);
        }
        return Object.freeze(rows);
      } catch (cause) {
        const failure = observationFailure(cause, observations, 'target');
        // Only a checked provider observation can identify a definitive
        // target refusal. Preserve its marker across the diagnostic wrapper.
        throw upsert && isEffectPreparationRefusal(cause) ? refusedEffectPreparation(failure) : failure;
      }
    },
    admitTargetReadApproval({member, decision}: Readonly<{member: Member; decision: unknown}>) {
      selected(member);
      const expected = {version: KINTONE_UPDATE_TARGET_VERSION, site_binding_cid: siteBindingCid,
        generation_cid: generationCid, effect_id: member.effectId, member_index: member.memberIndex,
        mapping_ref: requests.mappingRef, mapping_cid: requests.mappingCid, resource, effect_kind: kind,
        key: upsert ? (requests as UpsertRequests).key : '$id', fields: beforeFields};
      return admitCheckpointPhysicalRead(decision, expected, KINTONE_TARGET_READ_OPERATION,
        admitTarget, 'KintoneTargetReadApprovalNotAdmitted');
    },
    footprint({member}: Pick<Current, 'member'>) {
      selected(member);
      return Object.freeze({providerNamespace: 'kintone', resourceKind: 'app-record',
        boundaryCid: cid({origin, appId, guestSpaceId: guestSpaceId ?? null})});
    },
    recoveryEntry({member, current, entries}: Entries) {
      const original = frame(member, current);
      const wires = installedRowUpdateRequestWires(entries, original.maxRows, requests,
        invalidRecovery, foreignRequest);
      return packInstalledRowUpdateRecovery(recoveryKind, {version: recoveryVersion, binding,
        member: memberFacts(member), requests: wires}, maxRecoveryBytes, subject + 'RecoveryLimit');
    },
    recoverRequests: restore, recoverMemberRequests: restore,
  });
}
