import {checked} from '../../../host-common/runtime-result.mjs';
import {types as nodeTypes} from 'node:util';
import {KINTONE_FORM_READ_OPERATION} from './kintone-record-read.mjs';
import {KINTONE_RECORD_CREATE_OPERATION} from './kintone-record-write.mjs';
import {sendRawKintoneWrite} from './kintone-record-write.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const requiredPorts = ['clientProgramKintoneCreateMappingMatchesDeclaration',
  'clientProgramKintoneCreateMappingMatchesRequest', 'clientProgramKintoneCreateExecutionRequest',
  'clientProgramKintoneWriteLimits', 'clientProgramKintoneMutationLimits'];

function originalMapping(moon, mapping, declaration) {
  if (requiredPorts.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneCreateExecutionRuntimeUnavailable');
  }
  if (!mapping || !declaration ||
      !moon.clientProgramKintoneCreateMappingMatchesDeclaration(mapping, declaration)) {
    fail('ForeignKintoneCreateMapping');
  }
}

// Mapped values use the same original Form and Mapping. This prepares DATA,
// without provider records, defaults, IDs, insertion decisions or permissions.
export function prepareMappedKintoneCreate({moon, mapping, declaration, bytes, limits}) {
  originalMapping(moon, mapping, declaration);
  if (!(bytes instanceof Uint8Array) || !['maxRequestBytes', 'maxNodes', 'maxDepth',
    'maxFields', 'maxNameUnits', 'maxRows', 'maxIdentityBytes', 'maxComparisonWork']
    .every(name => positive(limits?.[name])) || bytes.byteLength > limits.maxRequestBytes) {
    fail('InvalidKintoneCreateValues');
  }
  const write = moon.clientProgramKintoneWriteLimits(limits.maxFields, limits.maxNameUnits,
    limits.maxNodes, limits.maxDepth, limits.maxRequestBytes, limits.maxRequestBytes);
  const request = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxRequestBytes,
    limits.maxNodes, limits.maxDepth);
  return checked(moon.clientProgramKintoneCreateExecutionRequest(mapping, bytes,
    limits.maxRequestBytes, write, request));
}

// This is a thin caller of the existing physical port, after the Effect Owner's
// original claim. It adds no retries, observations, settlement or cleanup Owner.
export async function sendMappedKintoneCreate({moon, mapping, declaration, request, ...options}) {
  originalMapping(moon, mapping, declaration);
  if (!moon.clientProgramKintoneCreateMappingMatchesRequest(mapping, request)) {
    fail('ForeignKintoneCreateRequest');
  }
  return sendRawKintoneWrite({...options, moon, kind: 'create', request});
}

// Pure request/response DATA for one independently authorized Form read. The
// standard Host supplies its fixed POST+GET-override endpoint and owns the
// physical child. No Credential, grant, read, write or cleanup is created here.
export function prepareMappedKintoneCreateFormCheck({moon, mapping, declaration, request, limits}) {
  originalMapping(moon, mapping, declaration);
  const app = moon.clientProgramKintoneCreateApp, count = moon.clientProgramKintoneCreateCount,
    matches = moon.clientProgramKintoneCreateMappingMatchesRequest,
    formLimits = moon.clientProgramKintoneFormLimits, recheck = moon.clientProgramKintoneCreateRecheckForm;
  if (![app,count,matches,formLimits,recheck].every(value => typeof value === 'function') ||
      !['maxRequestBytes','maxResponseBytes','maxNodes','maxDepth','maxFields','maxNameUnits']
        .every(name => positive(limits?.[name]))) fail('InvalidKintoneCreateFormCheck');
  if (Reflect.apply(count,moon,[request]) !== 1 || !Reflect.apply(matches,moon,[mapping,request])) {
    fail('ForeignKintoneCreateRequest');
  }
  const appId = Reflect.apply(app,moon,[request]);
  if (typeof appId !== 'string' || !/^[1-9][0-9]*$/u.test(appId) || appId.length > limits.maxRequestBytes - 10) {
    fail('KintoneWriteRequestLimit');
  }
  const maxResponseBytes = limits.maxResponseBytes;
  const bounded = Reflect.apply(formLimits,moon,[maxResponseBytes,limits.maxNodes,
    limits.maxDepth,limits.maxFields,limits.maxNameUnits]);
  const body = JSON.stringify({app:appId});
  return Object.freeze({body,
    project(observation) {
      if (!(observation?.body instanceof Uint8Array) || observation.body.byteLength > maxResponseBytes ||
          !Number.isInteger(observation.statusCode)) fail('InvalidKintoneCreateFormObservation');
      if (observation.statusCode !== 200) fail('KintoneWriteReadRejected');
      return checked(Reflect.apply(recheck,moon,[request,observation.body,bounded]));
    }});
}


