// Pinned MoonBit compiler's JS representation of raised results. This adapter
// handles runtime results, not provider data.
import {runtimeIsOk, runtimeIsError, runtimeField} from './compiler-binding.generated.mjs';

export function checked(result) {
  if (runtimeIsOk(result)) return runtimeField(result, 0);
  if (runtimeIsError(result)) {
    throw Object.assign(new Error('MoonBitHostFailure', {cause: runtimeField(result, 0)}), {code: 'MoonBitHostFailure'});
  }
  throw Object.assign(new Error('InvalidHostRuntimeResult'), {code: 'InvalidHostRuntimeResult'});
}
