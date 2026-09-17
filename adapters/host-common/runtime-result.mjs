// Pinned MoonBit raise ABI. This adapter handles runtime results, not provider data.
export function checked(result) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) {
    throw Object.assign(new Error('MoonBitHostFailure', {cause: result._0}), {code: 'MoonBitHostFailure'});
  }
  throw Object.assign(new Error('InvalidHostRuntimeResult'), {code: 'InvalidHostRuntimeResult'});
}
