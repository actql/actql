import {createHttpChatPreflight} from './model-port.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';

const fail = code => { throw new TypeError(code); };
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' && value.length > 0;
const integer = (value, minimum = 1) => Number.isSafeInteger(value) &&
  value >= minimum && value <= 2_147_483_647;
const frozen = value => value !== null && typeof value === 'object' && Object.isFrozen(value);

// Inspect and retain the same own DATA values. This is an installation
// snapshot, not canonical admission, funding, nominal custody or authority.
function snapshot(value, fields, code) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail(code);
  const names = Reflect.ownKeys(value);
  const expected = [...fields].sort();
  if (names.some(name => typeof name !== 'string') || names.length !== expected.length ||
      names.slice().sort().some((name, index) => name !== expected[index])) fail(code);
  return Object.freeze(Object.fromEntries(names.map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) fail(code);
    return [name, descriptor.value];
  })));
}

function snapshotArray(value, maximum, code) {
  if (!Array.isArray(value)) fail(code);
  const length = Object.getOwnPropertyDescriptor(value, 'length');
  if (length === undefined || !Object.hasOwn(length, 'value') ||
      !Number.isSafeInteger(length.value) || length.value < 0 || length.value > maximum) fail(code);
  const count = length.value;
  const names = Reflect.ownKeys(value);
  if (names.length !== count + 1 || names.some(name => typeof name !== 'string') ||
      !names.includes('length')) fail(code);
  for (let index = 0; index < count; index++) {
    if (!names.includes(String(index))) fail(code);
  }
  const result = [];
  for (let index = 0; index < count; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) fail(code);
    result.push(descriptor.value);
  }
  return Object.freeze(result);
}