// One actual typed CREATE acknowledgement, not bytes-as-success. The original
// Effect Owner still owns saved response/dispatch correlation, current grant,
// footprint and terminal Ledger admission. No response is retried here.
export function projectMappedKintoneCreateOutcome({moon, mapping, declaration,
  request, response, preview, memberIndex, rowIndex, limits}) {
  originalMapping(moon, mapping, declaration);
  const names = ['clientProgramKintoneCreatePreviewOutcome',
    'clientProgramKintoneCreatePreviewOutcomeWire', 'clientProgramKintoneCreatePreviewOutcomeRowCid',
    'clientProgramKintoneCreatePreviewOutcomeResponseSha256', 'clientProgramKintoneCreatePreviewOutcomeMatches'];
  if (names.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneCreateOutcomeRuntimeUnavailable');
  }
  if (!Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
      !Number.isSafeInteger(rowIndex) || rowIndex < 0 ||
      !['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth', 'maxFields',
        'maxNameUnits', 'maxRows', 'maxIdentityBytes', 'maxComparisonWork']
        .every(name => positive(limits?.[name]))) fail('InvalidKintoneCreateOutcome');
  const write = moon.clientProgramKintoneWriteLimits(limits.maxFields, limits.maxNameUnits,
    limits.maxNodes, limits.maxDepth, limits.maxRequestBytes, limits.maxRequestBytes);
  const bounds = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxResponseBytes,
    limits.maxNodes, limits.maxDepth);
  const projected = checked(moon.clientProgramKintoneCreatePreviewOutcome(mapping,
    request, response, preview, memberIndex, rowIndex, limits.maxRequestBytes, write, bounds));
  if (!moon.clientProgramKintoneCreatePreviewOutcomeMatches(projected,
    mapping, request, preview, memberIndex, rowIndex)) fail('ForeignKintoneCreateOutcome');
  return Object.freeze({kind: 'typed-success-response', projected,
    outcome: JSON.parse(moon.clientProgramKintoneCreatePreviewOutcomeWire(projected)),
    rowPreviewCid: moon.clientProgramKintoneCreatePreviewOutcomeRowCid(projected),
    responseSha256: moon.clientProgramKintoneCreatePreviewOutcomeResponseSha256(projected)});
}

