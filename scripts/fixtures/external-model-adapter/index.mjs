import {isDeepStrictEqual} from 'node:util';

const baseURL = 'https://api.openai.com/v1';
export const sdkProvider = 'openai.chat';
export const optionNamespace = 'openai';
export const optionSchema = Object.freeze({store: Object.freeze([false]),
  strictJsonSchema: Object.freeze([true])});
export const credentialBinding = Object.freeze({reference: 'OPENAI_API_KEY',
  header: 'authorization', endpoint: baseURL + '/chat/completions',
  prefix: 'Bearer ', placeholder: 'actql-external-adapter-unbound'});

export function createLanguageModel(factory, modelId, fetch, route) {
  if (route.endpoint !== credentialBinding.endpoint || route.apiMode !== 'chat_completions' ||
      route.modelId !== modelId) throw new TypeError('ExternalAdapterRouteChanged');
  return factory({baseURL, apiKey: credentialBinding.placeholder, fetch}).chat(modelId);
}

export function verifyRequest(wire, options, route, providerOptions) {
  const {prompt, responseFormat} = options;
  const value = JSON.parse(wire);
  const system = {role: 'system', content: prompt[0].content};
  const user = {role: 'user', content: prompt[1].content[0].text};
  const schema = {name: responseFormat.name, strict: true, schema: responseFormat.schema};
  return isDeepStrictEqual(value, {
    model: route.modelId,
    messages: [system, user],
    response_format: {type: 'json_schema', json_schema: schema},
    temperature: options.temperature,
    top_p: options.topP,
    max_tokens: options.maxOutputTokens,
    ...(options.seed === undefined ? {} : {seed: options.seed}),
    ...(providerOptions.openai.store === undefined ? {} : {store: providerOptions.openai.store}),
  });
}

export function readReportedUsage(body) {
  const tokenCount = value => Number.isSafeInteger(value) && value >= 0 ? BigInt(value) : undefined;
  if (body?.usage === null || typeof body?.usage !== 'object') return undefined;
  return {inputTokens: tokenCount(body.usage.prompt_tokens),
    outputTokens: tokenCount(body.usage.completion_tokens)};
}

export function readReportedResponse(body) {
  if (!Array.isArray(body?.choices) || body.choices.length !== 1) return undefined;
  return {model: body.model, requestId: body.id, finishReason: body.choices[0].finish_reason};
}
