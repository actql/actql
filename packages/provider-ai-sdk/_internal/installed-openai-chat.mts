import {runtimeField, runtimeIsOk} from './compiler-binding.generated.mjs';
import {createAdmittedOpenAIChatPreflight} from './original-openai-chat.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';
import {createOriginalUndiciFetch,fixedOriginalAcquisitionLimits,fixedOriginalTransportTimeouts} from './original-undici-transport.mjs';
import {snapshotOpenAIOriginalMaterials,admitOpenAIOriginalMaterials} from './original-materials.mjs';
import {openAIChatStaticOriginals} from './openai-chat.mjs';
import type {OriginalStringLimits, RequestLimits, QuantityCapacity} from '../index.d.ts';

type Preflight = Parameters<typeof createAdmittedOpenAIChatPreflight>[0];
type Runtime = Preflight['moon'] & Parameters<typeof admitOpenAIOriginalMaterials>[0] & {
  clientProgramModelResponseProfileTransportMatches(profile: unknown, ...limits: number[]): unknown;
  [name: string]: unknown;
};
// Unchecked views over the existing borrowed originals. Only the unchanged
// descriptor, frozen-field, Common and same-original checks below admit them.
interface ReadOriginal {bootstrap: unknown; nodeInstallation: {
  layout: {response_profile: unknown}; probability: unknown;
}}
interface Installation {sdk: {package_name: unknown; version: unknown; interface: unknown; lock_artifact_cid: unknown};
  endpoint: unknown; http_method: unknown; streaming: unknown; completion_basis: unknown;
}
interface RawOriginal {profile: unknown; probability: unknown; installation: Installation}
interface Configuration {
  apiKey: string; baseURL: string; modelId: string; modelSelector: string;
  providerId: string; taskCid: string; promptCid: string; outputSchemaCid: string; promptPayloadWire: string;
  originalStringLimits: OriginalStringLimits; originalMaterials: unknown;
  originalReadInstallation: ReadOriginal; originalReadRecipe: ReadOriginal;
  rawCaptureSelection: RawOriginal; bindingOriginals: Readonly<Record<string, unknown>>;
  quantityCapacity: QuantityCapacity; projectionLimits: Preflight['projectionLimits'];
  requestLimits: RequestLimits; responseLimits: NonNullable<Preflight['responseLimits']>;
  physicalAcquisitionLimits: unknown; fetch: Preflight['fetch'];
  observeAt: Preflight['observeAt']; observeEgress: (facts: unknown) => unknown;
}
type Notification = {notify: NonNullable<Preflight['notify']>};
type Binder = NonNullable<Preflight['rawCaptureBinder']>;
interface Entry extends Readonly<Record<string, unknown>> {
  validatePrompt(task: unknown, selector: unknown, payload: unknown): boolean;
  physicalPreflight(request: unknown, notification: Notification, retainRawBinder: Binder, admittedProvider: unknown): unknown;
}
type Registration = (moon: Runtime) => Readonly<Entry>[];

const issue = (code: string): never => { throw Object.assign(new TypeError(code), {code}); };
const cid = (value: unknown) => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const text = (value: unknown) => typeof value === 'string' && value.length > 0;
const int = (value: unknown, minimum=1) => Number.isSafeInteger(value) &&
  (value as number)>=minimum && (value as number)<=2_147_483_647;
