// Source-only consumer entry in the actual package self-reference scope.
// Not in the package files allowlist. No SDK/Provider call or secret read.
if (process.argv[2] === 'entry-unreachable') {
  console.log('unexpected-entry-import');
} else if (process.argv[2]?.startsWith('eager-')) {
  await import('../../adapters/host-node/infer-trusted-sdk-eager.fixture.mjs');
} else {
  if (process.argv[2] === 'import-window') {
    // An isolated synthetic child, never the operator's ambient environment.
    // A late import rejects this empty setting before bind/current could
    // observe restored absence. The real preload must initialize first.
    process.env.OPENAI_BASE_URL = '';
    try { await import('./_internal/openai-chat.mjs'); }
    finally { delete process.env.OPENAI_BASE_URL; }
  }
  await import('../../adapters/host-node/infer-trusted-sdk-static.fixture.mjs');
}
