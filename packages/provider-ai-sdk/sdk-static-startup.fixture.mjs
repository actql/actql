// Source-only consumer entry in the actual package self-reference scope.
// Not in the package files allowlist. No SDK/Provider call or secret read.
if (process.argv[2] === 'entry-unreachable') {
  console.log('unexpected-entry-import');
} else {
  if (process.argv[2] === 'import-window') {
    // An isolated synthetic child, never the operator's ambient environment.
    // A late import would validate this unsupported URL before bind/current
    // could observe the restored absence. The real preload must import first.
    process.env.OPENAI_BASE_URL = 'synthetic-invalid-relative-url';
    try { await import('./_internal/openai-chat.mjs'); }
    finally { delete process.env.OPENAI_BASE_URL; }
  }
  await import('../../adapters/host-node/infer-trusted-sdk-static.fixture.mjs');
}
