import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
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
  put('packages/native-cli/lib/local-runtime.mjs', 'import {original} from "./product-members.mjs"; export function read() {return original;}');
  put('packages/native-cli/lib/product-members.mjs', 'export const original = 7;');
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
  assert.equal(result.correspondence.coverage.modules, 3);
  assert.equal(result.correspondence.coverage.primaryCovered, 3);
  assert.equal(result.dependencies.modules, 3);
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
