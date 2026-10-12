import {prepareOpenAIChatRequest} from './openai-chat.mjs';
import {isDeepStrictEqual} from 'node:util';

// Private original-request consumer. The trusted installation supplies its
// selector-to-model binding, endpoint, secret and admitted prompt/schema.
// Reading Task values does not authorize I/O or establish that installation.
export function prepareOriginalOpenAIChatRequest({moon, request, modelSelector,
  modelId, baseURL, apiKey, prompt, responseFormat, maxRequestBytes,
  maxHeaderBytes, maxHeaders, signal, notify, verifyRequest}) {
  const generation = moon.clientProgramModelRequestGeneration(request);
  if (generation === undefined || typeof modelSelector !== 'string' ||
      generation._0 !== modelSelector) {
    throw new TypeError('OpenAIOriginalGenerationUnavailable');
  }
  const exactInteger = (value, minimum) => typeof value === 'bigint' &&
    value >= minimum && value <= BigInt(Number.MAX_SAFE_INTEGER);
  // The pinned MoonBit JS Int64 ABI may expose negative values as their
  // unsigned 64-bit backing. Interpret that typed backing as signed before
  // the SDK Number check, without wrapping an out-of-domain carrier.
  const rawSeed = generation._4;
  const seed = typeof rawSeed === 'bigint' &&
      rawSeed >= -9_223_372_036_854_775_808n && rawSeed <= 18_446_744_073_709_551_615n
    ? BigInt.asIntN(64, rawSeed) : rawSeed;
  if (!Number.isFinite(generation._1) || !Number.isFinite(generation._2) ||
      !exactInteger(generation._3, 1n) ||
      seed !== undefined && !exactInteger(seed, -BigInt(Number.MAX_SAFE_INTEGER))) {
    // The selected SDK accepts Number, not arbitrary Int64. Do not round an
    // authored seed/token count or redefine the common Task's integer domain.
    throw new TypeError('OpenAIOriginalGenerationUnsupported');
  }
  const temperature = generation._1, topP = generation._2;
  const maxOutputTokens = Number(generation._3);
  return prepareOpenAIChatRequest({modelId, baseURL, apiKey,
    options: {prompt, responseFormat, temperature,
      topP, maxOutputTokens,
      ...(seed === undefined ? {} : {seed: Number(seed)})},
    maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify,
    ...(verifyRequest === undefined ? {} : {
      verifyRequest: body => verifyRequest(body, {
        model: modelId, temperature, top_p: topP,
        max_tokens: maxOutputTokens,
        ...(seed === undefined ? {} : {seed: Number(seed)}),
      }),
    })});
}

// Private installer consumer, not a public startup grant or schema factory.
// The original operation must fund all projection and SDK overlap first.
export function prepareAdmittedOpenAIChatRequest({moon, admittedProvider,
  request, taskCid, promptCid, outputSchemaCid, modelSelector, projectionLimits,
  ...installation}) {
  const projected = moon.clientProgramProjectOpenAIChatRequest(admittedProvider,
    request, projectionLimits.maxBytes, projectionLimits.maxNodes,
    projectionLimits.maxDepth, projectionLimits.maxFrames, projectionLimits.maxWork);
  if (projected?.$tag === 0) {
    throw new TypeError('OpenAIProjection:' +
      moon.clientProgramOpenAIChatProjectionIssueKind(projected._0));
  }
  if (projected?.$tag !== 1) throw new TypeError('OpenAIProjectionUnavailable');
  const value = projected._0;
  if (value._3 !== taskCid || value._4 !== promptCid ||
      value._5 !== outputSchemaCid || value._6 !== modelSelector) {
    throw new TypeError('OpenAIOriginalSchemaBindingMismatch');
  }
  const instructions = value._0, inputWire = value._1, schemaWire = value._2;
  const schema = JSON.parse(schemaWire);
  const prompt = [{role: 'system', content: instructions},
    {role: 'user', content: [{type: 'text', text: inputWire}]}];
  const responseFormat = {type: 'json', name: 'actql_output', schema};
  return prepareOriginalOpenAIChatRequest({...installation, moon, request,
    modelSelector, prompt, responseFormat,
    verifyRequest(body, generation) {
      // Do not parse/rebuild mapped data-text or normalize instructions. Only
      // the SDK request envelope and projected schema are compared as JSON.
      return isDeepStrictEqual(JSON.parse(body), {...generation,
        messages: [{role: 'system', content: instructions},
          {role: 'user', content: inputWire}],
        response_format: {type: 'json_schema', json_schema: {
          // Compare against original wire, not the tree handed to SDK code.
          // A normalizer mutating its argument cannot rewrite our expectation.
          schema: JSON.parse(schemaWire), strict: true, name: 'actql_output',
        }},
      });
    },
  });
}
