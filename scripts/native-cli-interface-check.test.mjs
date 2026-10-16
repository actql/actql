import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {checkInterfaceOwners} from './check-interface-owners.mjs';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {nativeCliLauncherInputs} from './native-cli-package-inputs.mjs';
import {checkStagedNativeCliInterfaces} from './native-cli-interface-check.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-cli-interface-source-'));
  const directory = mkdtempSync(join(tmpdir(), 'actql-cli-interface-stage-'));
  t.after(() => { rmSync(root, {recursive: true}); rmSync(directory, {recursive: true}); });
  const put = (path, text) => {mkdirSync(dirname(join(root, path)), {recursive: true});writeFileSync(join(root, path), text);};
  put('packages/native-cli/package.json', JSON.stringify({name: 'actql', type: 'module', bin: {actql: 'bin/actql.mjs'}}));
  put('packages/native-cli/README.md', 'Synthetic staging control, not a Native execution.');
  put('packages/native-cli/bin/actql.mjs', 'import {read} from "../lib/local-runtime.mjs"; export {read};');
  put('packages/native-cli/lib/local-runtime.mjs', 'export function read() {return 7;}');
  put('packages/native-cli/lib/product-members.mjs', 'export const original = 7;');
  put('packages/native-cli/lib/project-template.mjs', 'export const template = "input-only";');
  put('packages/native-cli/lib/project-scaffold.mjs', 'import {template} from "./project-template.mjs"; export const scaffold = template;');
  put('owner.md', 'Existing synthetic Source, Unknown and cleanup control');
  const declarations = nativeCliLauncherInputs.filter(name => name.endsWith('.mjs')).map(name => {
    const module = `packages/native-cli/${name}`, bytes = readFileSync(join(root, module));
    const syntax = javascriptInterface(bytes.toString());
    return {module, sha256: hash(bytes), ...syntax, role: 'physical-io', owner: 'existing-control',
      responsibilityFacet: 'primary', contracts: [{operations: ['<module>', ...syntax.operations.map(value => value.name)],
        exports: syntax.exports, attributes: Object.fromEntries(interfaceAttributes.map(name => [name,
          [{path: 'owner.md', anchor: 'Existing synthetic Source, Unknown and cleanup control'}]]))}]};
  });
  put('references/interface-boundaries.json', JSON.stringify(declarations));
  execFileSync('git', ['init', '-q'], {cwd: root});execFileSync('git', ['add', '.'], {cwd: root});
  execFileSync('git', ['-c', 'user.name=Interface control', '-c', 'user.email=interface-control@example.invalid',
    'commit', '-qm', 'Original source control'], {cwd: root});
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  const checkedSource = await checkInterfaceOwners(root, {manifests: ['packages/native-cli/package.json']});
  for (const name of ['package.json', ...nativeCliLauncherInputs]) {
    mkdirSync(dirname(join(directory, name)), {recursive: true});
    copyFileSync(join(root, 'packages/native-cli', name), join(directory, name));
  }
  return {root, directory, source, checkedSource,
    check: artifact => checkStagedNativeCliInterfaces({repository: root, directory, source, checkedSource, artifact})};
}

test('normal CLI copy inputs retain actual source and primary correspondence', async t => {
  const f = await fixture(t), result = await f.check();
  assert.equal(result.correspondence.coverage.modules, 5);
  assert.equal(result.correspondence.coverage.primaryCovered, 5);
  assert.equal(result.dependencies.modules, 5);
  assert.equal(f.checkedSource.modules.length, 5, 'ordinary producer inputs include both project helpers and the dormant member helper');
  assert.equal(result.artifactSource, f.source);
});

test('CLI correspondence refuses dormant unregistered helpers and replaced original bodies', async t => {
  const f = await fixture(t), helper = join(f.directory, 'lib/new-decision.mjs');
  writeFileSync(helper, 'export const accepted = true;');
  await assert.rejects(f.check(), /Unbound installed authored interface: lib\/new-decision.mjs/u);
  rmSync(helper);
  const original = join(f.directory, 'lib/product-members.mjs');
  writeFileSync(original, 'export const original = 8;');
  await assert.rejects(f.check(), /Changed installed interface bytes/u);
});

test('a dormant shipped helper requires its original primary even after the entry check succeeds', async t => {
  const f = await fixture(t), path = join(f.root, 'references/interface-boundaries.json');
  const declarations = JSON.parse(readFileSync(path));
  writeFileSync(path, JSON.stringify(declarations.filter(value =>
    value.module !== 'packages/native-cli/lib/product-members.mjs')));
  await assert.rejects(checkInterfaceOwners(f.root, {manifests: ['packages/native-cli/package.json']}),
    /Unregistered distributed interfaces: packages\/native-cli\/lib\/product-members.mjs/u);
  await assert.rejects(f.check(), /Unregistered distributed interfaces: packages\/native-cli\/lib\/product-members.mjs/u);
});

