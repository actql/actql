import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {gitTree, hash, packageImports, packageSourceInputs} from './inputs.mjs';
import {packageConfigurationReviewFor, currentPackageConfigurationReviewFor} from './package-configurations.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const directory = 'src/platform_native/remote_transfer_journal';
const path = `${directory}/moon.pkg`;
const digest = '4af6a1f153011554ab829bb6b494cbd8a8cf32110ed39f66de7c7974993411b5';
const oldDigest = 'da01cf66f62a1632dce894f19a8d781d3b8c7f4d822aaf71e3e1cb1d07556ffd';
const toolchainDigest = '8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a';
const request = {path, digest, target: 'js', toolchainDigest};
const treeAtHead = () => gitTree(repository,
  execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim());

function assertCurrentSuccessor(path, bytes) {
  assert(currentPackageConfigurationReviewFor({path, digest: hash(bytes), target: 'js', toolchainDigest}),
    'Current bytes require their independent successor review, not a historical introduction pin');
}

const boundedDirectory = 'src/platform_native/bounded_files';
const boundedPath = `${boundedDirectory}/moon.pkg`;
const priorBoundedDigest = 'd3226436c6183cae948253152b6f49c386881ae9f3653c7e970183d7d1b99f57';
const boundedDigest = '383a532bbbee2be32d5c4c7ccab853fa392892667451095a7b553c495d5c578d';
const boundedRequest = {path: boundedPath, digest: boundedDigest, target: 'js', toolchainDigest};

test('bounded Root review preserves prior bytes and binds the scoped cleanup predicate and every source member', () => {
  const tree = treeAtHead(), current = tree.read(boundedPath);
  const author = 'f089341cd29c2989c1e462333ca2e382fc9c9e55';
  execFileSync('git', ['merge-base', '--is-ancestor', author, 'HEAD'], {cwd: repository});
  const before = execFileSync('git', ['show', `${author}:${boundedPath}`], {cwd: repository});
  assert.equal(hash(before), priorBoundedDigest);
  const scoped = 'ea73884358631b4c6de7ef89d8db2515a9db6788';
  const parent = '7b602b9152720cb1264a6209b7c130d14f7830eb';
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', scoped],
    {cwd: repository, encoding: 'utf8'}).trim(), parent);
  execFileSync('git', ['merge-base', '--is-ancestor', scoped, 'HEAD'], {cwd: repository});
  assert.deepEqual(before, execFileSync('git', ['show', `${parent}:${boundedPath}`], {cwd: repository}));
  const introduced = execFileSync('git', ['show', `${scoped}:${boundedPath}`], {cwd: repository});
  const selector = '    "scoped_cleanup_native_wbtest.mbt": [ "native" ],\n';
  assert.equal(introduced.toString().split(selector).length, 2);
  assert.equal(introduced.toString().replace(selector, ''), before.toString());
  assert.equal(hash(introduced), boundedDigest);
  assert.deepEqual(packageImports(introduced.toString()).imports, packageImports(before.toString()).imports);
  assertCurrentSuccessor(boundedPath, current);
  assert.equal(hash(tree.read('toolchain.json')), toolchainDigest);
  for (const selector of [
    '"root_open_custody_native_wbtest.mbt": [ "native" ]',
    '"root_open_custody_unsupported_wbtest.mbt": [ "not", "native" ]',
  ]) assert.equal(current.toString().split(selector).length, 2);
  const selected = packageSourceInputs({tree, packages: [boundedDirectory], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert.equal(selected.packageConfigurations.find(entry => entry.path === boundedPath)?.review.rule,
    'literal-native-options-with-bound-source-membership');
  const members = [...tree.entries.keys()].filter(member => member.startsWith(`${boundedDirectory}/`) &&
    !member.slice(boundedDirectory.length + 1).includes('/')).sort();
  assert.deepEqual(selected.directories.find(entry => entry.path === `${boundedDirectory}/*`)?.members, members);
  for (const member of members) {
    assert(selected.paths.includes(member));
    assert.equal(tree.entries.get(member).mode, '100644');
    assert.equal(tree.entries.get(member).kind, 'blob');
  }
});

