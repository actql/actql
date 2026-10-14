import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {gitTree, hash, packageImports, packageSourceInputs} from './inputs.mjs';
import {packageConfigurationReviewFor} from './package-configurations.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const directory = 'src/platform_native/remote_transfer_journal';
const path = `${directory}/moon.pkg`;
const digest = '4af6a1f153011554ab829bb6b494cbd8a8cf32110ed39f66de7c7974993411b5';
const oldDigest = 'da01cf66f62a1632dce894f19a8d781d3b8c7f4d822aaf71e3e1cb1d07556ffd';
const toolchainDigest = '8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a';
const request = {path, digest, target: 'js', toolchainDigest};
const treeAtHead = () => gitTree(repository,
  execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim());

test('Journal review binds the actual selector-only introduction and every source member', () => {
  const tree = treeAtHead(), current = tree.read(path);
  const intro = '01ce3a949932b5b6e55405c14dc04d69373626ae';
  const parent = '3dfe5a2dc371b17ff06aa4d6eeddf5e9263b2918';
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', intro],
    {cwd: repository, encoding: 'utf8'}).trim(), parent);
  execFileSync('git', ['merge-base', '--is-ancestor', intro, 'HEAD'], {cwd: repository});
  const before = execFileSync('git', ['show', `${parent}:${path}`], {cwd: repository});
  const introduced = execFileSync('git', ['show', `${intro}:${path}`], {cwd: repository});
  const selector = '    "open_close_custody_native_wbtest.mbt": [ "native" ],\n';
  assert.equal(introduced.toString().split(selector).length, 2);
  assert.equal(introduced.toString().replace(selector, ''), before.toString());
  assert.deepEqual(current, introduced);
  assert.equal(hash(before), oldDigest);
  assert.equal(hash(current), digest);
  assert.equal(hash(tree.read('toolchain.json')), toolchainDigest);
  assert.deepEqual(packageImports(current.toString()).imports, packageImports(before.toString()).imports);
  const selected = packageSourceInputs({tree, packages: [directory], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert.equal(selected.packageConfigurations.find(entry => entry.path === path)?.review.rule,
    'literal-native-options-with-bound-source-membership');
  const members = [...tree.entries.keys()].filter(member => member.startsWith(`${directory}/`) &&
    !member.slice(directory.length + 1).includes('/')).sort();
  assert(members.includes(`${directory}/open_close_custody_native_wbtest.mbt`));
  assert.deepEqual(selected.directories.find(entry => entry.path === `${directory}/*`)?.members, members);
  for (const member of members) {
    assert(selected.paths.includes(member));
    assert.equal(tree.entries.get(member).kind, 'blob');
    assert.equal(tree.entries.get(member).mode, '100644');
    assert(tree.read(member).length > 0);
  }
  for (const dependency of packageImports(current.toString()).imports)
    if (dependency.startsWith('actql/actql/')) assert(selected.paths.includes(
      `src/${dependency.slice('actql/actql/'.length)}/moon.pkg`));
});

test('Journal review refuses old bytes, another path, target or toolchain', () => {
  assert.equal(packageConfigurationReviewFor(request)?.rule,
    'literal-native-options-with-bound-source-membership');
  for (const change of [{digest: oldDigest}, {digest: '0'.repeat(64)},
    {path: 'src/unreviewed_journal/moon.pkg'}, {path: `./${path}`},
    {target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)}])
    assert.equal(packageConfigurationReviewFor({...request, ...change}), null);
});

test('Journal import, selector and unknown-option changes remain unresolved', () => {
  const tree = treeAtHead(), original = tree.read(path).toString();
  for (const changed of [
    original.replace('"actql/actql/sha256"', '"actql/actql/string"'),
    original.replace('"open_close_custody_native_wbtest.mbt": [ "native" ]',
      '"open_close_custody_native_wbtest.mbt": [ "js" ]'),
    `${original}\noptions(unreviewed: true)\n`,
  ]) {
    assert.notEqual(changed, original);
    const changedTree = {...tree, read(member) {
      return member === path ? Buffer.from(changed) : tree.read(member);
    }};
    const selected = packageSourceInputs({tree: changedTree, packages: [directory], target: 'js'});
    assert(selected.unresolved.includes(`Unreviewed package configuration: ${path}`));
    assert(!selected.packageConfigurations.some(entry => entry.path === path));
  }
});

const observationDirectory = 'src/platform_native/filesystem';
const observationPath = `${observationDirectory}/moon.pkg`;
const observationDigest = '765802bc29d68ff7e87d427d3e68555fb648387de56ad49b2052fdff412f376b';
const oldObservationDigest = '6968c40ed7d166f9d94e00af31d42654efd27afc8e7ceaca2f1aaead3a8f5e0f';
const observationRequest = {path: observationPath, digest: observationDigest,
  target: 'js', toolchainDigest};

