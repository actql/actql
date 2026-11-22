import {runtimeField, runtimeIsError, runtimeIsOk} from './compiler-binding.generated.mjs';
import {prepareOpenAIChatRequest, readReportedUsage} from './openai-chat.mjs';
import {isDeepStrictEqual} from 'node:util';
import {createSdkModelPreflight, createSdkStructuredModelPreflight,
  originalSdkCallOptions, sdkProjectionBounds} from './model-port.mjs';

type BuilderOptions = Parameters<typeof prepareOpenAIChatRequest>[0];
type SdkCallOptions = BuilderOptions['options'];
type InstallationOptions = Omit<BuilderOptions, 'options' | 'verifyRequest'>;
type PhysicalOptions = Parameters<typeof createSdkModelPreflight>[0];
type PhysicalRuntime = PhysicalOptions['moon'];
interface OriginalRuntime {
  clientProgramModelRequestGeneration(request: unknown): unknown;
  clientProgramAdmittedStructuredSdkRouteMatches?(admission: unknown, selector: string,
    modelId: string, apiMode: string, endpoint: string): unknown;
}
interface AdmittedRuntime extends OriginalRuntime {
  clientProgramProjectOpenAIChatSdkV4Request(provider: unknown, request: unknown,
    modelId: string, maxRequestBytes: number, maxBytes: number, maxNodes: number,
    maxDepth: number, maxFrames: number, maxWork: number): unknown;
  clientProgramOpenAIChatProjectionIssueKind(issue: unknown): unknown;
}
interface ProjectionRuntime extends OriginalRuntime, PhysicalRuntime {
  clientProgramStartOpenAIChatProjection(provider: unknown, request: unknown,
    maxBytes: number, maxNodes: number, maxDepth: number, maxFrames: number, maxWork: number): unknown;
  clientProgramAdvanceOpenAIChatProjection(cursor: unknown): unknown;
  clientProgramRetireOpenAIChatProjection(cursor: unknown): unknown;
  clientProgramFinishOpenAIChatSdkV4Projection(cursor: unknown, modelId: string, maxRequestBytes: number): unknown;
}
interface ProjectionBounds {maxBytes: number; maxDepth: number; maxFrames: number; maxNodes: number; maxWork: number}
interface OriginalBinding {request: unknown; taskCid: string; promptCid: string;
  outputSchemaCid: string; modelSelector: string}
type OriginalInput = InstallationOptions & {moon: OriginalRuntime; request: unknown;
  modelSelector: string; prompt: SdkCallOptions['prompt']; responseFormat: SdkCallOptions['responseFormat'];
  verifyRequest?: BuilderOptions['verifyRequest']; structuredAdmission?: unknown};
type ProjectedInput = InstallationOptions & OriginalBinding & {moon: OriginalRuntime; structuredAdmission?: unknown};
type AdmittedInput = ProjectedInput & {moon: AdmittedRuntime; admittedProvider: unknown; projectionLimits: ProjectionBounds};
type PreflightInput = Omit<PhysicalOptions, 'moon'> & ProjectedInput & {
  moon: ProjectionRuntime; admittedProvider: unknown; projectionLimits: ProjectionBounds;
};

// Isolate this callback context from the original seven-material handoff.
// The original Read keeps this same expected wire until SDK/Read retirement.
function originalExpectedBodyVerifier(expectedWire: unknown) {
  if (typeof expectedWire !== 'string' || expectedWire.length === 0) {
    throw new TypeError('OpenAIExpectedRequestUnavailable');
  }
  return (body: string) => isDeepStrictEqual(JSON.parse(body), JSON.parse(expectedWire));
}

// Private original-request consumer. The trusted installation supplies its
// selector-to-model binding, endpoint, secret and admitted prompt/schema.
// Reading Task values does not authorize I/O or establish that installation.
export function prepareOriginalOpenAIChatRequest({moon, request, modelSelector,
  modelId, baseURL, apiKey, prompt, responseFormat, maxRequestBytes,
  maxHeaderBytes, maxHeaders, signal, notify, verifyRequest, structuredAdmission}: OriginalInput) {
  const generation = moon.clientProgramModelRequestGeneration(request);
  if (generation === undefined || typeof modelSelector !== 'string' ||
      runtimeField(generation, 0) !== modelSelector) {
    throw new TypeError('OpenAIOriginalGenerationUnavailable');
  }
  return prepareOpenAIChatRequest({modelId, baseURL, apiKey,
    options: originalSdkCallOptions(generation, prompt, responseFormat, 'OpenAIOriginalGenerationUnsupported'),
    maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify,
    ...(structuredAdmission === undefined ? {} : {registered: {moon,
      admission: structuredAdmission, selector: modelSelector}}),
    ...(verifyRequest === undefined ? {} : {verifyRequest})});
}