test('bounded Root review refuses changed selectors, options, path, target and toolchain', () => {
  assert.equal(packageConfigurationReviewFor(boundedRequest)?.rule,
    'literal-native-options-with-bound-source-membership');
  for (const change of [{digest: priorBoundedDigest}, {digest: '0'.repeat(64)}, {path: './'+boundedPath},
    {target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)}]) {
    assert.equal(packageConfigurationReviewFor({...boundedRequest, ...change}), null);
  }
  const tree = treeAtHead(), original = tree.read(boundedPath).toString();
  for (const value of [original.replace('[ "native" ]', '[ "js" ]'),
    original+'\noptions(extra_unknown: true)\n']) {
    const changed = {...tree, read: member => member === boundedPath ? Buffer.from(value) : tree.read(member)};
    const selected = packageSourceInputs({tree: changed, packages: [boundedDirectory], target: 'js'});
    assert(selected.unresolved.includes(`Unreviewed package configuration: ${boundedPath}`));
    assert(!selected.packageConfigurations.some(entry => entry.path === boundedPath));
  }
});

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
const readLayoutDigest = 'bb816061434a3d23d1446366e137d3e64539cd0ef6ae191bea81f71f93400a86';
const priorChildCustodyDigest = '98c10419328d72de804dd3e65aea84346db093880edce96cd679e6fbc55a6460';
const observationDigest = 'a39f92dff1dba87ca4d59dfdcc3fb81ea4167b4f3e48c36bba69b9f28bda44e9';
const priorObservationDigest = '765802bc29d68ff7e87d427d3e68555fb648387de56ad49b2052fdff412f376b';
const oldObservationDigest = '6968c40ed7d166f9d94e00af31d42654efd27afc8e7ceaca2f1aaead3a8f5e0f';
const observationRequest = {path: observationPath, digest: observationDigest,
  target: 'js', toolchainDigest};

