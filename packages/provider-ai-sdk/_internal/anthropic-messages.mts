import {createAnthropic} from '@ai-sdk/anthropic';
import {isDeepStrictEqual} from 'node:util';
import type {RegisteredRequestOptions, RegisteredRequestRoute, RegisteredSdk} from './model-port.mjs';

export const sdkProvider = 'anthropic.messages';
export const optionNamespace = 'anthropic';
export const optionSchema = Object.freeze({structuredOutputMode: Object.freeze(['outputFormat'])});
export const credentialBinding = Object.freeze({reference: 'ANTHROPIC_API_KEY', header: 'x-api-key',
  endpoint: 'https://api.anthropic.com/v1/messages', prefix: '', placeholder: 'actql-unbound-anthropic-key'});

export function createLanguageModel(factory: typeof createAnthropic, modelId: string,
  fetch: typeof globalThis.fetch, route: RegisteredRequestRoute): ReturnType<RegisteredSdk['createLanguageModel']> {
  if (factory !== createAnthropic || route.endpoint !== credentialBinding.endpoint ||
      route.apiMode !== 'messages' || modelId !== 'claude-sonnet-4-6') {
    throw new TypeError('InvalidRegisteredAnthropicMessages');
  }
  return factory({apiKey: credentialBinding.placeholder, fetch})(modelId);
}

export function verifyRequest(body: string, options: RegisteredRequestOptions, route: RegisteredRequestRoute,
  providerOptions: Readonly<{anthropic: {structuredOutputMode: string}}>) {
  const {prompt, responseFormat, temperature, topP, maxOutputTokens, seed} = options;
  // This admitted Messages configuration sends temperature. The SDK drops
  // topP in that mode, so admit only the neutral value and refuse a seed.
  if (topP !== 1 || seed !== undefined ||
      providerOptions.anthropic.structuredOutputMode !== 'outputFormat') return false;
  return isDeepStrictEqual(JSON.parse(body), {
    model: route.modelId, max_tokens: maxOutputTokens, temperature,
    system: [{type: 'text', text: prompt[0].content}],
    messages: [prompt[1]],
    output_config: {format: {type: 'json_schema', schema: responseFormat.schema}},
  });
}

export function readReportedUsage(body: unknown) {
  const usage = (body as {usage?: {input_tokens?: unknown; output_tokens?: unknown}} | undefined)?.usage;
  if (usage === null || typeof usage !== 'object') return undefined;
  const tokenCount = (value: unknown) => Number.isSafeInteger(value) && (value as number) >= 0 ? BigInt(value as number) : undefined;
  return {inputTokens: tokenCount(usage.input_tokens), outputTokens: tokenCount(usage.output_tokens)};
}

export function readReportedResponse(body: unknown) {
  if (body === null || typeof body !== 'object') return undefined;
  const reported = body as {
    model?: unknown; id?: unknown; stop_reason?: unknown;
  };
  return {model: reported.model, requestId: reported.id, finishReason: reported.stop_reason,
    outcome: reported.stop_reason === 'refusal' ? 'refusal' : undefined};
}
