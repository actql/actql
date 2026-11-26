// First Linux execution proof for reviewed platform cases. This does not retire
// Darwin cases or admit the physical siblings in the same compiler driver.
import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCoreLinuxCommonArguments} from './ci-core-partitions.mjs';
import {nativeCoreTestCaseInventory} from './native-core-test-selection.mjs';
import {nativeCoreCCompiler} from './native-core-c-compiler.mjs';
import {runMeasuredNativeTests} from './native-core-measured-tests.mjs';
import {runLocalCheck} from './local-checks-guard.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {commandSource} from './packed-query-evidence.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
export const reviewedNativeCoreSource = 'src/platform_native/row_source/capacity_wbtest.mbt';
const packageName = 'actql/actql/platform_native/row_source';
export const reviewedNativeCoreNames = Object.freeze([
  'Native transport quote rejects each invalid layout fact and overflow',
  'relation file preflight quotes the same complete constructor overlap without acquisition',
  'Native prepared File provider quotes its exact ordered projection',
  'completed Native Query keeps its full original typed projection and initial peak',
  'relation file preflight rejects equivalent declaration foreign requirement and wrong resource',
  'relation file resource-only preflight preserves mapping and selection refusals',
  'Source caller preparation inventory matches independent constructor vectors',
  'Native target Text response backing keeps original guards and maximum',
]);
// Closed reviewed scope, not all tests in this platform package. Layout
// witnesses still run on both OSes; no Darwin case is retired by this list.
export const reviewedNativeCoreFiles = Object.freeze([
  Object.freeze({source: reviewedNativeCoreSource, names: reviewedNativeCoreNames}),
  Object.freeze({source: 'src/platform_native/row_source/keyed_read_profile_wbtest.mbt', names: Object.freeze([
    'Native file read profile retains same provider roles and refuses missing projections',
    'Native file read profile preserves admitted long physical paths',
  ])}),
  Object.freeze({source: 'src/platform_native/row_source/file_listing_page_wbtest.mbt', names: Object.freeze([
    'Native file listing projects original rows with Source-issued refs and row-bound versions',
    'Native file listing refuses unavailable nominal refs and parent retirement during issuance',
    'Native file listing validates physical roles before issuance and quotes bounded construction',
    'Native file listing canonical version keeps the full admitted raw byte boundary',
  ])}),
  Object.freeze({source: 'src/platform_native/row_source/file_content_bytes_wbtest.mbt', names: Object.freeze([
    'Native file Content extracts exact bytes only for the original listing version',
    'Native file Content rejects a changed row even when its authored label is unchanged',
    'Native file Content preserves decomposed Unicode CRLF empty bytes and the exact byte ceiling',
    'Native file Content refuses unavailable fields retired originals and invalid constructor bounds',
  ])}),
]);
type LocalCheckConfig = Parameters<typeof runLocalCheck>[0];
type CompilerRecord = ReturnType<typeof nativeCoreTestCaseInventory>['records'][number];
type ReviewedSuiteOptions = {
  root?: string;
  env?: NodeJS.ProcessEnv;
  platform?: NodeJS.Platform;
  arch?: NodeJS.Architecture;
  execute?: (config: LocalCheckConfig) => number | Promise<number>;
};
const caseKey = (source: string, name: unknown) => JSON.stringify([source, name]);

export function selectReviewedNativeCoreCases(inventory: {records: readonly CompilerRecord[]}) {
  assert(Array.isArray(inventory?.records), 'Actual compiler case inventory required');
  const records = inventory.records.filter(record => reviewedNativeCoreFiles.some(file => file.source === record.source));
  const names = new Set<string>(), indexes = new Set<string>();
  for (const record of records) {
    const [driver, file, test] = record.entry;
    const reviewed = reviewedNativeCoreFiles.find(file => file.source === record.source);
    const nameKey = caseKey(record.source, test.name), indexKey = caseKey(record.source, test.index);
    assert.deepEqual(JSON.parse(driver), [packageName, 'whitebox'], 'Foreign reviewed Native driver');
    assert.equal(file, record.source.split('/').at(-1));
    assert.equal(record.directory, 'src/platform_native/row_source');
    assert.equal(record.benchmark, false, 'Reviewed Native cases cannot become benchmarks');
    assert.deepEqual(test.attrs, [], 'Reviewed Native cases cannot be skipped or reclassified');
    assert(Number.isSafeInteger(test.index) && test.index >= 0 && !indexes.has(indexKey),
      'Duplicate or invalid reviewed Native case index');
    assert(reviewed!.names.includes(test.name as string) && !names.has(nameKey),
      'Unknown or duplicate reviewed Native case');
    names.add(nameKey); indexes.add(indexKey);
  }
  const expected = reviewedNativeCoreFiles.flatMap(file => file.names.map(name => caseKey(file.source, name)));
  assert.deepEqual([...names].sort(), expected.sort(),
    'Missing reviewed Native case');
  return records;
}