// Inspect and retain DATA once. A later Proxy property callback must not swap
// validated selectors or bounds during the copy. This snapshot is not an
// installation, physical adequacy, capacity or dispatch grant.
function snapshotData(value: unknown, keys: string, code: string): Readonly<Record<string, unknown>> {
  if (value===null || typeof value!=='object' || Array.isArray(value)) issue(code);
  const names=Reflect.ownKeys(value as object);
  const expected=keys.split(',');
  if (names.some(name=>typeof name!=='string') || names.length!==expected.length ||
      names.slice().sort().some((name,index)=>name!==expected[index])) issue(code);
  const entries=names.map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(value as object,name);
    if (descriptor===undefined || descriptor.enumerable!==true || !('value' in descriptor)) issue(code);
    return [name,descriptor!.value as unknown];
  });
  return Object.freeze(Object.fromEntries(entries));
}
const frozen = (value: unknown) => value!==null && typeof value==='object' && Object.isFrozen(value);
const assertRuntime = (moon: Runtime) => {
  if (!['clientProgramStartOpenAIChatProjection','clientProgramAdvanceOpenAIChatProjection',
    'clientProgramRetireOpenAIChatProjection','clientProgramFinishOpenAIChatSdkV4Projection',
    'clientProgramInstallAsyncModelProvider',
    'clientProgramModelRequestGeneration','clientProgramModelRequestPreflight',
    'clientProgramModelAsyncPhysicalRequestPlan','clientProgramModelPhysicalCallForRequest',
    'clientProgramModelPhysicalPending','clientProgramModelPhysicalUnknown',
    'clientProgramModelPhysicalSavedChat',
    'clientProgramModelResponseProfileTransportMatches'].every(name=>typeof moon?.[name]==='function')) {
    issue('OpenAIOriginalRuntimeUnavailable');
  }
};

// Private trusted-installation consumer, not a profile/grant factory. The Host
// supplies already retained declaration originals; opaque Owners are borrowed,
// never rebuilt from their CIDs. The package exposes this assembler only;
// complete numerical funding and public execution acceptance remain required.
export function createInstalledOpenAIChatRegistration(config: unknown): Registration {
  return installedChatRegistration(config as Configuration, false);
}

// Explicit selected transport, not an ambient fallback or an installed profile.
// Reuse the same original Host selections, snapshots and common admission.
export function createInstalledUndiciOpenAIChatRegistration(config: unknown): Registration {
  return installedChatRegistration(config as Configuration, true);
}

// Private normal-configuration continuation. The normal factory has already
// included these same frozen settings in its original contract/configuration
// bodies under the initial construction Resource. Legacy public low-level
// registrations accept no unbound timeout field.
export function createConfiguredUndiciOpenAIChatRegistration(config: unknown, transportTimeouts: unknown, openAICredentialBytes?: number): Registration {
  return installedChatRegistration(config as Configuration, true, fixedOriginalTransportTimeouts(transportTimeouts), openAICredentialBytes);
}

