// Discover cases through the pinned compiler's own test-driver metadata.
// --outline builds every executable first; package selection avoids only wholly
// testless packages. Moon still owns every driver, case, ordering and execution.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, relative, resolve, sep} from 'node:path';
import {parseCommands} from './verification-actions.mjs';
import {nativeCoreCiPartitions} from './ci-core-partitions.mjs';

export const nativeRelationWorkTestFile =
  'src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt';

export const nativeNonModelEntryTestFile =
  'src/platform_native/installed_arena_control/nonmodel_entry_original_physical_scoped_wbtest.mbt';

export const nativeProjectMockContentTestFile =
  'src/cmd/native_client/local_project_mock_content_physical_scoped_wbtest.mbt';

export const nativeRelationTargetIOTestFile =
  'src/platform_native/row_source/target_io_physical_scoped_wbtest.mbt';

export const nativeRelationTargetIOLineageTestFile =
  'src/platform_native/row_source/target_io_lineage_physical_scoped_wbtest.mbt';

export const nativeClientFileResponseTestFile =
  'src/platform_native/client_host/run_effect_file_response_wbtest.mbt';

// Both consume the same original file/Backing namespace constructor.
export const nativeRelationCaptureTestFiles = Object.freeze([
  'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt',
  'src/platform_native/row_source/listing_capture_physical_scoped_wbtest.mbt',
]);

const nativeRequestEffectHandoffTestFile =
  'src/platform_native/client_host/native_test/request_effect_test.mbt';

// These two independent fixtures use the same existing 8192-page backing.
// All other selected Arena cases retain their original 256-page declarations.
export function nativeCoreScopedBackingPages(source) {
  return source === nativeNonModelEntryTestFile || source ===
    'src/platform_native/installed_arena_control/local_host_crypto_physical_scoped_wbtest.mbt'
    ? 8192 : 256;
}

// Keep the established profile prefixes. Only this one new public-API case
// joins them; its package siblings and client_host retain their prior profile.
export function nativeCoreScopedAllocationProfile(source) {
  return source === nativeRequestEffectHandoffTestFile || source === nativeRelationWorkTestFile ||
    source === nativeClientFileResponseTestFile ||
    source === 'src/cmd/native_client/local_command_business_window_scoped_wbtest.mbt' ||
    source === 'src/platform_native/host_bootstrap/request_preparation_physical_scoped_wbtest.mbt' ||
    source === 'src/platform_native/host_bootstrap/root_control_physical_scoped_wbtest.mbt' ||
    source.startsWith('src/platform_native/installed_arena_control/') ||
    source.startsWith('src/platform_native/row_source/')
    ? 'scoped-review-values' : 'runtime-values';
}

// Observe counters only in these existing case-owned processes. Ordinary Core
// still exercises disabled observation and keeps its original allocation profile.
export function nativeCoreScopedTestEnvironment({source, index}) {
  return source === 'src/platform_native/client_host/local_initial_configuration_cid_wbtest.mbt' ||
    source === 'src/platform_native/client_host/local_initial_host_signing_original_wbtest.mbt' ||
    source === 'src/cmd/native_client/local_project_mock_physical_scoped_wbtest.mbt' && index === 13
    ? {ACTQL_NATIVE_TIMINGS: '1'} : {};
}

