// The original HTTP-harness installer seam, also selected by its focused runner.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {prepareNativeRuntimeBundle,prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import {signRemoteRuntimeBundle} from '../adapters/site-node/remote-bundle-signature.mjs';
const physicalCid=value=>`sha256:${createHash('sha256').update(value).digest('hex')}`;

export async function installNativeApplicationBundle({repositoryRoot,root,applicationExecutable,
  applicationRuntimeRoot,applicationBundleInputRoot,runtimeControl,runtimeKeys,publicKey,targetTriple,runCaptured}) {
  const runtimeBundleExecutable = prepareNativeRuntimeBundle(repositoryRoot,
    join(root, 'runtime-bundle-producer'));
  const runtimeBundleLibraries = prepareNativeRuntimeBundleLibraries(repositoryRoot,
    join(root, 'runtime-bundle-components'));
  const applicationComponent = await readFile(applicationExecutable);
  const applicationComponentCid = physicalCid(applicationComponent);
  const duckdbLibrary = join(
    repositoryRoot,
    `adapters/connectors/duckdb/node/node_modules/@duckdb/` +
      `node-bindings-${process.platform}-${process.arch}/` +
      (process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so'),
  );
  assert.equal(existsSync(duckdbLibrary), true, duckdbLibrary);
  const duckdbComponent = await readFile(duckdbLibrary);
  const applicationRuntimeManifest = runtimeControl.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'native-application-site',
    revision: 'native-application/1',
    targetTriple,
    components: [
      {
        role: 'duckdb_library',
        cid: physicalCid(duckdbComponent),
        bytes: BigInt(duckdbComponent.byteLength),
      },
      {
        role: 'runtime_executable',
        cid: applicationComponentCid,
        bytes: BigInt(applicationComponent.byteLength),
      },
    ],
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
  });
  const applicationRuntimeEnvelope = signRemoteRuntimeBundle(
    applicationRuntimeManifest,
    runtimeControl,
    {keyId: 'key-a', privateKey: runtimeKeys.privateKey},
  );
  await Promise.all([
    writeFile(
      join(applicationBundleInputRoot, 'runtime-public.pem'),
      publicKey,
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'trust.json'),
      JSON.stringify({
        authorities: [{
          admit_new_bundles: true,
          issuer_authority: 'bundle-authority-a',
          key_id: 'key-a',
          public_key_name: 'runtime-public.pem',
        }],
        version: 'actql-native-runtime-bundle-trust/0.1',
      }),
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'manifest.json'),
      applicationRuntimeEnvelope.body,
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'signature.txt'),
      applicationRuntimeEnvelope.signature,
      {mode: 0o600},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'component.bin'),
      applicationComponent,
      {mode: 0o700},
    ),
    writeFile(
      join(applicationBundleInputRoot, 'duckdb.bin'),
      duckdbComponent,
      {mode: 0o600},
    ),
  ]);
  const applicationBundleCommon = [
    '--store-root', applicationRuntimeRoot,
    '--sqlite-library', runtimeBundleLibraries.sqliteLibrary,
    '--crypto-library', runtimeBundleLibraries.cryptoLibrary,
    '--target-triple', targetTriple,
    '--authority-root', applicationBundleInputRoot,
    '--trust-config-name', 'trust.json',
    '--capacity-bytes', '268435456',
    '--max-bundles', '4',
    '--max-owners', '8',
    '--max-record-bytes', '1048576',
  ];
  const installedApplicationBundle = await runCaptured(
    runtimeBundleExecutable,
    [
      ...applicationBundleCommon,
      'install',
      '--install-id', 'native-application-install',
      '--signature-key-id', 'key-a',
      '--bundle-cid', applicationRuntimeEnvelope.runtimeBundleCid,
      '--input-root', applicationBundleInputRoot,
      '--manifest-name', 'manifest.json',
      '--signature-name', 'signature.txt',
      '--component-file', 'duckdb_library=duckdb.bin',
      '--component-file', 'runtime_executable=component.bin',
    ],
  ).completed;
  assert.equal(
    installedApplicationBundle.code,
    0,
    installedApplicationBundle.stderr,
  );
  const activatedApplicationBundle = await runCaptured(
    runtimeBundleExecutable,
    [
      ...applicationBundleCommon,
      'activate',
      '--bundle-cid', applicationRuntimeEnvelope.runtimeBundleCid,
    ],
  ).completed;
  assert.equal(
    activatedApplicationBundle.code,
    0,
    activatedApplicationBundle.stderr,
  );

  return {applicationRuntimeEnvelope,applicationComponentCid};
}
