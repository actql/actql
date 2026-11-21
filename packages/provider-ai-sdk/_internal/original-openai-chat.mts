import {runtimeField, runtimeIsError, runtimeIsOk} from './compiler-binding.generated.mjs';
import {prepareOpenAIChatRequest} from './openai-chat.mjs';
import {isDeepStrictEqual} from 'node:util';
import {createSdkModelPreflight} from './model-port.mjs';

type BuilderOptions = Parameters<typeof prepareOpenAIChatRequest>[0];
type SdkCallOptions = BuilderOptions['options'];
type InstallationOptions = Omit<BuilderOptions, 'options' | 'verifyRequest'>;
type PhysicalOptions = Parameters<typeof createSdkModelPreflight>[0];
type PhysicalRuntime = PhysicalOptions['moon'];
interface OriginalRuntime {
  clientProgramModelRequestGeneration(request: unknown): unknown;
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
  verifyRequest?: BuilderOptions['verifyRequest']};
type ProjectedInput = InstallationOptions & OriginalBinding & {moon: OriginalRuntime};
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
  maxHeaderBytes, maxHeaders, signal, notify, verifyRequest}: OriginalInput) {
  const generation = moon.clientProgramModelRequestGeneration(request);
  if (generation === undefined || typeof modelSelector !== 'string' ||
      runtimeField(generation, 0) !== modelSelector) {
    throw new TypeError('OpenAIOriginalGenerationUnavailable');
  }
  const exactInteger = (value: unknown, minimum: bigint): value is bigint => typeof value === 'bigint' &&
    value >= minimum && value <= BigInt(Number.MAX_SAFE_INTEGER);
  // The pinned MoonBit JS Int64 ABI may expose negative values as their
  // unsigned 64-bit backing. Interpret that typed backing as signed before
  // the SDK Number check, without wrapping an out-of-domain carrier.
  const rawSeed = runtimeField(generation, 4);
  const seed = typeof rawSeed === 'bigint' &&
      rawSeed >= -9_223_372_036_854_775_808n && rawSeed <= 18_446_744_073_709_551_615n
    ? BigInt.asIntN(64, rawSeed) : rawSeed;
  if (!Number.isFinite(runtimeField(generation, 1)) || !Number.isFinite(runtimeField(generation, 2)) ||
      !exactInteger(runtimeField(generation, 3), 1n) ||
      seed !== undefined && !exactInteger(seed, -BigInt(Number.MAX_SAFE_INTEGER))) {
    // The selected SDK accepts Number, not arbitrary Int64. Do not round an
    // authored seed/token count or redefine the common Task's integer domain.
    throw new TypeError('OpenAIOriginalGenerationUnsupported');
  }
  const temperature = runtimeField(generation, 1) as number, topP = runtimeField(generation, 2) as number;
  const maxOutputTokens = Number(runtimeField(generation, 3));
  return prepareOpenAIChatRequest({modelId, baseURL, apiKey,
    options: {prompt, responseFormat, temperature,
      topP, maxOutputTokens,
      ...(seed === undefined ? {} : {seed: Number(seed)})},
    maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify,
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
  notify,rawCaptureBinder,...port}: PreflightInput): ReturnType<typeof createSdkModelPreflight> {
  const fields=['maxBytes','maxDepth','maxFrames','maxNodes','maxWork'] as const;
  if (projectionLimits===null || typeof projectionLimits!=='object' ||
      Array.isArray(projectionLimits) ||
      Object.keys(projectionLimits).sort().join(',')!==fields.join(',') ||
      fields.some(name=>!Number.isSafeInteger(projectionLimits[name]) ||
        projectionLimits[name]<(name==='maxWork'?0:1) ||
        projectionLimits[name]>2_147_483_647)) {
    throw new TypeError('InvalidOpenAIProjectionLimits');
  }
  const bounds=Object.freeze({...projectionLimits});
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
        maxHeaderBytes,maxHeaders,signal,notify},sdkValue);
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
  return createSdkModelPreflight({...port,moon,request,notify,preparationProgress:progress,
    ...(rawCaptureBinder === undefined ? {} : {rawCaptureBinder})});
}