test('package observation review binds six exact predicates and all original source members', () => {
  const tree = treeAtHead(), current = tree.read(observationPath);
  const intro = '869310a0b34a7a704fbb61f2aec9af2f15b9ffa9';
  const original = '11b84334744819e4fb1bcc65382225bd8fc949d2';
  assert.deepEqual(execFileSync('git', ['show', '-s', '--format=%P', intro],
    {cwd: repository, encoding: 'utf8'}).trim().split(' '), [original,
    '9ac94732829b113e29a1f5467bdb9009093df366']);
  execFileSync('git', ['merge-base', '--is-ancestor', original, intro], {cwd: repository});
  execFileSync('git', ['merge-base', '--is-ancestor', intro, 'HEAD'], {cwd: repository});
  const before = execFileSync('git', ['show',
    `d8422903caa55ce7a4a58382c8a46f9a9c4c27c0:${observationPath}`], {cwd: repository});
  const introduced = execFileSync('git', ['show', `${intro}:${observationPath}`],
    {cwd: repository});
  let restored = current.toString();
  for (const [member, targets] of [
    ['file_observation_native.mbt', '[ "native" ]'],
    ['file_observation_unsupported.mbt', '[ "not", "native" ]'],
    ['file_observation_native_wbtest.mbt', '[ "native" ]'],
    ['directory_observation_native.mbt', '[ "native" ]'],
    ['directory_observation_unsupported.mbt', '[ "not", "native" ]'],
    ['directory_observation_native_wbtest.mbt', '[ "native" ]'],
  ]) {
    const selector = `    "${member}": ${targets},\n`;
    assert.equal(restored.split(selector).length, 2);
    restored = restored.replace(selector, '');
  }
  assert.equal(restored, before.toString());
  assert.deepEqual(current, introduced);
  assert.equal(hash(before), oldObservationDigest);
  assert.equal(hash(current), observationDigest);
  assert.equal(hash(tree.read('toolchain.json')), toolchainDigest);
  assert.deepEqual(packageImports(current.toString()).imports, packageImports(before.toString()).imports);
  const selected = packageSourceInputs({tree, packages: [observationDirectory], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert.equal(selected.packageConfigurations.find(entry => entry.path === observationPath)?.review.rule,
    'literal-native-options-with-bound-source-membership');
  const members = [...tree.entries.keys()].filter(member => member.startsWith(`${observationDirectory}/`) &&
    !member.slice(observationDirectory.length + 1).includes('/')).sort();
  assert.deepEqual(selected.directories.find(entry => entry.path === `${observationDirectory}/*`)?.members, members);
  for (const member of members) {
    assert(selected.paths.includes(member));
    assert.equal(tree.entries.get(member).kind, 'blob');
    assert.equal(tree.entries.get(member).mode, '100644');
    assert(tree.read(member).length > 0);
  }
});

test('package observation review refuses old bytes, foreign path, target and toolchain', () => {
  assert.equal(packageConfigurationReviewFor(observationRequest)?.rule,
    'literal-native-options-with-bound-source-membership');
  for (const change of [{digest: oldObservationDigest}, {digest: '0'.repeat(64)},
    {path: './src/platform_native/filesystem/moon.pkg'},
    {path: 'src/unreviewed_filesystem/moon.pkg'}, {target: 'native'}, {target: 'wasm'},
    {toolchainDigest: '0'.repeat(64)}])
    assert.equal(packageConfigurationReviewFor({...observationRequest, ...change}), null);
});

test('package observation import, predicate and unknown-option changes remain unresolved', () => {
  const tree = treeAtHead(), original = tree.read(observationPath).toString();
  for (const changed of [
    original.replace('"moonbitlang/core/encoding/utf8"', '"moonbitlang/core/string"'),
    original.replace('"file_observation_native.mbt": [ "native" ]',
      '"file_observation_native.mbt": [ "js" ]'),
    `${original}\noptions(unreviewed: true)\n`,
  ]) {
    assert.notEqual(changed, original);
    const changedTree = {...tree, read(member) {
      return member === observationPath ? Buffer.from(changed) : tree.read(member);
    }};
    const selected = packageSourceInputs({tree: changedTree, packages: [observationDirectory], target: 'js'});
    assert(selected.unresolved.includes(`Unreviewed package configuration: ${observationPath}`));
    assert(!selected.packageConfigurations.some(entry => entry.path === observationPath));
  }
});
