import {createAdmittedOpenAIChatPreflight} from './original-openai-chat.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';
import {createOriginalUndiciFetch} from './original-undici-transport.mjs';
import {snapshotOpenAIOriginalMaterials,admitOpenAIOriginalMaterials} from './original-materials.mjs';

const issue = code => { throw Object.assign(new TypeError(code), {code}); };
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' && value.length > 0;
const int = (value, minimum=1) => Number.isSafeInteger(value) &&
  value>=minimum && value<=2_147_483_647;
// Inspect and retain DATA once. A later Proxy property callback must not swap
// validated selectors or bounds during the copy. This snapshot is not an
// installation, physical adequacy, capacity or dispatch grant.
function snapshotData(value, keys, code) {
  if (value===null || typeof value!=='object' || Array.isArray(value)) issue(code);
  const names=Reflect.ownKeys(value);
  const expected=keys.split(',');
  if (names.some(name=>typeof name!=='string') || names.length!==expected.length ||
      names.slice().sort().some((name,index)=>name!==expected[index])) issue(code);
  const entries=names.map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(value,name);
    if (descriptor===undefined || descriptor.enumerable!==true || !('value' in descriptor)) issue(code);
    return [name,descriptor.value];
  });
  return Object.freeze(Object.fromEntries(entries));
}
const frozen = value => value!==null && typeof value==='object' && Object.isFrozen(value);

// Private trusted-installation consumer, not a profile/grant factory. The Host
// supplies already retained declaration originals; opaque Owners are borrowed,
// never rebuilt from their CIDs. The package exposes this assembler only;
// complete numerical funding and public execution acceptance remain required.
export function createInstalledOpenAIChatRegistration(config) {
  return installedChatRegistration(config, false);
}

// Explicit selected transport, not an ambient fallback or an installed profile.
// Reuse the same original Host selections, snapshots and common admission.
export function createInstalledUndiciOpenAIChatRegistration(config) {
  return installedChatRegistration(config, true);
}

