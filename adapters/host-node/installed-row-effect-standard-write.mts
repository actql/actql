import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {ownHttpRequest, ownRequestHeaders, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {invokeScopedCredentialOperation} from '../host-common/owned-invocation-context.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {localContractLimits} from './local-publication-limits.mjs';

type ProviderCallback = (...args: unknown[]) => unknown;
type ControlConstruction = (receiver: unknown, callback: ProviderCallback, args: readonly unknown[]) => unknown;
type InvocationContext = Readonly<{
  request: unknown;
  authorization?: {scope?: {resourceOrigin?: unknown}};
  credential?: unknown;
  callResource: unknown;
  signal?: AbortSignal;
}>;
type CheckContext = InvocationContext & Readonly<{controlConstruction?: ControlConstruction}>;
type ConfirmationContext = CheckContext & Readonly<{providerEvidence?: unknown}>;
type ConfirmationConstruction = Readonly<{
  resource: string; operation: string; maxRequestBytes: number; maxResponseBytes: number;
}>;
type CheckConstruction = ConfirmationConstruction & Readonly<{beforeSend: boolean}>;
type TransportObservation = Readonly<{
  accepted: unknown; useCid: unknown; statusCode: unknown; body: unknown; headers?: unknown;
}>;
type PhysicalRequest = ReturnType<typeof ownHttpRequest> & Readonly<{body: string}>;
type LogicalIdentity = Readonly<{logicalCid: string; requestTag: string}>;
type BoundRequest = Readonly<{request: object; requestCid: string}>;
type Finalization = {
  phase: 'unprepared' | 'preparing' | 'prepared' | 'failed';
  requestTag?: string;
  prepared?: BoundRequest;
  cause?: unknown;
};
type RequestMaterial = Readonly<{resource: string; value: unknown}>;
type RequestOriginal = RequestMaterial & (Readonly<{
  exact: PhysicalRequest; requestCid: string; logicalCid?: string; requestTag?: string; finalization?: never;
}> | Readonly<{
  exact?: never; logicalCid: string; requestTag?: never; finalization: Finalization;
}>);
type EffectMember = Readonly<{kind: string; resource: string}>;
type PrepareContext = Readonly<{member?: EffectMember; value: unknown; proposalWire?: unknown}>;
type ProjectContext = Readonly<{request: unknown; observation: unknown; headers?: unknown}>;
type RecoveryEntry = Readonly<{request: unknown; requestCid: unknown; value: unknown}>;
type RecoveryContext = Readonly<{
  durable?: {connectorRecovery?: readonly {memberIndex: number; kind: string; wire: unknown; observationCid: string}[]};
  members: readonly EffectMember[];
  body?: {effects?: readonly {changes?: readonly {after?: {value?: unknown}}[]}[]};
  requestTags?: readonly (readonly unknown[])[];
}>;

// Standard CREATE plumbing for the SAME Row Effect, not another lifecycle.
export function deriveInstalledRowWrite(write: unknown, connectorRegistration: unknown) {
  const fail: () => never = () => { throw Object.assign(new TypeError('InvalidInstalledRowWrite'),
    {code: 'InvalidInstalledRowWrite'}); };
  const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
  const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
  function data(value: unknown, key: PropertyKey, optional = false): unknown {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) fail();
    const field = Object.getOwnPropertyDescriptor(value, key);
    if (field === undefined && optional) return undefined;
    if (!field || !Object.hasOwn(field, 'value')) fail();
    return field.value;
  }

  // Decoded proposal values already belong to the enclosing Row Effect. Freeze
  // them in place before mapping so the association retains the exact input,
  // including nested cells, without another JSON roundtrip or value checker.
  function freezeInput<T>(value: T): T {
    if (value !== null && typeof value === 'object') {
      for (const child of Object.values(value)) freezeInput(child);
      Object.freeze(value);
    }
    return value;
  }

  if (data(write, 'kind') !== 'create' || !text(connectorRegistration)) fail();
  const operation = data(write, 'operation'), resourceKind = data(write, 'resourceKind');
  const boundaryCid = data(write, 'boundaryCid'), http = data(write, 'http');
  const origin = data(http, 'origin'), method = data(http, 'method') as string, path = data(http, 'path');
  const maxRequestBytes = data(http, 'maxRequestBytes') as number, maxResponseBytes = data(http, 'maxResponseBytes') as number;
  const map = data(write, 'request') as ProviderCallback, classify = data(write, 'classify') as ProviderCallback;
  if (!text(operation) || !text(resourceKind) || !cid(boundaryCid) ||
      typeof origin !== 'string' || !URL.canParse(origin) || new URL(origin).origin !== origin ||
      !origin.startsWith('https://') || !text(path) || !['POST', 'PUT', 'PATCH'].includes(method) ||
      ![maxRequestBytes, maxResponseBytes].every(value => Number.isSafeInteger(value) && value > 0) ||
      typeof map !== 'function' || typeof classify !== 'function' ||
      nodeTypes.isAsyncFunction(map) || nodeTypes.isAsyncFunction(classify)) fail();
  const headers = ownRequestHeaders(data(http, 'headers', true));
  const responseHeaders = ownResponseHeaderNames(data(http, 'responseHeaders', true));
  const requestDomain = 'actql-installed-row-write-request/0.1';
  const recoveryKind = 'standard_row_write';
  const finalization = data(write, 'finalization', true);
  let finalize: ProviderCallback | undefined, restoreOriginal: ProviderCallback | undefined, stampRecipe: unknown;
  if (finalization !== undefined) {
    finalize = data(finalization, 'finalize') as ProviderCallback;
    restoreOriginal = data(finalization, 'restore') as ProviderCallback;
    stampRecipe = data(finalization, 'recipe');
    if ([finalize, restoreOriginal].some(method => typeof method !== 'function' ||
        nodeTypes.isAsyncFunction(method)) || stampRecipe === null ||
        typeof stampRecipe !== 'object') fail();
    freezeRequestData(stampRecipe);
  }
  // This is one immutable metadata input, not a byte tariff or a Run bound.
  // The same selected recipe later counts its actual serialization roles.
  let metadataTextUnits = connectorRegistration.length + resourceKind.length + boundaryCid.length +
    operation.length + origin.length + method.length + path.length + requestDomain.length + recoveryKind.length;
  if (stampRecipe !== undefined) metadataTextUnits += canonicalJson(stampRecipe).length;
  for (const [name, value] of headers) metadataTextUnits += name.length + value.length;
  for (const name of responseHeaders) metadataTextUnits += name.length;
  const confirmation = data(write, 'confirmation', true);
  let confirmationOptions, constructionConfirmation: ConfirmationConstruction | undefined;
  if (confirmation !== undefined) {
    const resource = data(confirmation, 'resource'), readOperation = data(confirmation, 'operation');
    const readHttp = data(confirmation, 'http'), body = data(confirmation, 'body') as ProviderCallback, project = data(confirmation, 'project') as ProviderCallback;
    const readOrigin = data(readHttp, 'origin'), readMethod = data(readHttp, 'method') as string, readPath = data(readHttp, 'path');
    const requestBytes = data(readHttp, 'maxRequestBytes') as number, responseBytes = data(readHttp, 'maxResponseBytes') as number;
    if (!text(resource) || !text(readOperation) || readOrigin !== origin ||
        !['GET', 'POST', 'HEAD'].includes(readMethod) || !text(readPath) ||
        ![requestBytes, responseBytes].every(value => Number.isSafeInteger(value) && value > 0) ||
        [body, project].some(fn => typeof fn !== 'function' || nodeTypes.isAsyncFunction(fn))) fail();
    const readHeaders = ownRequestHeaders(data(readHttp, 'headers', true));
    const readResponseHeaders = ownResponseHeaderNames(data(readHttp, 'responseHeaders', true));
    const template = ownHttpRequest({method: readMethod, path: readPath,
      query: data(readHttp, 'query', true), headers: readHeaders});
    constructionConfirmation = Object.freeze({resource, operation: readOperation,
      maxRequestBytes: requestBytes, maxResponseBytes: responseBytes});
    metadataTextUnits += resource.length + readOperation.length + readOrigin.length + readMethod.length + template.target.length;
    for (const [name, value] of readHeaders) metadataTextUnits += name.length + value.length;
    for (const name of readResponseHeaders) metadataTextUnits += name.length;
    confirmationOptions = {confirmation: constructionConfirmation,
      async confirmResponse({request, providerEvidence, authorization, credential, callResource, signal, controlConstruction}: ConfirmationContext) {
        const {value} = physicalOriginal(request);
        if (authorization?.scope?.resourceOrigin !== readOrigin) fail();
        signal?.throwIfAborted();
        const context = Object.freeze({resource, value, request, providerEvidence});
        const preparedBody = controlConstruction === undefined ? Reflect.apply(body, confirmation, [context])
          : controlConstruction(confirmation, body, [context]);
        const absentBody = preparedBody === undefined && readMethod === 'GET';
        if (!absentBody && typeof preparedBody !== 'string') {await preparedBody; fail();}
        if (!absentBody && (preparedBody!.length > requestBytes || Buffer.byteLength(preparedBody!) > requestBytes)) fail();
        const observed = await invokeScopedCredentialOperation({authorization, credential, callResource,
          operation: readOperation, method: readMethod, path: template.target, headers: template.headers,
          ...(absentBody ? {} : {body: preparedBody}), responseHeaders: readResponseHeaders,
          maxRequestBytes: requestBytes, maxResponseBytes: responseBytes, signal}) as TransportObservation;
        signal?.throwIfAborted();
        const facts = Object.freeze({resource, value, request, providerEvidence,
          accepted: observed.accepted,
          observation: Object.freeze({useCid: observed.useCid, statusCode: observed.statusCode, body: observed.body}),
          ...(Object.hasOwn(observed, 'headers') ? {headers: observed.headers} : {})});
        const projected: unknown = controlConstruction === undefined ? Reflect.apply(project, confirmation, [facts])
          : controlConstruction(confirmation, project, [facts]);
        // An invalid async pure projector stays inside this same read child;
        // its eventual value is never accepted as a synchronous provider fact.
        if (nodeTypes.isPromise(projected) || (projected !== null && typeof projected === 'object' &&
            typeof (projected as {then?: unknown}).then === 'function')) {await projected; fail();}
        return projected;
      }};
  }
  const check = data(write, 'check', true);
  let checkOptions, constructionCheck: CheckConstruction | null | undefined = check === undefined ? undefined : null;
  if (check !== undefined) {
    const resource = data(check, 'resource'), operation = data(check, 'operation');
    const beforeSend = data(check, 'beforeSend', true);
    const checkHttp = data(check, 'http', true);
    const request = data(check, 'request', checkHttp !== undefined);
    if (!text(resource) || !text(operation) ||
        (beforeSend !== undefined && typeof beforeSend !== 'boolean')) fail();
    const description = Object.freeze({resource, operation, ...(beforeSend === true ? {beforeSend} : {})});
    if (checkHttp === undefined) {
      if (typeof request !== 'function') fail();
      checkOptions = {check: description, checkRequest: (context: CheckContext) => Reflect.apply(request, check, [context])};
    } else {
      const body = data(check, 'body') as ProviderCallback, project = data(check, 'project') as ProviderCallback;
      const checkOrigin = data(checkHttp, 'origin'), checkMethod = data(checkHttp, 'method') as string, checkPath = data(checkHttp, 'path');
      const requestBytes = data(checkHttp, 'maxRequestBytes') as number, responseBytes = data(checkHttp, 'maxResponseBytes') as number;
      if (request !== undefined || checkOrigin !== origin || !['GET','POST','HEAD'].includes(checkMethod) || !text(checkPath) ||
          ![requestBytes,responseBytes].every(value => Number.isSafeInteger(value) && value > 0) ||
          typeof body !== 'function' || typeof project !== 'function' ||
          nodeTypes.isAsyncFunction(body) || nodeTypes.isAsyncFunction(project)) fail();
      const readHeaders = ownRequestHeaders(data(checkHttp, 'headers', true));
      const readResponseHeaders = ownResponseHeaderNames(data(checkHttp, 'responseHeaders', true));
      const template = ownHttpRequest({method: checkMethod, path: checkPath,
        query: data(checkHttp, 'query', true), headers: readHeaders});
      constructionCheck = Object.freeze({resource, operation, beforeSend: beforeSend === true,
        maxRequestBytes: requestBytes, maxResponseBytes: responseBytes});
      metadataTextUnits += resource.length + operation.length + checkOrigin.length + checkMethod.length + template.target.length;
      for (const [name, value] of readHeaders) metadataTextUnits += name.length + value.length;
      for (const name of readResponseHeaders) metadataTextUnits += name.length;
      checkOptions = {check: description,
        async checkRequest({request, authorization, credential, callResource, signal, controlConstruction}: CheckContext) {
          const {value: mappedValue} = original(request);
          if (authorization?.scope?.resourceOrigin !== checkOrigin) fail();
          signal?.throwIfAborted();
          const context = Object.freeze({resource, value: mappedValue, request});
          const value = controlConstruction === undefined ? Reflect.apply(body, check, [context])
            : controlConstruction(check, body, [context]);
          // Existing metadata GET operations carry no entity body. Keep
          // that original wire distinction; an empty String adds HTTP framing.
          const absentBody = value === undefined && checkMethod === 'GET';
          if (!absentBody && typeof value !== 'string') {
            // Invalid async provider work stays in this SAME original child
            // until settlement. Rejection preserves its original cause.
            await value;
            fail();
          }
          if (!absentBody && (value!.length > requestBytes || Buffer.byteLength(value!) > requestBytes)) fail();
          const observed = await invokeScopedCredentialOperation({authorization, credential, callResource,
            operation, method: checkMethod, path: template.target, headers: template.headers,
            ...(absentBody ? {} : {body: value}),
            responseHeaders: readResponseHeaders, maxRequestBytes: requestBytes, maxResponseBytes: responseBytes, signal}) as TransportObservation;
          signal?.throwIfAborted();
          const projection = Object.freeze({resource, value: mappedValue, request,
            accepted: observed.accepted,
            observation: Object.freeze({useCid: observed.useCid, statusCode: observed.statusCode, body: observed.body}),
            ...(Object.hasOwn(observed, 'headers') ? {headers: observed.headers} : {})});
          // The HTTP child keeps its physical holdings. The synchronous native
          // projector uses the same Run's separately retained control frame;
          // an invalid async result stays joined by that original owner.
          const projected = controlConstruction === undefined ? Reflect.apply(project, check, [projection])
            : controlConstruction(check, project, [projection]);
          if (projected !== undefined) {await projected; fail();}
        }};
    }
  }
  const originals = new WeakMap<object, RequestOriginal>();
  const original = (request: unknown) => {
    const selected = originals.get(request as object);
    if (selected === undefined) fail();
    return selected;
  };
  // This standard path accepts plain JSON request DATA, not native opaque
  // provider originals. Existing contract bounds cap the saved capture bytes;
  // they do not issue capacity, permission or a physical retention receipt.
  function freezeRequestData(value: unknown, depth = 0, state = {nodes: 0, active: new Set<object>()}): unknown {
    if (++state.nodes > localContractLimits.maxNodes || depth > localContractLimits.maxDepth) fail();
    if (value === null || typeof value === 'boolean') return value;
    if (typeof value === 'string') {
      if (value.length > localContractLimits.maxWireBytes || Buffer.byteLength(value) > localContractLimits.maxWireBytes) fail();
      return value;
    }
    if (typeof value === 'number') {
      if (!Number.isFinite(value) || Object.is(value, -0)) fail();
      return value;
    }
    if (typeof value !== 'object' || nodeTypes.isProxy(value) || state.active.has(value) ||
        Object.getPrototypeOf(value) !== (Array.isArray(value) ? Array.prototype : Object.prototype)) fail();
    state.active.add(value);
    const keys = Reflect.ownKeys(value);
    if (Array.isArray(value) && (keys.length !== value.length + 1 ||
        keys.some((key, index) => key !== (index === value.length ? 'length' : String(index))))) fail();
    for (const key of keys) {
      if (Array.isArray(value) && key === 'length') continue;
      if (typeof key !== 'string' || key.length > localContractLimits.maxWireBytes) fail();
      const field = Object.getOwnPropertyDescriptor(value, key);
      if (!field || !Object.hasOwn(field, 'value') || !field.enumerable) fail();
      freezeRequestData(field.value, depth + 1, state);
    }
    state.active.delete(value);
    return Object.freeze(value);
  }
  function bindRequest(request: unknown, resource: string, value: unknown, expectedCid?: string, logical?: LogicalIdentity) {
    if (request === null || typeof request !== 'object' || nodeTypes.isProxy(request) ||
        data(request, 'then', true) !== undefined || originals.has(request)) fail();
    const requestOrigin = data(request, 'origin', true), requestMethod = data(request, 'method', true);
    if ((requestOrigin !== undefined && requestOrigin !== origin) ||
        (requestMethod !== undefined && requestMethod !== method) ||
        data(request, 'headers', true) !== undefined || data(request, 'path') !== path) fail();
    const body = data(request, 'body');
    if (typeof body !== 'string') fail();
    const exact = ownHttpRequest({method, path,
      query: data(request, 'query', true), body, headers}) as PhysicalRequest;
    if (Buffer.byteLength(exact.body) > maxRequestBytes) fail();
    const providerCid = data(request, 'requestCid', true);
    if (providerCid !== undefined && !cid(providerCid)) fail();
    // Existing typed providers keep their original request identity. Plain
    // standard HTTP mappings need no separate identity callback.
    const requestCid = providerCid ?? `sha256:${createHash('sha256').update(JSON.stringify([
      requestDomain, connectorRegistration,
      resourceKind, boundaryCid, operation, origin, method, exact.target,
      exact.headers, exact.body])).digest('hex')}`;
    if (expectedCid !== undefined && expectedCid !== requestCid) fail();
    freezeRequestData(request);
    originals.set(request, Object.freeze({resource, value, exact, requestCid,
      ...(logical === undefined ? {} : {logicalCid: logical.logicalCid,
        requestTag: logical.requestTag})}));
    return Object.freeze({request, requestCid});
  }
  function bindLogical(request: unknown, resource: string, value: unknown) {
    if (request === null || typeof request !== 'object' || originals.has(request) ||
        data(request, 'origin') !== origin || data(request, 'method') !== method ||
        data(request, 'path') !== path || data(request, 'body', true) !== undefined ||
        data(request, 'requestCid', true) !== undefined ||
        data(request, 'then', true) !== undefined) fail();
    freezeRequestData(request);
    // Existing request identity domain with a disjoint, complete logical
    // envelope. The stamp recipe is business binding, never a DispatchKey.
    const logicalCid = `sha256:${createHash('sha256').update(canonicalJson([
      requestDomain, {connectorRegistration, resourceKind, boundaryCid,
        operation, origin, method, path, headers, responseHeaders,
        resource, value, request, stampRecipe}])).digest('hex')}`;
    originals.set(request, Object.freeze({resource, value, logicalCid,
      finalization: {phase: 'unprepared' as const}}));
    return Object.freeze({request, requestCid: logicalCid});
  }
  function physicalOriginal(request: unknown, requestTag?: unknown) {
    const selected = original(request);
    if (selected.exact === undefined || (finalization !== undefined &&
        (!cid(selected.requestTag) ||
          (requestTag !== undefined && selected.requestTag !== requestTag)))) fail();
    return selected;
  }
  const recoveryBinding = (resource: string) => [connectorRegistration, resourceKind,
    boundaryCid, operation, origin, method, path, headers, responseHeaders,
    maxRequestBytes, maxResponseBytes, resource,
    ...(finalization === undefined ? [] : [stampRecipe])];
  const wireCid = (wire: string) => `sha256:${createHash('sha256').update(wire).digest('hex')}`;
  function restoreMembers({durable, members, body, requestTags}: RecoveryContext, indexes: readonly number[]) {
    if (!Array.isArray(durable?.connectorRecovery)) fail();
    return {requests: indexes.map(index => {
      const member = members[index];
      if (member?.kind !== 'create' || !text(member.resource)) fail();
      const saved = durable.connectorRecovery!.filter(item => item.memberIndex === index);
      if (saved.length !== 1 || saved[0].kind !== recoveryKind ||
          typeof saved[0].wire !== 'string' || Buffer.byteLength(saved[0].wire) > localContractLimits.maxWireBytes ||
          wireCid(saved[0].wire) !== saved[0].observationCid) fail();
      const envelope = JSON.parse(saved[0].wire);
      freezeRequestData(envelope);
      if (!Array.isArray(envelope) || envelope.length !== 2 ||
          JSON.stringify(envelope) !== saved[0].wire ||
          JSON.stringify(envelope[0]) !== JSON.stringify(recoveryBinding(member.resource)) ||
          !Array.isArray(envelope[1])) fail();
      if (finalization !== undefined &&
          envelope[1].length !== body?.effects?.[index]?.changes?.length) fail();
      return envelope[1].map((row, rowIndex) => {
        if (!Array.isArray(row) || row.length !== 3 || !cid(row[0]) ||
            row[1] === null || typeof row[1] !== 'object') fail();
        if (finalization === undefined) {
          return bindRequest(row[2], member.resource, row[1], row[0]).request;
        }
        // Rebuild logical DATA from the independently admitted Preview row,
        // never from the saved request's asserted logical fields. No physical
        // mutation encoder is available on this cold path.
        const value = freezeInput(body!.effects![index].changes![rowIndex].after?.value);
        const requestTag = requestTags?.[index]?.[rowIndex];
        if (!cid(requestTag) || canonicalJson(value) !== canonicalJson(row[1])) fail();
        const logical = bindLogical(Reflect.apply(map, write,
          [Object.freeze({resource: member.resource, value})]), member.resource, value);
        const restored = Reflect.apply(restoreOriginal!, finalization,
          [Object.freeze({request: row[2], logical: logical.request, requestTag,
            resource: member.resource, value})]);
        if (restored !== row[2]) fail();
        return bindRequest(restored, member.resource, value, row[0],
          {logicalCid: logical.requestCid, requestTag}).request;
      });
    })};
  }
  const driver = Object.freeze({
    kinds: Object.freeze(['create']),
    writeOperation: () => operation,
    footprint: () => ({providerNamespace: connectorRegistration, resourceKind, boundaryCid}),
    ...checkOptions,
    ...confirmationOptions,
    prepareRequest(context: PrepareContext) {
      if (context?.member?.kind !== 'create' || !text(context.member.resource)) fail();
      const resource = context.member.resource;
      const value = freezeInput(context.value);
      const proposalWire = data(context, 'proposalWire', true);
      if (proposalWire !== undefined && (typeof proposalWire !== 'string' ||
          proposalWire.length > localContractLimits.maxWireBytes ||
          Buffer.byteLength(proposalWire) > localContractLimits.maxWireBytes)) fail();
      const request = Reflect.apply(map, write, [Object.freeze({resource, value,
        ...(proposalWire === undefined ? {} : {proposalWire})})]);
      return finalization === undefined ? bindRequest(request, resource, value)
        : bindLogical(request, resource, value);
    },
    requestCid: (request: unknown) => physicalOriginal(request).requestCid,
    ...(finalization === undefined ? {} : {
      capabilityRequestCid(request: unknown) { return original(request).logicalCid; },
      assertRequestFinalized(request: unknown, requestTag: unknown) {
        if (!cid(requestTag)) fail();
        physicalOriginal(request, requestTag);
      },
      finalizeRequest({request, requestTag}: {request: unknown; requestTag: unknown}) {
        const selected = original(request), state = selected.finalization;
        if (state === undefined || !cid(requestTag)) fail();
        if (state.phase !== 'unprepared') {
          if (state.requestTag !== requestTag || state.phase === 'preparing') fail();
          if (state.phase === 'failed') throw state.cause;
          return state.prepared;
        }
        state.requestTag = requestTag;
        state.phase = 'preparing';
        try {
          const physical = Reflect.apply(finalize!, finalization,
            [Object.freeze({request, requestTag, resource: selected.resource, value: selected.value})]);
          // Return an invalid asynchronous original to the enclosing existing
          // constructor child, which retains it until settlement and refuses.
          // It can never publish a physical association or be prepared again.
          if (nodeTypes.isPromise(physical) || (physical !== null &&
              typeof physical === 'object' && typeof data(physical, 'then', true) === 'function')) {
            return physical;
          }
          state.prepared = bindRequest(physical, selected.resource, selected.value,
            undefined, {logicalCid: selected.logicalCid, requestTag});
          state.phase = 'prepared';
          return state.prepared;
        } catch (cause) { state.phase = 'failed'; state.cause = cause; throw cause; }
      },
    }),
    recoveryEntry({member, entries}: {member?: EffectMember; entries: readonly RecoveryEntry[]}) {
      if (member?.kind !== 'create' || !text(member.resource) || !Array.isArray(entries)) fail();
      const bindingValue = recoveryBinding(member.resource);
      const selectedRows = entries.map(entry => {
        const selected = physicalOriginal(entry.request);
        if (selected.resource !== member.resource || entry.requestCid !== selected.requestCid ||
            entry.value !== selected.value) fail();
        return [selected.requestCid, selected.value, entry.request];
      });
      freezeRequestData([bindingValue, selectedRows]);
      const binding = JSON.stringify(bindingValue);
      let bytes = Buffer.byteLength(binding) + 5;
      const rows = selectedRows.map(row => {
        const wire = JSON.stringify(row);
        bytes += Buffer.byteLength(wire) + 1;
        if (bytes > localContractLimits.maxWireBytes) fail();
        return wire;
      });
      const wire = `[${binding},[${rows.join(',')}]]`;
      return Object.freeze({kind: recoveryKind, observationCid: wireCid(wire), wire});
    },
    recoverRequests(context: RecoveryContext) {
      return restoreMembers(context, context.members.map((_, index) => index));
    },
    recoverMemberRequests(context: RecoveryContext & {memberIndexes: readonly number[]}) {
      return restoreMembers(context, context.memberIndexes);
    },
    requestFacts(request: unknown) { return {value: original(request).value}; },
    async send({request, authorization, credential, callResource, signal}: InvocationContext) {
      const {exact} = physicalOriginal(request);
      if (authorization?.scope?.resourceOrigin !== origin) fail();
      signal?.throwIfAborted();
      const response = await invokeScopedCredentialOperation({authorization, credential,
        callResource, operation, method, path: exact.target, headers: exact.headers,
        body: exact.body, responseHeaders, maxRequestBytes, maxResponseBytes, signal}) as TransportObservation;
      return Object.freeze({observation: Object.freeze({useCid: response.useCid,
        statusCode: response.statusCode, body: response.body}), headers: response.headers});
    },
    project(context: ProjectContext) {
      const {resource, value} = physicalOriginal(context.request);
      return Reflect.apply(classify, write, [Object.freeze({resource, value,
        request: context.request, observation: context.observation,
        ...(Object.hasOwn(context, 'headers') ? {headers: context.headers} : {})})]);
    },
  });
  return Object.freeze({driver, construction: Object.freeze({
    write: Object.freeze({operation, maxRequestBytes, maxResponseBytes}),
    check: constructionCheck, metadataTextUnits,
    ...(constructionConfirmation === undefined ? {} : {confirmation: constructionConfirmation}),
    ...(finalization === undefined ? {} : {finalization: stampRecipe})})});
}
