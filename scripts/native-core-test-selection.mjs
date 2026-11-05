// Discover cases through the pinned compiler's own Native driver metadata.
// --outline builds every executable first; package selection avoids only wholly
// testless packages. Moon still owns every driver, case, ordering and execution.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, relative, resolve, sep} from 'node:path';
import {parseCommands} from './verification-actions.mjs';

// These existing physical cases require the selected read provider. Ordinary
// Core deliberately also tests the absence of that provider, so its allocator
// must not be replaced globally. Both profiles remain required.
export const nativeScopedTestFiles = Object.freeze([
  'src/cmd/native_client/local_command_business_cleanup_wbtest.mbt',
  'src/platform_native/installed_arena_control/initial_preparation_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/local_host_crypto_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/original_read_consumer_phases_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/original_read_root_binding_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/retained_execution_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_operation_reentry_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_result_return_physical_scoped_wbtest.mbt',
  'src/platform_native/installed_arena_control/store_wal_original_physical_scoped_wbtest.mbt',
]);
const selectedGeometryFiles = new Set([
  'src/cmd/native_client/local_command_business_wbtest.mbt',
  'src/cmd/native_client/local_command_installed_profile_wbtest.mbt',
]);

function partitionProfiles(args, records) {
  const scopedFiles = new Set(nativeScopedTestFiles);
  const physical = records.filter(record => scopedFiles.has(record.source));
  const ordinary = records.filter(record => !scopedFiles.has(record.source));
  const geometry = ordinary.filter(record => selectedGeometryFiles.has(record.source));
  assert.equal(ordinary.length + physical.length, records.length);
  const affected = new Set(physical.map(record => record.directory));
  const ordinaryPaths = [...new Set(ordinary.map(record =>
    affected.has(record.directory) ? record.source : record.directory))];
  const selectedRecords = records.filter(record =>
    scopedFiles.has(record.source) || selectedGeometryFiles.has(record.source));
  const selectedPaths = [...new Set(selectedRecords.map(record => record.source))];
  const tests = selectedRecords.map(record => {
    const index = record.entry[2].index;
    assert(Number.isSafeInteger(index) && index >= 0, 'Original compiler case index required');
    return {source: record.source, index};
  });
  assert.equal(new Set(tests.map(value => JSON.stringify(value))).size, tests.length,
    'Selected physical case must retain a unique original file/index');
  // Empty PATH would run the whole project, never an empty profile.
  return {
    ordinary: {args: ordinaryPaths.length ? [...args, ...ordinaryPaths] : null,
      cases: ordinary.length},
    scoped: {args: selectedPaths.length ? [...args, ...selectedPaths] : null,
      cases: physical.length + geometry.length, tests},
    physicalCases: physical.length,
    repeatedGeometryCases: geometry.length,
    uniqueCases: records.length,
  };
}

export function nativeCoreTestSelection(repository, args, {
  env = process.env, execute = execFileSync, partitionProfiles: splitProfiles = false,
} = {}) {
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
  const full = discover([]), packages = new Set(), cases = [], records = [];
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
      for (const [file, tests] of Object.entries(metadata.tests)) {
        assert(Array.isArray(tests));
        if (tests.length === 0) continue;
        const originals = sources.filter(path => basename(path) === file);
        assert.equal(originals.length, 1, 'Native test file must have one compiler input');
        const directory = relative(repository, dirname(realpathSync(resolve(repository, originals[0]))));
        assert(directory !== '..' && !directory.startsWith('..' + sep));
        packages.add(directory || '.');
        const source = relative(repository, realpathSync(resolve(repository, originals[0]))).split(sep).join('/');
        for (const test of tests) {
          const entry = [key, file, test];
          driver.cases.push(entry);
          records.push({entry, source, directory: directory || '.'});
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
    if (splitProfiles) result.profiles = partitionProfiles(args, records);
    complete = true;
    return result;
  } finally {
    // Every compiler child above is synchronous and reaped. Preserve failed
    // discovery for diagnosis; never adopt or remove the real build outputs.
    if (complete) rmSync(scratch, {recursive: true});
    else console.error('Native metadata discovery failed; scratch kept: ' + scratch);
  }
}
