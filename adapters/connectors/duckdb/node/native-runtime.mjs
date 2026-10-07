// Only an explicitly selected DuckDB installation crosses this boundary.
// Configuration, capacity and captured-handle inspection remain dependency-free.
export async function loadDuckDBNativeRuntime() {
  try {
    await import('@duckdb/node-api');
  } catch (cause) {
    if (cause?.code !== 'ERR_MODULE_NOT_FOUND' ||
        !cause.message.startsWith("Cannot find package '@duckdb/node-api'")) {
      throw cause;
    }
    throw Object.assign(new Error(
      'DuckDBDependencyUnavailable: install @duckdb/node-api@1.5.5-r.4 ' +
      'to use the selected DuckDB installation', {cause}),
    {code: 'DuckDBDependencyUnavailable'});
  }
  const [host, session] = await Promise.all([
    import('./host.mjs'), import('./session.mjs'),
  ]);
  return {host, session};
}
