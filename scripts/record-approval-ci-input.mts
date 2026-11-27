// Adapt the existing exact-checkout packed input gate for an installed
// consumer. This neither packs a package nor manufactures release metadata.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {CLIENT_PACKAGES, checkoutState, packedClientPackage} from './packed-client-packages.mjs';
import {inventory, unpack} from './package-release.mjs';
import type {AuthoredRecordApprovalCase} from './fixtures/record-approval/workflow.mjs';

type Invocation = {
  application: string;
  approvalConnector?: string;
  mockConnector?: string;
  mockVariant?: string;
  authoredCasePath?: string;
  reject?: boolean;
  env?: NodeJS.ProcessEnv;
};
type UncheckedManifest = {revision?: unknown; tarballs: Record<string, unknown>};

const sha256 = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

export function packedRecordApprovalInvocation({application, approvalConnector, mockConnector,
  mockVariant = '', authoredCasePath, reject, env = process.env}: Invocation) {
  const approval = approvalConnector !== undefined;
  const file = mockConnector ? 'scripts/fixtures/packed-record-approval-mock.mjs'
    : approval ? `scripts/fixtures/packed-${approvalConnector}-approval.mjs` : 'scripts/fixtures/packed-hubspot-public.mjs';
  const childEnv = mockConnector ? {...env, ACTQL_RECORD_APPROVAL_MOCK_CONNECTOR: mockConnector,
    ACTQL_RECORD_APPROVAL_MOCK_VARIANT: mockVariant,
    ...(mockVariant ? {ACTQL_RECORD_APPROVAL_REMOVE_PROGRAMS: '1'} : {}),
    ...(authoredCasePath === undefined ? {} : {ACTQL_RECORD_APPROVAL_MOCK_CASE: authoredCasePath}),
    ...(reject ? {ACTQL_RECORD_APPROVAL_DECISION: 'rejected'} : {})}
    : {...env,
      ...(authoredCasePath === undefined ? {} : {ACTQL_RECORD_APPROVAL_HTTP_CASE: authoredCasePath}),
      ...(reject ? {ACTQL_RECORD_APPROVAL_DECISION: 'rejected'} : {})};
  return {files: [file], options: {cwd: application, expectedTests: approval ? 1 : 2,
    timeout: approval ? 110000 : 50000, killSignal: 'SIGTERM' as const, env: childEnv}};
}

type FixtureSelection = Pick<Invocation, 'approvalConnector' | 'mockConnector' | 'mockVariant'>;

export function packedRecordApprovalFixturePaths({approvalConnector, mockConnector, mockVariant}: FixtureSelection) {
  return mockConnector ? ['scripts/fixtures/packed-record-approval-mock.mjs',
    ...['mock-project.mjs', 'run.mjs', 'workflow.mjs', 'update.aql', 'read.aql']
      .map(name => `scripts/fixtures/${mockConnector}-approval/` + name),
    ...(!mockVariant && ['hubspot', 'kintone'].includes(mockConnector)
      ? [`scripts/fixtures/${mockConnector}-approval/case.json`] : []),
    ...(mockVariant === 'binary-source' ? ['scripts/fixtures/hubspot-approval/binary-source-mock-project.mjs'] : []),
    ...['command.mjs', 'workflow.mjs', 'cases.mjs', 'mock-project.mjs',
      'scoped-fds.fixture.mjs', 'installed-child.mjs'].map(name => 'scripts/fixtures/record-approval/' + name),
    'adapters/host-node/fixtures/work-observation.fixture.mjs']
    : approvalConnector !== undefined ? [`scripts/fixtures/packed-${approvalConnector}-approval.mjs`,
    ...['provider.mjs', 'installed.fixture.mjs', 'update.aql', 'read.aql', 'case.json']
      .map(name => `scripts/fixtures/${approvalConnector}-approval/` + name),
    ...['command.mjs', 'workflow.mjs', 'cases.mjs', 'host-account.fixture.mjs', 'scoped-fds.fixture.mjs',
      'installed.fixture.mjs', 'installed-child.mjs', 'provider-state.mjs']
      .map(name => 'scripts/fixtures/record-approval/' + name),
    'adapters/host-node/fixtures/work-observation.fixture.mjs',
    ...(approvalConnector === 'kintone' ? ['adapters/connectors/kintone/test/kintone-update-form.fixture.mjs'] : []),
    'adapters/site-node/https-exchange-fixture.mjs'] : ['scripts/fixtures/packed-hubspot-public.mjs',
    'scripts/fixtures/packed-hubspot-public.fixture.mjs',
    'scripts/fixtures/packed-hubspot-restart.mjs',
    'adapters/site-node/https-exchange-fixture.mjs'];
}

