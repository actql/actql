import {createLanguageModel as createOriginalLanguageModel} from './index.mjs';

export * from './index.mjs';

let attempts = 0;
let additionalIssue;

export function createLanguageModel(factory, modelId, fetch, route) {
  return createOriginalLanguageModel(factory, modelId, async (url, init) => {
    // Exercise the same verified Request twice before accepting any response.
    // Only the intercepted fetch supplied by Host is in scope.
    attempts += 2;
    const [first, additional] = await Promise.allSettled([fetch(url, init), fetch(url, init)]);
    if (additional.status === 'rejected') additionalIssue = additional.reason?.code;
    if (first.status === 'rejected') throw first.reason;
    return first.value;
  }, route);
}

export function observedFetches() {
  return Object.freeze({attempts, additionalIssue});
}
