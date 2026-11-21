import {runtimeField, runtimeIsError, runtimeIsOk} from './compiler-binding.generated.mjs';
import {clientValuesHostRenderStaticExplanation} from './dist/client_values_host_abi.js';

const fail = code => {throw Object.assign(new Error(code), {code});};

/** Present the already disclosed canonical static view without opening a Host. */
export function renderStaticExplanationNarrative(wire, locale) {
  if (typeof wire !== 'string' || (locale !== 'en' && locale !== 'ja')) {
    fail('InvalidStaticExplanationNarrative');
  }
  const result = clientValuesHostRenderStaticExplanation(wire, locale);
  if (runtimeIsError(result) && runtimeField(result, 0) === 1) {
    fail('StaticExplanationNarrativeLimit');
  }
  if (!runtimeIsOk(result)) fail('InvalidStaticExplanationNarrative');
  return JSON.parse(runtimeField(result, 0));
}
