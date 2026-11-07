// Discover cases through the pinned compiler's own Native driver metadata.
// --outline builds every executable first; package selection avoids only wholly
// testless packages. Moon still owns every driver, case, ordering and execution.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, relative, resolve, sep} from 'node:path';
import {parseCommands} from './verification-actions.mjs';

export const nativeRelationWorkTestFile =
  'src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt';

export const nativeNonModelEntryTestFile =
  'src/platform_native/installed_arena_control/nonmodel_entry_original_physical_scoped_wbtest.mbt';

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
  return source === nativeRelationWorkTestFile ||
    source === 'src/platform_native/host_bootstrap/request_preparation_physical_scoped_wbtest.mbt' ||
    source === 'src/platform_native/host_bootstrap/root_control_physical_scoped_wbtest.mbt' ||
    source.startsWith('src/platform_native/installed_arena_control/') ||
    source.startsWith('src/platform_native/row_source/')
    ? 'scoped-review-values' : 'runtime-values';
}

// These existing physical cases require the selected read provider. Ordinary
// Core deliberately also tests the absence of that provider, so its allocator
// must not be replaced globally. Both profiles remain required.
export const nativeScopedTestFiles = Object.freeze([
  'src/cmd/native_client/local_command_business_cleanup_wbtest.mbt',
  'src/platform_native/client_host/submitted_request_preparation_native_wbtest.mbt',
  'src/platform_native/client_host/submitted_request_source_native_wbtest.mbt',
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
  'src/platform_native/installed_arena_control/retained_execution_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_operation_reentry_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_result_return_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_wal_original_physical_scoped_wbtest.mbt',
  'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt',
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
// Balance compiler units first, then case counts; this is not a time estimate.
export function nativeCoreOrdinaryPartitions(args, paths, records) {
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
  assert([...groups.values()].filter(group => group.cases > 0).length >= 2,
    'Two nonempty Native ordinary package partitions required');
  const partitions = Array.from({length: 2}, () => ({drivers: 0, cases: 0, directories: new Set()}));
  for (const group of [...groups.values()].sort((a, b) =>
    b.drivers.size - a.drivers.size || b.cases - a.cases ||
    (a.directory < b.directory ? -1 : a.directory > b.directory ? 1 : 0))) {
    const selected = partitions[0].drivers < partitions[1].drivers ||
      partitions[0].drivers === partitions[1].drivers && partitions[0].cases <= partitions[1].cases
      ? partitions[0] : partitions[1];
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
  assert(value === '1/2' || value === '2/2', 'Invalid Native Core partition');
  assert.equal(profiles.ordinary.partitions?.length, 2, 'Missing Native Core partitions');
  const ordinary = profiles.ordinary.partitions[Number(value[0]) - 1];
  assert(ordinary.cases > 0 && ordinary.args?.length > 0, 'Empty Native Core partition');
  return value === '1/2' ? {...profiles, ordinary} : {...profiles, ordinary,
    http: {args: null, cases: 0}, source: {args: null, cases: 0},
    scoped: {args: null, cases: 0, tests: []}, physicalCases: 0, repeatedGeometryCases: 0};
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
  if (ordinaryPartitions) {
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
        partitions: nativeCoreOrdinaryPartitions(args, ordinaryPaths, ordinary),
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

export function nativeCoreTestSelection(repository, args, {
  env = process.env, execute = execFileSync, partitionProfiles: splitProfiles = false,
  ordinaryPartitions = false,
} = {}) {
  assert(!ordinaryPartitions || splitProfiles, 'Native partitions require original profile discovery');
  repository = realpathSync(repository);
  const deadline = Date.now() + 60000;
  const run = values => {
    const timeout = deadline - Date.now();
    assert(timeout > 0, 'Native test metadata discovery deadline exhausted');
    return execute('moon', values, {cwd: repository, env, encoding: 'utf8',
      timeout, maxBuffer: 16 * 1024 ** 2});
  };
  const discover = paths => {
    const plan = run(['test', '--target', 'native', ...args, ...paths, '--dry-run']);
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
      assert.equal(value('--target'), 'native');
      const key = JSON.stringify([value('--pkg-name'), value('--driver-kind')]);
      assert(!drivers.has(key), 'Duplicate Native test driver');
      drivers.set(key, {command, metadata: resolve(repository, value('--output-metadata')),
        output: value('--output-driver')});
    }
    assert(drivers.size > 0, 'No compiler-owned Native test drivers');
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
      if (ordinaryPartitions) for (const source of sources) {
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
    assert(cases.length > 0, 'No compiler-owned Native test cases');
    const paths = [...packages], selected = discover(paths), selectedCases = [];
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
    complete = true;
    return result;
  } finally {
    // Every compiler child above is synchronous and reaped. Preserve failed
    // discovery for diagnosis; never adopt or remove the real build outputs.
    if (complete) rmSync(scratch, {recursive: true});
    else console.error('Native metadata discovery failed; scratch kept: ' + scratch);
  }
}
