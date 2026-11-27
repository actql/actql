import assert from 'node:assert/strict';
import {createOpenAI} from '@ai-sdk/openai';
import {sdkProvider, verifyRequest} from './_internal/openai-chat.mjs';
import {prepareRegisteredSdkLanguageModel} from './_internal/intercepted-request.mjs';

// The real SDK and selected request verifier use a fixture admission at this
// boundary. Actual Common capability tests install a separate nominal original.
export function prepareSelectedChat({baseURL, apiKey, modelId, selector, options, verify, ...limits}) {
  const admission = Object.freeze({});
  const route = {selector, modelId, apiMode: 'chat_completions', endpoint: baseURL + '/chat/completions'};
  const providerOptions = options.providerOptions ?? {openai: {}};
  return prepareRegisteredSdkLanguageModel({
    ...limits, ...route, admission, sdkProvider, options,
    moon: {clientProgramAdmittedStructuredSdkRouteMatches(...actual) {
      assert.deepEqual(actual, [admission, selector, modelId, route.apiMode, route.endpoint]);
      return true;
    }},
    createLanguageModel: fetch => createOpenAI({baseURL, apiKey, fetch}).chat(modelId),
    verifyRequest: body => verify === undefined
      ? verifyRequest(body, options, route, providerOptions)
      : verify(body),
  });
}

export function fixtureStructuredChatOptions(text, maxOutputTokens) {
  return {
    prompt: [{role: 'system', content: 'Return the fixture object.'},
      {role: 'user', content: [{type: 'text', text}]}],
    temperature: 0, topP: 1, maxOutputTokens,
    responseFormat: {type: 'json', name: 'fixture', schema: {
      type: 'object', properties: {}, additionalProperties: false,
    }},
  };
}
