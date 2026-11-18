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
import {admitInstalledNativeArtifactMaterial} from './native-cli-artifact-reader.mjs';
import {withNativeMockReleaseAdmission, originalNativeMockReleaseAdmission} from './native-cli-release.mjs';
import {retainNativeMockCampaignInputs} from './native-mock-campaign-inputs.mjs';
import {inventory} from './package-release.mjs';
import {runNativeCliMockInstall} from './test-native-cli-mock-install.mjs';

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

// Real readers, archives and original checker instances over inert container
// bytes. These controls do not execute Native or establish an installed cohort.
async function campaignFixture(t) {
  const f = await localRuntimeFixture(t), version = '0.0.7-rc.1';
  const output = mkdtempSync(join(tmpdir(), 'actql-mock-campaign-release-'));
  const launcher = mkdtempSync(join(tmpdir(), 'actql-mock-campaign-launcher-'));
  t.after(() => {rmSync(output, {recursive: true}); rmSync(launcher, {recursive: true});});
  const notices = {};
  for (const name of ['MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE']) {
    const bytes = Buffer.from(`Independent inert fixture notice: ${name}`);
    f.put(name, bytes); notices[name] = hash(bytes);
  }
  const record = {...f.record, notices}; f.save(record);
  f.put('package.json', JSON.stringify({name: '@actql/cli-darwin-arm64', version,
    license: 'Apache-2.0', os: ['darwin'], cpu: ['arm64']}));
  const platforms = {'darwin-arm64': {package: '@actql/cli-darwin-arm64', sourceSha: f.source,
    binarySha256: record.binarySha256, binaryBytes: record.binaryBytes, localRuntimeSha256: record.localRuntime.sha256}};
  for (const name of nativeCliLauncherInputs) {
    mkdirSync(dirname(join(launcher, name)), {recursive: true});
    copyFileSync(join(f.root, 'packages/native-cli', name), join(launcher, name));
  }
  writeFileSync(join(launcher, 'package.json'), JSON.stringify({name: 'actql', version,
    license: 'Apache-2.0', bin: {actql: 'bin/actql.mjs'}, optionalDependencies: {'@actql/cli-darwin-arm64': version}}));
  writeFileSync(join(launcher, 'platforms.json'), JSON.stringify(platforms));
  const packages = [];
  for (const [name, directory] of [['@actql/cli-darwin-arm64', f.directory], ['actql', launcher]]) {
    // tar's selected root is the ordinary package root, not another copied
    // implementation. Staging of these small inert fixtures is test DATA.
    const input = join(output, name.replaceAll('/', '-')); mkdirSync(input);
    execFileSync('cp', ['-R', directory, join(input, 'package')]);
    const file = `${name.replace('@', '').replace('/', '-')}-${version}.tgz`;
    execFileSync('tar', ['-czf', join(output, file), '-C', input, 'package']);
    const bytes = readFileSync(join(output, file));
    packages.push({name, version, file, bytes: bytes.length, sha256: hash(bytes),
      integrity: 'sha512-' + createHash('sha512').update(bytes).digest('base64'), files: await inventory(directory)});
    rmSync(input, {recursive: true});
  }
  const manifest = {version: 'actql-native-cli-release/0.1', sourceSha: f.source,
    preparedAt: '2000-01-01T00:00:00Z', recipeSha256: 'd'.repeat(64),
    cohort: {packageVersion: version, registry: 'https://registry.npmjs.org/', access: 'public', tag: 'candidate-fixture'},
    platforms, artifacts: [record], packages};
  writeFileSync(join(output, 'release.json'), JSON.stringify(manifest));
  mkdirSync(join(f.root, 'node_modules'));
  writeFileSync(join(f.root, '.git/info/exclude'), 'node_modules/\n');
  let sourceChecks = 0;
  return {...f, output, record, manifest, options: {sourceRepository: f.root, controller: f.root,
    checkSource: async (...args) => {sourceChecks++; return checkInterfaceOwners(...args);}}, sourceChecks: () => sourceChecks};
}

