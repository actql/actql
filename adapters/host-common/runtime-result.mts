// Pinned MoonBit compiler's JS representation of raised results. This adapter
// handles runtime results, not provider data.
import {runtimeIsOk, runtimeIsError, runtimeField} from './compiler-binding.generated.mjs';

// A static view for selected synchronous bindings. Generic checked() still
// exposes opaque data until its actual caller identifies the result family.
export type SynchronousRuntimeData = void | null | boolean | number | bigint | string |
  (object & Readonly<{then?: never}>);
export type SynchronousResultCheck = (result: unknown) => SynchronousRuntimeData;

export function checked(result: unknown): unknown {
  if (runtimeIsOk(result)) return runtimeField(result, 0);
  if (runtimeIsError(result)) {
    throw Object.assign(new Error('MoonBitHostFailure', {cause: runtimeField(result, 0)}), {code: 'MoonBitHostFailure'});
  }
  throw Object.assign(new Error('InvalidHostRuntimeResult'), {code: 'InvalidHostRuntimeResult'});
}