// Provider DATA for the standard Row Effect classifier. The enclosing common
// owner already compares request facts with its exact mapped/approved row and
// binds this outcome to the original saved response and durable claim. This
// projection supplies no Preview, authority, physical call or terminal receipt.
export function projectMappedKintoneCreateResponseOutcome({moon, mapping, declaration,
  request, observation, limits}) {
  originalMapping(moon, mapping, declaration);
  const names = ['clientProgramKintoneCreateMappingMatchesRequest',
    'clientProgramKintoneCreateResponse', 'clientProgramKintoneCreateEffectOutcome',
    'clientProgramKintoneCreateEffectOutcomeWire',
    'clientProgramKintoneCreateEffectOutcomeResponseSha256',
    'clientProgramKintoneCreateEffectOutcomeMatchesRequest'];
  if (names.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneCreateOutcomeRuntimeUnavailable');
  }
  if (!moon.clientProgramKintoneCreateMappingMatchesRequest(mapping, request)) {
    fail('ForeignKintoneCreateRequest');
  }
  if (!(observation?.body instanceof Uint8Array) || !Number.isInteger(observation.statusCode) ||
      !['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows', 'maxIdentityBytes',
        'maxComparisonWork'].every(name => positive(limits?.[name])) ||
      observation.body.byteLength > limits.maxResponseBytes) fail('InvalidKintoneCreateOutcome');
  const bounds = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxResponseBytes,
    limits.maxNodes, limits.maxDepth);
  const response = checked(moon.clientProgramKintoneCreateResponse(request,
    observation.statusCode, observation.body, bounds));
  const projected = checked(moon.clientProgramKintoneCreateEffectOutcome(request, response, bounds));
  if (!moon.clientProgramKintoneCreateEffectOutcomeMatchesRequest(projected, request)) {
    fail('ForeignKintoneCreateOutcome');
  }
  return Object.freeze({kind: 'typed-success-response', projected,
    outcome: JSON.parse(moon.clientProgramKintoneCreateEffectOutcomeWire(projected)),
    responseSha256: moon.clientProgramKintoneCreateEffectOutcomeResponseSha256(projected)});
}

