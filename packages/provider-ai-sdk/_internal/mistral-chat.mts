import {createMistral, type MistralProviderSettings} from '@ai-sdk/mistral';
import {isDeepStrictEqual} from 'node:util';

type Route = Readonly<{modelId: string; apiMode: string; endpoint: string}>;
type Model = ReturnType<ReturnType<typeof createMistral>['chat']>;
type CallOptions = Parameters<Model['doGenerate']>[0];

export const sdkProvider = 'mistral.chat';
export const optionNamespace = 'mistral';
export const optionSchema = Object.freeze({strictJsonSchema: Object.freeze([true])});
export const supportedModel = 'mistral-small-2603';
const baseURL = 'https://api.mistral.ai/v1';
export const credentialBinding = Object.freeze({
  reference: 'MISTRAL_API_KEY',
  header: 'authorization',
  endpoint: baseURL + '/chat/completions',
  prefix: 'Bearer ',
  placeholder: 'actql-unbound-mistral-key',
});

function selectedRoute(route: Route): boolean {
  return route.endpoint === credentialBinding.endpoint &&
    route.apiMode === 'chat_completions' &&
    route.modelId === supportedModel;
}

export function createLanguageModel(factory: typeof createMistral, modelId: string,
  fetch: NonNullable<MistralProviderSettings['fetch']>, route: Route): Model {
  if (factory !== createMistral || !selectedRoute(route) || modelId !== route.modelId) {
    throw new TypeError('InvalidRegisteredMistralChat');
  }
  return factory({baseURL, apiKey: credentialBinding.placeholder, fetch}).chat(modelId);
}

export function verifyRequest(wire: string, options: CallOptions, route: Route,
  providerOptions: CallOptions['providerOptions']): boolean {
  const {prompt, responseFormat, maxOutputTokens, temperature, topP, seed} = options;
  const [system, user] = prompt;
  if (!selectedRoute(route) || prompt.length !== 2 || system?.role !== 'system' ||
      user?.role !== 'user' || user.content.length !== 1 || user.content[0].type !== 'text' ||
      typeof maxOutputTokens !== 'number' || typeof temperature !== 'number' ||
      typeof topP !== 'number' || responseFormat?.type !== 'json' ||
      responseFormat.schema === undefined || typeof responseFormat.name !== 'string' ||
      responseFormat.description !== undefined ||
      !isDeepStrictEqual(providerOptions, {mistral: {strictJsonSchema: true}})) {
    return false;
  }
  return isDeepStrictEqual(JSON.parse(wire), {
    model: route.modelId, max_tokens: maxOutputTokens, temperature, top_p: topP,
    ...(seed === undefined ? {} : {random_seed: seed}),
    messages: [
      {role: 'system', content: system.content},
      {role: 'user', content: [{type: 'text', text: user.content[0].text}]},
    ],
    response_format: {type: 'json_schema',
      json_schema: {schema: responseFormat.schema, strict: true, name: responseFormat.name}},
  });
}

export function readReportedUsage(body: unknown): {inputTokens?: bigint; outputTokens?: bigint} | undefined {
  if (body === null || typeof body !== 'object' || !('usage' in body)) return undefined;
  const usage = body.usage;
  if (usage === null || typeof usage !== 'object') return undefined;
  const tokenCount = (value: unknown) =>
    typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? BigInt(value) : undefined;
  return {
    inputTokens: tokenCount('prompt_tokens' in usage ? usage.prompt_tokens : undefined),
    outputTokens: tokenCount('completion_tokens' in usage ? usage.completion_tokens : undefined),
  };
}
