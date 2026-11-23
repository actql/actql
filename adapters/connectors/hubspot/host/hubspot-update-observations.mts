// HubSpot's existing Native Account/Catalog/target decoders inside the SAME
// installed row Effect's independently authorized physical read slots. This
// adapter does not grant reads, approve a target, claim or send an update.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {ownHttpRequest} from '../../../host-common/http-exchange.mjs';
import {projectHubSpotAccountIdentity, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_OBJECT_BATCH_READ_OPERATION} from '../site/hubspot-target-read.mjs';
import type {HubSpotResourceInput, HubSpotResponse, HubSpotObservationCause} from '../site/hubspot-account-read.mjs';
import type {createHubSpotUpdateRequestAdapter, HubSpotUpdateMember, InstalledHubSpotUpdateMapping} from './hubspot-update-request.mjs';

type Native = Readonly<{
  hubspotRecheckAccountIdentityJson: Parameters<typeof projectHubSpotAccountIdentity>[0]['moon']['hubspotRecheckAccountIdentityJson'];
  hubspotProjectProperties(bytes: Uint8Array, objectType: string, maxBytes: number, maxNodes: number,
    maxDepth: number, maxProperties: number, maxNameUnits: number): unknown;
  hubspotRecheckPropertyCatalog(original: unknown, current: unknown, maxProperties: number): unknown;
  hubspotPropertyCatalogObjectType(catalog: unknown): string;
  hubspotRecordReadBody(request: unknown): string;
  hubspotRecheckRecordReadRequest(request: unknown, catalog: unknown, maxProperties: number): unknown;
  hubspotProjectRecordRead(request: unknown, bytes: Uint8Array, maxBytes: number, maxNodes: number,
    maxDepth: number, maxRows: number, maxColumns: number, maxCursorUnits: number, maxValueNodes: number,
    maxValueTextBytes: number, maxOutputBytes: number, maxOutputNodes: number, maxOutputDepth: number): unknown;
  hubspotRecordReadWire(observation: unknown): string;
  hubspotPreparePropertyResponseSource(bytes: Uint8Array, path: string, objectType: string, maxBytes: number,
    maxNodes: number, maxDepth: number, maxProperties: number, maxNameUnits: number): unknown;
  hubspotPropertyResponseSourceGeometryData(original: unknown): readonly number[];
  hubspotConsumePropertyResponseSource(original: unknown, path: string, bytes: Uint8Array): unknown;
  hubspotRetirePropertyResponseSource(original: unknown): void;
}>;
type RequestPorts = Pick<ReturnType<typeof createHubSpotUpdateRequestAdapter>, 'requestFacts' | 'nativeTargetRead' | 'objectType'>;
type Limits = Readonly<Record<(typeof limitNames)[number], number>>;
type Options = Readonly<{moon: unknown; portalId: string; installedFor(member: HubSpotUpdateMember): InstalledHubSpotUpdateMapping | undefined;
  requests: RequestPorts; limits: unknown; maxRows?: number}>;
type CatalogSlot = 'schema' | 'schema-before' | 'schema-after';
export type HubSpotReadSlot = 'account' | CatalogSlot | 'target';
type HttpMethod = 'GET' | 'POST';
type Request = Readonly<{method: HttpMethod; path: string; query: readonly (readonly string[])[];
  headers: readonly (readonly string[])[]; body?: string}>;
type Preparation = Readonly<{prepare(body: Uint8Array): readonly number[]; retire(): void}>;
type Project<Value> = ((bytes: Uint8Array) => Value) & Readonly<{responsePreparation?: Preparation}>;
type Consume<Value> = (response: HubSpotResponse) => Value;
type RequestInput = Pick<HubSpotResourceInput, 'grant' | 'useId' | 'operations' | 'maxRequestBytes' |
  'maxResponseBytes' | 'returnRejectedResponse' | 'signal' | 'currentBeforeSend'>;
export type HubSpotReadAuthorization = Readonly<{useId: string; grant?: unknown; originalAuthorization?: unknown}>;
type ReadScope = Readonly<{authorizationFor(slot: HubSpotReadSlot, row: number): HubSpotReadAuthorization | PromiseLike<HubSpotReadAuthorization>;
  readChild<Value>(authorization: unknown, input: RequestInput, row: number, slot: HubSpotReadSlot,
    consume: Consume<Value>): Value | PromiseLike<Value>;
  readTarget?<Value>(row: number, request: Request, consume: Consume<Value>, verify: () => Promise<void>): Value | PromiseLike<Value>;
  verify(slot: HubSpotReadSlot): unknown; signal?: AbortSignal}>;
