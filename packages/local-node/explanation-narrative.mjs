import {runtimeField, runtimeIsError, runtimeIsOk} from './adapters/host-common/compiler-binding.generated.mjs';
import {clientRenderStaticExplanationNarrative} from './_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const fail = code => {throw Object.assign(new Error(code), {code});};

/** Present already disclosed canonical data through the installed Local runtime. */
export function renderStaticExplanationNarrative(wire, locale) {
  if (typeof wire !== 'string' || (locale !== 'en' && locale !== 'ja')) {
    fail('InvalidStaticExplanationNarrative');
  }
  const result = clientRenderStaticExplanationNarrative(wire, locale);
  if (runtimeIsError(result) && runtimeField(result, 0) === 1) {
    fail('StaticExplanationNarrativeLimit');
  }
  if (!runtimeIsOk(result)) fail('InvalidStaticExplanationNarrative');
  return JSON.parse(runtimeField(result, 0));
}
