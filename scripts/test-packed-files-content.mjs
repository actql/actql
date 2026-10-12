// Focused public Content acceptance through the five real distributions.
// Custody, including unknown writes, is kept outside disposable installations.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {CLIENT_PACKAGES, checkoutState, packedClientPackage,
  packedNpmCache} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence} from './packed-query-evidence.mjs';
import {stagePackedContentFixtures} from './packed-files-content-fixtures.mjs';
import {packedContentSelection, verifyPackedContentProducerManifest,
  verifyPackedContentScenario} from './packed-files-content-acceptance.mjs';

const selected = packedContentSelection(process.argv.slice(2));
const producerDirectory = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
if (selected.scope === 'pure' &&
    (producerDirectory === undefined || producerDirectory === '')) {
  throw new Error('PackedPureContentRequiresVerifiedProducer');
}
const repository = fileURLToPath(new URL('../', import.meta.url));
const initial = checkoutState(repository);
assert.ok(initial.clean, 'Packed Content requires committed source, not a diagnostic overlay');
// The existing package consumer verifies each actual tarball. Retain the exact
// original producer manifest as a separate diagnostic identity as well; a
// later manifest replacement cannot silently mix producer observations.
const producerManifest = producerDirectory === undefined || producerDirectory === ''
  ? undefined : await readFile(join(producerDirectory, 'packed-client-packages.json'));
const producer = producerManifest === undefined ? undefined
  : JSON.parse(producerManifest.toString('utf8'));
if (producer !== undefined) verifyPackedContentProducerManifest(producer, initial.revision);
const scratchParent = join(repository, '..', '.codex-scratch');
const evidence = createCommandEvidence({scratch: scratchParent, revision: initial.revision,
  cwd: repository, prefix: 'packed-files-content-evidence-'});
const scratch = await createOwnedScratch({parent: scratchParent,
  prefix: 'packed-files-content-install-', label: 'packed Files Content installation',
  digests: () => CLIENT_PACKAGES.map(name => `actql-${name}-0.0.0-development.tgz`)});
const application = join(scratch.path, 'application');
await mkdir(application);
const environment = {...process.env, npm_config_cache: packedNpmCache(scratch.path)};
for (const key of ['NODE_PATH', 'NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS',
  'ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_CONTENT_CPU_PROFILE']) {
  delete environment[key];
}
function run(command, args, cwd = application, env = environment, timeout = 120000) {
  const {result, outcome, writeFailure} = evidence.capture(command, args,
    {cwd, env, timeout});
  if (result.error || result.signal || result.status !== 0) throw Object.assign(
    new Error(`PackedContentCommandFailed:${outcome.id}`, {cause: result.error}),
    {code: 'PackedContentCommandFailed', evidenceDirectory: evidence.directory});
  if (writeFailure) throw writeFailure;
  return result.stdout;
}
const nonsecretReceipt = {version: 'actql-packed-files-content-acceptance/0.1',
  sourceRevision: initial.revision, scope: selected.scope, complete: false, cases: [],
  ...(producerManifest === undefined ? {} : {producerManifestSha256:
    createHash('sha256').update(producerManifest).digest('hex')}),
  limitations: ['not real GCS acceptance', 'not version-fixed keyed capture INFER acceptance',
    'not full Core or Hosted CI', 'unknown custody is retained, not declared cleaned']};
