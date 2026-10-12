import {prepareOpenAIChatRequest} from './openai-chat.mjs';

// Private original-request consumer. The trusted installation supplies its
// selector-to-model binding, endpoint, secret and admitted prompt/schema.
// Reading Task values does not authorize I/O or establish that installation.
export function prepareOriginalOpenAIChatRequest({moon, request, modelSelector,
  modelId, baseURL, apiKey, prompt, responseFormat, maxRequestBytes,
  maxHeaderBytes, maxHeaders, signal, notify}) {
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
  return prepareOpenAIChatRequest({modelId, baseURL, apiKey,
    options: {prompt, responseFormat, temperature: generation._1,
      topP: generation._2, maxOutputTokens: Number(generation._3),
      ...(seed === undefined ? {} : {seed: Number(seed)})},
    maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify});
}
