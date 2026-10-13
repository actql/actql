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
  if (projected?.$tag !== 1) throw new TypeError('HTTPChatOriginalProjectionRefused');
  const value = projected._0;
  if (value._1 !== taskCid || value._2 !== promptCid ||
      value._3 !== outputSchemaCid || value._4 !== modelSelector ||
      typeof value._0 !== 'string') {
    throw new TypeError('HTTPChatOriginalBindingMismatch');
  }
  // This DATA view is neither nominal prepared transport nor permission.
  // Future physical preflight fixes headers/endpoint/egress separately and
  // uses the existing original Entry and saved-raw response Owner.
  return Object.freeze({body: value._0});
}
