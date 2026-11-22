import {createGoogle} from '@ai-sdk/google';
import {isDeepStrictEqual} from 'node:util';

const supportedModel = 'gemini-2.5-flash';
export const sdkProvider = 'google.generative-ai';
export const optionNamespace = 'google';
export const optionSchema = Object.freeze({structuredOutputs: Object.freeze([true])});
export const credentialBinding = Object.freeze({reference: 'GOOGLE_GENERATIVE_AI_API_KEY', header: 'x-goog-api-key',
  endpoint: 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
  prefix: '', placeholder: 'actql-unbound-google-key'});

export function createLanguageModel(factory, modelId, fetch, route) {
  if (factory !== createGoogle || route.endpoint !== credentialBinding.endpoint ||
      route.apiMode !== 'generate_content' || modelId !== supportedModel) {
    throw new TypeError('InvalidRegisteredGoogleGenerateContent');
  }
  return factory({apiKey: credentialBinding.placeholder, fetch})(modelId);
}

export function verifyRequest(body, options, _route, providerOptions) {
  const {prompt, responseFormat, temperature, topP, maxOutputTokens, seed} = options;
  if (seed !== undefined || providerOptions.google.structuredOutputs !== true) return false;
  return isDeepStrictEqual(JSON.parse(body), {
    generationConfig: {maxOutputTokens, temperature, topP, responseMimeType: 'application/json',
      responseJsonSchema: responseFormat.schema},
    contents: [{role: 'user', parts: [{text: prompt[1].content[0].text}]}],
    systemInstruction: {parts: [{text: prompt[0].content}]},
  });
}

function reportedCount(value) {
  return Number.isSafeInteger(value) && value >= 0 ? BigInt(value) : undefined;
}

function reportedTotal(base, supplemental) {
  const count = reportedCount(base);
  const extra = supplemental === undefined ? 0n : reportedCount(supplemental);
  return count === undefined || extra === undefined ? undefined : count + extra;
}

export function readReportedUsage(body) {
  const usage = body?.usageMetadata;
  if (usage === null || typeof usage !== 'object') return undefined;
  return {inputTokens: reportedTotal(usage.promptTokenCount, usage.toolUsePromptTokenCount),
    outputTokens: reportedTotal(usage.candidatesTokenCount, usage.thoughtsTokenCount)};
}