test('package observation review preserves historical predicates and binds scoped acquisition selectors', () => {
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
  let restored = introduced.toString();
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
  assert.equal(hash(introduced), priorObservationDigest);
  const layoutIntro = '93a7f22cc369e17b985436fbec3a3f9dddaa71fb';
  const layoutParent = 'fa968102a08ad0bf183ba9f35afe4fe89390a599';
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', layoutIntro],
    {cwd: repository, encoding: 'utf8'}).trim(), layoutParent);
  execFileSync('git', ['merge-base', '--is-ancestor', intro, layoutParent], {cwd: repository});
  execFileSync('git', ['merge-base', '--is-ancestor', layoutIntro, 'HEAD'], {cwd: repository});
  assert.deepEqual(execFileSync('git', ['show', `${layoutParent}:${observationPath}`],
    {cwd: repository}), introduced);
  const layoutIntroduced = execFileSync('git', ['show', `${layoutIntro}:${observationPath}`],
    {cwd: repository});
  assert.equal(hash(layoutIntroduced), readLayoutDigest);
  const scopedIntro = '4a62dc0cfc30be562405d2fc31bdfa1556bfae9c';
  const scopedParent = '8d93c89d48e5991d9a890648db023a4336ff8979';
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', scopedIntro],
    {cwd: repository, encoding: 'utf8'}).trim(), scopedParent);
  execFileSync('git', ['merge-base', '--is-ancestor', scopedIntro, 'HEAD'], {cwd: repository});
  assert.deepEqual(execFileSync('git', ['show', `${scopedParent}:${observationPath}`],
    {cwd: repository}), layoutIntroduced);
  const scopedIntroduced = execFileSync('git', ['show', `${scopedIntro}:${observationPath}`],
    {cwd: repository});
  const refusalIntro = '6db6f2ce88454b80c21dbb3f5fb0bb9e7127d003';
  const refusalParent = '380473dc6794b09bd561946aa8c7d9c2bcd9d1b4';
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', refusalIntro],
    {cwd: repository, encoding: 'utf8'}).trim(), refusalParent);
  execFileSync('git', ['merge-base', '--is-ancestor', scopedIntro, refusalParent], {cwd: repository});
  execFileSync('git', ['merge-base', '--is-ancestor', refusalIntro, 'HEAD'], {cwd: repository});
  assert.deepEqual(execFileSync('git', ['show', `${refusalParent}:${observationPath}`],
    {cwd: repository}), scopedIntroduced);
  const refusalIntroduced = execFileSync('git', ['show', `${refusalIntro}:${observationPath}`],
    {cwd: repository});
  assert.equal(hash(refusalIntroduced), priorChildCustodyDigest);
  const childIntro = '23296c2b738e3be7f7990ac3026fbbba7a6e86ef';
  const childParent = '22ec7edcd3edcd4a9dd95780534feeded3f6f599';
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', childIntro],
    {cwd: repository, encoding: 'utf8'}).trim(), childParent);
  execFileSync('git', ['merge-base', '--is-ancestor', childIntro, 'HEAD'], {cwd: repository});
  assert.deepEqual(execFileSync('git', ['show', `${childParent}:${observationPath}`],
    {cwd: repository}), refusalIntroduced);
  const childIntroduced = execFileSync('git', ['show', `${childIntro}:${observationPath}`],
    {cwd: repository});
  const childSelector = '    "child_custody_native_wbtest.mbt": [ "native" ],\n';
  assert.equal(childIntroduced.toString().split(childSelector).length, 2);
  assert.equal(childIntroduced.toString().replace(childSelector, ''), refusalIntroduced.toString());
  assert(tree.entries.has(`${observationDirectory}/child_custody_native_wbtest.mbt`));
  assert.equal(hash(childIntroduced), observationDigest);
  assertCurrentSuccessor(observationPath, current);
  restored = refusalIntroduced.toString();
  for (const [member, targets] of [
    ['scoped_read_unselected_native_wbtest.mbt', '[ "native" ]'],
    ['scoped_read_unsupported_wbtest.mbt', '[ "not", "native" ]'],
  ]) {
    const selector = `    "${member}": ${targets},\n`;
    assert.equal(restored.split(selector).length, 2);
    restored = restored.replace(selector, '');
    assert(tree.entries.has(`${observationDirectory}/${member}`));
  }
  assert.equal(restored, scopedIntroduced.toString());
  restored = scopedIntroduced.toString();
  for (const [member, targets] of [
    ['scoped_read_native.mbt', '[ "native" ]'],
    ['scoped_read_unsupported.mbt', '[ "not", "native" ]'],
  ]) {
    const selector = `    "${member}": ${targets},\n`;
    assert.equal(restored.split(selector).length, 2);
    restored = restored.replace(selector, '');
    assert(tree.entries.has(`${observationDirectory}/${member}`));
  }
  assert.equal(restored, layoutIntroduced.toString());
  restored = layoutIntroduced.toString();
  for (const [member, targets] of [
    ['read_layout_native.mbt', '[ "native" ]'],
    ['read_layout_native_wbtest.mbt', '[ "native" ]'],
    ['read_layout_unsupported.mbt', '[ "not", "native" ]'],
    ['read_layout_unsupported_wbtest.mbt', '[ "not", "native" ]'],
  ]) {
    const selector = `    "${member}": ${targets},\n`;
    assert.equal(restored.split(selector).length, 2);
    restored = restored.replace(selector, '');
    assert(tree.entries.has(`${observationDirectory}/${member}`));
  }
  assert.equal(restored, introduced.toString());
  assert.equal(hash(before), oldObservationDigest);
  assert.equal(hash(childIntroduced), observationDigest);
  assert.equal(hash(tree.read('toolchain.json')), toolchainDigest);
  assert.deepEqual(packageImports(childIntroduced.toString()).imports, packageImports(before.toString()).imports);
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
  for (const change of [{digest: oldObservationDigest}, {digest: priorObservationDigest},
    {digest: readLayoutDigest}, {digest: priorChildCustodyDigest},
    {digest: '0'.repeat(64)},
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
    original.replace('"read_layout_native.mbt": [ "native" ]',
      '"read_layout_native.mbt": [ "js" ]'),
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

const sqliteDirectory = 'src/platform_native/sqlite';
const sqlitePath = `${sqliteDirectory}/moon.pkg`;
const sqlitePriorDigest = 'b181b5bce06d908faef1642aaad1d417ab5403fed56af41c6c028fd6608ab1e2';
const sqliteDigest = 'f05438392188f1d1f2c08a6872f25e07c782ec6fbc3b9769c09b155b564face5';
const sqliteRequest = {path: sqlitePath, digest: sqliteDigest, target: 'js', toolchainDigest};

test('SQLite body-limit review binds the sole Native selector addition and every source member', () => {
  const author = '9531187a12e25ec1f23ba9df8a27e53932af5c72';
  const base = 'b09bd6b0b40b84d1e72fffed0365bca316281bef';
  execFileSync('git', ['merge-base', '--is-ancestor', author, 'HEAD'], {cwd: repository});
  const before = execFileSync('git', ['show', `${base}:${sqlitePath}`], {cwd: repository});
  const introduced = execFileSync('git', ['show', `${author}:${sqlitePath}`], {cwd: repository});
  const selector = '    "bounded_read_native_wbtest.mbt": [ "native" ],\n';
  assert.equal(introduced.toString().split(selector).length, 2);
  assert.equal(introduced.toString().replace(selector, ''), before.toString());
  assert.equal(hash(before), sqlitePriorDigest);
  assert.equal(hash(introduced), sqliteDigest);
  const tree = treeAtHead(), current = tree.read(sqlitePath);
  assertCurrentSuccessor(sqlitePath, current);
  assert.deepEqual(packageImports(introduced.toString()).imports, packageImports(before.toString()).imports);
  assert.equal(hash(tree.read('toolchain.json')), toolchainDigest);
  const selected = packageSourceInputs({tree, packages: [sqliteDirectory], target: 'js'});
  // Preserve unresolved dependency outcomes; this finite review admits only
  // the SQLite manifest and cannot turn an unreviewed dependency into a pass.
  const dependency = packageSourceInputs({tree, packages: ['src/platform_native/filesystem'], target: 'js'});
  assert.deepEqual(selected.unresolved, dependency.unresolved);
  assert.equal(selected.packageConfigurations.find(entry => entry.path === sqlitePath)?.review.rule,
    'literal-native-options-with-bound-source-membership');
  const members = [...tree.entries.keys()].filter(member => member.startsWith(`${sqliteDirectory}/`) &&
    !member.slice(sqliteDirectory.length + 1).includes('/')).sort();
  assert(members.includes(`${sqliteDirectory}/bounded_read_native_wbtest.mbt`));
  assert.deepEqual(selected.directories.find(entry => entry.path === `${sqliteDirectory}/*`)?.members, members);
  for (const member of members) {
    assert(selected.paths.includes(member));
    assert.equal(tree.entries.get(member).mode, '100644');
    assert.equal(tree.entries.get(member).kind, 'blob');
  }
});

test('SQLite body-limit review rejects changed bytes imports selectors targets and unknown options', () => {
  assert.equal(packageConfigurationReviewFor(sqliteRequest)?.rule,
    'literal-native-options-with-bound-source-membership');
  for (const change of [{digest: sqlitePriorDigest},
    {digest: '92f1a01552e82ba65b56f680cf82e048505b83625c9c13c9cfb3f202c19d3996'}, {digest: '0'.repeat(64)},
    {path: './' + sqlitePath}, {path: 'src/unreviewed_sqlite/moon.pkg'},
    {target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)}])
    assert.equal(packageConfigurationReviewFor({...sqliteRequest, ...change}), null);
  const tree = treeAtHead(), original = tree.read(sqlitePath).toString();
  for (const value of [
    original.replace('"actql/actql/platform_native/filesystem"', '"actql/actql/unreviewed_filesystem"'),
    original.replace('"bounded_read_native_wbtest.mbt": [ "native" ]',
      '"bounded_read_native_wbtest.mbt": [ "js" ]'),
    original + '\noptions(unreviewed: true)\n',
  ]) {
    assert.notEqual(value, original);
    const changed = {...tree, read: member => member === sqlitePath ? Buffer.from(value) : tree.read(member)};
    const selected = packageSourceInputs({tree: changed, packages: [sqliteDirectory], target: 'js'});
    assert(selected.unresolved.includes(`Unreviewed package configuration: ${sqlitePath}`));
    assert(!selected.packageConfigurations.some(entry => entry.path === sqlitePath));
  }
});

const catalogDirectory = 'src/platform_native/runtime_bundle';
const catalogPath = `${catalogDirectory}/moon.pkg`;
const priorCatalogDigest = '3261be3fb00a789680d76f5304bf1bff98d3db4e7d904d45fd50a05205c955fe';
const catalogDigest = '4a6441d96a441ac67adf1f38d806ae59bf4936217faf2b8269310f2e500aac00';
const catalogRequest = {path: catalogPath, digest: catalogDigest, target: 'js', toolchainDigest};

test('bounded catalog review binds the actual sole selector introduction and every source member', () => {
  const intro = '202aed1b7f33bb825d8b5c3e9c313a80f04d6f7f', parent = 'c0834dc952fc3ffc11908b782331c0eeddb17dad';
  assert.equal(execFileSync('git', ['show', '-s', '--format=%P', intro],
    {cwd: repository, encoding: 'utf8'}).trim(), parent);
  execFileSync('git', ['merge-base', '--is-ancestor', intro, 'HEAD'], {cwd: repository});
  const before = execFileSync('git', ['show', `${parent}:${catalogPath}`], {cwd: repository});
  const introduced = execFileSync('git', ['show', `${intro}:${catalogPath}`], {cwd: repository});
  const selector = '    "bounded_catalog_current_native_wbtest.mbt": [ "native" ],\n';
  assert.equal(introduced.toString().split(selector).length, 2);
  assert.equal(introduced.toString().replace(selector, ''), before.toString());
  assert.equal(hash(before), priorCatalogDigest);
  assert.equal(hash(introduced), catalogDigest);
  const tree = treeAtHead(), current = tree.read(catalogPath);
  assertCurrentSuccessor(catalogPath, current);
  assert.equal(hash(tree.read('toolchain.json')), toolchainDigest);
  assert.deepEqual(packageImports(introduced.toString()).imports, packageImports(before.toString()).imports);
  const selected = packageSourceInputs({tree, packages: [catalogDirectory], target: 'js'});
  assert.deepEqual(selected.unresolved, []);
  assert.equal(selected.packageConfigurations.find(entry => entry.path === catalogPath)?.review.rule,
    'literal-native-options-with-bound-source-membership');
  const members = [...tree.entries.keys()].filter(member => member.startsWith(`${catalogDirectory}/`) &&
    !member.slice(catalogDirectory.length + 1).includes('/')).sort();
  assert(members.includes(`${catalogDirectory}/bounded_catalog_current_native_wbtest.mbt`));
  assert.deepEqual(selected.directories.find(entry => entry.path === `${catalogDirectory}/*`)?.members, members);
  for (const member of members) {
    assert(selected.paths.includes(member));
    assert.equal(tree.entries.get(member).mode, '100644');
    assert.equal(tree.entries.get(member).kind, 'blob');
  }
});

test('bounded catalog review refuses old bytes, changed imports, selectors, options, target and toolchain', () => {
  assert.equal(packageConfigurationReviewFor(catalogRequest)?.rule,
    'literal-native-options-with-bound-source-membership');
  for (const change of [{digest: priorCatalogDigest},
    {digest: 'e18d68c466e76cdc2fd81395df80fdfbdb86e13627c89110339d54503a6650fd'}, {digest: '0'.repeat(64)},
    {path: './' + catalogPath}, {path: 'src/unreviewed_bundle/moon.pkg'},
    {target: 'native'}, {target: 'wasm'}, {toolchainDigest: '0'.repeat(64)}])
    assert.equal(packageConfigurationReviewFor({...catalogRequest, ...change}), null);
  const tree = treeAtHead(), original = tree.read(catalogPath).toString();
  for (const value of [
    original.replace('"actql/actql/platform_native/sqlite"', '"actql/actql/unreviewed_sqlite"'),
    original.replace('"bounded_catalog_current_native_wbtest.mbt": [ "native" ]',
      '"bounded_catalog_current_native_wbtest.mbt": [ "js" ]'),
    original + '\noptions(unreviewed: true)\n',
  ]) {
    assert.notEqual(value, original);
    const changed = {...tree, read: member => member === catalogPath ? Buffer.from(value) : tree.read(member)};
    const selected = packageSourceInputs({tree: changed, packages: [catalogDirectory], target: 'js'});
    assert(selected.unresolved.includes(`Unreviewed package configuration: ${catalogPath}`));
    assert(!selected.packageConfigurations.some(entry => entry.path === catalogPath));
  }
});
