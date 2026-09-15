// Test harness only: the Worker itself does not import this Node-side module.
// The pinned Miniflare exposes its V4 options converter as an official API.
import {Miniflare, convertV4MiniflareOptions} from 'miniflare';

export const runtimeProfile = Object.freeze({
  compatibilityDate: '2026-09-11',
  compatibilityFlags: ['no_nodejs_compat', 'no_nodejs_compat_v2'],
});

export function createTestRuntime(script, onOutbound = () => {}) {
  return new Miniflare(convertV4MiniflareOptions({
    modules: true,
    ...runtimeProfile,
    script,
    outboundService(request) {
      onOutbound(request);
      // No real network fallback, including for unknown destinations.
      return new Response('outbound network forbidden by conformance harness', {status: 503});
    },
  }));
}
