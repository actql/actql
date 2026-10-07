import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
function child(code, cwd = root) {
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', code],
    {cwd, encoding: 'utf8', timeout: 30_000});
  assert.equal(result.status, 0, result.stdout + result.stderr);
}

test('ordinary Local imports and opaque DuckDB inspection load no physical runtime', () => {
  child(`
    import assert from 'node:assert/strict';
    import {registerHooks} from 'node:module';
    registerHooks({resolve(specifier, context, next) {
      const resolved = next(specifier, context);
      assert.equal(resolved.url.includes('node_modules/@duckdb/'), false);
      for (const name of ['host', 'session', 'physical-values', 'physical-appender', 'bounded-vector']) {
        assert.equal(resolved.url.endsWith('/duckdb/node/' + name + '.mjs'), false);
      }
      return resolved;
    }});
    const captured = await import('./adapters/host-node/captured-duckdb-source.mjs');
    await import('./adapters/host-node/installed-source.mjs');
    await import('./adapters/host-node/embedded-local.mjs');
    assert.throws(() => captured.capturedDuckDBConfiguration({}),
      {message: 'InstalledSourcePreparationMismatch'});
  `);
});

test('selected DuckDB reports an actually missing optional dependency', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-duckdb-missing-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  await copyFile(new URL('../connectors/duckdb/node/native-runtime.mjs', import.meta.url),
    join(directory, 'native-runtime.mjs'));
  child(`
    import assert from 'node:assert/strict';
    import {createRequire} from 'node:module';
    import {loadDuckDBNativeRuntime} from './native-runtime.mjs';
    assert.throws(() => createRequire(import.meta.url).resolve('@duckdb/node-api'),
      {code: 'MODULE_NOT_FOUND'});
    await assert.rejects(loadDuckDBNativeRuntime(), error => {
      assert.equal(error.code, 'DuckDBDependencyUnavailable');
      assert.equal(error.message.includes('install @duckdb/node-api@1.5.5-r.4'), true);
      assert.equal(error.cause.code, 'ERR_MODULE_NOT_FOUND');
      return true;
    });
  `, directory);
});
