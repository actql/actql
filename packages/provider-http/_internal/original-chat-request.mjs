import {runtimeField, runtimeIsOk} from './compiler-binding.generated.mjs';
// Private preparation consumer only. Common owns interpretation of the
// original Task, mapped input and strict schema. No SDK or vendor fetch runs.
export function prepareOriginalHttpChatRequest({moon, admittedProvider, request,
  modelId, taskCid, promptCid, outputSchemaCid, modelSelector, limits}) {
  if (typeof moon?.clientProgramProjectHTTPChatRequest !== 'function' ||
      typeof modelId !== 'string' || modelId.length === 0 ||
      limits === null || typeof limits !== 'object') {
    throw new TypeError('HTTPChatProjectionUnavailable');
  }
  const names = ['maxBytes', 'maxDepth', 'maxFrames', 'maxNodes', 'maxWork'];
  const descriptors = Object.getOwnPropertyDescriptors(limits);
  if (Reflect.ownKeys(descriptors).length !== names.length ||
      names.some(name => !descriptors[name]?.enumerable ||
        !Object.hasOwn(descriptors[name], 'value'))) {
    throw new TypeError('InvalidHTTPChatProjectionLimits');
  }
  const values = names.map(name => descriptors[name].value);
  if (values.some((value, index) => !Number.isSafeInteger(value) ||
      value < (names[index] === 'maxWork' ? 0 : 1) || value > 2_147_483_647)) {
    throw new TypeError('InvalidHTTPChatProjectionLimits');
  }
  const [maxBytes, maxDepth, maxFrames, maxNodes, maxWork] = values;
  const projected = moon.clientProgramProjectHTTPChatRequest(admittedProvider,
    request, modelId, maxBytes, maxNodes, maxDepth, maxFrames, maxWork);
  if (!runtimeIsOk(projected)) throw new TypeError('HTTPChatOriginalProjectionRefused');
  const value = runtimeField(projected, 0);
  if (runtimeField(value, 1) !== taskCid || runtimeField(value, 2) !== promptCid ||
      runtimeField(value, 3) !== outputSchemaCid || runtimeField(value, 4) !== modelSelector ||
      typeof runtimeField(value, 0) !== 'string') {
    throw new TypeError('HTTPChatOriginalBindingMismatch');
  }
  // This DATA view is neither nominal prepared transport nor permission.
  // Future physical preflight fixes headers/endpoint/egress separately and
  // uses the existing original Entry and saved-raw response Owner.
  return Object.freeze({body: runtimeField(value, 0)});
}
