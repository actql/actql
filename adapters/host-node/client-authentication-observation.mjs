// Private Host instrumentation only. Never copy headers, request bodies, or
// these causes into public errors. An observer failure cannot grant access.
export async function observeClientAuthorizationFailure(observe, operation,
  boundary, cause) {
  const failure = Object.assign(new Error('ClientAuthorizationFault',
    {cause}), {code: 'ClientAuthorizationFault', operation, boundary});
  try {
    await observe?.('client_authorization_failed', Object.freeze({failure}));
  } catch {
    // Diagnostics are not an authorization decision or a public response.
  }
}
