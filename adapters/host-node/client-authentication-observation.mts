// Private Host instrumentation only. Never copy headers, request bodies, or
// these causes into public errors. An observer failure cannot grant access.
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';

export function observeClientAuthorizationFailure(observe: unknown, operation: unknown,
  boundary: unknown, cause: unknown) {
  const failure = Object.assign(new Error('ClientAuthorizationFault',
    {cause}), {code: 'ClientAuthorizationFault', operation, boundary});
  diagnosticObserver(observe)('client_authorization_failed',
    Object.freeze({failure}));
}
