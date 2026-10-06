// Narrow Native recovery fixtures: no query_integration or runtime bridge build.
import {spawnSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {mkdtempSync, mkdirSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const parent = process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir();
mkdirSync(parent, {recursive: true});
const root = mkdtempSync(join(parent, 'actql-completed-restoration-'));
const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const component = Buffer.from('native-runtime');
// Independently authored canonical fixture, admitted and verified by Native.
// Its target matches the opaque test component; no platform executable is run.
const body = JSON.stringify({
  bundle_name: 'native-runtime',
  components: [{bytes: String(component.length), cid: hash(component),
    role: 'runtime_executable'}],
  connector_registration: 'local',
  connector_revision: 'local/1',
  issuer_authority: 'bundle-authority-a',
  revision: 'native/1',
  strategy_revision: 'strategy/1',
  target_triple: 'aarch64-apple-darwin',
  version: 'actql-remote-runtime-bundle/0.1',
});
const cid = hash(body);
const keys = generateKeyPairSync('ed25519');
const signature = sign(null, Buffer.from(
  `actql-remote-runtime-bundle-signature/0.1\0${cid}\0${body}`,
), keys.privateKey).toString('base64url');
for (const name of ['store', 'sqlite', 'bundles']) {
  mkdirSync(join(root, name), {mode: 0o700});
}
let passed = false;
try {
  const result = spawnSync(process.execPath, [
    'scripts/local-checks.mjs', 'test', 'moon', '--timeout-seconds', '300',
    '--', '--target', 'native',
    'src/platform_native/remote_standard_host/native_test', ...process.argv.slice(2),
  ], {
    cwd: repositoryRoot,
    stdio: 'inherit',
    env: {
      ...process.env,
      ACTQL_TEST_NATIVE_STORE_ROOT: join(root, 'store'),
      ACTQL_TEST_NATIVE_SQLITE_ROOT: join(root, 'sqlite'),
      ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT: join(root, 'bundles'),
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY:
        process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
        (process.platform === 'darwin' ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0'),
      ACTQL_TEST_NATIVE_CRYPTO_LIBRARY:
        process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
        (process.platform === 'darwin' ?
          '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib' : 'libcrypto.so.3'),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
        keys.publicKey.export({type: 'spki', format: 'pem'}),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: body,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: cid,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: signature,
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
