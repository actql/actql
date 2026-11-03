import {prepareNativeRuntimeBundle, prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import assert from 'node:assert/strict';
import {execFile, execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {existsSync} from 'node:fs';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
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
const nativeSiteNamespace = process.env.ACTQL_TEST_NATIVE_SITE_NETNS;
const nativeSiteUser = process.env.ACTQL_TEST_NATIVE_SITE_USER;
if ((nativeSiteNamespace === undefined) !== (nativeSiteUser === undefined) ||
    nativeSiteNamespace === '' || nativeSiteUser === '') {
  throw new Error('native Site namespace and user must be configured together');
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

let passed = false;
try {
  execFileSync(moon, [
    'build', '--target', 'js', '--release', 'src/connectors_builtin_node',
  ], {cwd: repositoryRoot, stdio: 'inherit'});
  const executable = prepareNativeRuntimeBundle(repositoryRoot,
    join(root, 'runtime-bundle-producer'));
  const bundleLibraries = prepareNativeRuntimeBundleLibraries(repositoryRoot,
    join(root, 'runtime-bundle-components'));
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

  const common = [
    '--store-root', storeRoot,
    '--sqlite-library', bundleLibraries.sqliteLibrary,
    '--crypto-library', bundleLibraries.cryptoLibrary,
    '--target-triple', targetTriple,
    '--authority-root', inputRoot,
    '--trust-config-name', 'trust.json',
    '--capacity-bytes', '1024',
    '--max-bundles', '16',
    '--max-owners', '4',
    '--max-record-bytes', '1048576',
  ];
  const invoke = async arguments_ => {
    const namespaced = nativeSiteNamespace !== undefined;
    const command = namespaced ? 'sudo' : executable;
    const commandArguments = namespaced
      ? [
          'ip', 'netns', 'exec', nativeSiteNamespace,
          'sudo', `--user=${nativeSiteUser}`, 'env',
          'PATH=/usr/bin:/bin', 'LANG=C',
          executable, ...arguments_,
        ]
      : arguments_;
    return execute(command, commandArguments, {
      cwd: repositoryRoot,
      env: namespaced ? process.env : {PATH: '/usr/bin:/bin', LANG: 'C'},
      maxBuffer: 2 * 1024 * 1024,
    });
  };
  const run = async (...operation) => JSON.parse(
    (await invoke([...common, ...operation])).stdout,
  );
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

  const snapshotStore = async directory => {
    if (!existsSync(directory)) return null;
    const snapshot = [];
    const visit = async (path, prefix) => {
      const entries = await readdir(path, {withFileTypes: true});
      entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
      for (const entry of entries) {
        const name = `${prefix}${entry.name}`;
        if (entry.isDirectory()) {
          snapshot.push([`${name}/`, null]);
          await visit(join(path, entry.name), `${name}/`);
        } else {
          assert.ok(entry.isFile(), `unexpected fixture entry: ${name}`);
          snapshot.push([name, createHash('sha256')
            .update(await readFile(join(path, entry.name))).digest('hex')]);
        }
      }
    };
    await visit(directory, '');
    return snapshot;
  };
  const assertRefusalsBeforeStore = async directory => {
    const before = await snapshotStore(directory);
    const arguments_ = [...common];
    arguments_[1] = directory;
    // Parser refusal must precede even library loading, not merely fail later
    // when opening the Store. This nonexistent path is never created.
    arguments_[arguments_.indexOf('--sqlite-library') + 1] =
      join(root, 'must-not-load.sqlite');
    const refuse = async (selected, expected) => {
      await assert.rejects(invoke(selected), error =>
        `${error.stdout}\n${error.stderr}`.includes(expected));
      assert.deepEqual(await snapshotStore(directory), before);
    };
    for (const retired of ['--issuer-authority', '--key-id', '--public-key-name']) {
      const expected = `error: unexpected argument '${retired}' found`;
      await refuse([...arguments_, retired, 'obsolete', 'list'], expected);
      await refuse([...arguments_, 'list', retired, 'obsolete'], expected);
    }
    const trustAt = arguments_.indexOf('--trust-config-name');
    const withoutTrust = [
      ...arguments_.slice(0, trustAt), ...arguments_.slice(trustAt + 2),
    ];
    await refuse([...withoutTrust, '--issuer-authority', 'issuer-a',
      '--key-id', 'key-a', '--public-key-name', 'public.pem', 'list'],
      "error: unexpected argument '--issuer-authority' found");
    await refuse([...withoutTrust, 'list'],
      "error: the following required argument was not provided: 'trust-config-name'");
    const withoutSignatureKey = [...arguments_, 'install',
      '--install-id', 'missing-signature-key', '--bundle-cid', first.cid,
      '--input-root', inputRoot, '--manifest-name', first.names.manifest,
      '--signature-name', first.names.signature,
      '--component-name', first.names.component];
    await refuse(withoutSignatureKey,
      "error: the following required argument was not provided: 'signature-key-id'");
    await refuse([...withoutSignatureKey, '--key-id', 'key-a'],
      "error: unexpected argument '--key-id' found");
  };
  const help = (await invoke(['--help'])).stdout;
  assert.match(help, /--trust-config-name/u);
  assert.doesNotMatch(help, /--(?:issuer-authority|key-id|public-key-name)\b/u);
  const installHelp = (await invoke(['install', '--help'])).stdout;
  assert.match(installHelp, /--signature-key-id/u);
  assert.doesNotMatch(installHelp, /--(?:issuer-authority|key-id|public-key-name)\b/u);

  await assertRefusalsBeforeStore(join(root, 'unopened-store'));
  assert.deepEqual((await install(1, first)).state, ['0', '0', '0']);
  await assertRefusalsBeforeStore(storeRoot);
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
  const multiExecutable = Buffer.from('native-multi-runtime');
  const multiLibrary = Buffer.from('native-multi-library');
  const multiManifest = control.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'native-site-runtime',
    revision: 'multi',
    targetTriple,
    components: [
      {
        role: 'duckdb_library',
        cid: `sha256:${createHash('sha256')
          .update(multiLibrary).digest('hex')}`,
        bytes: BigInt(multiLibrary.byteLength),
      },
      {
        role: 'runtime_executable',
        cid: `sha256:${createHash('sha256')
          .update(multiExecutable).digest('hex')}`,
        bytes: BigInt(multiExecutable.byteLength),
      },
    ],
    connectorRegistration: 'local',
    connectorRevision: 'local/multi',
    strategyRevision: 'strategy/multi',
  });
  const multiEnvelope = signRemoteRuntimeBundle(multiManifest, control, {
    keyId: 'key-b',
    privateKey: keysB.privateKey,
  });
  await Promise.all([
    writeFile(join(inputRoot, 'multi-library.bin'), multiLibrary),
    writeFile(join(inputRoot, 'multi-executable.bin'), multiExecutable),
    writeFile(join(inputRoot, 'multi-manifest.json'), multiEnvelope.body),
    writeFile(join(inputRoot, 'multi-signature.txt'),
      multiEnvelope.signature),
  ]);
  const multiCid = control.identity(multiManifest);
  const multiArguments = [
    'install',
    '--signature-key-id', 'key-b',
    '--bundle-cid', multiCid,
    '--input-root', inputRoot,
    '--manifest-name', 'multi-manifest.json',
    '--signature-name', 'multi-signature.txt',
  ];
  await assert.rejects(
    run(...multiArguments, '--install-id', 'multi-missing',
      '--component-file', 'runtime_executable=multi-executable.bin'),
    error => `${error.stdout}\n${error.stderr}`
      .includes('component-file inventory mismatch'),
  );
  await assert.rejects(
    run(...multiArguments, '--install-id', 'multi-swapped',
      '--component-file', 'duckdb_library=multi-executable.bin',
      '--component-file', 'runtime_executable=multi-library.bin'),
    error => `${error.stdout}\n${error.stderr}`
      .includes('component'),
  );
  assert.deepEqual((await run(
    ...multiArguments,
    '--install-id', 'multi-valid',
    '--component-file', 'duckdb_library=multi-library.bin',
    '--component-file', 'runtime_executable=multi-executable.bin',
  )).state, ['0', '0', '0']);
  assert.equal((await run('verify', '--bundle-cid', multiCid))
    .runtime_bundle_cid, multiCid);
  assert.equal((await run('capacity')).reserved_bytes,
    String(multiLibrary.byteLength + multiExecutable.byteLength));
  await run('activate', '--bundle-cid', multiCid);
  await run('drain', '--bundle-cid', multiCid);
  await run('reclaim', '--bundle-cid', multiCid);
  assert.equal((await run('capacity')).reserved_bytes, '0');
  for (let number = 3; number <= 13; number += 1) {
    const bundle = await prepare(
      number,
      Buffer.from(`native-runtime-${number}`),
      'key-b',
      keysB.privateKey,
    );
    await install(number, bundle);
  }
  assert.equal((await run('list')).length, 14);
  assert.equal((await run('recover')).length, 14);
  console.log('Native runtime bundle CLI lifecycle passed');
  passed = true;
} finally {
  if (passed && process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
    await rm(root, {recursive: true, force: true});
  } else console.error(`Native runtime bundle original scratch retained: ${root}`);
}
