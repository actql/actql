// One authorized real-service campaign in actual installed Client packages.
// Unknown/pending custody and original Runs never live in disposable npm roots.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {CLIENT_PACKAGES, checkoutState, packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence} from './packed-query-evidence.mjs';
import {checkGcsAcceptanceEnvironment} from './gcs-files-content-environment.mjs';
import {stagePackedGcsFixture} from './packed-gcs-content-fixture.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
assert.ok(isAbsolute(process.argv[2] ?? ''), 'Explicit authorized GCS manifest required');
const manifest = checkGcsAcceptanceEnvironment(JSON.parse(await readFile(process.argv[2], 'utf8')));
const initial = checkoutState(repository);
assert.ok(initial.clean, 'Packed GCS requires committed source');
const scratchParent = join(repository, '..', '.codex-scratch');
const evidence = createCommandEvidence({scratch: scratchParent, prefix: 'packed-gcs-content-evidence-',
  revision: initial.revision, cwd: repository});
const scratch = await createOwnedScratch({parent: scratchParent,
  prefix: 'packed-gcs-content-install-', label: 'packed GCS disposable installation'});
const application = join(scratch.path, 'application');
await mkdir(application);
const env = {...process.env, npm_config_cache: packedNpmCache(scratch.path)};
for (const key of ['NODE_PATH', 'NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS']) delete env[key];
const capture = (command, args, cwd = application, childEnv = env, timeout = 120000) => {
  const {result, outcome, writeFailure} = evidence.capture(command, args, {cwd, env: childEnv, timeout});
  if (writeFailure) throw writeFailure;
  assert.equal(result.status, 0, `PackedGcsCommandFailed:${outcome.id}`);
  assert.equal(result.signal, null);
  return result.stdout;
};
const record = {version: 'actql-packed-gcs-content-acceptance/0.1', source: initial,
  environment: manifest, complete: false, cases: [],
  limitations: ['not typed INFER/COMMAND or pending capture recovery', 'no GCS mutation/deletion',
    'response reservations are upper bounds, not measured network bytes', 'not Hosted CI or full Core']};
const save = () => writeFile(join(evidence.directory, 'acceptance.json'), JSON.stringify(record, null, 2) + '\n', {mode: 0o600});
await save();
try {
  for (const name of CLIENT_PACKAGES) await packedClientPackage({repository, name, destination: scratch.path,
    pack: () => capture('npm', ['pack', '--pack-destination', scratch.path, '--json'],
      join(repository, 'packages', name), env, 600000)});
  assert.deepEqual(checkoutState(repository), initial);
  await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n', {flag: 'wx'});
  capture('npm', ['install', '--ignore-scripts', '--no-save', '--no-audit', '--no-fund',
    ...CLIENT_PACKAGES.map(name => join(scratch.path, `actql-${name}-0.0.0-development.tgz`))]);
  auditPackedPackages(application, CLIENT_PACKAGES);
  record.fixture = await stagePackedGcsFixture({repository, application});
  record.packages = [];
  for (const name of CLIENT_PACKAGES) {
    const digest = createHash('sha256').update(await readFile(join(scratch.path,
      `actql-${name}-0.0.0-development.tgz`))).digest('hex');
    record.packages.push({name, sha256: digest});
    evidence.summary.tarballs.push({name, sha256: digest});
  }
  const deadlineUnixMs = Date.now() + manifest.limits.maxDurationMs;
  const childManifest = checkGcsAcceptanceEnvironment({...manifest, limits: {...manifest.limits,
    maxRequests: Math.floor(manifest.limits.maxRequests / 2),
    maxResponseBytes: Math.floor(manifest.limits.maxResponseBytes / 2)}});
  const childEnv = {...env, PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
  delete childEnv.ACTQL_PACKED_CLIENT_PACKAGES;
  for (const entrance of ['Local', 'HTTPS']) {
    const root = join(evidence.directory, 'custody', entrance);
    await mkdir(root, {recursive: true, mode: 0o700});
    const configuration = join(root, 'fixture.json');
    const keys = generateKeyPairSync('ed25519');
    await writeFile(configuration, JSON.stringify({root, entrance, manifest: childManifest, deadlineUnixMs,
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}), {flag: 'wx', mode: 0o600});
    const phases = [];
    for (const phase of ['capture', 'read']) {
      const output = capture(process.execPath, [record.fixture.entry, configuration, phase],
        application, childEnv, 60000);
      const value = JSON.parse(output.trim().split('\n').at(-1));
      assert.equal(value.complete, true);
      assert.equal(value.phase, phase);
      assert.equal(value.entrance, entrance);
      assert.equal(value.cases.length, 2);
      phases.push(value);
    }
    assert.notEqual(phases[0].pid, phases[1].pid);
    assert.ok(phases[0].credential.credentialResolutions > 0);
    assert.equal(phases[1].credential.credentialResolutions, 0);
    assert.equal(phases[1].credential.tokenMints, 0);
    assert.deepEqual(phases[0].cases.map(value => value.runRef), phases[1].cases.map(value => value.runRef));
    record.cases.push({entrance, phases, custodyDirectory: root});
    await save();
    console.log(`PACKED_GCS ${entrance}: capture and separate-process read passed`);
  }
  const requests = record.cases.reduce((n, value) => n + value.phases[0].credential.credentialResolutions, 0);
  const reservedBytes = record.cases.reduce((n, value) => n + value.phases[0].credential.reservedResponseBytes, 0);
  assert.ok(requests <= manifest.limits.maxRequests && reservedBytes <= manifest.limits.maxResponseBytes);
  assert.ok(Date.now() <= deadlineUnixMs);
  assert.deepEqual(checkoutState(repository), initial);
  record.complete = true;
  await save();
  evidence.finish('passed');
  scratch.passed();
  console.log(`Packed GCS passed; evidence and custody: ${evidence.directory}`);
} catch (error) {
  await save();
  evidence.finish('failed');
  console.error(`Packed GCS incomplete; evidence and custody retained: ${evidence.directory}`);
  throw error;
}
