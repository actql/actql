import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import type {TestContext} from 'node:test';
import {fileURLToPath} from 'node:url';
import {parse} from 'yaml';
import {inspectJavaScriptSources} from './javascript-source-inventory.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const executable = 'scripts/javascript-source-inventory.mjs';
const manifest = 'scripts/javascript-source-exceptions.json';

function fixture(t: TestContext) {
  const root = mkdtempSync(join(tmpdir(), 'actql-js-source-inventory-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const git = (...args: string[]) => {
    const result = spawnSync('git', args, {cwd: root, timeout: 10_000, encoding: 'utf8'});
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  const put = (path: string, bytes: string) => {
    const destination = join(root, path);
    mkdirSync(dirname(destination), {recursive: true});
    writeFileSync(destination, bytes);
  };
  const review = (exemptions: unknown[]) => {
    put(manifest, JSON.stringify({version: 1, exemptions}));
    git('add', '--', manifest);
  };
  git('init', '-q', '-b', 'main');
  git('config', 'user.name', 'JavaScript inventory fixture');
  git('config', 'user.email', 'test-fixture@example.invalid');
  git('config', 'commit.gpgsign', 'false');
  git('config', 'core.hooksPath', '/dev/null');
  review([]);
  put('.gitignore', `/${executable}\n`);
  git('add', '--', '.gitignore');
  copyFileSync(join(repository, executable), join(root, executable));
  const owned = (path: string, owner: string) => ({path, mode: '100644', object: git('rev-parse', `:${path}`),
    role: 'generated', owner, reason: 'Runtime counterpart of the selected typed generator fixture.'});
  const run = (args: string[], env = process.env) =>
    spawnSync(process.execPath, [executable, ...args], {cwd: root, encoding: 'utf8', env, timeout: 10_000});
  return {root, git, put, review, owned, run};
}

test('strict inventory refuses all unclassified tracked JavaScript even with no import references', t => {
  const f = fixture(t);
  f.put('tools/manual.generated.mjs', 'export const bytes = 1;\n');
  f.put('examples/retained experiment.cjs', 'module.exports = 1;\n');
  f.put('proofs/runner', '#!/usr/bin/env -S node --no-warnings\nconsole.log(1);\n');
  f.put('proofs/instruction.md', 'The example begins as follows.\n#!/usr/bin/env node\n');
  f.put('tools/manual.generated.mts', 'export const bytes: number = 1;\n');
  f.put('review/check.JSX', 'export default null;\n');
  f.git('add', '--', 'tools', 'examples', 'proofs', 'review');
  f.put('untracked.mjs', 'throw Error();\n');
  const report = f.run(['--inventory']);
  assert.equal(report.status, 0, report.stderr);
  const inventory = JSON.parse(report.stdout);
  assert.equal(inventory.complete, false);
  assert.deepEqual(inventory.unresolved.map((item: {path: string}) => item.path),
    ['examples/retained experiment.cjs', 'proofs/runner', 'review/check.JSX', 'tools/manual.generated.mjs']);
  const required = f.run([]);
  assert.equal(required.status, 1, required.stderr);
  assert.match(required.stdout, /4 unclassified/u);
});

test('retaining JavaScript needs the exact tracked file, owner, bytes and mode', t => {
  const f = fixture(t);
  const path = 'packages/demo/checked.mjs', owner = 'scripts/build-demo.mts';
  f.put(path, 'export const original = 1;\n');
  f.put(owner, 'export function build() {}\n');
  f.git('add', '--', path, owner);
  const exception = f.owned(path, owner);
  f.review([exception]);
  assert.equal(f.run([]).status, 0);
  assert.equal(inspectJavaScriptSources(f.root).complete, true);

  f.put('packages/demo/other.mjs', 'export const original = 1;\n');
  f.git('add', '--', 'packages/demo/other.mjs');
  assert.equal(f.run([]).status, 1, 'An adjacent copy is distinct from the reviewed output');
  f.git('rm', '-f', '--', 'packages/demo/other.mjs');
  f.git('update-index', '--chmod=+x', '--', path);
  assert.match(f.run([]).stderr, /Changed bytes or mode for retained JavaScript/u);
  f.put(path, 'export const changed = 2;\n');
  f.git('add', '--', path);
  assert.match(f.run([]).stderr, /Changed bytes or mode for retained JavaScript/u);
  f.git('rm', '-f', '--', path);
  assert.match(f.run([]).stderr, /Retired or non-JavaScript exception/u);
  f.git('rm', '-f', '--', owner);
  assert.match(f.run([]).stderr, /Missing tracked exception owner/u);
});

test('glob and symlink exceptions cannot admit sources', t => {
  const f = fixture(t);
  const owner = 'scripts/generator.mts';
  f.put(owner, 'export {};\n');
  f.git('add', '--', owner);
  symlinkSync('generator.mts', join(f.root, 'scripts/symlink.mjs'));
  f.git('add', '--', 'scripts/symlink.mjs');
  assert.match(f.run(['--inventory']).stderr, /Unclassified JavaScript source: scripts\/symlink.mjs/u);
  const exception = f.owned('scripts/symlink.mjs', owner);
  f.review([{...exception, path: 'scripts/*.mjs'}]);
  assert.equal(f.run([]).status, 1);
  assert.match(f.run([]).stderr, /Retired or non-JavaScript exception: scripts\/\*\.mjs/u);
  f.review([exception]);
  assert.equal(f.run([]).status, 1);
  assert.match(f.run([]).stderr, /Changed bytes or mode for retained JavaScript/u);
});

test('ordinary CI rejects unclassified tracked JavaScript already in the checkout', t => {
  const f = fixture(t);
  const workflow = parse(readFileSync(join(repository, '.github/workflows/ci.yml'), 'utf8')) as {
    jobs: {preflight: {needs: string[]; steps: {name?: string; if?: string; run?: string}[]}};
  };
  const {needs, steps} = workflow.jobs.preflight;
  assert.deepEqual(needs, ['select-targets']);
  const step = steps.find(item => item.name === 'Check tracked JavaScript source exceptions');
  assert(step?.run && steps.findIndex(item => item.run === 'npm ci') < steps.indexOf(step));
  assert.equal(step.if, undefined);
  const pkg = JSON.parse(readFileSync(join(repository, 'package.json'), 'utf8')) as {scripts: Record<string, string>};
  const recipe = 'check:javascript-sources';
  assert.equal(pkg.scripts[recipe], `node ${executable}`);
  assert.equal(step.run, `npm run ${recipe}`);
  f.put('package.json', JSON.stringify({private: true, scripts: {[recipe]: pkg.scripts[recipe]}}));
  f.put('retained.mjs', 'export const original = 1;\n');
  f.git('add', '--', 'retained.mjs', 'package.json');
  f.git('commit', '-qm', 'test: capture retained JavaScript');
  const invoke = () => spawnSync('bash', ['-eo', 'pipefail', '-c', step.run!],
    {cwd: f.root, env: {...process.env, npm_config_update_notifier: 'false'}, encoding: 'utf8', timeout: 15_000});
  const refused = invoke();
  assert.equal(refused.status, 1, refused.stderr);
  assert.match(refused.stderr, /Unclassified JavaScript source: retained\.mjs/u);
  f.git('mv', '--', 'retained.mjs', 'retained.mts');
  const migrated = invoke();
  assert.equal(migrated.status, 0, migrated.stderr);
  assert.match(migrated.stdout, /0 unclassified/u);
});
