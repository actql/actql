import {runtimeField, runtimeIsOk} from './compiler-binding.generated.mjs';
import {createAdmittedRegisteredSdkPreflight} from './model-port.mjs';
import type {RegisteredSdk} from './model-port.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';
import {originalLocalModelHttpTransport} from './local-model-http-transport.mjs';
import type {RequestLimits, QuantityCapacity} from '../index.d.ts';

type Preflight = Parameters<typeof createAdmittedRegisteredSdkPreflight>[0];
type Runtime = Preflight['moon'] & {
  clientProgramModelResponseProfileTransportMatches(profile: unknown, ...limits: number[]): unknown;
  [name: string]: unknown;
};
// Unchecked views over the existing borrowed originals. Only the unchanged
// descriptor, frozen-field, Common and same-original checks below admit them.
interface ReadOriginal {bootstrap: unknown; nodeInstallation: {
  layout: {response_profile: unknown}; probability: unknown; installation?: unknown;
}}
interface Installation {sdk: {package_name: unknown; version: unknown; interface: unknown; lock_artifact_cid: unknown};
  endpoint: unknown; build_artifact_cid: unknown; http_method: unknown; streaming: unknown; completion_basis: unknown;
}
interface RawOriginal {profile: unknown; probability: unknown; installation: Installation}
interface Configuration {
  providerId: string; taskCid: string; promptCid: string; outputSchemaCid: string; promptPayloadWire: string;
  originalReadRecipe: ReadOriginal;
  rawCaptureSelection: RawOriginal; bindingOriginals: Readonly<Record<string, unknown>>;
  quantityCapacity: QuantityCapacity; projectionLimits: Preflight['projectionLimits'];
  requestLimits: RequestLimits; responseLimits: NonNullable<Preflight['responseLimits']>;
  physicalAcquisitionLimits: unknown;
  observeAt: Preflight['observeAt']; observeEgress: (facts: unknown) => unknown;
}
type Notification = {notify: NonNullable<Preflight['notify']>};
type Binder = NonNullable<Preflight['rawCaptureBinder']>;
interface Entry extends Readonly<Record<string, unknown>> {
  validatePrompt(task: unknown, selector: unknown, payload: unknown): boolean;
  physicalPreflight(request: unknown, notification: Notification, retainRawBinder: Binder,
    admittedProvider: unknown, structuredAdmission: unknown): unknown;
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
  if (!['clientProgramStartAdmittedStructuredSdkProjection',
    'clientProgramAdmittedStructuredSdkRouteMatches',
    'clientProgramModelStructuredRequestPlan',
    'clientProgramModelPhysicalSavedStructured',
    'clientProgramAdvanceOpenAIChatProjection',
    'clientProgramRetireOpenAIChatProjection',
    'clientProgramInstallAsyncModelProvider',
    'clientProgramModelRequestGeneration','clientProgramModelRequestPreflight',
    'clientProgramModelPhysicalCallForRequest',
    'clientProgramModelPhysicalPending','clientProgramModelPhysicalUnknown',
    'clientProgramModelResponseProfileTransportMatches'].every(name=>typeof moon?.[name]==='function')) {
    issue('OpenAIOriginalRuntimeUnavailable');
  }
};

