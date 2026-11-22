import {runtimeField, runtimeIsError, runtimeIsOk} from './compiler-binding.generated.mjs';
import {prepareOpenAIChatRequest} from './openai-chat.mjs';
import {isDeepStrictEqual} from 'node:util';
import {createSdkModelPreflight, createSdkStructuredModelPreflight,
  originalSdkCallOptions, sdkProjectionBounds} from './model-port.mjs';

// Isolate this callback context from the original seven-material handoff.
// The original Read keeps this same expected wire until SDK/Read retirement.
function originalExpectedBodyVerifier(expectedWire) {
  if (typeof expectedWire !== 'string' || expectedWire.length === 0) {
    throw new TypeError('OpenAIExpectedRequestUnavailable');
  }
  return body => isDeepStrictEqual(JSON.parse(body), JSON.parse(expectedWire));
}

// Private original-request consumer. The trusted installation supplies its
// selector-to-model binding, endpoint, secret and admitted prompt/schema.
// Reading Task values does not authorize I/O or establish that installation.
export function prepareOriginalOpenAIChatRequest({moon, request, modelSelector,
  modelId, baseURL, apiKey, prompt, responseFormat, maxRequestBytes,
  maxHeaderBytes, maxHeaders, signal, notify, verifyRequest, structuredAdmission}) {
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
  ...installation}) {
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
  outputSchemaCid,modelSelector,...installation},value) {
  if (runtimeField(value, 3) !== taskCid || runtimeField(value, 4) !== promptCid ||
      runtimeField(value, 5) !== outputSchemaCid || runtimeField(value, 6) !== modelSelector) {
    throw new TypeError('OpenAIOriginalSchemaBindingMismatch');
  }
  const instructions = runtimeField(value, 0), inputWire = runtimeField(value, 1), schemaWire = runtimeField(value, 2);
  const verifyRequest = originalExpectedBodyVerifier(runtimeField(value, 7));
  const schema = JSON.parse(schemaWire);
  const prompt = [{role: 'system', content: instructions},
    {role: 'user', content: [{type: 'text', text: inputWire}]}];
  const responseFormat = {type: 'json', name: 'actql_output', schema};
  return prepareOriginalOpenAIChatRequest({...installation, moon, request,
    modelSelector, prompt, responseFormat,
    // Common owns every expected envelope rule. Mapped data text stays text.
    verifyRequest,
  });
}

// The pinned Chat SDK returns its parsed, unnormalized response as
// response.body. Its normalized usage may fill missing counters with zero.
function readOpenAIChatReportedUsage(body) {
  const reported = body?.usage;
  if (reported === null || typeof reported !== 'object') return undefined;
  const tokenCount = value => Number.isSafeInteger(value) && value >= 0
    ? BigInt(value) : undefined;
  return {
    inputTokens: tokenCount(reported.prompt_tokens),
    outputTokens: tokenCount(reported.completion_tokens),
  };
}

// Exact private builder for the existing physical preflight. Projection is a
// Common read-only child, not a JS schema evaluator or another execution owner.
// Installation must fund the child/callback/SDK overlap before calling this.
export function createAdmittedOpenAIChatPreflight({moon,admittedProvider,
  request,taskCid,promptCid,outputSchemaCid,modelSelector,projectionLimits,
  modelId,baseURL,apiKey,maxRequestBytes,maxHeaderBytes,maxHeaders,signal,
  notify,rawCaptureBinder,structuredAdmission,...port}) {
  const bounds=sdkProjectionBounds(projectionLimits,'InvalidOpenAIProjectionLimits');
  if (typeof moon.clientProgramStartOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramAdvanceOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramRetireOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramFinishOpenAIChatSdkV4Projection !== 'function') {
    throw new TypeError('OpenAIProjectionRuntimeUnavailable');
  }
  let cursor;
  let terminal=false;
  const progress={
    advance() {
      if (terminal) return {kind:'rejected'};
      if (signal?.aborted) { terminal=true;return {kind:'rejected'}; }
      // Let the existing port validate its callbacks before any child is
      // allocated. A constructor refusal must not lose an issued cursor.
      if (cursor===undefined) {
        cursor=port.checked(moon.clientProgramStartOpenAIChatProjection(
          admittedProvider,request,bounds.maxBytes,bounds.maxNodes,
          bounds.maxDepth,bounds.maxFrames,bounds.maxWork));
        return {kind:'pending'};
      }
      const value=port.checked(moon.clientProgramAdvanceOpenAIChatProjection(cursor));
      if (value===undefined) return {kind:'pending'};
      const sdkValue=port.checked(moon.clientProgramFinishOpenAIChatSdkV4Projection(
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
    : createSdkStructuredModelPreflight(options, structuredAdmission, readOpenAIChatReportedUsage);
}