// These existing physical cases require the selected read provider. Ordinary
// Core deliberately also tests the absence of that provider, so its allocator
// must not be replaced globally. Both profiles remain required.
export const nativeScopedTestFiles = Object.freeze([
  nativeRequestEffectHandoffTestFile,
  'src/cmd/native_client/local_project_mock_physical_scoped_wbtest.mbt',
  'src/cmd/native_client/local_project_mock_request_physical_scoped_wbtest.mbt',
  // Its first-member control uses that same real Request/Arena facility.
  'src/cmd/native_client/local_effect_capture_wbtest.mbt',
  nativeProjectMockContentTestFile,
  'src/cmd/native_client/local_command_business_cleanup_wbtest.mbt',
  'src/cmd/native_client/local_command_business_window_scoped_wbtest.mbt',
  'src/platform_native/client_host/submitted_request_preparation_native_wbtest.mbt',
  'src/platform_native/client_host/submitted_request_source_native_wbtest.mbt',
  'src/platform_native/client_host/local_initial_configuration_cid_wbtest.mbt',
  'src/platform_native/client_host/local_initial_host_signing_original_wbtest.mbt',
  'src/platform_native/host_bootstrap/request_preparation_physical_scoped_wbtest.mbt',
  'src/platform_native/host_bootstrap/root_control_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/initial_preparation_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/local_host_crypto_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/original_read_consumer_phases_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/original_read_root_binding_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/original_read_working_window_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/request_preparation_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/request_source_frame_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/model_read_frame_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/owned_body_extent_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/retained_execution_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_operation_reentry_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_result_return_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_wal_original_physical_scoped_wbtest.mbt',
  ...nativeRelationCaptureTestFiles,
  nativeRelationTargetIOTestFile,
  nativeRelationTargetIOLineageTestFile,
  nativeClientFileResponseTestFile,
  nativeRelationWorkTestFile,
  nativeNonModelEntryTestFile,
]);
// These existing credential cases acquire the same real HTTP Client/peer
// fixture; the rest of credential_resource retains the ordinary write oracle.
export const nativeCoreHttpTestFiles = Object.freeze([
  'src/platform_native/credential_resource/remote_use_retention_native_wbtest.mbt',
  'src/platform_native/credential_resource/remote_initial_use_native_wbtest.mbt',
]);

export function nativeCoreHttpArguments(args) {
  assert(Array.isArray(args) && args.every(value => typeof value === 'string'));
  const selected = args.filter(value => value.startsWith('src/'));
  assert(selected.length > 0 && new Set(selected).size === selected.length &&
    selected.every(value => value === 'src/platform_native/http_client' || nativeCoreHttpTestFiles.includes(value)),
  'Core HTTP selection must retain only its existing peer-owned cases');
  assert(!args.includes('--target'), 'Core retains its original Native target');
  return args;
}

const residentSourceDirectory = 'src/platform_native/remote_resident_source_compute_tests';
const selectedGeometryFiles = new Set([
  'src/cmd/native_client/local_command_business_wbtest.mbt',
  'src/cmd/native_client/local_command_installed_profile_wbtest.mbt',
]);

