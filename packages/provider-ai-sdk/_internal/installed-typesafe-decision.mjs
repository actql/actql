import {createAdmittedTypeSafeDecisionPreflight} from './native-decision-preflight.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';
import {requireTypeSafeOriginalTransportLimits} from './typesafe-decision.mjs';

const issue = code => {throw Object.assign(new TypeError(code), {code});};
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' && value.length > 0;
const frozen = value => value !== null && typeof value === 'object' && Object.isFrozen(value);
// Physical Host selection only. All semantic projection/Task/profile/native
// response checks stay with the existing Common Owner, not this assembler.
function snapshot(value, keys, code) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) issue(code);
  const names = Reflect.ownKeys(value), expected = keys.split(',');
  if (names.length !== expected.length || names.some(name => typeof name !== 'string') ||
      names.slice().sort().some((name, index) => name !== expected[index])) issue(code);
  return Object.freeze(Object.fromEntries(names.map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) issue(code);
    return [name, descriptor.value];
  })));
}

// Private Host registration consumer, not an exported native installation,
// numerical supplier, approval or capability. Missing originals remain refused.
export function createInstalledTypeSafeDecisionRegistration(config) {
  config = snapshot(config,
    'apiKey,baseURL,bindingOriginals,fetch,modelId,modelSelector,observeAt,observeEgress,originalReadInstallation,outputSchemaCid,projectionLimits,promptCid,promptPayloadWire,providerId,quantityCapacity,rawCaptureSelection,requestLimits,responseLimits,taskCid',
    'InvalidInstalledTypeSafeDecisionConfiguration');
  const {providerId, modelSelector, modelId, baseURL, apiKey, taskCid, promptCid,
    outputSchemaCid, promptPayloadWire, fetch, observeAt, observeEgress} = config;
  if (![providerId, modelSelector, modelId, baseURL, apiKey].every(text) ||
      ![taskCid, promptCid, outputSchemaCid].every(cid) || typeof promptPayloadWire !== 'string' ||
      ![fetch, observeAt, observeEgress].every(value => typeof value === 'function')) {
    issue('InvalidInstalledTypeSafeDecisionConfiguration');
  }
  let endpoint;
  try {endpoint = new URL(`${baseURL}/systemone`);} catch {issue('InvalidInstalledTypeSafeDecisionEndpoint');}
  if (baseURL.endsWith('/') || endpoint.href !== `${baseURL}/systemone` ||
      !['https:', 'http:'].includes(endpoint.protocol) || endpoint.username || endpoint.password ||
      endpoint.search || endpoint.hash) issue('InvalidInstalledTypeSafeDecisionEndpoint');
  const projectionLimits = snapshot(config.projectionLimits,
    'maxBytes,maxDepth,maxFrames,maxNodes,maxWork', 'InvalidTypeSafeDecisionProjection');
  const requestLimits = snapshot(config.requestLimits,
    'maxBytes,maxHeaderBytes,maxHeaders', 'InvalidTypeSafeDecisionRequestLimits');
  const int = (value, minimum) => Number.isSafeInteger(value) && value >= minimum && value <= 2147483647;
  if (Object.entries(projectionLimits).some(([key, value]) => !int(value, key === 'maxWork' ? 0 : 1)) ||
      Object.values(requestLimits).some(value => !int(value, 1)) || requestLimits.maxHeaders > 64) {
    issue('InvalidTypeSafeDecisionProjection');
  }
  const responseLimits = fixedInferResponseLimits(config.responseLimits);
  const original = config.originalReadInstallation, raw = config.rawCaptureSelection;
  if (!frozen(original) || !frozen(original.bootstrap) || !frozen(original.nodeInstallation) ||
      !frozen(original.nodeInstallation.layout) || !frozen(raw) || !frozen(raw.installation) ||
      !frozen(raw.installation.sdk) || raw.probability === null ||
      typeof raw.probability !== 'object') issue('TypeSafeOriginalInstallationUnavailable');
  // Common admits the opaque probability handle. JS freezing is not its
  // provenance; preserve and compare the original reference below.
  const installation = raw.installation, sdk = installation.sdk, probability = raw.probability;
  if (original.nodeInstallation.layout.response_profile !== raw.profile ||
      original.nodeInstallation.probability !== probability ||
      installation.endpoint !== endpoint.href || installation.http_method !== 'POST' ||
      installation.streaming !== false || installation.completion_basis !== 'native_decision' ||
      sdk.package_name !== '@ai-sdk/typesafe-ai' || sdk.version !== '3.0.13' ||
      sdk.interface !== 'v4' || !cid(sdk.lock_artifact_cid)) issue('TypeSafeOriginalInstallationMismatch');
  const quantities = config.quantityCapacity, bindings = config.bindingOriginals;
  if (!frozen(quantities) || !frozen(quantities.limits) || !frozen(quantities.perAttempt) ||
      !frozen(bindings) || !['configuration', 'configurationContract', 'installationRevision']
        .every(name => frozen(bindings[name]))) issue('TypeSafeOriginalInstallationUnavailable');
  return moon => {
    if (!['clientProgramInstallAsyncModelProvider', 'clientProgramStartNativeDecisionProjection',
      'clientProgramAdvanceNativeDecisionProjection', 'clientProgramRetireNativeDecisionProjection',
      'clientProgramRetireNativeDecisionRequest', 'clientProgramNativeDecisionRequestMatches',
      'clientProgramNativeDecisionRequestBinding', 'clientProgramNativeDecisionRequestWires',
      'clientProgramModelRequestPreflight', 'clientProgramModelAsyncNativeDecisionRequestPlan',
      'clientProgramModelPhysicalCallForRequest', 'clientProgramModelPhysicalPending',
      'clientProgramModelPhysicalUnknown', 'clientProgramModelPhysicalSavedNativeDecision']
      .every(name => typeof moon?.[name] === 'function')) issue('TypeSafeOriginalRuntimeUnavailable');
    requireTypeSafeOriginalTransportLimits(moon,raw.profile,requestLimits.maxBytes,responseLimits);
    return [Object.freeze({providerId, entryPersistence: 'async', bindingOriginals: bindings,
      originalReadInstallation: original, rawCaptureSelection: raw, quantityCapacity: quantities, observeEgress,
      validatePrompt: (task, selector, payload) => task === taskCid && selector === modelSelector && payload === promptPayloadWire,
      physicalPreflight(request, notification, retainRawBinder, admittedProvider) {
        if (typeof notification?.notify !== 'function' || typeof retainRawBinder !== 'function' ||
            admittedProvider === undefined) issue('TypeSafeOriginalPhysicalContextUnavailable');
        return createAdmittedTypeSafeDecisionPreflight({moon, request, admittedProvider, probability,
          taskCid, promptCid, outputSchemaCid, modelSelector, projectionLimits,
          modelId, baseURL, apiKey, fetch, observeAt, notify: notification.notify,
          rawCaptureBinder: retainRawBinder, profile: raw.profile, installation,
          quantities: quantities.perAttempt, responseLimits,
          maxRequestBytes: requestLimits.maxBytes, maxHeaderBytes: requestLimits.maxHeaderBytes,
          maxHeaders: requestLimits.maxHeaders,
          checked(value) {if (value?.$tag !== 1) issue('TypeSafeOriginalCommonRefused'); return value._0;},
        }).preflight;
      },
    })];
  };
}