function installedChatRegistration(config: Configuration, originalUndici: boolean, transportTimeouts?: ReturnType<typeof fixedOriginalTransportTimeouts>, openAICredentialBytes?: number): Registration {
  if (config!==null && typeof config==='object' && !Object.hasOwn(config,'originalStringLimits')) {
    issue('OpenAIOriginalStringLimitsUnavailable');
  }
  const keys='apiKey,baseURL,bindingOriginals,fetch,modelId,modelSelector,observeAt,observeEgress,originalReadInstallation,originalStringLimits,outputSchemaCid,projectionLimits,promptCid,promptPayloadWire,providerId,quantityCapacity,rawCaptureSelection,requestLimits,responseLimits,taskCid';
  const materialMode = config!==null && typeof config==='object' && Object.hasOwn(config,'originalMaterials');
  const recipeMode = config!==null && typeof config==='object' && Object.hasOwn(config,'originalReadRecipe');
  const selectedKeys = materialMode ? keys.replace(',originalReadInstallation',',originalMaterials')
    .replace(',rawCaptureSelection','') : recipeMode
      ? keys.replace(',originalReadInstallation',',originalReadRecipe') : keys;
  config=snapshotData(config,originalUndici ? selectedKeys.replace(',fetch', '')
    .replace(',projectionLimits',',physicalAcquisitionLimits,projectionLimits') : selectedKeys,
    'InvalidInstalledOpenAIChatConfiguration') as unknown as Configuration;
  // Original primitive UTF-16 code units, not encoded request/header bytes.
  // Refuse before the first input-dependent concatenation, URL, SDK child or
  // encoding. Host acquisition of the supplied originals remains separately
  // owned; this declaration and its snapshot are not physical funding.
  const originalStringLimits=snapshotData(config.originalStringLimits,
    'maxApiKeyCodeUnits,maxBaseURLCodeUnits,maxModelIdCodeUnits',
    'InvalidInstalledOpenAIChatOriginalStringLimits') as unknown as OriginalStringLimits;
  if (!Object.values(originalStringLimits).every(value=>int(value))) {
    issue('InvalidInstalledOpenAIChatOriginalStringLimits');
  }
  if (![config.apiKey,config.baseURL,config.modelId].every(text)) {
    issue('InvalidInstalledOpenAIChatConfiguration');
  }
  if (config.apiKey.length>originalStringLimits.maxApiKeyCodeUnits ||
      config.baseURL.length>originalStringLimits.maxBaseURLCodeUnits ||
      config.modelId.length>originalStringLimits.maxModelIdCodeUnits) {
    issue('OpenAIOriginalStringLimitExceeded');
  }
  config=Object.freeze({...config,originalStringLimits,
    ...(originalUndici ? {
      physicalAcquisitionLimits:fixedOriginalAcquisitionLimits(config.physicalAcquisitionLimits),
    } : {})});
  if (materialMode) {
    let materials: ReturnType<typeof snapshotOpenAIOriginalMaterials> | undefined=snapshotOpenAIOriginalMaterials(config.originalMaterials);
    const {originalMaterials:unused,...source}=config;void unused;
    let retained: Readonly<Configuration> | undefined=Object.freeze({...source,
      projectionLimits:snapshotData(source.projectionLimits,
        'maxBytes,maxDepth,maxFrames,maxNodes,maxWork','InvalidInstalledOpenAIChatProjection'),
      requestLimits:snapshotData(source.requestLimits,
        'maxBytes,maxHeaderBytes,maxHeaders','InvalidInstalledOpenAIChatRequestLimits'),
      responseLimits:fixedInferResponseLimits(source.responseLimits),
    }) as unknown as Configuration;
    // The opaque branch below also captures config in this function's scope.
    // Retain only the closed snapshot here, not the caller's original graph.
    config=undefined as unknown as Configuration;
    let entered = false;
    // One registration callback belongs to one actual Host installation. The
    // actual runtime is received here, never imported or reconstructed by a
    // consumer. Refuse another installation even if it shares that module.
    return moon => {
      if (entered) issue('OpenAIOriginalInstallationReused');
      assertRuntime(moon);
      // A failed admission is not a reason to move this original callback to
      // another Host or allocate another set of reader results from it.
      entered=true;
      try {
        const originals=admitOpenAIOriginalMaterials(moon,materials!);
        const register=installedChatRegistration({...retained,...originals} as unknown as Configuration,originalUndici,transportTimeouts);
        return register(moon);
      } finally {
        // Successful entries retain their original duties. A refused reader
        // has issued no physical Call/custody to this loader. In either case
        // the spent callback no longer borrows its admission-only snapshots;
        // dropping aliases is not GC, physical cleanup, ACK or budget release.
        materials=undefined;
        retained=undefined;
      }
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
  let endpoint!: URL;
  try {endpoint=new URL(`${baseURL}/chat/completions`);}
  catch {issue('InvalidInstalledOpenAIChatEndpoint');}
  if (baseURL.endsWith('/') || endpoint.href!==`${baseURL}/chat/completions` ||
      !['http:','https:'].includes(endpoint.protocol) ||
      endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
    issue('InvalidInstalledOpenAIChatEndpoint');
  }
  const projectionLimits=snapshotData(config.projectionLimits,
    'maxBytes,maxDepth,maxFrames,maxNodes,maxWork','InvalidInstalledOpenAIChatProjection') as unknown as Preflight['projectionLimits'];
  if (!Object.entries(projectionLimits).every(([name,value])=>int(value,name==='maxWork'?0:1))) {
    issue('InvalidInstalledOpenAIChatProjection');
  }
  const requestLimits=snapshotData(config.requestLimits,
    'maxBytes,maxHeaderBytes,maxHeaders','InvalidInstalledOpenAIChatRequestLimits') as unknown as RequestLimits;
  if (!Object.values(requestLimits).every(value=>int(value)) || requestLimits.maxHeaders>64) {
    issue('InvalidInstalledOpenAIChatRequestLimits');
  }
  const responseLimits=fixedInferResponseLimits(config.responseLimits);
  // No supported normal supplier is synthesized when installation is missing.
  // Clamps, positive integers or a matching profile CID are not that supplier.
  const original=recipeMode ? config.originalReadRecipe : config.originalReadInstallation;
  const raw=config.rawCaptureSelection;
  if (!frozen(original) || !frozen(original.bootstrap) || !frozen(original.nodeInstallation) ||
      !frozen(original.nodeInstallation.layout) || !frozen(raw) ||
      !frozen(raw.installation) || !frozen(raw.installation.sdk)) {
    issue('OpenAIOriginalInstallationUnavailable');
  }
  const installation=raw.installation;
  const sdk=installation.sdk;
  if (raw.profile===undefined || raw.profile===null ||
      original.nodeInstallation.layout.response_profile!==raw.profile ||
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
  let physicalFetch: Preflight['fetch'];
  return moon => {
    assertRuntime(moon);
    if (moon.clientProgramModelResponseProfileTransportMatches(raw.profile,
      requestLimits.maxBytes,responseLimits.maxBytes,responseLimits.maxChunkBytes,
      responseLimits.maxChunks,responseLimits.maxHeaderBytes)!==true) {
      issue('OpenAIOriginalTransportLimitsMismatch');
    }
    // The actual callback runtime checks the admitted profile BEFORE even the
    // physical selector is built. The existing Host envelope still must fund
    // this selector and all later Client/SDK allocations; matching is no grant.
    physicalFetch??=originalUndici ? createOriginalUndiciFetch({
      endpoint:endpoint.href,requestLimits,responseLimits,
      physicalAcquisitionLimits:config.physicalAcquisitionLimits,
      transportTimeouts, openAICredentialBytes}) : fetch;
    return [Object.freeze({providerId,entryPersistence:'async',
      sdkStaticOriginals:openAIChatStaticOriginals,
      bindingOriginals:bindings,
      ...(recipeMode ? {originalReadRecipe:original} : {originalReadInstallation:original}),
      rawCaptureSelection:raw,quantityCapacity:quantities,observeEgress,
      // Common has already admitted the exact Task/prompt dependency. This
      // comparator selects the installed interpretation, not a JS evaluator.
      validatePrompt:(task: unknown,selector: unknown,payload: unknown)=>task===taskCid &&
        selector===modelSelector && payload===promptPayloadWire,
      physicalPreflight(request: unknown,notification: Notification,retainRawBinder: Binder,admittedProvider: unknown) {
        if (typeof notification?.notify!=='function' || typeof retainRawBinder!=='function' ||
            admittedProvider===undefined) issue('OpenAIOriginalPhysicalContextUnavailable');
        return createAdmittedOpenAIChatPreflight({moon,request,admittedProvider,
          taskCid,promptCid,outputSchemaCid,modelSelector,projectionLimits,
          modelId,baseURL,apiKey,fetch:physicalFetch,observeAt,notify:notification.notify,
          rawCaptureBinder:retainRawBinder,profile:raw.profile,installation,
          needsCredential: openAICredentialBytes !== undefined,
          quantities:quantities.perAttempt,responseLimits,
          maxRequestBytes:requestLimits.maxBytes,
          maxHeaderBytes:requestLimits.maxHeaderBytes,maxHeaders:requestLimits.maxHeaders,
          checked(value: unknown) {
            if (runtimeIsOk(value)) return runtimeField(value, 0);
            issue('OpenAIOriginalCommonRefused');
          }}).preflight;
      },
    })];
  };
}
