// Narrow Native recovery fixtures: no query_integration or runtime bridge build.
import {spawnSync} from 'node:child_process';
import {nativeCompletedRestorationBundle} from './native-completed-restoration-fixture.mjs';
import {mkdtempSync, mkdirSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
const consumerCustody = args[0] === '--consumer-custody';
if (consumerCustody) {
  args.shift();
  if (!process.env.ACTQL_TEST_DUCKDB_LIBRARY) {
    throw new Error('Consumer custody requires ACTQL_TEST_DUCKDB_LIBRARY');
  }
}
const parent = process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir();
mkdirSync(parent, {recursive: true});
const root = mkdtempSync(join(parent, 'actql-completed-restoration-'));
const bundle = nativeCompletedRestorationBundle();
for (const name of ['store', 'sqlite', 'bundles']) {
  mkdirSync(join(root, name), {mode: 0o700});
}
let passed = false;
try {
  const result = spawnSync(process.execPath, [
    'scripts/local-checks.mjs', 'test', 'moon', '--timeout-seconds', consumerCustody ? '180' : '300',
    '--', '--target', 'native',
    ...(consumerCustody ? ['--strip', 'src/platform_native/remote_resident_source_compute_tests']
      : ['src/platform_native/remote_standard_host/native_test']), ...args,
  ], {
    cwd: repositoryRoot,
    stdio: 'inherit',
    env: {
      ...process.env,
      ...(consumerCustody ? {
        ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS: '1',
        ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT: join(root, 'store'),
        ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: 'aarch64-apple-darwin',
      } : {}),
      ACTQL_TEST_NATIVE_STORE_ROOT: join(root, 'store'),
      ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: join(root, 'store'),
      ACTQL_TEST_NATIVE_SQLITE_ROOT: join(root, 'sqlite'),
      ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT: join(root, 'bundles'),
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY:
        process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
        (process.platform === 'darwin' ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0'),
      ACTQL_TEST_NATIVE_CRYPTO_LIBRARY:
        process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
        (process.platform === 'darwin' ?
          '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib' : 'libcrypto.so.3'),
      ...bundle,
    },
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`Native completed restoration failed: ${result.signal ?? result.status}`);
  }
  passed = true;
} finally {
  if (passed && process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
    rmSync(root, {recursive: true});
  } else {
    console.error(`Native completed restoration scratch retained: ${root}`);
  }
}
