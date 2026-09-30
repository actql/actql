import { DuckDBTransportError } from './configuration.mjs';

// The pinned compiler exports typed raise as Result rather than a JS throw.
// Only fixed product runtime returns enter this JS bridge adapter, never provider data.
export function checked(result) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) throw new DuckDBTransportError('MoonBitHostFailure', { cause: result._0 });
  throw new DuckDBTransportError('InvalidHostRuntimeResult');
}
