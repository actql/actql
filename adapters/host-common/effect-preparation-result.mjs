import {checked} from './runtime-result.mjs';

const refusals = new WeakSet();

export const isEffectPreparationRefusal = error =>
  error !== null && typeof error === 'object' && refusals.has(error);

// Only use for a semantic check whose inputs have actually been observed.
// A checked ABI error alone says nothing about transport certainty. This
// marker neither grants dispatch nor proves physical stop or cleanup.
export function checkedEffectPreparation(result) {
  try {
    return checked(result);
  } catch (error) {
    if (result?.$tag === 0) refusals.add(error);
    throw error;
  }
}