// Keep each package's original test drivers together: splitting individual
// cases would compile the same large generated C executable on both runners.
// Separate the measured large packages, then balance other compiler units and
// case counts. This is not a time estimate.
export function nativeCoreOrdinaryPartitions(args, paths, records, count = 2) {
  assert(Number.isSafeInteger(count) && count >= 2 && count <= 16,
    'Invalid Native ordinary partition count');
  assert(Array.isArray(args) && args.every(value => typeof value === 'string'));
  assert(Array.isArray(paths) && new Set(paths).size === paths.length);
  const groups = new Map(), identities = new Set(), owners = new Map();
  for (const record of records) {
    const identity = JSON.stringify(record.entry);
    assert(!identities.has(identity), 'Duplicate original Native partition case');
    identities.add(identity);
    assert(typeof record.directory === 'string' && typeof record.source === 'string');
    assert(paths.includes(record.directory) || paths.includes(record.source),
      'Native partition case has no original selected input');
    const path = paths.includes(record.directory) ? record.directory : record.source;
    assert(!owners.has(path) || owners.get(path) === record.directory, 'Ambiguous Native input owner');
    owners.set(path, record.directory);
    if (!groups.has(record.directory)) groups.set(record.directory,
      {directory: record.directory, drivers: new Set(), cases: 0, records: []});
    const group = groups.get(record.directory);
    group.drivers.add(record.entry[0]);
    group.cases += record.benchmark ? 0 : 1;
    group.records.push(record);
  }
  assert([...groups.values()].filter(group => group.cases > 0).length >= count,
    'Enough nonempty Native ordinary package partitions required');
  // Seed the four-way plan with the measured large compiler units. Keeping
  // their whole packages separate avoids concentrating them by driver count;
  // all remaining packages retain the existing driver/case balance.
  const largeCompilerUnit = group => count === 4 &&
    (group.directory === 'src/canonical_value' || group.directory === 'src/query_integration' ||
      group.directory === 'src/cmd/native_client');
  const partitions = Array.from({length: count}, () => ({drivers: 0, cases: 0, directories: new Set()}));
  for (const group of [...groups.values()].sort((a, b) =>
    Number(largeCompilerUnit(b)) - Number(largeCompilerUnit(a)) ||
    b.drivers.size - a.drivers.size || b.cases - a.cases ||
    (a.directory < b.directory ? -1 : a.directory > b.directory ? 1 : 0))) {
    const selected = partitions.reduce((a, b) =>
      a.drivers < b.drivers || a.drivers === b.drivers && a.cases <= b.cases ? a : b);
    selected.drivers += group.drivers.size;
    selected.cases += group.cases;
    selected.directories.add(group.directory);
  }
  const result = partitions.map(partition => ({
    args: [...args, ...paths.filter(path => partition.directories.has(owners.get(path)))],
    cases: partition.cases,
  }));
  const selectedPaths = result.flatMap(partition => partition.args.slice(args.length));
  assert.equal(selectedPaths.length, paths.length, 'Native partition omitted an original input');
  assert.equal(new Set(selectedPaths).size, paths.length, 'Native partitions overlap');
  assert(result.every(partition => partition.cases > 0), 'Empty Native ordinary partition');
  assert.equal(result.reduce((sum, partition) => sum + partition.cases, 0),
    records.filter(record => !record.benchmark).length);
  return result;
}

export function nativeCorePartitionProfiles(profiles, value) {
  if (value === undefined || value === '') return profiles;
  const match = /^([1-4])\/(2|4)$/u.exec(value);
  const physical = nativeCoreCiPartitions.slice(4).includes(value);
  assert(physical || match && Number(match[1]) <= Number(match[2]), 'Invalid Native Core partition');
  const empty = {...profiles, ordinary: {args: null, cases: 0},
    http: {args: null, cases: 0}, source: {args: null, cases: 0},
    scoped: {args: null, cases: 0, tests: []}, physicalCases: 0, repeatedGeometryCases: 0};
  if (physical) {
    assert(profiles[value].cases > 0 && profiles[value].args?.length > 0,
      'Empty Native physical partition');
    return {...empty, [value]: profiles[value],
      ...(value === 'scoped' ? {physicalCases: profiles.physicalCases,
        repeatedGeometryCases: profiles.repeatedGeometryCases} : {})};
  }
  assert.equal(profiles.ordinary.partitions?.length, Number(match[2]), 'Missing Native Core partitions');
  const ordinary = profiles.ordinary.partitions[Number(match[1]) - 1];
  assert(ordinary.cases > 0 && ordinary.args?.length > 0, 'Empty Native Core partition');
  // Preserve the old two-runner local interface. The hosted four-way plan
  // gives each physical profile its own runner, with identical fixture owners.
  return value === '1/2' ? {...profiles, ordinary} : {...empty, ordinary};
}

// These original reference producers compile the large Client Host test
// driver. Only its assigned ordinary job and its scoped consumers need them;
// HTTP/Source jobs use their existing independently owned peer environments.
export function nativeCoreCheckpointRequired(profiles) {
  return profiles.ordinary.args?.some(value => value === 'src/platform_native/client_host' ||
    value.startsWith('src/platform_native/client_host/')) === true ||
    profiles.scoped.tests.some(test => test.source.startsWith('src/platform_native/client_host/'));
}

