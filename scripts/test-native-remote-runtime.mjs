import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {signRemoteRuntimeBundle} from
  '../adapters/site-node/remote-bundle-signature.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const scratchParent = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchParent !== 'string' || scratchParent.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchParent, {recursive: true});
const root = await mkdtemp(join(scratchParent, 'native-remote-runtime-'));
const storeRoot = join(root, 'store');
const agentRoot = join(root, 'agent');
await mkdir(storeRoot, {recursive: true});
await mkdir(agentRoot, {recursive: true});

const moon = join(process.env.MOON_HOME ?? '', 'bin', 'moon');
const cryptoLibrary = process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
  (process.platform === 'darwin'
    ? [
        '/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib',
        '/usr/local/opt/openssl@3/lib/libcrypto.3.dylib',
      ].find(existsSync) ?? 'libcrypto.3.dylib'
    : 'libcrypto.so.3');
const sqliteLibrary = process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
  (process.platform === 'darwin'
    ? '/usr/lib/libsqlite3.dylib'
    : 'libsqlite3.so.0');
const targetTriple = process.platform === 'darwin' && process.arch === 'arm64'
  ? 'aarch64-apple-darwin'
  : process.platform === 'linux' && process.arch === 'x64'
    ? 'x86_64-unknown-linux-gnu'
    : undefined;
if (targetTriple === undefined) {
  throw new Error(
    `unsupported native runtime test target ${process.platform}/${process.arch}`,
  );
}

try {
  execFileSync(moon, [
    'build', '--target', 'js', '--release', 'src/connectors_builtin_node',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  const moonModule = await import(pathToFileURL(join(
    repositoryRoot,
    '_build/js/release/build/connectors_builtin_node/' +
      'connectors_builtin_node.js',
  )).href);
  const control = runtimeCore(moonModule).remoteBundleControl;
  const keys = generateKeyPairSync('ed25519');
  const component = Buffer.from('native-runtime');
  const manifest = control.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'native-runtime',
    revision: 'native/1',
    targetTriple,
    componentCid: `sha256:${createHash('sha256')
      .update(component).digest('hex')}`,
    componentBytes: BigInt(component.byteLength),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
  });
  const envelope = signRemoteRuntimeBundle(manifest, control, {
    keyId: 'key-a',
    privateKey: keys.privateKey,
  });
  execFileSync(moon, [
    'test', 'src/platform_native/remote_runtime', '--target', 'native',
  ], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY: sqliteLibrary,
      ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: cryptoLibrary,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_ROOT: storeRoot,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: targetTriple,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
        keys.publicKey.export({type: 'spki', format: 'pem'}),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: envelope.body,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: envelope.runtimeBundleCid,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: envelope.signature,
    },
    stdio: 'inherit',
  });
  execFileSync(moon, [
    'test', 'src/platform_native/remote_agent', '--target', 'native',
  ], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY: sqliteLibrary,
      ACTQL_TEST_NATIVE_CRYPTO_LIBRARY: cryptoLibrary,
      ACTQL_TEST_NATIVE_REMOTE_AGENT_ROOT: agentRoot,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET: targetTriple,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY:
        keys.publicKey.export({type: 'spki', format: 'pem'}),
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY: envelope.body,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID: envelope.runtimeBundleCid,
      ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE: envelope.signature,
    },
    stdio: 'inherit',
  });
} finally {
  await rm(root, {recursive: true, force: true});
}
