// Discover cases through the pinned compiler's own Native driver metadata.
// --outline builds every executable first; package selection avoids only wholly
// testless packages. Moon still owns every driver, case, ordering and execution.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, realpathSync} from 'node:fs';
import {basename, dirname, relative, resolve, sep} from 'node:path';
import {parseCommands} from './verification-actions.mjs';

export function nativeCoreTestSelection(repository, args, {
  env = process.env, execute = execFileSync,
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
  const full = discover([]), packages = new Set(), cases = [];
  for (const [key, driver] of full) {
    // Never execute the other dry-run commands: no package build, C or link.
    run(driver.command.slice(1));
    const metadata = JSON.parse(readFileSync(driver.metadata, 'utf8'));
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
      for (const test of tests) driver.cases.push([key, file, test]);
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
  return {args: [...args, ...paths], cases: cases.length, packages: paths.length,
    prunedDrivers: full.size - selected.size};
}