function partitionProfiles(args, records, ordinaryPartitions, compilerDirectories) {
  const scopedFiles = new Set(nativeScopedTestFiles);
  const physical = records.filter(record => scopedFiles.has(record.source));
  // These existing transport cases require the real mTLS/bearer peers from
  // the HTTP harness. Do not inject its optional environment into other Core
  // packages, or count a missing environment as transport execution.
  const httpFiles = new Set(nativeCoreHttpTestFiles);
  const http = records.filter(record => record.directory === 'src/platform_native/http_client' ||
    httpFiles.has(record.source));
  const source = records.filter(record => record.directory === residentSourceDirectory);
  const ordinary = records.filter(record => !scopedFiles.has(record.source) &&
    record.directory !== residentSourceDirectory && record.directory !== 'src/platform_native/http_client' &&
    !httpFiles.has(record.source));
  const runnable = records => records.filter(record => !record.benchmark).length;
  const geometry = ordinary.filter(record => !record.benchmark && selectedGeometryFiles.has(record.source));
  assert.equal(ordinary.length + physical.length + http.length + source.length, records.length);
  const affected = new Set([...physical, ...source, ...http].map(record => record.directory));
  {
    // Moon directory inputs include nested test packages. Use the parent's
    // original files when another package lives below it, rather than compile
    // or execute that child's cases again on the parent's runner.
    const directories = [...new Set([...compilerDirectories, ...records.map(record => record.directory)])];
    for (const directory of directories) if (directories.some(other =>
      other.startsWith(directory === '.' ? '' : directory + '/'))) affected.add(directory);
  }
  const ordinaryPaths = [...new Set(ordinary.map(record =>
    affected.has(record.directory) ? record.source : record.directory))];
  const selectedRecords = records.filter(record =>
    scopedFiles.has(record.source) || selectedGeometryFiles.has(record.source));
  const selectedPaths = [...new Set(selectedRecords.map(record => record.source))];
  const tests = selectedRecords.filter(record => !record.benchmark).map(record => {
    const index = record.entry[2].index;
    assert(Number.isSafeInteger(index) && index >= 0, 'Original compiler case index required');
    return {source: record.source, index};
  });
  assert.equal(new Set(tests.map(value => JSON.stringify(value))).size, tests.length,
    'Selected physical case must retain a unique original file/index');
  // Empty PATH would run the whole project, never an empty profile.
  return {
    ordinary: {args: ordinaryPaths.length ? [...args, ...ordinaryPaths] : null,
      cases: runnable(ordinary), ...(ordinaryPartitions ? {
        partitions: nativeCoreOrdinaryPartitions(args, ordinaryPaths, ordinary,
          ordinaryPartitions === true ? 2 : ordinaryPartitions),
      } : {})},
    http: {args: http.length ? [...args, ...new Set(http.map(record =>
      record.directory === 'src/platform_native/http_client' ? record.directory : record.source))] : null,
      cases: runnable(http)},
    source: {args: source.length ? [...args, residentSourceDirectory] : null, cases: runnable(source)},
    scoped: {args: selectedPaths.length ? [...args, ...selectedPaths] : null,
      cases: runnable(physical) + geometry.length, tests},
    physicalCases: runnable(physical),
    repeatedGeometryCases: geometry.length,
    uniqueCases: records.length,
    ...(records.length !== runnable(records)
      ? {benchmarkDeclarations: records.length - runnable(records)} : {}),
  };
}

export function nativeCoreTestSelection(repository, args, options = {}) {
  return compilerTestSelection(repository, args, options, 'native', false);
}

function runnableCompilerCase(record) {
  return !record.benchmark && !record.entry[2].attrs?.includes('skip');
}

// Portable selection uses the same bounded compiler metadata reader. A driver
// can contain only benchmarks or no cases; neither establishes test execution.
export function portableMoonTestCount(repository, args, target, options = {}) {
  assert(['js', 'wasm'].includes(target), 'Portable test metadata target required');
  return compilerTestSelection(repository, args, options, target, true).runnableCases;
}

export function nativeCoreFocusedTestCount(repository, args, options = {}) {
  return compilerTestSelection(repository, args, options, 'native', true).runnableCases;
}

