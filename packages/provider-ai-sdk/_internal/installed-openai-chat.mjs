import {createAdmittedOpenAIChatPreflight} from './original-openai-chat.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';

const issue = code => { throw Object.assign(new TypeError(code), {code}); };
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' && value.length > 0;
const int = (value, minimum=1) => Number.isSafeInteger(value) &&
  value>=minimum && value<=2_147_483_647;
const data = (value, keys) => value!==null && typeof value==='object' &&
  !Array.isArray(value) &&
  Object.values(Object.getOwnPropertyDescriptors(value)).every(d=>'value' in d) &&
  Object.keys(value).sort().join(',')===keys;
const frozen = value => value!==null && typeof value==='object' && Object.isFrozen(value);

// Private trusted-installation consumer, not a profile/grant factory. The Host
// supplies already retained declaration originals; opaque Owners are borrowed,
// never rebuilt from their CIDs. Public package exports remain closed until
// the original complete numerical funding and public acceptance are adopted.
export function createInstalledOpenAIChatRegistration(config) {
  const keys='apiKey,baseURL,bindingOriginals,fetch,modelId,modelSelector,observeAt,observeEgress,originalReadInstallation,outputSchemaCid,projectionLimits,promptCid,promptPayloadWire,providerId,quantityCapacity,rawCaptureSelection,requestLimits,responseLimits,taskCid';
  if (!data(config,keys)) issue('InvalidInstalledOpenAIChatConfiguration');
  const {providerId,modelSelector,modelId,baseURL,taskCid,promptCid,outputSchemaCid,
    promptPayloadWire,apiKey,fetch,observeAt,observeEgress}=config;
  if (![providerId,modelSelector,modelId,baseURL,apiKey].every(text) ||
      ![taskCid,promptCid,outputSchemaCid].every(cid) ||
      typeof promptPayloadWire!=='string' ||
      ![fetch,observeAt,observeEgress].every(value=>typeof value==='function')) {
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
  const projection=config.projectionLimits;
  if (!data(projection,'maxBytes,maxDepth,maxFrames,maxNodes,maxWork') ||
      !Object.entries(projection).every(([name,value])=>int(value,name==='maxWork'?0:1))) {
    issue('InvalidInstalledOpenAIChatProjection');
  }
  const projectionLimits=Object.freeze({...projection});
  const request=config.requestLimits;
  if (!data(request,'maxBytes,maxHeaderBytes,maxHeaders') ||
      !Object.values(request).every(value=>int(value)) || request.maxHeaders>64) {
    issue('InvalidInstalledOpenAIChatRequestLimits');
  }
  const requestLimits=Object.freeze({...request});
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
          modelId,baseURL,apiKey,fetch,observeAt,notify:notification.notify,
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