type Read = <Value>(slot: HubSpotReadSlot, operation: string, method: HttpMethod, path: string, body: string | undefined,
  rowIndex: number, project: Project<Value>) => Promise<Value>;
type Selection = Pick<InstalledHubSpotUpdateMapping, 'catalog' | 'resource' | 'mappingCid' | 'mappingRef'> &
  Readonly<{objectType: string}>;
export type HubSpotUpdateCurrent = Readonly<{identity: ReturnType<typeof projectHubSpotAccountIdentity>; catalog: unknown}>;
type Describe = ReadScope & Readonly<{member: HubSpotUpdateMember}>;
type ObserveTargets = Describe & Readonly<{current: HubSpotUpdateCurrent; entries: readonly Readonly<{request: unknown}>[]}>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const encode = (value: unknown) => canonicalJson(value, {dataKeys: true});
const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(encode(value)).digest('hex');
const segment = (value: string) => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => '%' + unit.charCodeAt(0).toString(16).toUpperCase());
const limitNames = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxNameUnits', 'maxRows', 'maxColumns', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
  'maxOutputBytes', 'maxOutputNodes', 'maxOutputDepth', 'maxRequestNodes', 'maxRequestDepth'] as const;
const capture = <Key extends string,>(object: unknown, names: readonly Key[]) => {
  if (!object || nodeTypes.isProxy(object)) fail('InvalidHubSpotUpdateObservation');
  return Object.fromEntries(names.map(name => {
    const field = Object.getOwnPropertyDescriptor(object, name);
    if (!field || !Object.hasOwn(field, 'value')) fail('InvalidHubSpotUpdateObservation');
    return [name, field.value];
  })) as Record<Key, unknown>;
};

export class HubSpotUpdateObservationFailure extends Error {
  declare readonly code: unknown;
  declare readonly observations: readonly HubSpotResponse[];

