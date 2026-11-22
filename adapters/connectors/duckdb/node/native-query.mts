// Trusted Host assembly only. This selects exactly two real row receipts;
// neither Program data nor ordinary Connector registration supplies the verifier.
import { runNativeAcquisition } from './native-acquisition.mjs';
import { runSettledQuery } from './settled-query.mjs';
import type {NativeAcquisitionPort} from './native-acquisition.mjs';
import type {PrepareQuery} from './settled-query.mjs';
import type {SourceAccounting, SourceLimits} from './source-acquisition.mjs';

export function runNativeQuery<Attempt, Observation, InputArgs extends unknown[], BoundInput>(
  grant: object, prepare: PrepareQuery<NativeAcquisitionPort, Attempt, Observation, InputArgs, BoundInput>,
  limits: SourceLimits, signal?: AbortSignal, accounting?: SourceAccounting,
) {
  return runSettledQuery(grant, prepare, limits, signal, runNativeAcquisition,
    (value, attempt) => value.validation.accepted === attempt
      && value.native.accepted === attempt, accounting);
}
