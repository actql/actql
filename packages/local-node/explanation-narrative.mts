import {runtimeField, runtimeIsError, runtimeIsOk} from './adapters/host-common/compiler-binding.generated.mjs';
import {clientRenderStaticExplanationNarrative} from './_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

import type {StaticExplanationNarrative} from './explanation-narrative.d.ts';

const fail = (code: string): never => {throw Object.assign(new Error(code), {code});};

/** Present already disclosed canonical data through the installed Local runtime. */
export function renderStaticExplanationNarrative(wire: string, locale: 'en' | 'ja') {
  if (typeof wire !== 'string' || (locale !== 'en' && locale !== 'ja')) {
    fail('InvalidStaticExplanationNarrative');
  }
  const result = clientRenderStaticExplanationNarrative(wire, locale);
  if (runtimeIsError(result) && runtimeField(result, 0) === 1) {
    fail('StaticExplanationNarrativeLimit');
  }
  if (!runtimeIsOk(result)) fail('InvalidStaticExplanationNarrative');
  return JSON.parse(runtimeField(result, 0) as string) as StaticExplanationNarrative;
}