function installedChatRegistration(config, originalUndici) {
  const keys='apiKey,baseURL,bindingOriginals,fetch,modelId,modelSelector,observeAt,observeEgress,originalReadInstallation,outputSchemaCid,projectionLimits,promptCid,promptPayloadWire,providerId,quantityCapacity,rawCaptureSelection,requestLimits,responseLimits,taskCid';
  const materialMode = config!==null && typeof config==='object' && Object.hasOwn(config,'originalMaterials');
  const selectedKeys = materialMode ? keys.replace(',originalReadInstallation',',originalMaterials')
    .replace(',rawCaptureSelection','') : keys;
  config=snapshotData(config,originalUndici ? selectedKeys.replace(',fetch', '') : selectedKeys,
    'InvalidInstalledOpenAIChatConfiguration');
  if (materialMode) {
    const materials=snapshotOpenAIOriginalMaterials(config.originalMaterials);
    const {originalMaterials:unused,...source}=config;void unused;
    const retained=Object.freeze({...source,
      projectionLimits:snapshotData(source.projectionLimits,
        'maxBytes,maxDepth,maxFrames,maxNodes,maxWork','InvalidInstalledOpenAIChatProjection'),
      requestLimits:snapshotData(source.requestLimits,
        'maxBytes,maxHeaderBytes,maxHeaders','InvalidInstalledOpenAIChatRequestLimits'),
      responseLimits:fixedInferResponseLimits(source.responseLimits),
    });
    let installed = false;
    // One registration callback belongs to one actual Host installation. The
    // actual runtime is received here, never imported or reconstructed by a
    // consumer. Refuse another installation even if it shares that module.
    return moon => {
      if (installed) issue('OpenAIOriginalInstallationReused');
      const originals=admitOpenAIOriginalMaterials(moon,materials);
      const register=installedChatRegistration({...retained,...originals},originalUndici);
      const entries=register(moon);
      installed=true;
      return entries;
    };
  }
  const {providerId,modelSelector,modelId,baseURL,taskCid,promptCid,outputSchemaCid,
    promptPayloadWire,apiKey,fetch,observeAt,observeEgress}=config;
  if (![providerId,modelSelector,modelId,baseURL,apiKey].every(text) ||
      ![taskCid,promptCid,outputSchemaCid].every(cid) ||
      typeof promptPayloadWire!=='string' ||
      ![observeAt,observeEgress].every(value=>typeof value==='function') ||
      !originalUndici && typeof fetch!=='function') {
    issue('InvalidInstalledOpenAIChatConfiguration');
  }
  let endpoint;
  try {endpoint=new URL(`${baseURL}/chat/completions`);}
  catch {issue('InvalidInstalledOpenAIChatEndpoint');}
  if (baseURL.endsWith('/') || endpoint.href!==`${baseURL}/chat/completions` ||
      !['http:','https:'].includes(endpoint.protocol) ||
      endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
    issue('InvalidInstalledOpenAIChatEndpoint');
  }
  const projectionLimits=snapshotData(config.projectionLimits,
    'maxBytes,maxDepth,maxFrames,maxNodes,maxWork','InvalidInstalledOpenAIChatProjection');
  if (!Object.entries(projectionLimits).every(([name,value])=>int(value,name==='maxWork'?0:1))) {
    issue('InvalidInstalledOpenAIChatProjection');
  }
  const requestLimits=snapshotData(config.requestLimits,
    'maxBytes,maxHeaderBytes,maxHeaders','InvalidInstalledOpenAIChatRequestLimits');
  if (!Object.values(requestLimits).every(value=>int(value)) || requestLimits.maxHeaders>64) {
    issue('InvalidInstalledOpenAIChatRequestLimits');
  }
  const responseLimits=fixedInferResponseLimits(config.responseLimits);
  // No supported normal supplier is synthesized when installation is missing.
  // Clamps, positive integers or a matching profile CID are not that supplier.
  const original=config.originalReadInstallation;
  const raw=config.rawCaptureSelection;
  if (!frozen(original) || !frozen(original.bootstrap) || !frozen(original.nodeInstallation) ||
      !frozen(original.nodeInstallation.layout) || !frozen(raw) ||
      !frozen(raw.installation) || !frozen(raw.installation.sdk)) {
    issue('OpenAIOriginalInstallationUnavailable');
  }
  const installation=raw.installation;
  const sdk=installation.sdk;
  if (original.nodeInstallation.layout.response_profile!==raw.profile ||
      original.nodeInstallation.probability!==undefined || raw.probability!==undefined ||
      installation.endpoint!==endpoint.href || installation.http_method!=='POST' ||
      installation.streaming!==false || installation.completion_basis!=='generation_finish' ||
      sdk.package_name!=='@ai-sdk/openai' || sdk.version!=='4.0.91' ||
      sdk.interface!=='v4' || !cid(sdk.lock_artifact_cid)) {
    issue('OpenAIOriginalInstallationMismatch');
  }
  const quantities=config.quantityCapacity;
  const bindings=config.bindingOriginals;
  // These are existing Host-retained originals, not caller-owned mutable
  // declarations crossing an await. The normal Host still admits/checks each
  // body and amount and snapshots its own installation before any Run starts.
  if (!frozen(quantities) || !frozen(quantities.limits) || !frozen(quantities.perAttempt) ||
      !frozen(bindings) || !['configuration','configurationContract','installationRevision']
        .every(name=>frozen(bindings[name]))) {
    issue('OpenAIOriginalInstallationUnavailable');
  }
  // A missing/mismatched original selection above refuses before constructing
  // even this physical selector. The per-call Client remains later original
  // SDK preparation, after its existing same-Ledger funding and before Entry.
  const physicalFetch=originalUndici ? createOriginalUndiciFetch({
    endpoint:endpoint.href,requestLimits,responseLimits}) : fetch;
  return moon => {
    if (!['clientProgramStartOpenAIChatProjection','clientProgramAdvanceOpenAIChatProjection',
      'clientProgramRetireOpenAIChatProjection','clientProgramInstallAsyncModelProvider',
      'clientProgramModelRequestGeneration','clientProgramModelRequestPreflight',
      'clientProgramModelAsyncPhysicalRequestPlan','clientProgramModelPhysicalCallForRequest',
      'clientProgramModelPhysicalPending','clientProgramModelPhysicalUnknown',
      'clientProgramModelPhysicalSavedChat'].every(name=>typeof moon?.[name]==='function')) {
      issue('OpenAIOriginalRuntimeUnavailable');
    }
    return [Object.freeze({providerId,entryPersistence:'async',
      bindingOriginals:bindings,originalReadInstallation:original,
      rawCaptureSelection:raw,quantityCapacity:quantities,observeEgress,
      // Common has already admitted the exact Task/prompt dependency. This
      // comparator selects the installed interpretation, not a JS evaluator.
      validatePrompt:(task,selector,payload)=>task===taskCid &&
        selector===modelSelector && payload===promptPayloadWire,
      physicalPreflight(request,notification,retainRawBinder,admittedProvider) {
        if (typeof notification?.notify!=='function' || typeof retainRawBinder!=='function' ||
            admittedProvider===undefined) issue('OpenAIOriginalPhysicalContextUnavailable');
        return createAdmittedOpenAIChatPreflight({moon,request,admittedProvider,
          taskCid,promptCid,outputSchemaCid,modelSelector,projectionLimits,
          modelId,baseURL,apiKey,fetch:physicalFetch,observeAt,notify:notification.notify,
          rawCaptureBinder:retainRawBinder,profile:raw.profile,installation,
          quantities:quantities.perAttempt,responseLimits,
          maxRequestBytes:requestLimits.maxBytes,
          maxHeaderBytes:requestLimits.maxHeaderBytes,maxHeaders:requestLimits.maxHeaders,
          checked(value) {
            if (value?.$tag===1) return value._0;
            issue('OpenAIOriginalCommonRefused');
          }}).preflight;
      },
    })];
  };
}
