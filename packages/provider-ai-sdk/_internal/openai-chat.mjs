import * as openai from '@ai-sdk/openai';
import * as providerUtils from '@ai-sdk/provider-utils';
import {isDeepStrictEqual} from 'node:util';
import {generateSdkLanguageModel, interceptSdkRequest, prepareRegisteredSdkLanguageModel} from './intercepted-request.mjs';
import {unboundOpenAICredential} from './original-undici-transport.mjs';

const createOpenAI=openai.createOpenAI;
// The actual builder's module originals, never caller DATA, a source hash or
// a numerical/dispatch grant. Existing Host custody selects their fixed static
// graph responsibility. Per-call factories, lazy/mutable state and all inputs
// remain separately funded; forgetting this borrowed shell is not module GC.
export const openAIChatStaticOriginals=Object.freeze({openai,providerUtils,createOpenAI});

export const sdkProvider = 'openai.chat';
export const optionNamespace = 'openai';
export const optionSchema = Object.freeze({store: Object.freeze([false]), strictJsonSchema: Object.freeze([true])});
export const credentialBinding = Object.freeze({reference: 'OPENAI_API_KEY', header: 'authorization',
  endpoint: 'https://api.openai.com/v1/chat/completions', prefix: 'Bearer ', placeholder: unboundOpenAICredential});

export function createLanguageModel(factory, modelId, fetch, route) {
  if (factory !== createOpenAI || route.endpoint !== credentialBinding.endpoint || route.apiMode !== 'chat_completions') {
    throw new TypeError('InvalidRegisteredOpenAIChat');
  }
  // Only the original transport binds the environment credential, after
  // approval and independently current configuration checks.
  return factory({baseURL: 'https://api.openai.com/v1', apiKey: unboundOpenAICredential, fetch}).chat(modelId);
}

export function verifyRequest(body, options, route, providerOptions) {
  // This adapter selects the native Chat request format. Common still checks
  // the original Plan, Entry and response independently of this comparison.
  const {prompt, responseFormat, temperature, topP, maxOutputTokens, seed} = options;
  return isDeepStrictEqual(JSON.parse(body), {model: route.modelId, temperature, top_p: topP,
    max_tokens: maxOutputTokens, ...(seed === undefined ? {} : {seed}),
    ...(providerOptions.openai.store === undefined ? {} : {store: providerOptions.openai.store}),
    messages: [prompt[0], {role: 'user', content: prompt[1].content[0].text}],
    response_format: {type: 'json_schema', json_schema: {name: responseFormat.name,
      schema: responseFormat.schema, strict: true}}});
}

export function readReportedUsage(body) {
  const reported = body?.usage;
  if (reported === null || typeof reported !== 'object') return undefined;
  const tokenCount = value => Number.isSafeInteger(value) && value >= 0 ? BigInt(value) : undefined;
  return {inputTokens: tokenCount(reported.prompt_tokens), outputTokens: tokenCount(reported.completion_tokens)};
}

export function readReportedResponse(body) {
  if (body === null || typeof body !== 'object') return undefined;
  const choice = Array.isArray(body.choices) && body.choices.length === 1 ? body.choices[0] : undefined;
  const refusal = choice?.message?.refusal;
  return {model: body.model, requestId: body.id, finishReason: choice?.finish_reason,
    metadataName: 'system_fingerprint', metadataValue: body.system_fingerprint,
    outcome: typeof refusal === 'string' && refusal.length > 0 ? 'refusal' : undefined};
}

// Private verified builder, never a caller's preconstructed model instance.
// The Host obtains current secrets through its existing authorized mechanism;
// do not accept endpoint or credentials from a Program or public Run value.
export function prepareOpenAIChatRequest({modelId, baseURL, apiKey, options,
  maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify, verifyRequest, registered}) {
  if (typeof modelId !== 'string' || modelId.length === 0 ||
      typeof baseURL !== 'string' || baseURL.endsWith('/') ||
      typeof apiKey !== 'string' || apiKey.length === 0 ||
      options === null || typeof options !== 'object' ||
      options.tools !== undefined || options.toolChoice !== undefined) {
    throw new TypeError('InvalidOpenAISdkPreparation');
  }
  // Common admission supplies bounded, mapped text-only options and the exact
  // supported schema. Preparation does not replace that checker with JS.
  const endpoint = baseURL + '/chat/completions';
  if (registered !== undefined) {
    return prepareRegisteredSdkLanguageModel({moon:registered.moon,
      admission:registered.admission,selector:registered.selector,modelId,
      apiMode:'chat_completions',sdkProvider:'openai.chat',endpoint,
      createLanguageModel: fetch => createOpenAI({baseURL,apiKey,fetch}).chat(modelId),
      options,verifyRequest,maxRequestBytes,maxHeaderBytes,maxHeaders,signal,notify});
  }
  return interceptSdkRequest({endpoint,maxRequestBytes,maxHeaderBytes,maxHeaders,signal,
    notify,verifyRequest,runSdk: (fetch,abortSignal) => generateSdkLanguageModel(
      createOpenAI({baseURL,apiKey,fetch}).chat(modelId),modelId,options,abortSignal)});
}