test('CLI correspondence cannot recreate checked Source qualification from DATA', async t => {
  const f = await fixture(t);
  await assert.rejects(checkStagedNativeCliInterfaces({repository: f.root, directory: f.directory,
    source: f.source, checkedSource: structuredClone(f.checkedSource)}), /Untrusted checked interface source/u);
});

test('Native staged artifact references retain the original header validator and no authored-helper exemption', async t => {
  const f = await fixture(t);
  for (const name of nativeCliLauncherInputs) rmSync(join(f.directory, name));
  writeFileSync(join(f.directory, 'package.json'), JSON.stringify({name: '@actql/cli-darwin-arm64'}));
  const binary = Buffer.alloc(32);binary.writeUInt32LE(0xfeedfacf, 0);binary.writeUInt32LE(0x0100000c, 4);
  const record = {version: 'actql-native-cli-artifact/0.1', sourceSha: f.source,
    platform: 'darwin-arm64', binarySha256: hash(binary), binaryBytes: binary.length,
    generatedCSha256: 'b'.repeat(64), toolchainPinSha256: 'c'.repeat(64),
    notices: {'MOONBIT-CORE-LICENSE': 'd'.repeat(64), 'MOONBIT-CORE-NOTICE': 'e'.repeat(64)},
    toolchain: {qualification: 'synthetic header control, not Native compilation or runtime'},
    abi: {format: 'Mach-O', minimumMacOS: '26.0'}, testedHost: {}, generation: []};
  writeFileSync(join(f.directory, 'bin/actql-native-client'), binary);
  chmodSync(join(f.directory, 'bin/actql-native-client'), 0o755);
  writeFileSync(join(f.directory, 'artifact.json'), JSON.stringify(record));
  const result = await f.check(record);
  assert.equal(result.correspondence.artifacts.length, 1);
  assert.equal(result.correspondence.coverage.modules, 0);
  writeFileSync(join(f.directory, 'lib/unregistered.mjs'), 'export const accepted = true;');
  await assert.rejects(f.check(record), /Unbound installed authored interface/u);
  rmSync(join(f.directory, 'lib/unregistered.mjs'));
  writeFileSync(join(f.directory, 'bin/actql-native-client'), Buffer.alloc(32));
  await assert.rejects(f.check(record), {code: 'ERR_ASSERTION'});
});


// Real authored copies and real Owner references, without building/packing or
// executing a Native binary. This does not claim a complete installable cohort.
test('actual ordinary Native launcher staging includes its dormant product metadata helper', async t => {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const checkedSource = await checkInterfaceOwners(repository, {manifests: ['packages/native-cli/package.json']});
  assert(checkedSource.modules.some(value => value.module === 'packages/native-cli/lib/product-members.mjs'));
  for (const name of ['project-template.mjs', 'project-scaffold.mjs']) {
    assert(checkedSource.modules.some(value => value.module === `packages/native-cli/lib/${name}`));
  }
  const directory = mkdtempSync(join(tmpdir(), 'actql-cli-actual-authored-stage-'));
  t.after(() => rmSync(directory, {recursive: true}));
  for (const member of ['package.json', ...nativeCliLauncherInputs]) {
    mkdirSync(dirname(join(directory, member)), {recursive: true});
    copyFileSync(join(repository, 'packages/native-cli', member), join(directory, member));
  }
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const result = await checkStagedNativeCliInterfaces({repository, directory, source, checkedSource});
  assert.equal(result.correspondence.coverage.primaryCovered, 5);
  assert.equal(result.dependencies.modules, 5);
});

