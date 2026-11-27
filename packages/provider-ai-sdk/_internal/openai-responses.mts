import {createOpenAI} from '@ai-sdk/openai';
import {isDeepStrictEqual} from 'node:util';
import type {RegisteredRequestOptions, RegisteredRequestRoute} from './model-port.mjs';
import {unboundOpenAICredential} from './original-undici-transport.mjs';

export const sdkProvider = 'openai.responses';
export const optionNamespace = 'openai';
export const optionSchema = Object.freeze({store: Object.freeze([false]), strictJsonSchema: Object.freeze([true])});
const endpoint = 'https://api.openai.com/v1/responses';
const supportedModel = 'gpt-4.1-mini';

export const credentialBinding = Object.freeze({reference: 'OPENAI_API_KEY', header: 'authorization',
  endpoint, prefix: 'Bearer ', placeholder: unboundOpenAICredential});

function matchesRoute(modelId: string, route: RegisteredRequestRoute) {
  return modelId === supportedModel && route.modelId === modelId &&
    route.apiMode === 'responses' && route.endpoint === endpoint;
}

export function createLanguageModel(factory: typeof createOpenAI, modelId: string,
  fetch: typeof globalThis.fetch, route: RegisteredRequestRoute) {
  if (factory !== createOpenAI || !matchesRoute(modelId, route)) {
    throw new TypeError('InvalidRegisteredOpenAIResponses');
  }
  return factory({baseURL: 'https://api.openai.com/v1', apiKey: unboundOpenAICredential, fetch}).responses(modelId);
}

export function verifyRequest(wire: string, options: RegisteredRequestOptions, route: RegisteredRequestRoute,
  providerOptions: Readonly<{openai?: {store?: boolean; strictJsonSchema?: boolean}}>) {
  const {prompt, responseFormat, temperature, topP, maxOutputTokens, seed} = options;
  if (!matchesRoute(route.modelId, route) || seed !== undefined || providerOptions.openai?.store !== false) return false;
  // The same Common projection gives the SDK and this verifier the original
  // system/user text, strict output schema and bounded generation parameters.
  return isDeepStrictEqual(JSON.parse(wire), {model: route.modelId,
    input: [prompt[0], {role: 'user', content: [{type: 'input_text', text: prompt[1].content[0].text}]}],
    ...(temperature === undefined ? {} : {temperature}),
    ...(topP === undefined ? {} : {top_p: topP}),
    ...(maxOutputTokens === undefined ? {} : {max_output_tokens: maxOutputTokens}), store: false,
    text: {format: {type: 'json_schema', strict: true, name: responseFormat.name, schema: responseFormat.schema}}});
}

export function readReportedUsage(body: unknown) {
  const usage = (body as {usage?: {input_tokens?: unknown; output_tokens?: unknown}} | null)?.usage;
  if (usage === null || typeof usage !== 'object') return undefined;
  const count = (value: unknown) => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
    ? BigInt(value) : undefined;
  return {inputTokens: count(usage.input_tokens), outputTokens: count(usage.output_tokens)};
}

export function readReportedResponse(body: unknown) {
  if (body === null || typeof body !== 'object') return undefined;
  const reported = body as {id?: unknown; model?: unknown; status?: unknown;
    incomplete_details?: {reason?: unknown};
    output?: readonly {type?: unknown; role?: unknown;
      content?: readonly {type?: unknown; refusal?: unknown; text?: unknown}[]}[]};
  const incomplete = reported.status === 'incomplete' ? reported.incomplete_details?.reason : undefined;
  const message = Array.isArray(reported.output) && reported.output.length === 1 ? reported.output[0] : undefined;
  const content = message?.type === 'message' && message.role === 'assistant' &&
    Array.isArray(message.content) && message.content.length === 1 ? message.content[0] : undefined;
  let outcome = 'other';
  if (incomplete === 'max_output_tokens') outcome = 'length';
  else if (incomplete === 'content_filter') outcome = 'content-filter';
  else if (reported.status === 'completed' && reported.incomplete_details == null) {
    if (content?.type === 'refusal' && typeof content.refusal === 'string' && content.refusal.length > 0) {
      outcome = 'refusal';
    } else if (content?.type === 'output_text' && typeof content.text === 'string') outcome = 'stop';
  }
  return {model: reported.model, requestId: reported.id, finishReason: incomplete ?? reported.status, outcome};
}
