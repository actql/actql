// Select the supplied ordinary installation and run its existing Record case.
// Fixture modes own their independent state and never accept live credentials.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstat, mkdir, readFile, readlink, realpath, symlink, unlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readConnectorConformanceInput} from '../../connector-conformance-input.mjs';
import type {RecordApprovalConformanceInput} from '../../connector-conformance-input.mjs';
import {isInstalledAuthoringToolkit, observeInstalledAuthoringToolkit} from '../../connector-authoring-toolkit.mjs';
import {checkoutState} from '../../packed-client-packages.mjs';
import {verifyNodeBenchmarkPackages} from '../../node-benchmark-evidence.mjs';
import {packedRecordApprovalInvocation, stagePackedRecordApprovalFixtures} from '../../record-approval-ci-input.mjs';
import {runFocusedTests} from '../../test-execution.mjs';
import {prepareExternalRestCohort} from '../external-rest/installed-modules.mjs';
import {readAuthoredCase} from './command.mjs';
import {recordApprovalFixtureResultNames} from './host-account.fixture.mjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const inputPath = process.env.ACTQL_RECORD_APPROVAL_CONFORMANCE_INPUT;
const sha256 = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const privateFile = {mode: 0o600, flag: 'wx'};

async function toolkitOriginal(selection: RecordApprovalConformanceInput,
  cohort: Awaited<ReturnType<typeof prepareExternalRestCohort>>) {
  if (isInstalledAuthoringToolkit(root)) return observeInstalledAuthoringToolkit(root, cohort);
  const checkout = checkoutState(root);
  assert(checkout.clean, 'Record approval conformance requires the exact clean source');
  assert.equal(checkout.revision, selection.sourceSha);
  assert.equal(execFileSync('git', ['rev-parse', 'HEAD^{tree}'], {cwd: root, encoding: 'utf8'}).trim(), selection.sourceTree);
  return checkout;
}

test('ordinary installed authored Record approval and original cold Saved', async () => {
  assert(typeof inputPath === 'string', 'Select an explicit Record approval conformance descriptor');
  assert(!process.env.NODE_PATH && !process.env.NODE_OPTIONS, 'Ordinary Record approval refuses ambient module and loader settings');
  assert(!process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
    'Ordinary Record approval uses its own private fixture profiles');
  const selection = readConnectorConformanceInput(inputPath);
  assert(selection.kind === 'actql-record-approval-normal/0.1');
  const {casePath, caseSha256, connector, consumerRoot, decision, mode, outputRoot} = selection;
  const authoredCase = await readAuthoredCase(casePath, caseSha256);
  const ordered = authoredCase.collection !== undefined;
  const reject = decision === 'rejected';
  if (mode === 'mock') {
    assert(ordered || (connector !== 'salesforce' && authoredCase.fixture !== undefined && !reject),
      'Select the authored ordered Mock or the existing single-record approved case');
  } else {
    assert(authoredCase.fixture !== undefined && !('effects' in authoredCase.review) &&
      (!reject || authoredCase.fixture.faults === undefined), 'Select the original authored HTTP case and its matching decision');
  }
  const resultNames = mode === 'http' ? recordApprovalFixtureResultNames([...new Set([
    authoredCase.effect.resultName, authoredCase.read.resultName, ...Object.keys(authoredCase.effect.additionalResults ?? {}),
  ])]) : undefined;
  const cohort = await prepareExternalRestCohort(selection);
  const authoring = await toolkitOriginal(selection, cohort);
  const installedModules = join(await realpath(consumerRoot), 'node_modules');
  assert((await lstat(installedModules)).isDirectory(), 'Select an ordinary installed node_modules directory');
  const verifyInstalled = () => verifyNodeBenchmarkPackages(cohort.manifest, cohort.artifactManifestPath, consumerRoot);
  const installedBefore = await verifyInstalled();
  await mkdir(outputRoot, {mode: 0o700});
  const application = join(outputRoot, 'application');
  await mkdir(application, {mode: 0o700});
  await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n', privateFile);
  const mockConnector = mode === 'mock' ? connector : undefined;
  const {inputs, stagedCasePath, verifyStagedCase} = await stagePackedRecordApprovalFixtures({
    repository: root, application, authoredCase, mockConnector, approvalConnector: connector,
  });
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('ACTQL_RECORD_APPROVAL_')));
  const invocation = packedRecordApprovalInvocation({application, approvalConnector: connector,
    mockConnector, authoredCasePath: stagedCasePath, reject,
    env: {...env, ACTQL_TEST_PRESERVE_SCRATCH: '1',
      ...(resultNames === undefined ? {} : {ACTQL_RECORD_APPROVAL_RESULT_NAMES: JSON.stringify(resultNames)})}});
  const alias = join(application, 'node_modules');
  await symlink(installedModules, alias, 'dir');
  let code: number;
  try {
    code = runFocusedTests('node', invocation.files, {...invocation.options, requireAllPassed: true});
  } finally {
    assert.equal(await readlink(alias), installedModules);
    await unlink(alias);
    assert.deepEqual(await verifyInstalled(), installedBefore);
    assert.deepEqual(await toolkitOriginal(selection, cohort), authoring);
    for (const original of cohort.originalBindings) assert.equal(sha256(await readFile(original.path)), original.sha256);
    assert.deepEqual(await readAuthoredCase(casePath, caseSha256), authoredCase);
    await verifyStagedCase();
  }
  assert.equal(code, 0, `Ordinary authored Record approval failed; retained application: ${application}`);
  await writeFile(join(outputRoot, 'qualification.json'), JSON.stringify({
    sourceSha: selection.sourceSha, sourceTree: selection.sourceTree, manifestSha256: selection.manifestSha256,
    caseSha256, mode, connector, decision, originalCase: authoredCase.name, inputs,
    application, expectedTests: invocation.options.expectedTests,
    installedMembers: installedBefore.reduce((count, item) => count + item.files.length, 0),
  }, null, 2) + '\n', privateFile);
});
