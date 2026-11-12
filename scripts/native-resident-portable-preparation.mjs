// Reuse generated software only inside the original Native job. Every consumer
// rechecks the actual source, tools, dependencies and outputs before import.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {originalDescriptor, verifyOriginal} from './native-preparation-originals.mjs';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {installationFiles} from './moonbit-installation.mjs';
import {verifyWorkspacePackageLinks} from './verify-local-source-runtime.mjs';

const names = ['coordinator-core', 'run-host-core', ...(process.platform === 'linux' ? ['transfer-core'] : [])];
const coreArgs = ['build', '--target', 'js', '--release', 'src/connectors_builtin_node'];
const ownerArgs = ['scripts/build-runtime-packages.mjs', ...names];

function files(directory, excluded = new Set()) {
  return readdirSync(directory, {withFileTypes: true}).sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(item => {
      if (excluded.has(item.name)) return [];
      const path = join(directory, item.name);
      return statSync(path).isDirectory() ? files(path, excluded) : [path];
    });
}
function selection(repository, env) {
  repository = verifyWorkspacePackageLinks(repository);
  const git = args => execFileSync('git', args, {cwd: repository, encoding: 'utf8'}).trim();
  assert.equal(git(['status', '--porcelain']), '', 'Portable preparation requires unchanged clean source');
  const source = git(['rev-parse', 'HEAD']);
  const moonHome = realpathSync(env.MOON_HOME);
  const tracked = execFileSync('git', ['ls-files', '-z', '--', 'src', 'adapters', 'packages', 'scripts',
    'spec', 'vendor', 'toolchain.json', 'package.json', 'package-lock.json', 'moon.mod', 'moon.mod.json',
    'moon.work', 'moon.work.json', 'moon.lock', '.npmrc'],
  {cwd: repository, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024})
    .split('\0').filter(Boolean).flatMap(path => {
      path = join(repository, path);
      return statSync(path).isDirectory() ? files(path) : [path];
    });
  const inputs = [...tracked, process.execPath,
    ...installationFiles.map(path => join(moonHome, path)), join(moonHome, 'installed.json'),
    ...files(join(moonHome, 'lib/core'), new Set(['_build', '.git'])),
    ...files(join(moonHome, 'lib/core/_build/js/release/bundle'))
      .filter(path => /\.(?:mi|core)$/u.test(path)),
    ...files(join(repository, 'node_modules'), new Set(['@actql', '.cache']))];
  const packages = runtimePackageInputs(repository);
  const sources = ['connectors_builtin_node', ...new Set(names.flatMap(name => packages[name].sources))];
  const artifacts = [...names.flatMap(name => packages[name].files).map(path => join(repository, path)),
    ...sources.map(path => join(repository, '_build/js/release/build', path, path.split('/').at(-1) + '.js'))];
  return {repository, source, moonHome, nodeVersion: process.version,
    environment: Object.fromEntries(Object.entries(env).filter(([key]) =>
      /^MOON_/u.test(key) || ['NODE_OPTIONS', 'NODE_PATH', 'CC', 'CXX'].includes(key)).sort()),
    commands: [[join(moonHome, 'bin/moon'), coreArgs], [process.execPath, ownerArgs]],
    inputs: [...new Set(inputs)].sort(), artifacts: [...new Set(artifacts)].sort()};
}
function describe(paths) {
  return paths.map(path => {
    const original = realpathSync(path);
    return {selectedPath: path, ...(statSync(original).size === 0
      ? {path: original, bytes: 0} : originalDescriptor(original))};
  });
}
function verify(paths, records) {
  assert.deepEqual(records.map(item => item.selectedPath), paths, 'Portable input inventory changed');
  for (const item of records) {
    assert.equal(realpathSync(item.selectedPath), item.path, 'Portable input target changed');
    if (item.bytes === 0) assert.equal(statSync(item.path).size, 0, 'Empty input changed');
    else verifyOriginal(item);
  }
}
function identity(selected) {
  const {inputs, artifacts, ...value} = selected;
  return value;
}

export function verifyNativeResidentPortablePreparation(repository, receiptPath, {env = process.env} = {}) {
  const selected = selection(repository, env);
  const receipt = JSON.parse(readFileSync(receiptPath, 'utf8'));
  assert.deepEqual(receipt.identity, identity(selected), 'Foreign portable preparation');
  verify(selected.inputs, receipt.inputs);
  verify(selected.artifacts, receipt.artifacts);
}

export function prepareNativeResidentPortableRuntime(repository, receiptPath,
  {env = process.env, execute = execFileSync} = {}) {
  if (existsSync(receiptPath)) {
    verifyNativeResidentPortablePreparation(repository, receiptPath, {env});
    return;
  }
  const selected = selection(repository, env), inputs = describe(selected.inputs);
  for (const [command, args] of selected.commands) {
    execute(command, args, {cwd: selected.repository, env, stdio: 'inherit'});
  }
  const after = selection(repository, env);
  assert.deepEqual(after, selected, 'Portable build inputs changed during preparation');
  verify(selected.inputs, inputs);
  writeFileSync(receiptPath, JSON.stringify({identity: identity(selected), inputs,
    artifacts: describe(selected.artifacts)}) + '\n', {flag: 'wx', mode: 0o600});
  verifyNativeResidentPortablePreparation(repository, receiptPath, {env});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 4);
  assert.equal(process.argv[2], 'verify');
  verifyNativeResidentPortablePreparation(fileURLToPath(new URL('../', import.meta.url)), process.argv[3]);
}
