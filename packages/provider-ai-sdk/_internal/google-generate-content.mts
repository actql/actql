import {createGoogle} from '@ai-sdk/google';
import {isDeepStrictEqual} from 'node:util';
import type {RegisteredRequestOptions, RegisteredRequestRoute, RegisteredSdk} from './model-port.mjs';

const supportedModel = 'gemini-2.5-flash';
export const sdkProvider = 'google.generative-ai';
export const optionNamespace = 'google';
export const optionSchema = Object.freeze({structuredOutputs: Object.freeze([true])});
export const credentialBinding = Object.freeze({reference: 'GOOGLE_GENERATIVE_AI_API_KEY', header: 'x-goog-api-key',
  endpoint: 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
  prefix: '', placeholder: 'actql-unbound-google-key'});

export function createLanguageModel(factory: typeof createGoogle, modelId: string,
  fetch: typeof globalThis.fetch, route: RegisteredRequestRoute): ReturnType<RegisteredSdk['createLanguageModel']> {
  if (factory !== createGoogle || route.endpoint !== credentialBinding.endpoint ||
      route.apiMode !== 'generate_content' || modelId !== supportedModel) {
    throw new TypeError('InvalidRegisteredGoogleGenerateContent');
  }
  return factory({apiKey: credentialBinding.placeholder, fetch})(modelId);
}

export function verifyRequest(body: string, options: RegisteredRequestOptions, _route: RegisteredRequestRoute,
  providerOptions: Readonly<{google: {structuredOutputs: boolean}}>) {
  const {prompt, responseFormat, temperature, topP, maxOutputTokens, seed} = options;
  if (seed !== undefined || providerOptions.google.structuredOutputs !== true) return false;
  return isDeepStrictEqual(JSON.parse(body), {
    generationConfig: {maxOutputTokens, temperature, topP, responseMimeType: 'application/json',
      responseJsonSchema: responseFormat.schema},
    contents: [{role: 'user', parts: [{text: prompt[1].content[0].text}]}],
    systemInstruction: {parts: [{text: prompt[0].content}]},
  });
}

function reportedCount(value: unknown) {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? BigInt(value as number) : undefined;
}

function reportedTotal(base: unknown, supplemental: unknown) {
  const count = reportedCount(base);
  const extra = supplemental === undefined ? 0n : reportedCount(supplemental);
  return count === undefined || extra === undefined ? undefined : count + extra;
}

export function readReportedUsage(body: unknown) {
  const usage = (body as {usageMetadata?: {promptTokenCount?: unknown; toolUsePromptTokenCount?: unknown;
    candidatesTokenCount?: unknown; thoughtsTokenCount?: unknown}} | undefined)?.usageMetadata;
  if (usage === null || typeof usage !== 'object') return undefined;
  return {inputTokens: reportedTotal(usage.promptTokenCount, usage.toolUsePromptTokenCount),
    outputTokens: reportedTotal(usage.candidatesTokenCount, usage.thoughtsTokenCount)};
}