function compilerTestSelection(repository, args, {
  env = process.env, execute = execFileSync, partitionProfiles: splitProfiles = false,
  ordinaryPartitions = false, timeoutMs = 60_000, now = Date.now, executionPackages,
  allowNestedFileInputs = false,
} = {}, target, countOnly) {
  assert(!countOnly || (!splitProfiles && !ordinaryPartitions && executionPackages === undefined));
  assert(!ordinaryPartitions || splitProfiles, 'Native partitions require original profile discovery');
  assert(executionPackages === undefined || splitProfiles, 'Dependency selection requires original Native profiles');
  assert(typeof allowNestedFileInputs === 'boolean' && (!allowNestedFileInputs ||
    splitProfiles && executionPackages !== undefined), 'Nested Native file inputs require an explicit package scope');
  assert(Number.isSafeInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 2147483647,
    'Native metadata timeout must be a finite positive timer duration');
  assert.equal(typeof now, 'function');
  repository = realpathSync(repository);
  let observed = now();
  assert(Number.isSafeInteger(observed) && observed >= 0);
  const deadline = observed + timeoutMs;
  assert(Number.isSafeInteger(deadline));
  const remaining = () => {
    const current = now();
    assert(Number.isSafeInteger(current) && current >= observed,
      'Native metadata clock cannot move backwards');
    observed = current;
    const timeout = deadline - current;
    assert(timeout > 0, 'Native test metadata discovery deadline exhausted');
    return timeout;
  };
  const run = values => {
    const result = execute('moon', values, {cwd: repository, env, encoding: 'utf8',
      timeout: remaining(), maxBuffer: 16 * 1024 ** 2});
    remaining();
    return result;
  };
  const discover = paths => {
    const plan = run(['test', '--target', target, ...args, ...paths, '--dry-run']);
    const drivers = new Map();
    for (const line of plan.split('\n')) {
      if (!line.includes(' generate-test-driver ')) continue;
      const parsed = parseCommands(line);
      assert.equal(parsed.reason, null);
      assert.equal(parsed.commands.length, 1);
      const command = parsed.commands[0].argv;
      assert.equal(basename(command[0]), 'moon');
      assert.equal(command[1], 'generate-test-driver');
      const value = option => {
        assert.equal(command.filter(arg => arg === option).length, 1);
        const result = command[command.indexOf(option) + 1];
        assert(result); return result;
      };
      assert.equal(value('--target'), target);
      const key = JSON.stringify([value('--pkg-name'), value('--driver-kind')]);
      assert(!drivers.has(key), 'Duplicate Native test driver');
      drivers.set(key, {command, metadata: resolve(repository, value('--output-metadata')),
        output: value('--output-driver')});
    }
    assert(countOnly || drivers.size > 0, 'No compiler-owned Native test drivers');
    return drivers;
  };
  const full = discover([]), packages = new Set(), cases = [], records = [], compilerDirectories = new Set();
  const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-test-metadata-')));
  let complete = false, ordinal = 0;
  try {
    for (const [key, driver] of full) {
      // Keep the original command for exact full/selected comparison. Only this
      // metadata invocation's two output destinations move to private scratch;
      // rewriting a byte-identical real test driver invalidates Moon's C cache.
      // Driver kind/package pairs are unique even when they have no cases.
      const privateDirectory = join(scratch, String(ordinal++));
      mkdirSync(privateDirectory, {mode: 0o700});
      const command = driver.command.slice(1);
      const metadataPath = join(privateDirectory, basename(driver.metadata));
      command[command.indexOf('--output-driver') + 1] = join(privateDirectory, basename(driver.output));
      command[command.indexOf('--output-metadata') + 1] = metadataPath;
      // Never execute the other dry-run commands: no package build, C or link.
      run(command);
      const metadata = JSON.parse(readFileSync(metadataPath, 'utf8'));
      assert(metadata.tests && typeof metadata.tests === 'object' && !Array.isArray(metadata.tests));
      driver.cases = [];
      const sources = driver.command.slice(2).filter(arg => arg.endsWith('.mbt') && arg !== driver.output);
      if (splitProfiles) for (const source of sources) {
        const directory = relative(repository, dirname(realpathSync(resolve(repository, source)))).split(sep).join('/') || '.';
        assert(directory !== '..' && !directory.startsWith('../'));
        compilerDirectories.add(directory);
      }
      for (const [file, tests] of Object.entries(metadata.tests)) {
        assert(Array.isArray(tests));
        if (tests.length === 0) continue;
        const originals = sources.filter(path => basename(path) === file);
        assert.equal(originals.length, 1, 'Native test file must have one compiler input');
        const directory = relative(repository, dirname(realpathSync(resolve(repository, originals[0]))));
        assert(directory !== '..' && !directory.startsWith('..' + sep));
        packages.add(directory || '.');
        const source = relative(repository, realpathSync(resolve(repository, originals[0]))).split(sep).join('/');
        // The compiler lists benchmark declarations in tests as well, but
        // moon test does not run them. Preserve every opaque identity and path;
        // only required execution counts use the compiler's separate class.
        const benchmarks = metadata.with_bench_args_tests?.[file] ?? [];
        assert(Array.isArray(benchmarks));
        const benchmarkIdentities = new Set(benchmarks.map(value => JSON.stringify(value)));
        assert.equal(benchmarkIdentities.size, benchmarks.length);
        assert(benchmarks.every(value => tests.some(test => JSON.stringify(test) === JSON.stringify(value))),
          'Benchmark declaration must be the same original compiler test entry');
        for (const test of tests) {
          const entry = [key, file, test];
          driver.cases.push(entry);
          records.push({entry, source, directory: directory || '.',
            benchmark: benchmarkIdentities.has(JSON.stringify(test))});
        }
      }
      cases.push(...driver.cases);
    }
    if (countOnly) {
      // Keep case identities opaque. Only the compiler's existing benchmark
      // class and explicit skip attribute are excluded from runnable counts.
      const runnableCases = records.filter(runnableCompilerCase).length;
      remaining(); complete = true;
      return {runnableCases};
    }
    let executionScope, scopedInputs;
    if (executionPackages !== undefined) {
      assert(Array.isArray(executionPackages) && executionPackages.length > 0 &&
        new Set(executionPackages).size === executionPackages.length, 'Invalid Native dependency package inventory');
      for (const path of executionPackages) {
        assert(typeof path === 'string' && path.length > 0 && !path.startsWith('/') &&
          !path.split('/').some(part => !part || part === '.' || part === '..'), 'Foreign Native dependency path');
        const original = realpathSync(resolve(repository, path));
        assert.equal(relative(repository, original).split(sep).join('/'), path, 'Aliased Native dependency package');
      }
      const requested = new Set(executionPackages);
      const subset = records.filter(record => requested.has(record.directory));
      const preview = partitionProfiles(args, subset, false, compilerDirectories);
      if (allowNestedFileInputs) {
        assert.equal(preview.http.cases + preview.source.cases + preview.scoped.cases, 0,
          'Explicit common Native files cannot select physical profiles');
        scopedInputs = preview.ordinary.args?.slice(args.length);
      }
      const ordinaryPaths = preview.ordinary.args?.slice(args.length) ?? [];
      const ordinaryPackages = new Set(subset.filter(record => runnableCompilerCase(record) &&
        (ordinaryPaths.includes(record.directory) || ordinaryPaths.includes(record.source))).map(record => record.directory));
      // A directory input includes nested packages. Keep the complete original
      // plan if the closure cannot express that boundary without changing any
      // compiler driver inputs or admitting an unrelated nested driver.
      const nestedOutside = [...compilerDirectories].some(directory => !requested.has(directory) &&
        executionPackages.some(parent => directory.startsWith(parent + '/')));
      // Existing partition balancing counts original driver/case inventory.
      // A skipped-only driver can win a partition even when two other packages
      // have runnable cases; test the actual assigned inputs before narrowing.
      const partitionCount = ordinaryPartitions === true ? 2 : ordinaryPartitions;
      const nonemptyPartitions = !ordinaryPartitions || ordinaryPackages.size >= partitionCount &&
        partitionProfiles(args, subset, ordinaryPartitions, compilerDirectories).ordinary.partitions.every(partition =>
          subset.some(record => runnableCompilerCase(record) &&
            (partition.args.slice(args.length).includes(record.directory) ||
              partition.args.slice(args.length).includes(record.source))));
      const admitted = subset.some(runnableCompilerCase) &&
        (!nestedOutside || allowNestedFileInputs) && nonemptyPartitions;
      executionScope = {packages:[...executionPackages].sort(), originalCases:cases.length,
        mode:admitted ? 'subset' : 'full-fallback',
        reason:admitted ? 'compiler-owned reverse dependency closure' : nestedOutside
          ? 'retain original inputs for an unselected nested Native package'
          : 'retain nonempty original Native cases and both ordinary partitions'};
      if (admitted) {
        records.splice(0, records.length, ...subset);
        cases.splice(0, cases.length, ...subset.map(record => record.entry));
        packages.clear(); for (const record of subset) packages.add(record.directory);
      }
      executionScope.selectedCases = cases.length;
    }
    assert(cases.length > 0, 'No compiler-owned Native test cases');
    const paths = executionScope?.mode === 'subset' && allowNestedFileInputs ? scopedInputs : [...packages];
    assert(Array.isArray(paths) && paths.length > 0, 'Nonempty original Native inputs required');
    const selected = discover(paths), selectedCases = [];
    for (const [key, driver] of selected) {
      const original = full.get(key);
      assert(original, 'Foreign selected Native driver');
      assert.deepEqual(driver.command, original.command,
        'Selected Native driver inputs must retain their complete original case inventory');
      selectedCases.push(...original.cases);
    }
    assert.deepEqual(selectedCases, cases, 'Native selection changed case identity or order');
    const result = {args: [...args, ...paths], cases: cases.length, packages: paths.length,
      prunedDrivers: full.size - selected.size};
    if (executionScope) result.executionScope = executionScope;
    const benchmarks = records.filter(record => record.benchmark).length;
    if (benchmarks) result.benchmarkDeclarations = benchmarks;
    if (splitProfiles) result.profiles = partitionProfiles(args, records, ordinaryPartitions, compilerDirectories);
    if (ordinaryPartitions) {
      const ownedDrivers = new Set();
      for (const partition of result.profiles.ordinary.partitions) {
        const paths = partition.args.slice(args.length);
        const assigned = records.filter(record => paths.includes(record.directory) || paths.includes(record.source));
        const packages = new Set(assigned.map(record => JSON.parse(record.entry[0])[0]));
        const drivers = discover(paths);
        assert(drivers.size > 0, 'Empty compiler-owned Native partition');
        for (const [key, driver] of drivers) {
          const original = full.get(key);
          assert(original, 'Foreign compiler-owned Native partition driver');
          assert(!ownedDrivers.has(key), 'Native partition compiles an overlapping original driver');
          ownedDrivers.add(key);
          assert.deepEqual(driver.command, original.command,
            'Native partition changed original compiler driver inputs');
          // A blackbox-only package can also have an empty internal driver.
          // Its original package identity still belongs to this runner; no
          // source-directory guess may reject it or admit another package.
          assert(packages.has(JSON.parse(key)[0]),
          'Native partition selected a foreign or nested package driver: ' + key);
        }
        assert(assigned.every(record => drivers.has(record.entry[0])),
          'Native partition omitted an original compiler case driver');
        partition.drivers = [...drivers.keys()];
      }
    }
    remaining();
    complete = true;
    return result;
  } finally {
    // Every compiler child above is synchronous and reaped. Preserve failed
    // discovery for diagnosis; never adopt or remove the real build outputs.
    if (complete) rmSync(scratch, {recursive: true});
    else console.error('Native metadata discovery failed; scratch kept: ' + scratch);
  }
}