// Container/header controls only. These bytes are not compiled libraries and
// are never loaded, linked or counted as Native or vendor ABI acceptance.
async function localRuntimeFixture(t) {
  const f = await fixture(t);
  for (const name of nativeCliLauncherInputs) rmSync(join(f.directory, name));
  writeFileSync(join(f.directory, 'package.json'), JSON.stringify({name: '@actql/cli-darwin-arm64'}));
  const binary = Buffer.alloc(32); binary.writeUInt32LE(0xfeedfacf, 0); binary.writeUInt32LE(0x0100000c, 4);
  const put = (path, bytes) => {
    mkdirSync(dirname(join(f.directory, path)), {recursive: true});
    writeFileSync(join(f.directory, path), bytes, {mode: 0o644});
    return {path, bytes: Buffer.byteLength(bytes), sha256: hash(bytes)};
  };
  put('bin/actql-native-client', binary); chmodSync(join(f.directory, 'bin/actql-native-client'), 0o755);
  const header = '/* Original public SQLite header notice control, not an ABI fixture. */\n';
  const licenses = [put('licenses/sqlite3.h', header), put('licenses/crypto-LICENSE.txt', 'Original crypto license control.\n')];
  const library = Buffer.from(binary); library.writeUInt32LE(6, 12);
  const libraries = [['sqlite', 'libsqlite3.dylib'], ['crypto', 'libcrypto.3.dylib']].map(([role, name], index) => ({
    ...put(`lib/${name}`, library), role, license: licenses[index].path,
    dependencies: ['/usr/lib/libSystem.B.dylib'], abi: {minimumMacOS: '26.0'},
  }));
  const assets = ['environment', 'registry', 'values', 'fragment', 'result-policy'].map(role => ({
    ...put(`data/${role}.json`, '{}'), role,
  }));
  const manifest = {sourceSha: f.source, platform: 'darwin-arm64', libraries, assets, licenses};
  const metadata = put('local-runtime.json', JSON.stringify(manifest));
  const record = {version: 'actql-native-cli-artifact/0.1', sourceSha: f.source,
    platform: 'darwin-arm64', binarySha256: hash(binary), binaryBytes: binary.length,
    generatedCSha256: 'b'.repeat(64), toolchainPinSha256: 'c'.repeat(64),
    notices: {'MOONBIT-CORE-LICENSE': 'd'.repeat(64), 'MOONBIT-CORE-NOTICE': 'e'.repeat(64)},
    toolchain: {qualification: 'synthetic metadata control, not compiled Native or vendor ABI evidence'},
    abi: {format: 'Mach-O', minimumMacOS: '26.0'}, testedHost: {}, generation: [], localRuntime: metadata};
  const save = value => writeFileSync(join(f.directory, 'artifact.json'), JSON.stringify(value));
  save(record);
  return {...f, binary, library, header, manifest, record, save, put};
}

test('Local runtime sidecar selects the actual original libraries and SQLite header without inventing Moon compilation', async t => {
  const f = await localRuntimeFixture(t), result = await f.check(f.record);
  const artifacts = result.correspondence.artifacts;
  assert.deepEqual(artifacts.map(value => [value.module, value.target]), [
    ['bin/actql-native-client', 'native'], ['lib/libcrypto.3.dylib', 'native-runtime-library'],
    ['lib/libsqlite3.dylib', 'native-runtime-library'], ['licenses/sqlite3.h', 'native-runtime-original-header'],
  ]);
  for (const artifact of artifacts.slice(1)) {
    assert.deepEqual(artifact.verification.manifest, f.record.localRuntime);
    assert.equal(artifact.verification.reader, 'packages/native-cli/lib/local-runtime.mjs#admitInstalledLocalRuntime');
    assert.equal(Object.hasOwn(artifact.verification, 'generatedCSha256'), false);
    assert.equal(Object.hasOwn(artifact.verification, 'build'), false);
  }
  assert.deepEqual(artifacts.at(-1).verification.libraryRoles, ['sqlite']);
  assert.equal(result.correspondence.coverage.modules, 0);
});

test('runtime original registration cannot accept changed library/header bytes, foreign manifest or inline candidate library claims', async t => {
  const f = await localRuntimeFixture(t);
  writeFileSync(join(f.directory, 'lib/libcrypto.3.dylib'), Buffer.alloc(32));
  await assert.rejects(f.check(f.record), error => error.exitCode === 65);
  writeFileSync(join(f.directory, 'lib/libcrypto.3.dylib'), f.library);
  writeFileSync(join(f.directory, 'licenses/sqlite3.h'), f.header + 'changed');
  await assert.rejects(f.check(f.record), error => error.exitCode === 65);
  writeFileSync(join(f.directory, 'licenses/sqlite3.h'), f.header);
  const foreign = f.put('local-runtime.json', JSON.stringify({...f.manifest, sourceSha: 'f'.repeat(40)}));
  f.save({...f.record, localRuntime: foreign});
  await assert.rejects(f.check({...f.record, localRuntime: foreign}), error => error.exitCode === 65);
  f.put('local-runtime.json', JSON.stringify(f.manifest));
  const inline = {...f.record, localRuntime: {...f.record.localRuntime, libraries: f.manifest.libraries}};
  f.save(inline);
  await assert.rejects(f.check(inline), error => error.exitCode === 65);
});

test('only exact admitted original notices are registered while extra authored code and executable headers still refuse', async t => {
  const f = await localRuntimeFixture(t);
  const extra = join(f.directory, 'licenses/extra.h'); writeFileSync(extra, '/* unknown */');
  await assert.rejects(f.check(f.record), /Unbound installed authored interface: licenses\/extra.h/u); rmSync(extra);
  const helper = join(f.directory, 'licenses/helper.mjs'); writeFileSync(helper, 'export const accepted = true;');
  await assert.rejects(f.check(f.record), /Unbound installed authored interface: licenses\/helper.mjs/u); rmSync(helper);
  chmodSync(join(f.directory, 'licenses/sqlite3.h'), 0o755);
  await assert.rejects(f.check(f.record), /Executable runtime license header/u);
  chmodSync(join(f.directory, 'licenses/sqlite3.h'), 0o644);
});
