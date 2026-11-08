// Reuse a closed ordinary installation and its exact normal cohort. This
// runner never produces a package, installs dependencies or overlays a product.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, readdir, readlink, symlink, unlink, writeFile} from 'node:fs/promises';
import {isAbsolute, join, dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {runFocusedTests} from './test-execution.mjs';

assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1',
  'Preserve original Run/DB/keys/raw on success and failure');
const repository = fileURLToPath(new URL('../', import.meta.url));
const [source, release, consumer, selection] = process.argv.slice(2);
assert((process.argv.length === 5 || process.argv.length === 6 &&
  ['--approval', '--kintone-approval', '--mock-salesforce-approval',
    '--mock-hubspot-approval', '--mock-kintone-approval'].includes(selection)),
  'usage: test-packed-hubspot-source.mjs <original-normal-source> <RC-directory> <closed-installed-consumer> [--approval|--kintone-approval|--mock-CONNECTOR-approval]');
const mockConnector = /^--mock-(salesforce|hubspot|kintone)-approval$/u.exec(selection ?? '')?.[1];
const approvalConnector = mockConnector ?? (selection === '--approval' ? 'hubspot'
  : selection === '--kintone-approval' ? 'kintone' : undefined);
const approval = approvalConnector !== undefined;
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
  prefix: 'packed-hubspot-original-', label: approval
    ? `ordinary installed ${approvalConnector}${mockConnector ? ' mock' : ''} approval and original Saved restoration`
    : 'ordinary installed HubSpot Source and original Run restoration'});
const application = join(scratch.path, 'application');
await mkdir(application);
await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
// Read-only borrow of the independently installed exact artifact closure;
// fresh Host/Run/credential/TLS/SQLite roots below never mutate that donor.
const software = join(consumer, 'node_modules'), softwareAlias = join(application, 'node_modules');
const fixtureFiles = mockConnector ? ['scripts/fixtures/packed-record-approval-mock.mjs',
  ...['mock-project.mjs', 'run.mjs', 'workflow.mjs', 'update.aql', 'read.aql']
    .map(name => `scripts/fixtures/${mockConnector}-approval/` + name),
  ...['command.mjs', 'workflow.mjs', 'cases.mjs', 'mock-project.mjs',
    'scoped-fds.fixture.mjs', 'installed-child.mjs'].map(name => 'scripts/fixtures/record-approval/' + name)]
  : approval ? [`scripts/fixtures/packed-${approvalConnector}-approval.mjs`,
  ...['provider.mjs', 'installed.fixture.mjs', 'update.aql', 'read.aql']
    .map(name => `scripts/fixtures/${approvalConnector}-approval/` + name),
  ...['command.mjs', 'workflow.mjs', 'cases.mjs', 'host-account.fixture.mjs', 'scoped-fds.fixture.mjs',
    'installed.fixture.mjs', 'installed-child.mjs']
    .map(name => 'scripts/fixtures/record-approval/' + name),
  ...(approvalConnector === 'kintone' ? ['adapters/connectors/kintone/test/kintone-update-form.fixture.mjs'] : []),
  'adapters/site-node/https-exchange-fixture.mjs'] : ['scripts/fixtures/packed-hubspot-public.mjs',
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
const expectedTests = approval ? 1 : 2;
let code;
await symlink(software, softwareAlias, 'dir');
try {
  code = runFocusedTests('node', [approval
    ? mockConnector ? 'scripts/fixtures/packed-record-approval-mock.mjs'
      : `scripts/fixtures/packed-${approvalConnector}-approval.mjs` : 'scripts/fixtures/packed-hubspot-public.mjs'],
    {cwd: application, expectedTests, timeout: approval ? 110000 : 50000, killSignal: 'SIGTERM',
      env: mockConnector ? {...process.env, ACTQL_RECORD_APPROVAL_MOCK_CONNECTOR: mockConnector} : process.env});
} finally {
  // Return only this fresh link, never its original installed software target.
  assert.equal(await readlink(softwareAlias), software);
  await unlink(softwareAlias);
  await original.verifyUnchanged(); await verifyInstalled();
}
// No false pass from startup failure, zero discovery, timeout or failed cleanup.
assert.equal(code, 0, `Ordinary installed HubSpot runtime refused; original evidence: ${scratch.path}`);
const focusedRoot = join(application, '_build', 'focused-evidence');
const focused = await readdir(focusedRoot);
assert.equal(focused.length, 1, 'Exactly one original runtime attempt');
const execution = JSON.parse(await readFile(join(focusedRoot, focused[0], '001.result.json'), 'utf8'));
assert(execution.complete && execution.outputComplete && execution.status === 0 && execution.verificationStatus === 0);
assert.deepEqual(execution.counts, {tests: expectedTests, passed: expectedTests,
  failed: 0, cancelled: 0, skipped: 0, todo: 0});
const receipt = {qualification: mockConnector
  ? 'Actual declared mock capture, explicit default Local approval and separate-process original Saved before status on the selected normal installation. No provider or installed Effect acceptance claim.'
  : approval
  ? 'Actual installed Local capture, signed approval, exactly one synthetic TLS provider UPDATE and separate-process original Saved before status. No real provider, performance or physical cleanup ACK claim.'
  : 'Actual public Local/HTTPS using the exact borrowed ordinary installed cohort; fresh Host and original same-Run restoration in a fresh process. No new npm install, package build, live service, write or normal numeric-profile claim.',
  productSource: original.manifest.sourceSha, manifestSha256: original.manifestSha256,
  consumer, application, node: process.version, fixtures: inputs,
  expectedTests, actualCounts: execution.counts, observedExitCode: code,
  installedMembers: original.manifest.packages.reduce((count, item) => count + item.files.length, 0)};
await writeFile(join(scratch.path, 'qualification.json'), JSON.stringify(receipt, null, 2) + '\n');
scratch.passed();
console.log('PACKED_HUBSPOT_PUBLIC', JSON.stringify(receipt));