// Borrow the verified Host route, profile and Read recipe. The selected
// physical transport stays under the original Call's funding and Entry.
export function createConfiguredUndiciRegisteredSdkRegistration(physical: unknown, timeouts: unknown,
  credentialBytes: number, registeredSdk: RegisteredSdk): Registration {
  const credential = registeredSdk?.credential ?? issue('RegisteredSdkPhysicalInstallationUnavailable');
  if (credentialBytes === undefined) issue('RegisteredSdkPhysicalInstallationUnavailable');
  const transport = originalLocalModelHttpTransport();
  const transportTimeouts = transport.fixedOriginalTransportTimeouts(timeouts);
  const config = snapshotData(physical,
    'bindingOriginals,observeAt,observeEgress,originalReadRecipe,outputSchemaCid,physicalAcquisitionLimits,projectionLimits,promptCid,promptPayloadWire,providerId,quantityCapacity,rawCaptureSelection,requestLimits,responseLimits,taskCid',
    'InvalidInstalledOpenAIChatConfiguration') as unknown as Configuration;
  const physicalAcquisitionLimits = transport.fixedOriginalAcquisitionLimits(config.physicalAcquisitionLimits);
  const {providerId,taskCid,promptCid,outputSchemaCid,promptPayloadWire,observeAt,observeEgress}=config;
  const {route}=registeredSdk;
  const {selector:modelSelector, modelId}=route;
  if (![providerId,modelSelector,modelId].every(text) ||
      ![taskCid,promptCid,outputSchemaCid].every(cid) ||
      typeof promptPayloadWire!=='string' ||
      ![observeAt,observeEgress].every(value=>typeof value==='function')) {
    issue('InvalidInstalledOpenAIChatConfiguration');
  }
  const endpointText = route.endpoint;
  let endpoint!: URL;
  try {endpoint=new URL(endpointText);}
  catch {issue('InvalidInstalledOpenAIChatEndpoint');}
  if (endpoint.href!==endpointText || endpoint.protocol!=='https:' ||
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
  const original=config.originalReadRecipe;
  const raw=config.rawCaptureSelection;
  if (!frozen(original) || !frozen(original.bootstrap) || !frozen(original.nodeInstallation) ||
      !frozen(original.nodeInstallation.layout) || !frozen(raw) ||
      !frozen(raw.installation) || !frozen(raw.installation.sdk)) {
    issue('OpenAIOriginalInstallationUnavailable');
  }
  const installation=raw.installation;
  const sdk=installation.sdk;
  const sdkMatches = route.providerId===providerId &&
    sdk.package_name===registeredSdk.sdkPackage && sdk.version===registeredSdk.sdkVersion &&
    sdk.lock_artifact_cid===registeredSdk.lockArtifactCid &&
    installation.build_artifact_cid===registeredSdk.adapterArtifactCid;
  if (raw.profile===undefined || raw.profile===null ||
      original.nodeInstallation.layout.response_profile!==raw.profile ||
      original.nodeInstallation.installation!==installation ||
      original.nodeInstallation.probability!==undefined || raw.probability!==undefined ||
      installation.endpoint!==endpoint.href || installation.http_method!=='POST' ||
      installation.streaming!==false || installation.completion_basis!=='generation_finish' ||
      !sdkMatches ||
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
    physicalFetch??=transport.createOriginalUndiciFetch({
      endpoint:endpoint.href,requestLimits,responseLimits,physicalAcquisitionLimits,transportTimeouts,
      registeredCredential:{...credential.transport,maxBytes:credentialBytes},
    });
    return [Object.freeze({providerId,entryPersistence:'async',registeredSdk,
      bindingOriginals:bindings,originalReadRecipe:original,
      rawCaptureSelection:raw,quantityCapacity:quantities,observeEgress,
      // Common has already admitted the exact Task/prompt dependency. This
      // comparator selects the installed interpretation, not a JS evaluator.
      validatePrompt:(task: unknown,selector: unknown,payload: unknown)=>task===taskCid &&
        selector===modelSelector && payload===promptPayloadWire,
      physicalPreflight(request: unknown, notification: Notification, retainRawBinder: Binder,
        admittedProvider: unknown, structuredAdmission: unknown) {
        if (typeof notification?.notify!=='function' || typeof retainRawBinder!=='function' ||
            admittedProvider===undefined) issue('OpenAIOriginalPhysicalContextUnavailable');
        if (structuredAdmission === undefined) issue('RegisteredSdkPhysicalInstallationUnavailable');
        return createAdmittedRegisteredSdkPreflight({moon,request,admittedProvider,
          registeredSdk,admission:structuredAdmission,
          taskCid,promptCid,outputSchemaCid,modelSelector,projectionLimits,
          fetch:physicalFetch,observeAt,notify:notification.notify,
          rawCaptureBinder:retainRawBinder,profile:raw.profile,installation,
          needsCredential: true,
          quantities:quantities.perAttempt,responseLimits,
          maxRequestBytes:requestLimits.maxBytes,
          maxHeaderBytes:requestLimits.maxHeaderBytes,maxHeaders:requestLimits.maxHeaders,
          checked(value: unknown) {
            if (runtimeIsOk(value)) return runtimeField(value, 0);
            issue('OpenAIOriginalCommonRefused');
          },
        } as unknown as Preflight).preflight;
      },
    })];
  };
}
