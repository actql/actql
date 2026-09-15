// Test harness only: the Worker itself does not import this Node-side module.
// The pinned Miniflare exposes its V4 options converter as an official API.
import {Miniflare, convertV4MiniflareOptions} from 'miniflare';

export const runtimeProfile = Object.freeze({
  compatibilityDate: '2026-09-11',
  compatibilityFlags: ['no_nodejs_compat', 'no_nodejs_compat_v2'],
});

export function createTestRuntime(script, {onOutbound = () => {}, expectedOutbound = 0} = {}) {
  if (!Number.isSafeInteger(expectedOutbound) || expectedOutbound < 0) {
    throw new TypeError('Expected outbound count must be a nonnegative integer');
  }
  let attempts = 0, disposal;
  const runtime = new Miniflare(convertV4MiniflareOptions({
    modules: true,
    ...runtimeProfile,
    script,
    outboundService(request) {
      attempts++;
      onOutbound(request);
      // No real network fallback, including for unknown destinations.
      return new Response('outbound network forbidden by conformance harness', {status: 503});
    },
  }));
  // Audit outside the Worker: catching a failed fetch cannot hide its attempt.
  // Always stop the runtime before reporting violations, including startup
  // failures. All tests use this same finalizer; intentional I/O opts in.
  return Object.freeze({
    get ready() { return runtime.ready; },
    dispatchFetch: (...args) => runtime.dispatchFetch(...args),
    get outboundAttempts() { return attempts; },
    dispose() {
      return disposal ??= (async () => {
        const errors = [];
        try { await runtime.dispose(); } catch (error) { errors.push(error); }
        if (attempts !== expectedOutbound) {
          const error = new Error(`UnexpectedOutbound: expected ${expectedOutbound}, observed ${attempts}`);
          error.code = 'UnexpectedOutbound';
          errors.push(error);
        }
        if (errors.length === 1) throw errors[0];
        if (errors.length) throw new AggregateError(errors, 'Runtime cleanup and outbound audit failed');
      })();
    },
  });
}