export function verifyReviewedNativeCoreOutput(records: readonly CompilerRecord[], output: string) {
  // The nonzero wrapper independently checks Moon's total. Also check identity:
  // an equal number of unrelated cases is not the selected Linux proof.
  const selected = selectReviewedNativeCoreCases({records});
  const expected = new Set(selected.map(record => caseKey(record.source, record.entry[2].name))), observed = new Set<string>();
  for (const line of output.split(/\r?\n/u)) {
    if (!/^\[[^\]]+\] test /u.test(line)) continue;
    const match = /^\[actql\/actql\] test ([^\s:]+):\d+ \(("(?:[^"\\]|\\.)*")\) ok$/u.exec(line);
    assert(match, 'Foreign, failed or skipped Native execution result');
    const key = caseKey('src/' + match[1], JSON.parse(match[2]));
    assert(expected.has(key) && !observed.has(key), 'Unknown or duplicate Native execution result');
    observed.add(key);
  }
  assert.deepEqual([...observed].sort(), [...expected].sort(), 'Missing actual Native execution result');
}

export async function runReviewedNativeCoreSuite({root = repository, env = process.env,
  platform = process.platform, arch = process.arch, execute = runLocalCheck}: ReviewedSuiteOptions = {}) {
  assert.equal(platform, 'linux', 'Reviewed Native execution requires Linux');
  assert.equal(arch, 'x64', 'Reviewed Native execution requires the hosted Linux architecture');
  assert.equal(realpathSync(root), realpathSync(repository), 'Reviewed Native entry must own this checkout');
  // A separate supervised child owns this suite's scratch and descendants.
  // Twenty minutes is a finite diagnostic envelope within the existing 90min
  // Native job; it is not a measured duration or a product resource allowance.
  return await execute({root, heavy: true, timeoutSeconds: 1200, graceSeconds: 5,
    steps: [{name: 'Reviewed ordinary Native platform cases', command: process.execPath,
      args: ['--input-type=module', '-e',
        "import {executeReviewedNativeCoreSuite} from './scripts/native-core-reviewed-suite.mjs'; process.exitCode = await executeReviewedNativeCoreSuite();"],
      env: {...env, MOONBIT_NEW_NATIVE: '0', ACTQL_TEST_NATIVE_CORE_PARTITION: undefined,
        ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: undefined}}]});
}

export async function executeReviewedNativeCoreSuite() {
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  const root = realpathSync(repository), source = commandSource(root);
  assert(source.revision && source.dirty === false, 'Clean same-source Native checkout required');
  const scratch = await createOwnedScratch({parent: join(process.env.RUNNER_TEMP ?? tmpdir(), 'native-reviewed'),
    prefix: 'ordinary-', label: 'Reviewed Native ordinary cases'});
  const env = {...process.env, MOONBIT_NEW_NATIVE: '0',
    ACTQL_TEST_NATIVE_CORE_PARTITION: undefined, ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: undefined,
    ...nativeCoreCCompiler(root, scratch.path)};
  const args = ['--target', 'native', ...nativeCoreLinuxCommonArguments, ...reviewedNativeCoreFiles.map(file => file.source)];
  const inventory = nativeCoreTestCaseInventory(root, args.slice(2), {env});
  const records = selectReviewedNativeCoreCases(inventory);
  const evidenceScratch = join(root, '_build', 'native-reviewed-evidence');
  mkdirSync(evidenceScratch, {recursive: true});
  // A unique evidence namespace keeps the completed raw execution inspectable
  // even when this suite's temporary compiler/scratch namespace is removed.
  const evidence = mkdtempSync(join(evidenceScratch, 'ordinary-'));
  writeFileSync(join(evidence, 'selection.json'), JSON.stringify({source, target: 'native',
    profile: 'ordinary', records, compilerRunnableCases: inventory.runnableCases,
    darwinRetired: false}, null, 2) + '\n', {flag: 'wx'});
  console.log('ACTQL_NATIVE_REVIEWED_SELECTION ' + JSON.stringify({source, target: 'native',
    profile: 'ordinary', records, compilerRunnableCases: inventory.runnableCases, darwinRetired: false}));
  const status = runMeasuredNativeTests(args, {cwd: root, env, timeout: 19 * 60_000,
    expectedTests: records.length, evidenceScratch: evidence});
  if (status !== 0) return status;
  const executions = readdirSync(evidence).filter(name => name.startsWith('focused-test-'));
  assert.equal(executions.length, 1, 'One actual counted Native execution required');
  verifyReviewedNativeCoreOutput(records, readFileSync(join(evidence, executions[0], '001.stdout.log'), 'utf8'));
  assert.deepEqual(commandSource(root), source, 'Reviewed Native source changed during execution');
  console.log('ACTQL_NATIVE_REVIEWED_EXECUTION ' + JSON.stringify({source: source.revision,
    profile: 'ordinary', cases: records.length, identityVerified: true, evidence}));
  scratch.passed();
  return 0;
}
