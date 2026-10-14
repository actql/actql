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