// Stage the existing ordinary fixture as DATA beside the verified installation.
export async function stagePackedRecordApprovalFixtures({repository, application, authoredCase,
  approvalConnector, mockConnector, mockVariant}: FixtureSelection & {
  repository: string; application: string; authoredCase?: AuthoredRecordApprovalCase;
}) {
  const inputs: {path: string; bytes: number; sha256: string}[] = [];
  let stagedCasePath: string | undefined, stagedCaseBytes: Buffer | undefined;
  if (authoredCase !== undefined) {
    const path = 'authored-case.json';
    stagedCasePath = join(application, path);
    stagedCaseBytes = Buffer.from(JSON.stringify(authoredCase));
    await writeFile(stagedCasePath, stagedCaseBytes, {mode: 0o600, flag: 'wx'});
    inputs.push({path, bytes: stagedCaseBytes.byteLength, sha256: sha256(stagedCaseBytes)});
  }
  for (const path of packedRecordApprovalFixturePaths({approvalConnector, mockConnector, mockVariant})) {
    // This is an independently authored consumer input, not a product overlay.
    // Every approval/Result/Saved/close helper remains the same original file.
    const sourcePath = mockVariant === 'three-source' && path === 'scripts/fixtures/hubspot-approval/mock-project.mjs'
      ? 'scripts/fixtures/hubspot-approval/three-source-mock-project.mjs'
      : mockVariant && path === 'scripts/fixtures/hubspot-approval/update.aql'
        ? mockVariant === 'binary-source' ? 'scripts/fixtures/hubspot-approval/binary-source-update.aql'
          : mockVariant === 'three-source' ? 'scripts/fixtures/hubspot-approval/three-source-update.aql'
            : 'scripts/fixtures/hubspot-approval/whole-update.aql' : path;
    const from = join(repository, sourcePath), to = join(application, path);
    await mkdir(dirname(to), {recursive: true}); await copyFile(from, to);
    const bytes = await readFile(from);
    assert.deepEqual(await readFile(to), bytes, `Changed fixture: ${path}`);
    inputs.push({path, ...(sourcePath === path ? {} : {sourcePath}), bytes: bytes.byteLength,
      sha256: sha256(bytes)});
  }
  return {inputs, stagedCasePath, async verifyStagedCase() {
    if (stagedCasePath !== undefined) assert.deepEqual(await readFile(stagedCasePath), stagedCaseBytes);
  }};
}

export async function admitRecordApprovalCIInput({repository, destination}: {
  repository: string;
  destination: string;
}) {
  const directory = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  assert(typeof directory === 'string' && isAbsolute(directory),
    'CI record approval requires explicit ACTQL_PACKED_CLIENT_PACKAGES; no packing fallback');
  assert.notEqual(resolve(directory), resolve(destination), 'Retain original archives outside the copied input');
  const before = checkoutState(repository);
  assert(before.clean, 'CI record approval requires clean source');
  const manifestPath = join(directory, 'packed-client-packages.json');
  const wire = await readFile(manifestPath), manifest = JSON.parse(wire as unknown as string) as UncheckedManifest;
  assert.equal(manifest.revision, before.revision, 'CI record approval requires the exact packed source');
  assert.deepEqual(Object.keys(manifest.tarballs ?? {}).sort(), [...CLIENT_PACKAGES].sort(),
    'CI record approval requires the complete five-package input');
  await mkdir(destination, {recursive: true});
  const packages: {name: string; file: string; files: Awaited<ReturnType<typeof inventory>>}[] = [];
  for (const name of CLIENT_PACKAGES) {
    await packedClientPackage({repository, name, destination,
      pack() {throw new Error('RecordApprovalCannotProducePackages');}});
    const file = `actql-${name}-0.0.0-development.tgz`;
    const payload = await unpack(join(destination, file), join(destination, 'payload', name));
    const metadata = JSON.parse(await readFile(join(payload, 'package.json')) as unknown as string) as {name: string};
    assert.equal(metadata.name, '@actql/' + name, 'The archive must contain its original named package');
    packages.push({name: metadata.name, file, files: await inventory(payload)});
  }
  const admitted = {kind: 'ci-packed-client-packages', directory,
    manifestSha256: sha256(wire), manifest: {sourceSha: before.revision, packages},
    archives: packages.map(item => join(destination, item.file)),
    async verifyUnchanged() {
      assert.deepEqual(checkoutState(repository), before, 'Packed source changed during record approval');
      assert.deepEqual(await readFile(manifestPath), wire, 'Original packed manifest changed');
      for (const [index, name] of CLIENT_PACKAGES.entries()) {
        const file = packages[index].file, expected = manifest.tarballs[name];
        assert.equal(sha256(await readFile(join(directory, file))), expected, 'Original packed archive changed');
        assert.equal(sha256(await readFile(join(destination, file))), expected, 'Copied packed archive changed');
      }
    }};
  await admitted.verifyUnchanged();
  return admitted;
}