// Private trusted Host assembler. It does not load a package, admit a numeric
// profile, infer credentials or replace the existing Model/Run/Store Owner.
// The package exposes this assembler only; original funding and public
// execution acceptance remain separate required boundaries.
export function createInstalledHttpChatRegistration(value) {
  const config = snapshot(value, ['providerId', 'modelSelector', 'modelId',
    'endpoint', 'headers', 'taskCid', 'promptCid', 'outputSchemaCid',
    'promptPayloadWire', 'originalReadInstallation', 'rawCaptureSelection',
    'bindingOriginals', 'quantityCapacity', 'projectionLimits', 'requestLimits',
    'responseLimits', 'fetch', 'observeAt', 'observeEgress'], 'InvalidInstalledHTTPChatConfiguration');
  const {providerId, modelSelector, modelId, endpoint, taskCid, promptCid,
    outputSchemaCid, promptPayloadWire, fetch, observeAt, observeEgress} = config;
  if (![providerId, modelSelector, modelId, endpoint].every(text) ||
      ![taskCid, promptCid, outputSchemaCid].every(cid) ||
      typeof promptPayloadWire !== 'string' ||
      ![fetch, observeAt, observeEgress].every(x => typeof x === 'function')) {
    fail('InvalidInstalledHTTPChatConfiguration');
  }
  let url;
  try { url = new URL(endpoint); } catch { fail('InvalidInstalledHTTPChatEndpoint'); }
  if (url.href !== endpoint || !['http:', 'https:'].includes(url.protocol) ||
      url.username || url.password || url.search || url.hash) fail('InvalidInstalledHTTPChatEndpoint');
  const projectionLimits = snapshot(config.projectionLimits,
    ['maxBytes', 'maxDepth', 'maxFrames', 'maxNodes', 'maxWork'], 'InvalidInstalledHTTPChatProjection');
  if (!Object.entries(projectionLimits).every(([name, amount]) =>
    integer(amount, name === 'maxWork' ? 0 : 1))) fail('InvalidInstalledHTTPChatProjection');
  const requestLimits = snapshot(config.requestLimits,
    ['maxBytes', 'maxHeaderBytes', 'maxHeaders'], 'InvalidInstalledHTTPChatRequestLimits');
  if (!Object.values(requestLimits).every(x => integer(x)) || requestLimits.maxHeaders > 64) {
    fail('InvalidInstalledHTTPChatRequestLimits');
  }
  const responseLimits = fixedInferResponseLimits(config.responseLimits);
  const pairs = snapshotArray(config.headers, requestLimits.maxHeaders, 'InvalidInstalledHTTPChatHeaders');
  let headerBytes = 0;
  const headerNames = new Set();
  const headers = Object.freeze(pairs.map(originalPair => {
    const pair = snapshotArray(originalPair, 2, 'InvalidInstalledHTTPChatHeaders');
    const [name, content] = pair;
    if (pair.length !== 2 || typeof name !== 'string' || !/^[a-z0-9-]+$/u.test(name) ||
        typeof content !== 'string' || /[\r\n]/u.test(content) || headerNames.has(name)) {
      fail('InvalidInstalledHTTPChatHeaders');
    }
    headerNames.add(name);
    headerBytes += Buffer.byteLength(name) + Buffer.byteLength(content);
    if (headerBytes > requestLimits.maxHeaderBytes) fail('InvalidInstalledHTTPChatHeaders');
    return Object.freeze([name, content]);
  }));
  const original = config.originalReadInstallation;
  const raw = config.rawCaptureSelection;
  if (!frozen(original) || !frozen(original.bootstrap) ||
      !frozen(original.nodeInstallation) || !frozen(original.nodeInstallation.layout) ||
      !frozen(raw) || !frozen(raw.installation) || raw.profile == null) fail('HTTPChatOriginalInstallationUnavailable');
  const installation = raw.installation;
  if (original.nodeInstallation.layout.response_profile !== raw.profile ||
      original.nodeInstallation.probability !== undefined || raw.probability !== undefined ||
      installation.endpoint !== endpoint || installation.http_method !== 'POST' ||
      installation.streaming !== false || installation.completion_basis !== 'generation_finish' ||
      installation.sdk !== undefined && installation.sdk !== null) {
    // SDK-free is an explicit existing installation shape, not a dummy SDK.
    fail('HTTPChatOriginalInstallationMismatch');
  }
  const quantities = config.quantityCapacity;
  const bindings = config.bindingOriginals;
  if (!frozen(quantities) || !frozen(quantities.limits) || !frozen(quantities.perAttempt) ||
      !frozen(bindings) || !['configuration', 'configurationContract', 'installationRevision']
        .every(name => frozen(bindings[name]))) fail('HTTPChatOriginalInstallationUnavailable');
  return moon => {
    if (!['clientProgramModelResponseProfileTransportMatches',
      'clientProgramProjectHTTPChatRequest', 'clientProgramInstallAsyncModelProvider',
      'clientProgramModelRequestPreflight', 'clientProgramModelAsyncPhysicalRequestPlan',
      'clientProgramModelPhysicalCallForRequest', 'clientProgramModelPhysicalPending',
      'clientProgramModelPhysicalUnknown', 'clientProgramModelPhysicalSavedChat']
      .every(name => typeof moon?.[name] === 'function')) fail('HTTPChatOriginalRuntimeUnavailable');
    if (moon.clientProgramModelResponseProfileTransportMatches(raw.profile,
      requestLimits.maxBytes, responseLimits.maxBytes, responseLimits.maxChunkBytes,
      responseLimits.maxChunks, responseLimits.maxHeaderBytes) !== true) {
      fail('HTTPChatOriginalTransportLimitsMismatch');
    }
    return [Object.freeze({providerId, entryPersistence: 'async',
      bindingOriginals: bindings, originalReadInstallation: original,
      rawCaptureSelection: raw, quantityCapacity: quantities, observeEgress,
      validatePrompt: (task, selector, payload) => task === taskCid &&
        selector === modelSelector && payload === promptPayloadWire,
      physicalPreflight(request, notification, retainRawBinder, admittedProvider) {
        if (typeof notification?.notify !== 'function' ||
            typeof retainRawBinder !== 'function' || admittedProvider === undefined) {
          fail('HTTPChatOriginalPhysicalContextUnavailable');
        }
        return createHttpChatPreflight({moon, request, admittedProvider, modelId,
          taskCid, promptCid, outputSchemaCid, modelSelector, projectionLimits,
          endpoint, headers, requestLimits, responseLimits, fetch, observeAt,
          notify: notification.notify, rawCaptureBinder: retainRawBinder,
          profile: raw.profile, installation, quantities: quantities.perAttempt,
          checked(result) {
            if (result?.$tag === 1) return result._0;
            fail('HTTPChatOriginalCommonRefused');
          }}).preflight;
      },
    })];
  };
}