// Provider semantic declaration for the EXISTING standard Row Effect. It owns
// no send/recovery loop, Account/Site, claim, grant, parent or cleanup callback.
// Complete Host/constructor/failed-prefix funding remains the caller's duty.
export function createMappedKintoneCreateWrite({moon, mapping, declaration,
  resource, formResource, origin, guestSpaceId, boundaryCid, limits: supplied}) {
  const invalid = () => fail('InvalidKintoneCreateWrite');
  const data = (value, names) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) invalid();
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== names.length ||
        names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) invalid();
    return fields;
  };
  const names = ['maxInputBytes','maxRequestBytes','maxResponseBytes','maxNodes','maxDepth',
    'maxFields','maxNameUnits','maxRows','maxIdentityBytes','maxComparisonWork'];
  const fields = data(supplied,names), limits = Object.freeze(Object.fromEntries(
    names.map(name => [name,fields[name].value])));
  if (!names.every(name => positive(limits[name])) || limits.maxRows !== 1 ||
      ![resource,formResource].every(value => typeof value === 'string' && value.length > 0 &&
        value.length <= limits.maxIdentityBytes && value.isWellFormed()) || resource === formResource ||
      typeof origin !== 'string' || !URL.canParse(origin) || !origin.startsWith('https://') ||
      new URL(origin).origin !== origin || !/^sha256:[0-9a-f]{64}$/u.test(boundaryCid ?? '') ||
      (guestSpaceId !== undefined && (typeof guestSpaceId !== 'string' ||
        guestSpaceId.length > limits.maxIdentityBytes || !/^[1-9][0-9]*$/u.test(guestSpaceId)))) invalid();
  const declaredExports = [...requiredPorts,'clientProgramKintoneCreateMappingResource',
    'clientProgramKintonePrepareCreateExecutionProposal','clientProgramKintoneRestoreCreateExecutionProposal',
    'clientProgramKintoneCreateBody','clientProgramKintoneCreateApp','clientProgramKintoneCreateCount',
    'clientProgramKintoneFormLimits','clientProgramKintoneCreateRecheckForm',
    'clientProgramKintoneCreateResponse','clientProgramKintoneCreateEffectOutcome',
    'clientProgramKintoneCreateEffectOutcomeWire','clientProgramKintoneCreateEffectOutcomeResponseSha256',
    'clientProgramKintoneCreateEffectOutcomeMatchesRequest'];
  if (moon === null || typeof moon !== 'object' || nodeTypes.isProxy(moon)) invalid();
  const captured = Object.create(null);
  for (const name of declaredExports) {
    const field = Object.getOwnPropertyDescriptor(moon,name);
    if (!field || !Object.hasOwn(field,'value') || typeof field.value !== 'function') {
      fail('KintoneCreateExecutionRuntimeUnavailable');
    }
    const method = field.value;
    captured[name] = (...args) => Reflect.apply(method,moon,args);
  }
  Object.freeze(captured);
  originalMapping(captured,mapping,declaration);
  if (checked(captured.clientProgramKintoneCreateMappingResource(mapping)) !== resource) {
    fail('ForeignKintoneCreateMapping');
  }
  const writeLimits = captured.clientProgramKintoneWriteLimits(limits.maxFields,limits.maxNameUnits,
    limits.maxNodes,limits.maxDepth,limits.maxInputBytes,limits.maxRequestBytes);
  const requestLimits = captured.clientProgramKintoneMutationLimits(1,limits.maxIdentityBytes,
    limits.maxComparisonWork,limits.maxRequestBytes,limits.maxNodes,limits.maxDepth);
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const path = prefix+'records.json', originals = new WeakMap();
  const bytesOf = wire => {
    if (typeof wire !== 'string' || wire.length > limits.maxInputBytes ||
        Buffer.byteLength(wire) > limits.maxInputBytes) fail('KintoneCreateProposalLimit');
    return Buffer.from(wire,'utf8');
  };
  const retain = (request,value,native) => {
    const form = prepareMappedKintoneCreateFormCheck({moon:captured,mapping,declaration,request:native,limits});
    const owned = Object.freeze({value,native,form});
    originals.set(request,owned);return owned;
  };
  const selected = ({resource: selectedResource,request,value}) => {
    if (selectedResource !== resource && selectedResource !== formResource) fail('UndeclaredKintoneResource');
    const existing = originals.get(request);
    if (existing !== undefined) {
      if (existing.value !== value) fail('ForeignKintoneCreateRequest');
      return existing;
    }
    // Cold DATA consumes the SAME authenticated saved plain request. Exact
    // physical body comparison re-admits the native original without prepare,
    // re-encoding, a new tag/CID or provider I/O. Host current/custody still gate it.
    const fields = data(request,['origin','method','path','body','proposalWire']);
    if (fields.origin.value !== origin || fields.method.value !== 'POST' || fields.path.value !== path ||
        typeof fields.body.value !== 'string' || !Object.isFrozen(request)) fail('ForeignKintoneCreateRequest');
    const native = checked(captured.clientProgramKintoneRestoreCreateExecutionProposal(mapping,
      bytesOf(fields.proposalWire.value),fields.body.value,limits.maxInputBytes,writeLimits,requestLimits));
    return retain(request,value,native);
  };
  return Object.freeze({kind:'create',operation:KINTONE_RECORD_CREATE_OPERATION,
    resourceKind:resource,boundaryCid,
    http:Object.freeze({origin,method:'POST',path,maxRequestBytes:limits.maxRequestBytes,maxResponseBytes:limits.maxResponseBytes}),
    request({resource: selectedResource,value,proposalWire}) {
      if (selectedResource !== resource) fail('UndeclaredKintoneResource');
      const native = checked(captured.clientProgramKintonePrepareCreateExecutionProposal(mapping,
        bytesOf(proposalWire),limits.maxInputBytes,writeLimits,requestLimits));
      const request = Object.freeze({origin,method:'POST',path,
        body:captured.clientProgramKintoneCreateBody(native),proposalWire});
      retain(request,value,native);return request;
    },
    check:Object.freeze({resource:formResource,operation:KINTONE_FORM_READ_OPERATION,beforeSend:true,
      http:Object.freeze({origin,method:'POST',path:prefix+'app/form/fields.json',
        headers:Object.freeze([Object.freeze(['x-http-method-override','GET'])]),
        maxRequestBytes:limits.maxRequestBytes,maxResponseBytes:limits.maxResponseBytes}),
      body(context) { return selected(context).form.body; },
      project(context) { return selected(context).form.project(context.observation); }}),
    classify(context) {
      const original = selected(context);
      return projectMappedKintoneCreateResponseOutcome({moon:captured,mapping,declaration,
        request:original.native,observation:context.observation,limits});
    }});
}