  constructor(cause: HubSpotObservationCause, observations: readonly HubSpotResponse[]) {
    super('HubSpotUpdateObservationFailed', {cause});
    this.code = cause?.code ?? 'HubSpotUpdateObservationFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

export function createHubSpotUpdateObservationAdapter({moon, portalId, installedFor, requests, limits, maxRows}: Options) {
  if (!/^[1-9][0-9]{0,10}$/u.test(portalId ?? '') || typeof installedFor !== 'function' ||
      nodeTypes.isProxy(installedFor) || nodeTypes.isAsyncFunction(installedFor)) fail('InvalidHubSpotUpdateObservation');
  const native = capture(moon, ['hubspotRecheckAccountIdentityJson', 'hubspotProjectProperties',
    'hubspotRecheckPropertyCatalog', 'hubspotPropertyCatalogObjectType',
    'hubspotRecordReadBody', 'hubspotRecheckRecordReadRequest', 'hubspotProjectRecordRead', 'hubspotRecordReadWire',
    'hubspotPreparePropertyResponseSource', 'hubspotPropertyResponseSourceGeometryData',
    'hubspotConsumePropertyResponseSource', 'hubspotRetirePropertyResponseSource']) as Native;
  if (Object.values(native).some(method => typeof method !== 'function' || nodeTypes.isProxy(method) ||
      nodeTypes.isAsyncFunction(method))) fail('InvalidHubSpotUpdateObservation');
  const policy = Object.freeze(capture(limits, limitNames)) as Limits;
  // One physical batch-read decodes one target. The checked member may own
  // several serial target rows, each with its own current/grant/child slots.
  const rowLimit = maxRows === undefined ? policy.maxRows : maxRows;
  if (!Object.values(policy).every(value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647) ||
      policy.maxRows > 100 || !Number.isSafeInteger(rowLimit) || rowLimit < 1 || rowLimit > 100) {
    fail('InvalidHubSpotUpdateObservation');
  }
  const request = Object.freeze(capture(requests, ['requestFacts', 'nativeTargetRead', 'objectType'])) as RequestPorts;
  if (Object.values(request).some(method => typeof method !== 'function')) fail('InvalidHubSpotUpdateObservation');
  const currents = new WeakMap<HubSpotUpdateCurrent, Selection>();
  const selected = (member: HubSpotUpdateMember) => {
    const original = installedFor(member);
    if (!original || !Object.isFrozen(original) || nodeTypes.isProxy(original)) fail('ForeignHubSpotUpdateMapping');
    const fields = capture(original, ['catalog', 'resource', 'mappingCid', 'mappingRef']) as Omit<Selection, 'objectType'>;
    if (member?.kind !== 'update' || fields.resource !== member.resource ||
        fields.mappingCid !== member.mapping?.mappingCid || fields.mappingRef !== member.mapping?.mappingRef) {
      fail('ForeignHubSpotUpdateMapping');
    }
    const objectType = native.hubspotPropertyCatalogObjectType(fields.catalog);
    if (typeof objectType !== 'string' || !objectType || objectType === '.' || objectType === '..' ||
        objectType.length > policy.maxNameUnits) fail('ForeignHubSpotUpdateCatalog');
    return {...fields, objectType};
  };
  const scope = ({authorizationFor, readChild, readTarget, verify, signal}: ReadScope, observations: HubSpotResponse[]) => {
    if ([authorizationFor, readChild, verify].some(value => typeof value !== 'function')) {
      fail('HubSpotUpdateReadChildUnavailable');
    }
    const current = async (slot: HubSpotReadSlot) => {signal?.throwIfAborted(); await verify(slot); signal?.throwIfAborted();};
    return async <Value,>(slot: HubSpotReadSlot, operation: string, method: HttpMethod, path: string,
      body: string | undefined, rowIndex: number, project: Project<Value>) => {
      await current(slot);
      const consume = (response: HubSpotResponse) => {
        // The original child retains failed response custody. Snapshot and
        // decode before that child's projection-complete/shrink boundary.
        observations.push(response);
        if (!response.accepted || response.statusCode !== 200) fail('HubSpotUpdateReadRejected');
        return project(response.body);
      };
      if(project.responsePreparation!==undefined)Object.defineProperty(consume,'responsePreparation',
        {value:project.responsePreparation});
      const request = {method, path, query: [], headers: [['accept', 'application/json']], body};
      if (slot === 'target' && readTarget !== undefined) {
        const result = await readTarget(rowIndex, request, consume, () => current(slot));
        await current(slot);
        return result;
      }
      const selectedAuthorization = await authorizationFor(slot, rowIndex);
      await current(slot);
      if (!selectedAuthorization || nodeTypes.isProxy(selectedAuthorization)) fail('InvalidHubSpotUpdateAuthorization');
      const original = Object.getOwnPropertyDescriptor(selectedAuthorization, 'originalAuthorization');
      // The metadata caller keeps its same Site-issued authorization beside
      // the physical useId. Target rows retain their existing grant entrance.
      if (original !== undefined && (!Object.hasOwn(original, 'value') ||
          !original.value || nodeTypes.isProxy(original.value) || !Object.isFrozen(original.value))) {
        fail('InvalidHubSpotUpdateAuthorization');
      }
      const authorization = original === undefined ? selectedAuthorization : original.value;
      const http = ownHttpRequest(request);
      const input: RequestInput = {grant: authorization.grant, useId: selectedAuthorization.useId,
        operations: new Map([[operation, Object.freeze({method: http.method, path: http.target,
          headers: http.headers, ...(http.body === undefined ? {} : {body: http.body})})]]),
        maxRequestBytes: policy.maxRequestBytes, maxResponseBytes: policy.maxResponseBytes,
        returnRejectedResponse: true, signal, currentBeforeSend: () => current(slot)};
      const result = await readChild(authorization, input, rowIndex, slot, consume);
      await current(slot);
      return result;
    };
  };
  const account = (read: Read, rowIndex: number) => read('account', HUBSPOT_ACCOUNT_DETAILS_OPERATION,
    'GET', '/account-info/v3/details', undefined, rowIndex,
    body => projectHubSpotAccountIdentity({moon: native, body, originalPortalId: portalId, limits: policy}));
  const catalog = (read: Read, slot: CatalogSlot, original: Selection, rowIndex: number) => {
    const path='/crm/v3/properties/'+segment(original.objectType);
    // This original per-read projector retains the same provider cursor on a
    // refused grow. It is neither a shared Catalog cache nor a Resource owner.
    let prepared: unknown,retired=false;
    const project = (body: Uint8Array) => {
      if(retired)fail('HubSpotPropertyResponseRetired');
      const current=checked(prepared===undefined
        ? native.hubspotProjectProperties(body,original.objectType,
          policy.maxResponseBytes,policy.maxNodes,policy.maxDepth,policy.maxProperties,policy.maxNameUnits)
        : native.hubspotConsumePropertyResponseSource(prepared,path,body));
      checked(native.hubspotRecheckPropertyCatalog(original.catalog,current,policy.maxProperties));
      // This exact caller uses schema-after only for its full fresh check.
      // Return Unit so neither the Reader nor physical child retains Catalog.
      return slot === 'schema-after' ? undefined : current;
    };
    const responsePreparation=Object.freeze({
      prepare(body: Uint8Array){
        if(retired||prepared!==undefined)fail('HubSpotPropertyResponseAlreadyPrepared');
        // Keep a failed Result until accepted/status, preserving refusal order.
        prepared=native.hubspotPreparePropertyResponseSource(body,path,original.objectType,
          policy.maxResponseBytes,policy.maxNodes,policy.maxDepth,policy.maxProperties,policy.maxNameUnits);
        return Object.freeze([...native.hubspotPropertyResponseSourceGeometryData(prepared)]);
      },
      retire(){
        if(retired)return;
        if(prepared!==undefined)native.hubspotRetirePropertyResponseSource(prepared);
        prepared=undefined;retired=true;
      },
    });
    Object.defineProperty(project,'responsePreparation',{value:responsePreparation});
    return read(slot,HUBSPOT_PROPERTIES_READ_OPERATION,'GET',path,undefined,rowIndex,project);
  };
  return Object.freeze({
    async describe(options: Describe) {
      const original = selected(options.member), observations: HubSpotResponse[] = [];
      try {
        const read = scope(options, observations), identity = await account(read, 0);
        const current = await catalog(read, 'schema', original, 0);
        const result = Object.freeze({identity, catalog: current});
        currents.set(result, original);
        return result;
      } catch (cause) {throw new HubSpotUpdateObservationFailure(cause as HubSpotObservationCause, observations);}
    },
    async observeTargets(options: ObserveTargets) {
      const original = selected(options.member), prior = currents.get(options.current), observations: HubSpotResponse[] = [];
      if (!prior || prior.catalog !== original.catalog || prior.mappingCid !== original.mappingCid ||
          prior.mappingRef !== original.mappingRef || !Array.isArray(options.entries) ||
          options.entries.length > rowLimit) fail('ForeignHubSpotUpdateCurrent');
      try {
        const read = scope(options, observations), rows = [];
        for (const [rowIndex, entry] of options.entries.entries()) {
          await account(read, rowIndex);
          const fresh = await catalog(read, 'schema-before', original, rowIndex);
          const facts = request.requestFacts(entry.request);
          if (request.objectType(entry.request) !== original.objectType) fail('ForeignHubSpotUpdateTarget');
          const target = request.nativeTargetRead(entry.request);
          checked(native.hubspotRecheckRecordReadRequest(target, fresh, policy.maxProperties));
          checked(native.hubspotRecheckRecordReadRequest(target, options.current.catalog, policy.maxProperties));
          const body = native.hubspotRecordReadBody(target);
          if (Buffer.byteLength(body) > policy.maxRequestBytes) fail('HubSpotUpdateTargetRequestLimit');
          const observed = await read('target', HUBSPOT_OBJECT_BATCH_READ_OPERATION, 'POST',
            '/crm/v3/objects/' + segment(original.objectType) + '/batch/read', body, rowIndex, bytes => {
              const decoded = checked(native.hubspotProjectRecordRead(target, bytes,
                policy.maxResponseBytes, policy.maxNodes, policy.maxDepth, 1, policy.maxColumns,
                policy.maxCursorUnits, policy.maxValueNodes, policy.maxValueTextBytes,
                policy.maxOutputBytes, policy.maxOutputNodes, policy.maxOutputDepth));
              const wire = native.hubspotRecordReadWire(decoded), value = JSON.parse(wire);
              if (JSON.stringify(value) !== wire || !Array.isArray(value) || value.length !== 1 ||
                  value[0].id !== facts.target) fail('ForeignHubSpotUpdateTarget');
              return Object.freeze({identity: facts.target, before: Object.freeze(value[0].properties),
                versionCid: cid({portalId, objectType: original.objectType, mappingCid: original.mappingCid,
                  mappingRef: original.mappingRef, wire})});
            });
          await catalog(read, 'schema-after', original, rowIndex);
          rows.push(observed);
        }
        return Object.freeze(rows);
      } catch (cause) {throw new HubSpotUpdateObservationFailure(cause as HubSpotObservationCause, observations);}
    },
  });
}
