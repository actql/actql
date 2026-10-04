import {checked} from './runtime-result.mjs';

const refusals = new WeakSet();

export const isEffectPreparationRefusal = error =>
  error !== null && typeof error === 'object' && refusals.has(error);

// Only use for a semantic check whose inputs have actually been observed.
// A checked JS bridge error alone says nothing about transport certainty. This
// marker neither grants dispatch nor proves physical stop or cleanup.
export function checkedEffectPreparation(result) {
  try {
    return checked(result);
  } catch (error) {
    if (result?.$tag === 0) refusals.add(error);
    throw error;
  }
}

// Mark `error` as a definitive preparation refusal: a provider's refusal of a
// row that it decided from an observed reply before any send (for example a
// pre-send check that found the target is not what the Mapping writes).
// Transport failures, rate limits and other unobserved outcomes must not be
// marked. Like `checkedEffectPreparation`, this grants nothing.
export function refusedEffectPreparation(error) {
  if (error === null || typeof error !== 'object') {
    throw new TypeError('InvalidEffectPreparationRefusal');
  }
  refusals.add(error);
  return error;
}
