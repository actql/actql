import assert from 'node:assert/strict';
import {execFile, execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {promisify} from 'node:util';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {signRemoteRuntimeBundle} from
  '../adapters/site-node/remote-bundle-signature.mjs';

const execute = promisify(execFile);
const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const scratchParent = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchParent !== 'string' || scratchParent.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchParent, {recursive: true});
const root = await mkdtemp(join(scratchParent, 'native-bundle-cli-'));
const inputRoot = join(root, 'input');
const storeRoot = join(root, 'store');
await Promise.all([
  mkdir(inputRoot, {recursive: true}),
  mkdir(storeRoot, {recursive: true}),
]);

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
    `unsupported native bundle CLI test target ${process.platform}/${process.arch}`,
  );
}

try {
  execFileSync(moon, [
    'build', '--target', 'js', '--release', 'src/connectors_builtin_node',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  execFileSync(moon, [
    'build', '--target', 'native', 'src/cmd/native_runtime_bundle',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  const moonModule = await import(pathToFileURL(join(
    repositoryRoot,
    '_build/js/release/build/connectors_builtin_node/' +
      'connectors_builtin_node.js',
  )).href);
  const control = runtimeCore(moonModule).remoteBundleControl;
  const keysA = generateKeyPairSync('ed25519');
  const keysB = generateKeyPairSync('ed25519');
  await Promise.all([
    writeFile(
      join(inputRoot, 'public-a.pem'),
      keysA.publicKey.export({type: 'spki', format: 'pem'}),
      {mode: 0o600},
    ),
    writeFile(
      join(inputRoot, 'public-b.pem'),
      keysB.publicKey.export({type: 'spki', format: 'pem'}),
      {mode: 0o600},
    ),
  ]);
  const writeTrust = async ({admitA, admitB}) => writeFile(
    join(inputRoot, 'trust.json'),
    JSON.stringify({
      authorities: [
        {
          admit_new_bundles: admitA,
          issuer_authority: 'bundle-authority-a',
          key_id: 'key-a',
          public_key_name: 'public-a.pem',
        },
        {
          admit_new_bundles: admitB,
          issuer_authority: 'bundle-authority-a',
          key_id: 'key-b',
          public_key_name: 'public-b.pem',
        },
      ],
      version: 'actql-native-runtime-bundle-trust/0.1',
    }),
    {mode: 0o600},
  );
  await writeTrust({admitA: true, admitB: false});

  const prepare = async (number, component, keyId, privateKey) => {
    const manifest = control.prepare({
      issuerAuthority: 'bundle-authority-a',
      bundleName: 'native-site-runtime',
      revision: String(number),
      targetTriple,
      componentCid: `sha256:${createHash('sha256')
        .update(component).digest('hex')}`,
      componentBytes: BigInt(component.byteLength),
      connectorRegistration: 'local',
      connectorRevision: `local/${number}`,
      strategyRevision: `strategy/${number}`,
    });
    const envelope = signRemoteRuntimeBundle(manifest, control, {
      keyId,
      privateKey,
    });
    const names = {
      component: `component-${number}.bin`,
      manifest: `manifest-${number}.json`,
      signature: `signature-${number}.txt`,
    };
    await Promise.all([
      writeFile(join(inputRoot, names.component), component, {mode: 0o600}),
      writeFile(join(inputRoot, names.manifest), envelope.body, {mode: 0o600}),
      writeFile(
        join(inputRoot, names.signature),
        envelope.signature,
        {mode: 0o600},
      ),
    ]);
    return Object.freeze({
      cid: control.identity(manifest),
      keyId,
      names: Object.freeze(names),
    });
  };

  const first = await prepare(
    1,
    Buffer.from('native-runtime-one'),
    'key-a',
    keysA.privateKey,
  );
  const second = await prepare(
    2,
    Buffer.from('native-runtime-two'),
    'key-b',
    keysB.privateKey,
  );
  const rejected = await prepare(
    3,
    Buffer.from('native-runtime-old'),
    'key-a',
    keysA.privateKey,
  );
  const executable = join(
    repositoryRoot,
    '_build/native/debug/build/cmd/native_runtime_bundle/' +
      'native_runtime_bundle.exe',
  );
  const common = [
    '--store-root', storeRoot,
    '--sqlite-library', sqliteLibrary,
    '--crypto-library', cryptoLibrary,
    '--target-triple', targetTriple,
    '--authority-root', inputRoot,
    '--trust-config-name', 'trust.json',
    '--capacity-bytes', '1024',
    '--max-bundles', '16',
    '--max-owners', '4',
    '--max-record-bytes', '1048576',
  ];
  const run = async (...operation) => {
    const result = await execute(executable, [...common, ...operation], {
      cwd: repositoryRoot,
      env: {PATH: '/usr/bin:/bin', LANG: 'C'},
      maxBuffer: 2 * 1024 * 1024,
    });
    return JSON.parse(result.stdout);
  };
  const install = async (number, bundle) => run(
    'install',
    '--install-id', `native-cli-install-${number}`,
    '--signature-key-id', bundle.keyId,
    '--bundle-cid', bundle.cid,
    '--input-root', inputRoot,
    '--manifest-name', bundle.names.manifest,
    '--signature-name', bundle.names.signature,
    '--component-name', bundle.names.component,
  );

  assert.deepEqual((await install(1, first)).state, ['0', '0', '0']);
  assert.deepEqual(
    (await run('activate', '--bundle-cid', first.cid)).state,
    ['1', '1', '0'],
  );
  await writeTrust({admitA: false, admitB: true});
  assert.equal(
    (await run('verify', '--bundle-cid', first.cid)).runtime_bundle_cid,
    first.cid,
  );
  await assert.rejects(
    install(3, rejected),
    error => `${error.stdout}\n${error.stderr}`.includes('admission-rejected'),
  );
  assert.equal((await run('list')).length, 1);
  assert.deepEqual((await install(2, second)).state, ['0', '0', '0']);
  assert.deepEqual(
    (await run('activate', '--bundle-cid', second.cid)).state,
    ['1', '1', '0'],
  );
  assert.equal((await run('active')).runtime_bundle_cid, second.cid);
  assert.deepEqual(
    (await run('rollback', '--bundle-cid', first.cid)).state,
    ['3', '1', '0'],
  );
  assert.equal((await run('active')).runtime_bundle_cid, first.cid);
  assert.deepEqual(
    (await run('drain', '--bundle-cid', second.cid)).state,
    ['2', '2', '0'],
  );
  assert.deepEqual(
    (await run('reclaim', '--bundle-cid', second.cid)).state,
    ['3', '3', '0'],
  );
  assert.deepEqual(
    (await run('drain', '--bundle-cid', first.cid)).state,
    ['4', '2', '0'],
  );
  assert.deepEqual(
    (await run('reclaim', '--bundle-cid', first.cid)).state,
    ['5', '3', '0'],
  );
  assert.deepEqual(await run('capacity'), {
    reserved_bytes: '0',
    reserved_objects: '0',
  });
  const recovered = await run('recover');
  assert.equal(recovered.length, 2);
  assert.ok(recovered.every(value => value.state[1] === '3'));
  for (let number = 3; number <= 13; number += 1) {
    const bundle = await prepare(
      number,
      Buffer.from(`native-runtime-${number}`),
      'key-b',
      keysB.privateKey,
    );
    await install(number, bundle);
  }
  assert.equal((await run('list')).length, 13);
  assert.equal((await run('recover')).length, 13);
  console.log('Native runtime bundle CLI lifecycle passed');
} finally {
  await rm(root, {recursive: true, force: true});
}
