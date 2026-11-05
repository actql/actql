// Reuse the exact Client packages for authored read, cancellation and Effect recovery.
// Only test inputs/support are copied; every product import uses the installation.
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, relative, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {checkoutState, packClientPackages, packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {nodeTestArguments, assertTestExecution} from './test-execution.mjs';

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
const tarball = name => `actql-${name}-0.0.0-development.tgz`;
const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
  prefix: 'packed-read-opening-', label: 'packed original Delivery lookup',
  digests: () => [...names.map(tarball), 'packed-client-packages.json']});
const root = scratch.path;
const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
function run(command, args, cwd, timeout = 120000) {
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
const support = [
  'adapters/host-node/client-read-opening.test.mjs',
  'adapters/host-node/client-read-opening.fixture.mjs',
  'adapters/host-node/client-read-opening-restart.fixture.mjs',
  'adapters/host-node/client-read-run-capacity.test.mjs',
  'adapters/host-node/client-read-run-capacity.fixture.mjs',
  'adapters/host-node/fixtures/read-121.program.json',
  'adapters/host-node/fixtures/read-121.expected.json',
  'adapters/host-node/client-values-row-limit.test.mjs',
  'adapters/host-node/client-values-row-limit.fixture.mjs',
  'adapters/host-node/client-cancellation-public.test.mjs',
  'adapters/host-node/client-cancellation-attempt-installed.test.mjs',
  'adapters/host-node/client-cancellation-public.fixture.mjs',
  'adapters/host-node/client-submission-custody-public.test.mjs',
  'adapters/host-node/client-submission-custody-public.fixture.mjs',
  'adapters/host-node/submission-epoch-public.test.mjs',
  'adapters/host-node/client-effect-uncertainty.test.mjs',
  'adapters/host-node/client-owner-observations-public.test.mjs',
  'adapters/host-node/client-effect-cancellation-public.test.mjs',
  'adapters/connectors/salesforce/test/read-compute-effect.fixture.mjs',
  'adapters/connectors/salesforce/test/read-compute-effect.embedded-child.mjs',
  'adapters/connectors/salesforce/test/salesforce-effect-site.fixture.mjs',
  'scripts/fixtures/client-effect-uncertainty.child.mjs',
  'scripts/fixtures/client-effect-cancellation.child.mjs',
  'adapters/site-node/https-exchange-fixture.mjs',
  'scripts/owned-scratch.mjs',
  'packages/sdk/fixtures/values.json',
  'packages/sdk/fixtures/values.environment.json',
];
for (const path of support) {
  const output = join(root, path);
  await mkdir(join(output, '..'), {recursive: true});
  let text = await readFile(join(repository, path), 'utf8');
  if (path.endsWith('.mjs') && path !== 'scripts/owned-scratch.mjs') {
    text = text.replace(
      "import {openInstalledRemoteHttpHost, publishInstalledEffect} from\n  '../../../host-node/embedded-local.mjs';",
      "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';\n" +
      "import {publishEffect as publishInstalledEffect} from '@actql/local-node';");
    text = text.replace(/import \{connectEmbeddedLocal\} from ['"](?:\.\.\/)+(?:adapters\/)?host-node\/embedded-local\.mjs['"];/gu,
      "import {connect as connectEmbeddedLocal} from '@actql/local-node';");
    if (path === 'scripts/fixtures/client-effect-cancellation.child.mjs') {
      text = text.replace(
        "import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';",
        "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';");
    }
    if (path === 'adapters/host-node/client-owner-observations-public.test.mjs' ||
        path === 'adapters/host-node/client-values-row-limit.test.mjs' ||
        path === 'adapters/host-node/client-values-row-limit.fixture.mjs' ||
        path === 'adapters/host-node/client-cancellation-public.fixture.mjs' ||
        path === 'adapters/host-node/submission-epoch-public.test.mjs') {
      text = text.replace(
        "import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';",
        "import {connect as connectEmbeddedLocal} from '@actql/local-node';\n" +
        "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';");
      text = text.replace(
        "import {connectEmbeddedLocal,openInstalledRemoteHttpHost} from './embedded-local.mjs';",
        "import {connect as connectEmbeddedLocal} from '@actql/local-node';\n" +
        "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';");
    }
    text = text.replace(/from\s+(['"])([^'"]+)\1/gu, (original, quote, specifier) => {
      if (specifier.startsWith('node:') || specifier.startsWith('@actql/')) return original;
      const target = relative(repository, resolve(repository, path, '..', specifier));
      if (support.includes(target)) return original;
      if (target === 'packages/client-wire/index.mjs') return `from ${quote}@actql/client-wire${quote}`;
      if (target === 'packages/sdk/index.mjs') return `from ${quote}@actql/sdk${quote}`;
      if (target === 'packages/sdk/host-port.mjs') return `from ${quote}@actql/sdk/host-port${quote}`;
      if (target === '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js') {
        return `from ${quote}@actql/local-node/runtime${quote}`;
      }
      if (target === '_build/js/release/build/connectors/salesforce/host_node/host_node.js') {
        return `from ${quote}${pathToFileURL(join(installedHost, target)).href}${quote}`;
      }
      if (!target.startsWith('adapters/')) throw new Error(`Unpackaged fixture import: ${target}`);
      return `from ${quote}${pathToFileURL(join(installedHost, target)).href}${quote}`;
    }).replace(/new URL\('((?:\.\.\/)+spec\/[^']+)', import.meta.url\)/gu,
      (_original, specifier) => `new URL(${JSON.stringify(pathToFileURL(join(installedHost,
        relative(repository, resolve(repository, path, '..', specifier)))).href)})`);
    text = text.replace(/new URL\(\s*'\.\.\/\.\.\/\.\.\/\.\.\/_build\/js\/release\/build\/connectors_builtin_node\/' \+\s*'connectors_builtin_node\.js', import\.meta\.url\)/gu,
      `new URL(${JSON.stringify(pathToFileURL(join(installedHost,
        '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')).href)})`);
  }
  await writeFile(output, text);
}
const custodyInputs = join(root, 'submission-custody-inputs.json');
await writeFile(custodyInputs, JSON.stringify({scratch: root, runtime: {
  client: '@actql/node', sdk: '@actql/sdk', httpHost: '@actql/local-node/http-host'}}));
environment.ACTQL_SUBMISSION_CUSTODY_ACCEPTANCE_INPUTS = custodyInputs;
const groups = [
  {name: 'opening-and-receipt', file: 'client-read-opening.test.mjs', count: 8},
  {name: 'interrupted-121-run', file: 'client-read-run-capacity.test.mjs', count: 4},
  {name: 'installed-capacity', file: 'client-values-row-limit.test.mjs', count: 5},
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
  assert.equal(checked.counts.tests, group.count);
  assert.equal(checked.counts.passed, group.count);
  passed += checked.counts.passed;
}
assert.equal(passed, cancellationOnly ? 8 : submissionCustodyOnly ? 6 : submissionRefusalOnly ? 11
  : effectReconciliationOnly ? 3 : ownerObservationsOnly ? 5 : 47);
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
      installedCapacity: 2, installedPrefixRecovery: 2, invalidCapacity: 1, originalCancellationRecovery: 4, typedCancellationRecovery: 2,
      unknownEffectCancellationRecovery: 2,
      submissionCustodyLoss: 2, durableSubmissionInputRefusal: 2, retiredSubmissionLookup: 2,
      explicitSubmissionRestart: 3, explicitSubmissionRestartProcessRecovery: 2,
      typedSubmissionConflictAndReplay: 2, typedSubmissionEpochRefusal: 2, typedSubmissionProcessRecovery: 2,
      originalEffectReconciliation: 3,scopedOwnerSnapshots:2},
  passed: true}, null, 2)}\n`);
console.log(`Packed original Delivery lookup passed for ${state.revision}: ${root}`);
scratch.passed();
