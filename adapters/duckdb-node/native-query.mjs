// Trusted Host assembly only. This selects exactly two real row receipts;
// neither Program data nor ordinary Connector registration supplies the verifier.
import { runNativeAcquisition } from './native-acquisition.mjs';
import { runSettledQuery } from './settled-query.mjs';

export function runNativeQuery(grant, prepare, limits, signal) {
  return runSettledQuery(grant, prepare, limits, signal, runNativeAcquisition,
    (value, attempt) => value.validation.accepted === attempt
      && value.native.accepted === attempt);
}