// Private installer consumer, not a public startup grant or schema factory.
// The original operation must fund all projection and SDK overlap first.
export function prepareAdmittedOpenAIChatRequest({moon, admittedProvider,
  request, taskCid, promptCid, outputSchemaCid, modelSelector, projectionLimits,
  ...installation}: AdmittedInput) {
  const projected = moon.clientProgramProjectOpenAIChatSdkV4Request(admittedProvider,
    request, installation.modelId, installation.maxRequestBytes, projectionLimits.maxBytes, projectionLimits.maxNodes,
    projectionLimits.maxDepth, projectionLimits.maxFrames, projectionLimits.maxWork);
  if (runtimeIsError(projected)) {
    throw new TypeError('OpenAIProjection:' +
      moon.clientProgramOpenAIChatProjectionIssueKind(runtimeField(projected, 0)));
  }
  if (!runtimeIsOk(projected)) throw new TypeError('OpenAIProjectionUnavailable');
  return prepareProjectedOriginal({...installation,moon,request,taskCid,
    promptCid,outputSchemaCid,modelSelector},runtimeField(projected, 0));
}

function prepareProjectedOriginal({moon,request,taskCid,promptCid,
  outputSchemaCid,modelSelector,...installation}: ProjectedInput, value: unknown) {
  if (runtimeField(value, 3) !== taskCid || runtimeField(value, 4) !== promptCid ||
      runtimeField(value, 5) !== outputSchemaCid || runtimeField(value, 6) !== modelSelector) {
    throw new TypeError('OpenAIOriginalSchemaBindingMismatch');
  }
  const instructions = runtimeField(value, 0) as string, inputWire = runtimeField(value, 1) as string, schemaWire = runtimeField(value, 2) as string;
  const verifyRequest = originalExpectedBodyVerifier(runtimeField(value, 7));
  const schema = JSON.parse(schemaWire) as Extract<NonNullable<SdkCallOptions['responseFormat']>, {type: 'json'}>['schema'];
  const prompt: SdkCallOptions['prompt'] = [{role: 'system', content: instructions},
    {role: 'user', content: [{type: 'text', text: inputWire}]}];
  const responseFormat: SdkCallOptions['responseFormat'] = {type: 'json', name: 'actql_output', schema};
  return prepareOriginalOpenAIChatRequest({...installation, moon, request,
    modelSelector, prompt, responseFormat,
    // Common owns every expected envelope rule. Mapped data text stays text.
    verifyRequest,
  });
}

// Exact private builder for the existing physical preflight. Projection is a
// Common read-only child, not a JS schema evaluator or another execution owner.
// Installation must fund the child/callback/SDK overlap before calling this.
export function createAdmittedOpenAIChatPreflight({moon,admittedProvider,
  request,taskCid,promptCid,outputSchemaCid,modelSelector,projectionLimits,
  modelId,baseURL,apiKey,maxRequestBytes,maxHeaderBytes,maxHeaders,signal,
  notify,rawCaptureBinder,structuredAdmission,...port}: PreflightInput): ReturnType<typeof createSdkModelPreflight> {
  const bounds=sdkProjectionBounds(projectionLimits,'InvalidOpenAIProjectionLimits');
  if (typeof moon.clientProgramStartOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramAdvanceOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramRetireOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramFinishOpenAIChatSdkV4Projection !== 'function') {
    throw new TypeError('OpenAIProjectionRuntimeUnavailable');
  }
  let cursor: unknown;
  let terminal=false;
  const progress={
    advance() {
      if (terminal) return {kind:'rejected'};
      if (signal?.aborted) { terminal=true;return {kind:'rejected'}; }
      // Let the existing port validate its callbacks before any child is
      // allocated. A constructor refusal must not lose an issued cursor.
      if (cursor===undefined) {
        cursor=port.checked!(moon.clientProgramStartOpenAIChatProjection(
          admittedProvider,request,bounds.maxBytes,bounds.maxNodes,
          bounds.maxDepth,bounds.maxFrames,bounds.maxWork));
        return {kind:'pending'};
      }
      const value=port.checked!(moon.clientProgramAdvanceOpenAIChatProjection(cursor));
      if (value===undefined) return {kind:'pending'};
      const sdkValue=port.checked!(moon.clientProgramFinishOpenAIChatSdkV4Projection(
        cursor,modelId,maxRequestBytes));
      terminal=true;
      // The immutable result escapes separately. Retire before creating any
      // SDK Promise so a retirement failure cannot orphan that new handle.
      moon.clientProgramRetireOpenAIChatProjection(cursor);
      cursor=undefined;
      const preparation=prepareProjectedOriginal({moon,request,taskCid,promptCid,
        outputSchemaCid,modelSelector,modelId,baseURL,apiKey,maxRequestBytes,
        maxHeaderBytes,maxHeaders,signal,notify,structuredAdmission},sdkValue);
      return {kind:'ready',preparation};
    },
    cleanup() {
      if (cursor!==undefined) {
        moon.clientProgramRetireOpenAIChatProjection(cursor);
        cursor=undefined;
      }
      terminal=true;
      return true;
    },
  };
  const options = {...port,moon,request,notify,preparationProgress:progress,
    ...(rawCaptureBinder === undefined ? {} : {rawCaptureBinder})};
  return structuredAdmission === undefined ? createSdkModelPreflight(options)
    : createSdkStructuredModelPreflight(options as unknown as Parameters<typeof createSdkStructuredModelPreflight>[0],
      structuredAdmission, readReportedUsage);
}
