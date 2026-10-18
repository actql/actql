import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const custody = fileURLToPath(new URL('./initial-control-package-custody.cjs', import.meta.url));
const actual = name => readFileSync(new URL(name, import.meta.url));
const fact = (path, bytes) => ({path, bytes: bytes.length,
  sha256: createHash('sha256').update(bytes).digest('hex')});
function fixture(t, host = 'globalThis.actualHostImageValue="original";export function assertInitialControlHostPreparation(){};') {
  const directory = mkdtempSync(join(tmpdir(), 'actql-package-image-custody-'));
  t.after(() => rmSync(directory, {recursive: true}));
  const root = join(directory, 'local');
  const sources = {'package.json': Buffer.from(JSON.stringify({name: '@actql/local-node', type: 'module'})),
    'adapters/host-node/embedded-local.mjs': Buffer.from(host),
    'spec/local-check-environment.json': Buffer.from('{"original":"asset"}\n')};
  for (const [path, bytes] of Object.entries(sources)) {
    mkdirSync(dirname(join(root, path)), {recursive: true}); writeFileSync(join(root, path), bytes);
  }
  const inventory = {images: Object.entries(sources).map(([path, bytes]) => fact(path, bytes)),
    packages: [], dependencies: [], optionalSdk: null, optionalSdkCoverage: 'absent',
    hostModule: 'adapters/host-node/embedded-local.mjs', hostValidator: 'assertInitialControlHostPreparation'};
  function run(body, before = '', afterCapture = '', tweak, initialize = true) {
    const selected = structuredClone(inventory); tweak?.(selected);
    const preload = join(directory, 'preload.cjs'), entry = join(directory, 'entry.mjs');
    writeFileSync(preload, [before,
      'const {captureInitialControlPackageCustody}=require('+JSON.stringify(custody)+');',
      'const root='+JSON.stringify(root)+', inventory='+JSON.stringify(selected)+';',
      'globalThis.packageImageCustody=captureInitialControlPackageCustody(inventory,root,'+JSON.stringify(entry)+');',
      afterCapture,
      initialize ? 'globalThis.originalHostNamespace=packageImageCustody.initializeHostNamespace();' : '',
    ].join('\n'));
    writeFileSync(entry, body);
    const result = spawnSync(process.execPath, ['--require', preload, entry], {
      cwd: directory, env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 30000});
    assert.equal(result.error, undefined); return result;
  }
  return {directory, root, inventory, sources, run};
}

