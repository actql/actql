// Reuse a closed ordinary installation and its exact normal cohort. This
// runner never produces a package, installs dependencies or overlays a product.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, readdir, symlink, writeFile} from 'node:fs/promises';
import {isAbsolute, join, dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {runFocusedTests} from './test-execution.mjs';

assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1',
  'Preserve original Run/DB/keys/raw on success and failure');
const repository = fileURLToPath(new URL('../', import.meta.url));
const [source, release, consumer] = process.argv.slice(2);
assert.equal(process.argv.length, 5,
  'usage: test-packed-hubspot-source.mjs <original-normal-source> <RC-directory> <closed-installed-consumer>');
for (const path of [source, release, consumer]) assert(isAbsolute(path), 'Require absolute original input paths');
assert(!process.env.NODE_PATH && !process.env.NODE_OPTIONS,
  'Ordinary installed acceptance refuses ambient module/loader overlays');
assert(!process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Ordinary installed acceptance uses only its fresh explicit profiles');
const {admitCompositionRelease} = await import(pathToFileURL(join(source, 'scripts/composition-release-input.mjs')));
const {inventory} = await import(pathToFileURL(join(source, 'scripts/package-release.mjs')));
const original = await admitCompositionRelease({repository: source, directory: release});
async function verifyInstalled() {
  for (const item of original.manifest.packages) assert.deepEqual(
    await inventory(join(consumer, 'node_modules', item.name)), item.files,
    `Changed original installed members: ${item.name}`);
}
await verifyInstalled();
const scratch = await createOwnedScratch({parent: join(repository, '_build'),
  prefix: 'packed-hubspot-original-', label: 'ordinary installed HubSpot Source and original Run restoration'});
const application = join(scratch.path, 'application');
await mkdir(application);
await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
// Read-only borrow of the independently installed exact artifact closure;
// fresh Host/Run/credential/TLS/SQLite roots below never mutate that donor.
await symlink(join(consumer, 'node_modules'), join(application, 'node_modules'), 'dir');
const fixtureFiles = ['scripts/fixtures/packed-hubspot-public.mjs',
  'scripts/fixtures/packed-hubspot-public.fixture.mjs',
  'scripts/fixtures/packed-hubspot-restart.mjs',
  'adapters/site-node/https-exchange-fixture.mjs'];
const inputs = [];
for (const path of fixtureFiles) {
  const from = join(repository, path), to = join(application, path);
  await mkdir(dirname(to), {recursive: true}); await copyFile(from, to);
  const bytes = await readFile(from);
  assert.deepEqual(await readFile(to), bytes, `Changed fixture: ${path}`);
  inputs.push({path, bytes: bytes.byteLength,
    sha256: createHash('sha256').update(bytes).digest('hex')});
}
const code = runFocusedTests('node', ['scripts/fixtures/packed-hubspot-public.mjs'],
  {cwd: application, timeout: 50000, killSignal: 'SIGTERM'});
// No false pass from startup failure, zero discovery, timeout or failed cleanup.
assert.equal(code, 0, `Ordinary installed HubSpot runtime refused; original evidence: ${scratch.path}`);
const focusedRoot = join(application, '_build', 'focused-evidence');
const focused = await readdir(focusedRoot);
assert.equal(focused.length, 1, 'Exactly one original runtime attempt');
const execution = JSON.parse(await readFile(join(focusedRoot, focused[0], '001.result.json'), 'utf8'));
assert(execution.complete && execution.outputComplete && execution.status === 0 && execution.verificationStatus === 0);
assert.deepEqual(execution.counts, {tests: 2, passed: 2, failed: 0, cancelled: 0, skipped: 0, todo: 0});
await original.verifyUnchanged(); await verifyInstalled();
const receipt = {qualification: 'Actual public Local/HTTPS using the exact borrowed ordinary installed cohort; fresh Host and original same-Run restoration in a fresh process. No new npm install, package build, live service, write or normal numeric-profile claim.',
  productSource: original.manifest.sourceSha, manifestSha256: original.manifestSha256,
  consumer, application, node: process.version, fixtures: inputs,
  expectedTests: 2, actualCounts: execution.counts, observedExitCode: code,
  installedMembers: original.manifest.packages.reduce((count, item) => count + item.files.length, 0)};
await writeFile(join(scratch.path, 'qualification.json'), JSON.stringify(receipt, null, 2) + '\n');
scratch.passed();
console.log('PACKED_HUBSPOT_PUBLIC', JSON.stringify(receipt));
