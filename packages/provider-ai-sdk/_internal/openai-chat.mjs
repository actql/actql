import {createOpenAI} from '@ai-sdk/openai';
import {interceptSdkRequest} from './intercepted-request.mjs';

// Private verified builder, never a caller's preconstructed model instance.
// The Host obtains current secrets through its existing authorized mechanism;
// do not accept endpoint or credentials from a Program or public Run value.
export function prepareOpenAIChatRequest({modelId, baseURL, apiKey, options,
  maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify}) {
  if (typeof modelId !== 'string' || modelId.length === 0 ||
      typeof baseURL !== 'string' || baseURL.endsWith('/') ||
      typeof apiKey !== 'string' || apiKey.length === 0 ||
      options === null || typeof options !== 'object' ||
      options.tools !== undefined || options.toolChoice !== undefined) {
    throw new TypeError('InvalidOpenAISdkPreparation');
  }
  // Common admission supplies bounded, mapped text-only options and the exact
  // supported schema. Preparation does not replace that checker with JS.
  return interceptSdkRequest({endpoint: `${baseURL}/chat/completions`,
    maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify,
    runSdk: (fetch, abortSignal) => createOpenAI({baseURL, apiKey, fetch})
      .chat(modelId).doGenerate({...options, abortSignal})});
}