// Real same-FD reads and Node loader/compilation; the small Host namespace is
// an explicit fixture, not the complete installed Host, original operational
// issuer, public consumer, numerical funding or all-history loader proof.
test('package custody loads the same captured Host Source and immutable asset before entry', t => {
  const f = fixture(t);
  const result = f.run([
    'import assert from "node:assert/strict";',
    'assert.equal(actualHostImageValue,"original");',
    'assert.equal(typeof originalHostNamespace.assertInitialControlHostPreparation,"function");',
    'assert.equal(packageImageCustody.readAsset("spec/local-check-environment.json"),\'{"original":"asset"}\\n\');',
    'packageImageCustody.assertCurrent();',
    'assert.equal(packageImageCustody.begin,undefined);',
  ].join('\n'), '', [
    'require("node:fs").writeFileSync(require("node:path").join(root,"adapters/host-node/embedded-local.mjs"),',
    ' "throw new Error(\\"ReplacementMustNotCompile\\")");',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('a mismatched captured package image refuses before Host and entry compilation', t => {
  const f = fixture(t), result = f.run('throw new Error("EntryMustNotRun");', '', '', inventory => {
    inventory.images.find(item => item.path.endsWith('embedded-local.mjs')).sha256 = '0'.repeat(64);
  });
  assert.notEqual(result.status, 0); assert.match(result.stderr, /InitialControlImageChanged/);
  assert.doesNotMatch(result.stderr, /EntryMustNotRun/);
});

test('uncaptured Host dependencies cannot acquire package-image coverage', t => {
  const f = fixture(t, 'import "./foreign.mjs";export function assertInitialControlHostPreparation(){};');
  writeFileSync(join(f.root, 'adapters/host-node/foreign.mjs'), 'globalThis.foreignWasCompiled=true;');
  const result = f.run('throw new Error("EntryMustNotRun");');
  assert.notEqual(result.status, 0); assert.match(result.stderr, /UncapturedInitialControlImage/);
  assert.doesNotMatch(result.stderr, /EntryMustNotRun/);
});

test('application-time package capture refuses before observing a caller inventory', t => {
  const f = fixture(t), result = f.run([
    'import assert from "node:assert/strict";',
    'import{createRequire}from"node:module";',
    'const{captureInitialControlPackageCustody}=createRequire(import.meta.url)('+JSON.stringify(custody)+');',
    'let reads=0;const packet=new Proxy({},{getOwnPropertyDescriptor(){reads++;throw new Error("CallerRead");}});',
    'assert.throws(()=>captureInitialControlPackageCustody(packet,"unused"),{code:"InitialControlPackageCustodyUnavailable"});',
    'assert.equal(reads,0);',
  ].join('\n'));
  assert.equal(result.status, 0, result.stderr);
});

test('the actual selected public preload consumes generated inventory without issuing a Scope', t => {
  const f = fixture(t), local = join(f.directory, 'node_modules/@actql/local-node');
  mkdirSync(join(local, 'adapters/host-node'), {recursive: true});
  const sources = {...f.sources,
    'adapters/host-node/embedded-local.mjs': Buffer.from(
      'import{createRequire}from"node:module";'+
      'const delivery=createRequire(import.meta.url)("../../selected-infer-startup.cjs");'+
      'globalThis.originalDelivery=delivery;globalThis.actualHostImageValue="original";'+
      'globalThis.actualConsumerCalls=0;'+
      'export function connectInitialControlHostPreparation(){actualConsumerCalls++;return Promise.resolve({});}'+
      'export function assertInitialControlHostPreparation(){};'),
    'package.json': Buffer.from(JSON.stringify({name: '@actql/local-node', type: 'module',
      exports: {'./selected-infer-startup': './selected-infer-startup.cjs'}})),
    'selected-infer-startup.cjs': readFileSync(new URL('../../packages/local-node/selected-infer-startup.cjs', import.meta.url))};
  for (const name of ['infer-trusted-node-preload.cjs', 'initial-control-installation-owner.cjs',
    'initial-control-package-custody.cjs', 'initial-control-image-source.cjs', 'initial-control-image-loader.cjs']) {
    sources['adapters/host-node/'+name] = actual(name);
  }
  const inventory = {...f.inventory, images: Object.entries(sources).map(([path, bytes]) => fact(path, bytes))};
  sources['adapters/host-node/initial-control-package-original.cjs'] = Buffer.from(
    'module.exports=Object.freeze({imageInventory:'+JSON.stringify(inventory)+'});');
  for (const [path, bytes] of Object.entries(sources)) {
    mkdirSync(dirname(join(local, path)), {recursive: true}); writeFileSync(join(local, path), bytes);
  }
  const entry = join(f.directory, 'selected-entry.mjs');
  writeFileSync(entry, [
    'import assert from "node:assert/strict";',
    'import{createRequire}from"node:module";',
    'const require=createRequire(import.meta.url);',
    'assert.equal(actualHostImageValue,"original");',
    'assert.equal(originalDelivery,require("@actql/local-node/selected-infer-startup"));',
    'assert.equal(Object.getPrototypeOf(originalDelivery),null);',
    'const root=require('+JSON.stringify(join(local, 'adapters/host-node/infer-trusted-node-preload.cjs'))+');',
    'const view={};assert.equal(root.associateHost(view,{runtime:process,host:{},installation:{},generation:{},supplier(){}}),view);',
    'let reads=0;const raw=new Proxy({},{ownKeys(){reads++;throw new Error("RawInput");}});',
    'assert.throws(()=>root.beginInitialControlInstallation({},raw),{code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.throws(()=>root.connectInitialControlHostPreparation("open",raw),{code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.equal(reads,0);',
    'assert.equal(actualConsumerCalls,0);',
  ].join('\n'));
  const result = spawnSync(process.execPath,
    ['--no-lazy', '--require', '@actql/local-node/selected-infer-startup', entry], {
      cwd: f.directory, env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 30000});
  assert.equal(result.error, undefined); assert.equal(result.status, 0, result.stderr);
});

test('selected dependency graph uses the actual resolved original package Sources', t => {
  const f = fixture(t, 'import dependency from "selected-dependency";globalThis.actualHostImageValue=dependency.value;export function assertInitialControlHostPreparation(){};');
  const sources = {'package.json': Buffer.from(JSON.stringify({name: 'selected-dependency', version: '1.0.0', main: './index.cjs'})),
    'index.cjs': Buffer.from('module.exports={value:"original-dependency"};')};
  const directory = join(f.root, 'node_modules/selected-dependency'); mkdirSync(directory, {recursive: true});
  for (const [path, bytes] of Object.entries(sources)) writeFileSync(join(directory, path), bytes);
  const result = f.run([
    'import assert from "node:assert/strict";',
    'assert.equal(actualHostImageValue,"original-dependency");packageImageCustody.assertCurrent();',
  ].join('\n'), '',
    'require("node:fs").writeFileSync('+JSON.stringify(join(directory, 'index.cjs'))+',"throw new Error(\\"ReplacementMustNotCompile\\")");',
    inventory => {
      inventory.dependencies = [{name: 'selected-dependency', package: 0}];
      inventory.packages = [{name: 'selected-dependency', version: '1.0.0',
        images: Object.entries(sources).map(([path, bytes]) => fact(path, bytes)), dependencies: []}];
    });
  assert.equal(result.status, 0, result.stderr);
});

test('a package identity mismatch refuses even when its captured files match the DATA facts', t => {
  const f = fixture(t), directory = join(f.root, 'node_modules/selected-dependency');
  mkdirSync(directory, {recursive: true});
  const sources = {'package.json': Buffer.from(JSON.stringify({name: 'selected-dependency', version: '1.0.0', main: './index.cjs'})),
    'index.cjs': Buffer.from('module.exports={};')};
  for (const [path, bytes] of Object.entries(sources)) writeFileSync(join(directory, path), bytes);
  const result = f.run('throw new Error("EntryMustNotRun");', '', '', inventory => {
    inventory.dependencies = [{name: 'selected-dependency', package: 0}];
    inventory.packages = [{name: 'selected-dependency', version: '2.0.0',
      images: Object.entries(sources).map(([path, bytes]) => fact(path, bytes)), dependencies: []}];
  });
  assert.notEqual(result.status, 0); assert.match(result.stderr, /InitialControlPackageImageChanged/);
  assert.doesNotMatch(result.stderr, /EntryMustNotRun/);
});

test('failed namespace initialization keeps the same original cause and never recompiles or retries', t => {
  const f = fixture(t, 'globalThis.initializations=(globalThis.initializations??0)+1;throw originalInitializationCause;export function assertInitialControlHostPreparation(){};');
  const result = f.run([
    'import assert from "node:assert/strict";',
    'assert.equal(firstInitializationCause,originalInitializationCause);',
    'assert.equal(secondInitializationCause,originalInitializationCause);',
    'assert.equal(initializations,1);',
    'assert.equal(secondInitializationCause.cleanupHandle,originalInitializationCause.cleanupHandle);',
    'assert.equal(secondInitializationCause.cleanupHandle.status().pending,true);',
  ].join('\n'),
    'globalThis.originalInitializationCause=Object.freeze(Object.assign(new Error("OriginalNamespaceFailure"),{cleanupHandle:Object.freeze({status(){return{pending:true};},retry(){throw new Error("DoNotRetryOriginalDuty");}})}));',
    [
      'try{packageImageCustody.initializeHostNamespace();}catch(cause){globalThis.firstInitializationCause=cause;}',
      'try{packageImageCustody.initializeHostNamespace();}catch(cause){globalThis.secondInitializationCause=cause;}',
    ].join('\n'), undefined, false);
  assert.equal(result.status, 0, result.stderr);
});

test('optional SDK custody follows the actual consumer resolution rather than a nested Local copy', t => {
  const f = fixture(t);
  const sdk = {'package.json': Buffer.from(JSON.stringify({name: '@actql/provider-ai-sdk', version: '1.0.0', main: './index.cjs'})),
    'index.cjs': Buffer.from('module.exports={value:"actual-consumer-original"};')};
  const installed = join(f.directory, 'node_modules/@actql/provider-ai-sdk');
  const foreign = join(f.root, 'node_modules/@actql/provider-ai-sdk');
  for (const directory of [installed, foreign]) mkdirSync(directory, {recursive: true});
  for (const [path, bytes] of Object.entries(sdk)) writeFileSync(join(installed, path), bytes);
  writeFileSync(join(foreign, 'package.json'), sdk['package.json']);
  writeFileSync(join(foreign, 'index.cjs'), 'module.exports={value:"unselected-nested-copy"};');
  const result = f.run([
    'import assert from "node:assert/strict";',
    'assert.equal(optionalSdkFromActualConsumer.value,"actual-consumer-original");',
    'packageImageCustody.assertCurrent();',
  ].join('\n'), '',
    'globalThis.optionalSdkFromActualConsumer=require("node:module").createRequire('+JSON.stringify(join(f.directory, 'entry.mjs'))+')'+
      '("@actql/provider-ai-sdk");',
    inventory => {
      inventory.optionalSdk = 0; inventory.optionalSdkCoverage = 'prepared';
      inventory.packages = [{name: '@actql/provider-ai-sdk', version: '1.0.0',
        images: Object.entries(sdk).map(([path, bytes]) => fact(path, bytes)), dependencies: []}];
    });
  assert.equal(result.status, 0, result.stderr);
});
