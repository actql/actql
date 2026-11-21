// Reuse the exact Client packages for authored read, cancellation and Effect recovery.
// Only test inputs/support are copied; every product import uses the installation.
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {checkoutState, packClientPackages, packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {nodeTestArguments, assertTestExecution} from './test-execution.mjs';
import {packedFixtureSupport, packedReadOpeningFixtureInputs, rewritePackedFixtureSource}
  from './packed-fixture-support.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const cancellationOnly = process.argv.slice(2).includes('--cancellation-only');
const submissionCustodyOnly = process.argv.slice(2).includes('--submission-custody-only');
const submissionRefusalOnly = process.argv.slice(2).includes('--submission-refusal-only');
const effectReconciliationOnly = process.argv.slice(2).includes('--effect-reconciliation-only');
const ownerObservationsOnly = process.argv.slice(2).includes('--owner-observations-only');
if ([cancellationOnly, submissionCustodyOnly, submissionRefusalOnly, effectReconciliationOnly,ownerObservationsOnly].filter(Boolean).length > 1 ||
    process.argv.slice(2).some(option => !['--cancellation-only', '--submission-custody-only', '--submission-refusal-only', '--effect-reconciliation-only','--owner-observations-only'].includes(option))) {
  throw new Error('Unknown public recovery acceptance selection');
}
const state = checkoutState(repository);
if (!state.clean) throw new Error('Build inputs differ from HEAD');
const names = ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node'];
const tarball = (name: string) => `actql-${name}-0.0.0-development.tgz`;
const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
  prefix: 'packed-read-opening-', label: 'packed original Delivery lookup',
  digests: () => [...names.map(tarball), 'packed-client-packages.json']});
const root = scratch.path;
const environment: NodeJS.ProcessEnv = {...process.env, npm_config_cache: packedNpmCache(root)};
function run(command: string, args: readonly string[], cwd: string, timeout = 120000) {
  const result = spawnSync(command, args, {cwd, env: environment, encoding: 'utf8', timeout});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} failed (${result.status}):\n${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}
if (!process.env.ACTQL_PACKED_CLIENT_PACKAGES) {
  const producer = join(root, 'producer');
  await packClientPackages({repository, destination: producer, names,
    pack: name => run('npm', ['pack', '--pack-destination', producer, '--json'],
      join(repository, 'packages', name), 180000)});
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = producer;
}
for (const name of names) {
  await packedClientPackage({repository, name, destination: root,
    pack: () => {throw new Error('Missing exact package manifest');}});
}
await copyFile(join(process.env.ACTQL_PACKED_CLIENT_PACKAGES, 'packed-client-packages.json'),
  join(root, 'packed-client-packages.json'));
await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', '--no-audit', '--no-fund',
  ...names.map(name => join(root, tarball(name)))], root);

const installedHost = join(root, 'node_modules/@actql/local-node');
const fixtureDirectory = join(root, 'adapters/host-node');
await mkdir(fixtureDirectory, {recursive: true});
const support = packedFixtureSupport(repository, packedReadOpeningFixtureInputs);
for (const path of support) {
  const output = join(root, path);
  await mkdir(join(output, '..'), {recursive: true});
  let text = await readFile(join(repository, path), 'utf8');
  text = rewritePackedFixtureSource(text, {repository, path, support, installedHost});
  await writeFile(output, text);
}
const custodyInputs = join(root, 'submission-custody-inputs.json');
await writeFile(custodyInputs, JSON.stringify({scratch: root, runtime: {
  client: '@actql/node', sdk: '@actql/sdk', httpHost: '@actql/local-node/http-host'}}));
environment.ACTQL_SUBMISSION_CUSTODY_ACCEPTANCE_INPUTS = custodyInputs;
const groups = [
  {name: 'opening-and-receipt', file: 'client-read-opening.test.mjs', count: 8},
  {name: 'interrupted-121-run', file: 'client-read-run-capacity.test.mjs', count: 4},
  {name: 'installed-capacity', file: 'client-values-row-limit.test.mjs', count: 10},
  {name: 'original-cancellation', file: 'client-cancellation-public.test.mjs', count: 4},
  {name: 'typed-cancellation', file: 'client-cancellation-attempt-installed.test.mjs', count: 2},
  {name: 'effect-cancellation', file: 'client-effect-cancellation-public.test.mjs', count: 2},
  {name: 'submission-custody', file: 'client-submission-custody-public.test.mjs', count: 6},
  {name: 'submission-input-refusal', file: 'submission-epoch-public.test.mjs',
    pattern: 'durable known-input category|retired pre-Run history|explicit unresolved-history restart|typed Submission Conflict|typed fresh-epoch refusal', count: 11},
  {name: 'effect-reconciliation', file: 'client-effect-uncertainty.test.mjs', count: 3},
  {name: 'owner-observations', file: 'client-owner-observations-public.test.mjs', count: 2},
];
const selectedGroups = cancellationOnly
  ? groups.filter(group => ['original-cancellation', 'typed-cancellation', 'effect-cancellation'].includes(group.name))
  : submissionCustodyOnly ? groups.filter(group => group.name === 'submission-custody')
  : submissionRefusalOnly ? groups.filter(group => group.name === 'submission-input-refusal')
  : effectReconciliationOnly ? groups.filter(group => group.name === 'effect-reconciliation')
  : ownerObservationsOnly ? groups.filter(group => ['effect-reconciliation','owner-observations'].includes(group.name)) : groups;