test('same-call installed artifact reader retains its actual runtime material and current byte refusals', async t => {
  const f = await localRuntimeFixture(t);
  const material = await admitInstalledNativeArtifactMaterial(f.directory, f.source);
  assert.deepEqual(material.artifact, f.record);
  assert.deepEqual(material.localRuntime, f.manifest);
  const checked = await f.check(f.record);
  assert.deepEqual(checked.artifactMaterial, material);
  assert.equal(checked.artifactMaterial.localRuntime.libraries[0].role, 'sqlite');
  f.put('lib/libsqlite3.dylib', Buffer.alloc(32));
  await assert.rejects(admitInstalledNativeArtifactMaterial(f.directory, f.source), error => error.exitCode === 65);
});

test('Native Mock original admission repeats full Source checks but extracts its unchanged archive only once', async t => {
  const f = await campaignFixture(t);
  let retained;
  const commands = join(f.output, 'commands'), calls = join(f.output, 'tar-calls');
  mkdirSync(commands);
  writeFileSync(join(commands, 'tar'), '#!/bin/sh\nprintf x >> ' + JSON.stringify(calls) + '\nexec /usr/bin/tar "$@"\n');
  chmodSync(join(commands, 'tar'), 0o755);
  const originalPath = process.env.PATH;
  process.env.PATH = commands + ':' + originalPath;
  try {
  await withNativeMockReleaseAdmission(f.output, async admission => {
    retained = admission;
    assert.deepEqual(await admission.verify(), f.manifest);
    assert.equal(f.sourceChecks(), 1);
    const extractions = readFileSync(calls, 'utf8');
    assert(extractions.length > 0);
    assert.deepEqual(await admission.verify(), f.manifest);
    assert.equal(readFileSync(calls, 'utf8'), extractions, 'Retained original admission must not extract again');
    assert.equal(f.sourceChecks(), 2);
    admission.assertCurrent();
  }, f.options);
  await assert.rejects(retained.verify(), /Closed or overlapping/u);
  assert.throws(retained.assertCurrent, /Closed/u);
  } finally {process.env.PATH = originalPath;}
});

test('Native Mock fixed candidate archive, Source discovery and dependency changes stop without replacement', async t => {
  for (const selected of ['archive', 'source', 'dependency']) {
    const f = await campaignFixture(t);
    const dependency = join(f.root, 'node_modules/fixture.mjs');
    writeFileSync(dependency, 'export const original = 1;');
    await withNativeMockReleaseAdmission(f.output, async admission => {
      await admission.verify();
      if (selected === 'archive') writeFileSync(join(f.output, f.manifest.packages[0].file), 'different software');
      else if (selected === 'source') writeFileSync(join(f.root, 'new-source.mjs'), 'export const added = true;');
      else writeFileSync(dependency, 'export const original = 2;');
      await assert.rejects(admission.verify(), /fixed candidate|source changed/u);
      await assert.rejects(admission.verify(), /Closed/u);
      assert.equal(f.sourceChecks(), 1, 'A changed candidate cannot enter a replacement verification');
    }, f.options);
  }
});


test('Native Mock fresh Source proof rejects copied checker DATA and post-await archive change', async t => {
  for (const selected of ['copy', 'post-await']) {
    const f = await campaignFixture(t);
    const originalCheck = f.options.checkSource;
    let checks = 0;
    f.options.checkSource = async (...args) => {
      const checked = await originalCheck(...args); checks++;
      if (selected === 'copy') return structuredClone(checked);
      if (checks === 2) writeFileSync(join(f.output, f.manifest.packages[0].file), 'changed after actual Source check');
      return checked;
    };
    await withNativeMockReleaseAdmission(f.output, async admission => {
      if (selected === 'post-await') await admission.verify();
      await assert.rejects(admission.verify(), selected === 'copy' ? /Untrusted checked interface source/u : /fixed candidate/u);
      await assert.rejects(admission.verify(), /Closed/u);
    }, f.options);
  }
});

