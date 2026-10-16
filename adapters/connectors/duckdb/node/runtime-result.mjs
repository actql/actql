import {runtimeField, runtimeIsError, runtimeIsOk} from '../../../host-common/compiler-binding.generated.mjs';
import { DuckDBTransportError } from './configuration.mjs';

// The pinned compiler exports typed raise as Result rather than a JS throw.
// Only fixed product runtime returns enter this JS bridge adapter, never provider data.
export function checked(result) {
  if (runtimeIsOk(result)) return runtimeField(result, 0);
  if (runtimeIsError(result)) throw new DuckDBTransportError('MoonBitHostFailure', { cause: runtimeField(result, 0) });
  throw new DuckDBTransportError('InvalidHostRuntimeResult');
}