const logs = [];
let passed = 0;
// Reuse one installation and the existing per-invocation bound. Preserve each
// completed group even if a later group fails; do not extend a test's timeout.
for (const group of selectedGroups) {
  const args = nodeTestArguments(['--test-concurrency', '1',
    ...(group.pattern === undefined ? [] : ['--test-name-pattern', group.pattern]),
    `adapters/host-node/${group.file}`]);
  const result = spawnSync(process.execPath, args, {cwd: root, env: environment, encoding: 'utf8', timeout: 120000});
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  logs.push(output);
  await writeFile(join(root, `${group.name}.log`), output);
  await writeFile(join(root, 'acceptance.log'), logs.join('\n'));
  console.log(output);
  const checked = assertTestExecution('node', process.execPath, args, result);
  assert.equal(checked.counts!.tests, group.count);
  assert.equal(checked.counts!.passed, group.count);
  passed += checked.counts!.passed;
}
assert.equal(passed, cancellationOnly ? 8 : submissionCustodyOnly ? 6 : submissionRefusalOnly ? 11
  : effectReconciliationOnly ? 3 : ownerObservationsOnly ? 5 : 52);
const after = checkoutState(repository);
if (!after.clean || after.revision !== state.revision) throw new Error('Checkout changed during acceptance');
await writeFile(join(root, 'acceptance.json'), `${JSON.stringify({sourceHead: state.revision,
  packageNames: names, productOverlay: false,
  expectedRows: submissionCustodyOnly ? [{id: 1}] : [{id: 1}, {id: 2}],
  expected121Rows: JSON.parse(await readFile(join(root, 'adapters/host-node/fixtures/read-121.expected.json'), 'utf8')),
  selection: cancellationOnly ? 'original-cancellation' : submissionCustodyOnly
    ? 'submission-custody' : submissionRefusalOnly ? 'submission-input-refusal'
    : effectReconciliationOnly ? 'effect-reconciliation' : ownerObservationsOnly ? 'scoped-owner-observations' : 'read-cancellation-submission-and-effect',
  cases: cancellationOnly ? {originalCancellationRecovery: 4, typedCancellationRecovery: 2, unknownEffectCancellationRecovery: 2}
    : submissionCustodyOnly ? {submissionCustodyLoss: 2, explicitSubmissionRestartProcessRecovery: 2,
      typedSubmissionProcessRecovery: 2}
    : submissionRefusalOnly ? {durableSubmissionInputRefusal: 2, retiredSubmissionLookup: 2,
      explicitSubmissionRestart: 3, typedSubmissionConflictAndReplay: 2, typedSubmissionEpochRefusal: 2}
    : effectReconciliationOnly ? {originalEffectReconciliation: 3}
    : ownerObservationsOnly ? {scopedOwnerSnapshots:2,originalEffectReconciliation:3}
    : {openingLoss: 4, receiptDurability: 4, actual121RunRecovery: 4,
      installedCapacity: 2, installedPrefixRecovery: 2, invalidCapacity: 1,
      finitePolicyOriginals: 1, publicRowPolicyAdmission: 2, publicHttpRowPolicyInstallation: 2,
      originalCancellationRecovery: 4, typedCancellationRecovery: 2,
      unknownEffectCancellationRecovery: 2,
      submissionCustodyLoss: 2, durableSubmissionInputRefusal: 2, retiredSubmissionLookup: 2,
      explicitSubmissionRestart: 3, explicitSubmissionRestartProcessRecovery: 2,
      typedSubmissionConflictAndReplay: 2, typedSubmissionEpochRefusal: 2, typedSubmissionProcessRecovery: 2,
      originalEffectReconciliation: 3,scopedOwnerSnapshots:2},
  passed: true}, null, 2)}\n`);
console.log(`Packed original Delivery lookup passed for ${state.revision}: ${root}`);
scratch.passed();