test('Native Mock same admission rejects overlapping use and revokes its original closure', async t => {
  const f = await campaignFixture(t), originalCheck = f.options.checkSource;
  let release, started;
  const entered = new Promise(resolve => {started = resolve;});
  f.options.checkSource = async (...args) => {
    started(); await new Promise(resolve => {release = resolve;});
    return originalCheck(...args);
  };
  let retained;
  await withNativeMockReleaseAdmission(f.output, async admission => {
    retained = admission;
    assert.equal(originalNativeMockReleaseAdmission(admission, f.output), admission);
    assert.throws(() => originalNativeMockReleaseAdmission({...admission}, f.output), /Untrusted/u);
    assert.throws(() => originalNativeMockReleaseAdmission(admission, f.directory), /foreign/u);
    let forgedCalls = 0;
    await assert.rejects(runNativeCliMockInstall(f.output, {releaseAdmission: {
      verify() {forgedCalls++; return f.manifest;}, assertCurrent() {},
    }}), /Untrusted/u);
    assert.equal(forgedCalls, 0, 'A structural consumer port cannot bypass artifact admission');
    const pending = admission.verify(); await entered;
    await assert.rejects(admission.verify(), /overlapping/u);
    release(); assert.deepEqual(await pending, f.manifest);
  }, f.options);
  await assert.rejects(retained.verify(), /Closed/u);
  assert.throws(() => originalNativeMockReleaseAdmission(retained, f.output), /Untrusted/u);
});

test('Native Mock original dependency target and loader changes refuse before a fresh consumer', async t => {
  const f = await campaignFixture(t), first = join(f.output, 'original-dependency.mjs'), other = join(f.output, 'copy-dependency.mjs');
  writeFileSync(first, 'export const sameBytes = true;'); writeFileSync(other, readFileSync(first));
  const dependency = join(f.root, 'node_modules/selected.mjs');
  const {symlinkSync, unlinkSync} = await import('node:fs');
  symlinkSync(first, dependency);
  await withNativeMockReleaseAdmission(f.output, async admission => {
    await admission.verify();
    unlinkSync(dependency); symlinkSync(other, dependency);
    await assert.rejects(admission.verify(), /fixed candidate/u);
  }, f.options);
  unlinkSync(dependency);
  const previous = process.env.NODE_OPTIONS;
  try {
    await withNativeMockReleaseAdmission(f.output, async admission => {
      await admission.verify();
      process.env.NODE_OPTIONS = '--no-warnings';
      await assert.rejects(admission.verify(), /controller admission changed/u);
    }, f.options);
  } finally {
    if (previous === undefined) delete process.env.NODE_OPTIONS; else process.env.NODE_OPTIONS = previous;
  }
});

test('Native Mock input reader rechecks the actual current controller and dependency installation', () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  // A read-only input integrity control on this dirty implementation checkout,
  // not a clean-Source/cohort admission or cached generation qualification.
  const assertCurrent = retainNativeMockCampaignInputs({repository: root, controller: root, files: []});
  assertCurrent();
});


test('Native Mock final currentness refusal permanently ends the original campaign even if bytes are restored', async t => {
  const f = await campaignFixture(t), dependency = join(f.root, 'node_modules/original.mjs');
  writeFileSync(dependency, 'original dependency');
  await withNativeMockReleaseAdmission(f.output, async admission => {
    await admission.verify();
    writeFileSync(dependency, 'changed dependency');
    assert.throws(admission.assertCurrent, /fixed candidate/u);
    writeFileSync(dependency, 'original dependency');
    await assert.rejects(admission.verify(), /Closed/u);
  }, f.options);
});
