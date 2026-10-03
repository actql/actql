import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {classifyJob, classifyMoon, heavyJobs} from './local-checks-policy.mjs';

test('full Moon test and build remain heavy despite target and build options', () => {
  for (const kind of ['test', 'build']) {
    for (const args of [[], ['--target', 'js'], ['--target=wasm', '--release'],
      ['--deny-warn', '-j', '2'], ['--target-dir', '_build/scratch'],
      ['--warn-list', '-a', '--render-no-loc', 'error'],
      ['.'], ['./'], ['src'], ['./src/'], ['src/foo/../'],
      ['src/foo', 'src']]) {
      const result = classifyMoon(kind, args);
      assert.equal(result.classification, 'full', `${kind} ${args}`);
      assert.equal(result.heavy, true);
      assert.ok(result.alternatives.length > 0);
    }
  }
});

test('Moon package and file/path selections stay usable', () => {
  for (const args of [
    ['-p', 'execution_relation'], ['--package=execution_relation'],
    ['--package', 'a', 'b'], ['--target', 'js', 'src/execution_relation'],
    ['src/execution_relation/cases_test.mbt'],
    ['--', 'src/execution_relation'],
    ['-p', 'execution_relation', '--filter', 'selected *'],
  ]) assert.equal(classifyMoon('test', args).heavy, false, args.join(' '));
  for (const args of [['src/bridge'], ['--release', '--target=js', 'src/bridge']]) {
    assert.equal(classifyMoon('build', args).classification, 'focused');
  }
});

test('filters, test indices and option values do not masquerade as package selection', () => {
  for (const args of [
    ['--filter', 'selected'], ['--filter=selected'], ['-f', 'selected'],
    ['--filter', 'src/a'], ['--index', '2'], ['--doc-index', '1'],
    ['--wasm-policy', 'policy.json'], ['--patch-file', 'patch.json'],
    ['-p', '*'], ['--package', 'src/*'],
  ]) assert.equal(classifyMoon('test', args).heavy, true, args.join(' '));
});

test('unknown flags or malformed option values cannot be mistaken for focused arguments', () => {
  for (const args of [
    ['--mystery', 'src/a'], ['--mystery=src/a'], ['--target'],
    ['--package'], ['--package='], ['-p', '--target', 'js'],
    ['--filtering', 'x'], ['--allow-heavy'],
    ['-p', 'a', '--new-option', 'b'],
  ]) {
    const result = classifyMoon('test', args);
    assert.equal(result.classification, 'unknown', args.join(' '));
    assert.equal(result.heavy, true);
  }
  assert.equal(classifyMoon('build', ['-p', 'a']).classification, 'unknown');
  assert.equal(classifyMoon('check', []).classification, 'unknown');
});

test('help and dry-run are reporting, but outline and build-only can still build', () => {
  for (const kind of ['test', 'build']) {
    for (const option of ['-h', '--help', '--dry-run']) {
      assert.equal(classifyMoon(kind, [option]).classification, 'reporting');
    }
  }
  assert.equal(classifyMoon('test', ['--outline']).heavy, true);
  assert.equal(classifyMoon('test', ['--build-only']).heavy, true);
});

test('CI classification is an explicit reviewed list, independent of time budgets', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  for (const name of heavyJobs) {
    assert.match(workflow, new RegExp(`^  ${name}:$`, 'mu'));
    assert.equal(classifyJob(name).classification, 'heavy');
  }
  assert.equal(classifyJob('lint').heavy, false);
  assert.equal(classifyJob('new-job').classification, 'unknown');
  assert.equal(classifyJob('new-job').heavy, true);
  assert.equal(classifyJob('check').classification, 'unknown');
});
