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

const fail = code => {throw Object.assign(new Error(code), {code});};
const encode = value => canonicalJson(value, {dataKeys: true});
const cid = value => 'sha256:' + createHash('sha256').update(encode(value)).digest('hex');
const segment = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => '%' + unit.charCodeAt(0).toString(16).toUpperCase());
const limitNames = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth', 'maxProperties',
  'maxNameUnits', 'maxRows', 'maxColumns', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
  'maxOutputBytes', 'maxOutputNodes', 'maxOutputDepth', 'maxRequestNodes', 'maxRequestDepth'];
const capture = (object, names) => {
  if (!object || nodeTypes.isProxy(object)) fail('InvalidHubSpotUpdateObservation');
  return Object.fromEntries(names.map(name => {
    const field = Object.getOwnPropertyDescriptor(object, name);
    if (!field || !Object.hasOwn(field, 'value')) fail('InvalidHubSpotUpdateObservation');
    return [name, field.value];
  }));
};

export class HubSpotUpdateObservationFailure extends Error {
  constructor(cause, observations) {
    super('HubSpotUpdateObservationFailed', {cause});
    this.code = cause?.code ?? 'HubSpotUpdateObservationFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

export function createHubSpotUpdateObservationAdapter({moon, portalId, installedFor, requests, limits, maxRows}) {
  if (!/^[1-9][0-9]{0,10}$/u.test(portalId ?? '') || typeof installedFor !== 'function' ||
      nodeTypes.isProxy(installedFor) || nodeTypes.isAsyncFunction(installedFor)) fail('InvalidHubSpotUpdateObservation');
  const native = capture(moon, ['hubspotRecheckAccountIdentityJson', 'hubspotProjectProperties',
    'hubspotRecheckPropertyCatalog', 'hubspotPropertyCatalogObjectType',
    'hubspotRecordReadBody', 'hubspotRecheckRecordReadRequest', 'hubspotProjectRecordRead', 'hubspotRecordReadWire']);
  if (Object.values(native).some(method => typeof method !== 'function' || nodeTypes.isProxy(method) ||
      nodeTypes.isAsyncFunction(method))) fail('InvalidHubSpotUpdateObservation');
  const policy = Object.freeze(capture(limits, limitNames));
  // One physical batch-read decodes one target. The checked member may own
  // several serial target rows, each with its own current/grant/child slots.
  const rowLimit = maxRows === undefined ? policy.maxRows : maxRows;
  if (!Object.values(policy).every(value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647) ||
      policy.maxRows > 100 || !Number.isSafeInteger(rowLimit) || rowLimit < 1 || rowLimit > 100) {
    fail('InvalidHubSpotUpdateObservation');
  }
  const request = Object.freeze(capture(requests, ['requestFacts', 'nativeTargetRead', 'objectType']));
  if (Object.values(request).some(method => typeof method !== 'function')) fail('InvalidHubSpotUpdateObservation');
  const currents = new WeakMap();
  const selected = member => {
    const original = installedFor(member);
    if (!original || !Object.isFrozen(original) || nodeTypes.isProxy(original)) fail('ForeignHubSpotUpdateMapping');
    const fields = capture(original, ['catalog', 'resource', 'mappingCid', 'mappingRef']);
    if (member?.kind !== 'update' || fields.resource !== member.resource ||
        fields.mappingCid !== member.mapping?.mappingCid || fields.mappingRef !== member.mapping?.mappingRef) {
      fail('ForeignHubSpotUpdateMapping');
    }
    const objectType = native.hubspotPropertyCatalogObjectType(fields.catalog);
    if (typeof objectType !== 'string' || !objectType || objectType === '.' || objectType === '..' ||
        objectType.length > policy.maxNameUnits) fail('ForeignHubSpotUpdateCatalog');
    return {...fields, objectType};
  };
  const scope = ({authorizationFor, readChild, verify, signal}, observations) => {
    if ([authorizationFor, readChild, verify].some(value => typeof value !== 'function')) {
      fail('HubSpotUpdateReadChildUnavailable');
    }
    const current = async slot => {signal?.throwIfAborted(); await verify(slot); signal?.throwIfAborted();};
    return async (slot, operation, method, path, body, rowIndex, project) => {
      await current(slot);
      const authorization = await authorizationFor(slot, rowIndex);
      await current(slot);
      const http = ownHttpRequest({method, path, query: [], headers: [['accept', 'application/json']], body});
      const input = {grant: authorization.grant, useId: authorization.useId,
        operations: new Map([[operation, Object.freeze({method: http.method, path: http.target,
          headers: http.headers, ...(http.body === undefined ? {} : {body: http.body})})]]),
        maxRequestBytes: policy.maxRequestBytes, maxResponseBytes: policy.maxResponseBytes,
        returnRejectedResponse: true, signal, currentBeforeSend: () => current(slot)};
      const result = await readChild(authorization, input, rowIndex, slot, response => {
        // The original child retains failed response custody. Snapshot and
        // decode before that child's projection-complete/shrink boundary.
        observations.push(response);
        if (!response.accepted || response.statusCode !== 200) fail('HubSpotUpdateReadRejected');
        return project(response.body);
      });
      await current(slot);
      return result;
    };
  };
  const account = (read, rowIndex) => read('account', HUBSPOT_ACCOUNT_DETAILS_OPERATION,
    'GET', '/account-info/v3/details', undefined, rowIndex,
    body => projectHubSpotAccountIdentity({moon: native, body, originalPortalId: portalId, limits: policy}));
  const catalog = (read, slot, original, rowIndex) => read(slot, HUBSPOT_PROPERTIES_READ_OPERATION,
    'GET', '/crm/v3/properties/' + segment(original.objectType), undefined, rowIndex, body => {
      const current = checked(native.hubspotProjectProperties(body, original.objectType,
        policy.maxResponseBytes, policy.maxNodes, policy.maxDepth, policy.maxProperties, policy.maxNameUnits));
      checked(native.hubspotRecheckPropertyCatalog(original.catalog, current, policy.maxProperties));
      return current;
    });
  return Object.freeze({
    async describe(options) {
      const original = selected(options.member), observations = [];
      try {
        const read = scope(options, observations), identity = await account(read, 0);
        const current = await catalog(read, 'schema', original, 0);
        const result = Object.freeze({identity, catalog: current});
        currents.set(result, original);
        return result;
      } catch (cause) {throw new HubSpotUpdateObservationFailure(cause, observations);}
    },
    async observeTargets(options) {
      const original = selected(options.member), prior = currents.get(options.current), observations = [];
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
      } catch (cause) {throw new HubSpotUpdateObservationFailure(cause, observations);}
    },
  });
}