try {
  for (const name of CLIENT_PACKAGES) {
    await packedClientPackage({repository, name, destination: scratch.path,
      pack: () => run('npm', ['pack', '--pack-destination', scratch.path, '--json'],
        join(repository, 'packages', name), environment, 600000)});
  }
  if (producerManifest !== undefined) assert.deepEqual(
    await readFile(join(producerDirectory, 'packed-client-packages.json')), producerManifest,
    'PackedContentProducerManifestChanged');
  assert.deepEqual(checkoutState(repository), initial, 'packing changed source identity');
  nonsecretReceipt.packages = [];
  const copiedTarballs = {};
  // Bind the actual copied bytes before npm can install them. Checking only
  // the producer path before copying does not establish destination identity.
  for (const name of CLIENT_PACKAGES) {
    const sha256 = createHash('sha256').update(await readFile(join(scratch.path,
      `actql-${name}-0.0.0-development.tgz`))).digest('hex');
    copiedTarballs[name] = sha256;
    nonsecretReceipt.packages.push({name, sha256});
    evidence.summary.tarballs.push({name: `actql-${name}-0.0.0-development.tgz`, sha256});
  }
  if (producer !== undefined) verifyPackedContentProducerManifest(
    producer, initial.revision, copiedTarballs);
  evidence.persist();
  await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n', {flag: 'wx'});
  run('npm', ['install', '--ignore-scripts', '--no-save', '--no-audit', '--no-fund',
    ...CLIENT_PACKAGES.map(name => join(scratch.path, `actql-${name}-0.0.0-development.tgz`))]);
  auditPackedPackages(application, CLIENT_PACKAGES);
  const staged = await stagePackedContentFixtures({repository, application});
  nonsecretReceipt.fixture = staged;
  const childEnvironment = {...environment,
    PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
  delete childEnvironment.ACTQL_PACKED_CLIENT_PACKAGES;
  for (const scenario of selected.cases) {
    const root = join(evidence.directory, 'custody', scenario.id);
    await mkdir(root, {recursive: true, mode: 0o700});
    const keys = generateKeyPairSync('ed25519');
    const config = join(root, 'fixture.json');
    await writeFile(config, JSON.stringify({root, entrance: scenario.entrance,
      fault: scenario.fault, generatedCommand: true, modelCommand: scenario.model === true,
      modelApprovalRequired: scenario.model === true, exposeAttachmentResult: scenario.attachment === true,
      expiresAt: new Date(Date.now() + 120000).toISOString(),
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}), {flag: 'wx', mode: 0o600});
    const phases = [];
    for (const phase of scenario.model
      ? ['capture', 'approve-model', 'approve', 'read'] : ['capture', 'approve', 'read']) {
      const output = run(process.execPath, [staged.entry, config, phase],
        application, childEnvironment, 30000);
      phases.push(JSON.parse(output.trim().split('\n').at(-1)));
    }
    verifyPackedContentScenario({scenario, phases,
      bytes: await readFile(join(root, 'approved.csv')),
      receipt: JSON.parse(await readFile(join(root, 'receiver-receipt.json'), 'utf8'))});
    nonsecretReceipt.cases.push({id: scenario.id, entrance: scenario.entrance,
      passed: true, custodyDirectory: root, retainedUnknown: scenario.fault === 'lost_reply', phases});
    await writeFile(join(evidence.directory, 'content-acceptance.json'),
      JSON.stringify(nonsecretReceipt, null, 2) + '\n', {mode: 0o600});
    console.log(`PACKED_CONTENT_CASE ${scenario.id}: passed`);
  }
  assert.deepEqual(checkoutState(repository), initial, 'source changed during packed acceptance');
  if (producerManifest !== undefined) assert.deepEqual(
    await readFile(join(producerDirectory, 'packed-client-packages.json')), producerManifest,
    'PackedContentProducerManifestChanged');
  nonsecretReceipt.complete = true;
  await writeFile(join(evidence.directory, 'content-acceptance.json'),
    JSON.stringify(nonsecretReceipt, null, 2) + '\n', {mode: 0o600});
  evidence.finish('passed');
  assert.equal(evidence.summary.complete, true);
  scratch.passed();
  console.log(`Packed Content (${selected.scope}): ${selected.cases.length} cases passed; evidence: ${evidence.directory}`);
} catch (error) {
  try { evidence.finish('failed'); }
  catch (writeError) {
    throw new AggregateError([error, writeError], 'PackedContentFailureEvidenceWriteFailed', {cause: error});
  }
  console.error(`Packed Content incomplete; evidence and custody retained: ${evidence.directory}`);
  throw error;
}
