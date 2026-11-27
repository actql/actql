import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test, {type TestContext} from 'node:test';
import {admitFixtureUndici} from './fixtures/ordinary-undici-custody.fixture.mjs';

type ImageFact = ReturnType<typeof fact> & {npmRelease?: ReturnType<typeof releaseFact>};
type Dependency = {name: string; package?: number; local?: boolean};
type FixturePackage = {name: string; version: string; releaseVersion?: string; images: ImageFact[]; dependencies: Dependency[]};
type FixtureInventory = {
  images: ImageFact[];
  packages: FixturePackage[];
  dependencies: Dependency[];
  optionalSdk: number | null;
  optionalSdkCoverage: 'absent' | 'prepared';
  publicNode: FixturePackage | null;
  publicNodeCoverage: 'absent' | 'prepared';
  localPublicModule: string;
  hostModule: string;
  hostValidator: string;
  localReleaseVersion?: string;
};

const custody = fileURLToPath(new URL('./initial-control-package-custody.cjs', import.meta.url));
const actual = (name: string) => readFileSync(new URL(name, import.meta.url));
const fact = (path: string, bytes: Uint8Array) => ({path, bytes: bytes.length,
  sha256: createHash('sha256').update(bytes).digest('hex')});
const releaseFact = (version: string, bytes: Uint8Array) => {
  const {bytes: length, sha256} = fact('package.json', bytes);
  return {version, bytes: length, sha256};
};
function fixture(t: TestContext, host = 'globalThis.actualHostImageValue="original";export function assertInitialControlHostPreparation(){};') {
  const directory = mkdtempSync(join(tmpdir(), 'actql-package-image-custody-'));
  t.after(() => rmSync(directory, {recursive: true}));
  const root = join(directory, 'local');
  const sources = {'package.json': Buffer.from(JSON.stringify({name: '@actql/local-node', type: 'module', exports: './index.mjs'})),
    'index.mjs': Buffer.from('globalThis.localPublicInitializations=(globalThis.localPublicInitializations??0)+1;export const originalLocal="original-local-public";'),
    'adapters/host-node/embedded-local.mjs': Buffer.from(host),
    'spec/local-check-environment.json': Buffer.from('{"original":"asset"}\n')};
  for (const [path, bytes] of Object.entries(sources)) {
    mkdirSync(dirname(join(root, path)), {recursive: true}); writeFileSync(join(root, path), bytes);
  }
  const inventory: FixtureInventory = {images: Object.entries(sources).map(([path, bytes]) => fact(path, bytes)),
    packages: [], dependencies: [], optionalSdk: null, optionalSdkCoverage: 'absent',
    publicNode: null, publicNodeCoverage: 'absent', localPublicModule: 'index.mjs',
    hostModule: 'adapters/host-node/embedded-local.mjs', hostValidator: 'assertInitialControlHostPreparation'};
  function run(body: string, before = '', afterCapture = '', tweak?: (selected: FixtureInventory) => void,
    initialize = true, publicEntry?: string, ordinary = false, sdkSelection?: unknown) {
    const selected = structuredClone(inventory); tweak?.(selected);
    const preload = join(directory, 'preload.cjs'), entry = join(directory, 'entry.mjs');
    const selector = ordinary ? 'captureOrdinaryInitialControlPackageCustody' : 'captureInitialControlPackageCustody';
    writeFileSync(preload, [before,
      'const {readVerifiedSdkImages,'+selector+'}=require('+JSON.stringify(custody)+');',
      'const root='+JSON.stringify(root)+', inventory='+JSON.stringify(selected)+';',
      'globalThis.readVerifiedSdkImages=readVerifiedSdkImages;',
      'globalThis.packageImageCustody='+selector+'(inventory,root,'+JSON.stringify(entry)+
        ','+(JSON.stringify(publicEntry) ?? 'undefined')+','+(JSON.stringify(sdkSelection) ?? 'undefined')+');',
      afterCapture,
      initialize ? 'globalThis.originalHostNamespace=packageImageCustody.initializeHostNamespace();' : '',
    ].join('\n'));
    writeFileSync(entry, ordinary ? 'import "./preload.cjs";\n' + body : body);
    const argv = ordinary ? [entry] : ['--require', preload, entry];
    const result = spawnSync(process.execPath, argv, {
      cwd: directory, env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 30000});
    assert.equal(result.error, undefined); return result;
  }
  return {directory, root, inventory, sources, run};
}

function addPublicNode(f: ReturnType<typeof fixture>, source = 'import{originalLocal}from"@actql/local-node";globalThis.nodePublicInitializations=(globalThis.nodePublicInitializations??0)+1;export const originalNode=originalLocal+"/node";') {
  const node = join(f.directory, 'node_modules/@actql/node');
  mkdirSync(node, {recursive: true});
  symlinkSync(f.root, join(f.directory, 'node_modules/@actql/local-node'));
  const sources = {'package.json': Buffer.from(JSON.stringify({name: '@actql/node', version: '1.0.0',
    type: 'module', exports: './index.mjs', dependencies: {'@actql/local-node': '1.0.0'}})),
  'index.mjs': Buffer.from(source), 'selected-infer-startup.cjs': Buffer.from('module.exports={};')};
  for (const [path, bytes] of Object.entries(sources)) writeFileSync(join(node, path), bytes);
  const selected = {name: '@actql/node', version: '1.0.0',
    images: Object.entries(sources).map(([path, bytes]) => fact(path, bytes)),
    dependencies: [{name: '@actql/local-node', local: true}]};
  return {node, entry: join(node, 'selected-infer-startup.cjs'), selected};
}

test('both actual public namespaces compile from captured Sources before entry and remain the same originals', t => {
  const f = fixture(t), n = addPublicNode(f);
  const result = f.run([
    'import assert from "node:assert/strict";',
    'assert.equal(localPublicInitializations,1);assert.equal(nodePublicInitializations,1);',
    'const local=await import("@actql/local-node");const node=await import("@actql/node");',
    'assert.equal(node.originalNode,"original-local-public/node");',
    'assert.equal(local.originalLocal,"original-local-public");',
    'assert.equal(localPublicInitializations,1);assert.equal(nodePublicInitializations,1);',
    'packageImageCustody.assertCurrent();',
  ].join('\n'), '',
  'require("node:fs").writeFileSync('+JSON.stringify(join(n.node, 'index.mjs'))+',"throw new Error(\\"LateNodeReplacement\\")");'+
  'require("node:fs").writeFileSync(require("node:path").join(root,"index.mjs"),"throw new Error(\\"LateLocalReplacement\\")");',
  inventory => { inventory.publicNode = n.selected; inventory.publicNodeCoverage = 'prepared'; }, true, n.entry);
  assert.equal(result.status, 0, result.stderr);
});

test('the selected public Node wrapper refuses missing public Source coverage before any namespace compiles', t => {
  const f = fixture(t), n = addPublicNode(f);
  const result = f.run('throw new Error("EntryMustNotRun");', '', '', undefined, true, n.entry);
  assert.notEqual(result.status, 0); assert.match(result.stderr, /InitialControlPublicNodeUnavailable/);
  assert.doesNotMatch(result.stderr, /EntryMustNotRun/);
});

test('a public Node dependency cannot substitute a distinct Local installation', t => {
  const f = fixture(t), n = addPublicNode(f);
  const foreign = join(n.node, 'node_modules/@actql/local-node');
  mkdirSync(foreign, {recursive: true});
  writeFileSync(join(foreign, 'package.json'), JSON.stringify({name: '@actql/local-node', exports: './index.mjs'}));
  writeFileSync(join(foreign, 'index.mjs'), 'throw new Error("ForeignLocalMustNotCompile");');
  const result = f.run('throw new Error("EntryMustNotRun");', '', '', inventory => {
    inventory.publicNode = n.selected; inventory.publicNodeCoverage = 'prepared';
  }, true, n.entry);
  assert.notEqual(result.status, 0); assert.match(result.stderr, /InitialControlPackageImageChanged/);
  assert.doesNotMatch(result.stderr, /ForeignLocalMustNotCompile|EntryMustNotRun/);
});

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
    inventory.images.find(item => item.path.endsWith('embedded-local.mjs'))!.sha256 = '0'.repeat(64);
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

for (const route of ['local-node', 'node']) test('the actual eager '+route+' preload bounds original Mock input before its explicit Host fixture', t => {
  const f = fixture(t), local = join(f.directory, 'node_modules/@actql/local-node');
  mkdirSync(join(local, 'adapters/host-node'), {recursive: true});
  const sources: Record<string, Buffer> = {...f.sources,
    'adapters/host-node/embedded-local.mjs': Buffer.from(
      'import{createRequire}from"node:module";'+
      'const delivery=createRequire(import.meta.url)("../../selected-infer-startup.cjs");'+
      'const dispatch=createRequire(import.meta.url)("../../initial-control-public-dispatch.cjs");'+
      'globalThis.originalLocalDispatch=dispatch;'+
      'globalThis.initialDispatchReads=0;'+
      'try{dispatch.selectedInitialControlHostPreparation("open",new Proxy({},{get(){initialDispatchReads++;},ownKeys(){initialDispatchReads++;}}));}'+
      'catch(error){globalThis.initialDispatchCause=error.code;}'+
      'globalThis.originalDelivery=delivery;globalThis.actualHostImageValue="original";'+
      'globalThis.actualConsumerCalls=0;'+
      'export {snapshotInitialControlHostInput as readInitialControlHostInput}from"./initial-control-host-input.mjs";'+
      'export function connectInitialControlHostPreparation(kind,raw){actualConsumerCalls++;'+
      'const root=createRequire(import.meta.url)("./infer-trusted-node-preload.cjs");'+
      'const held=Object.freeze({host:{},installation:{},generation:{},supplier:connectInitialControlHostPreparation,moduleLifetime:import.meta});'+
      'return root.beginInitialControlInstallation(held,raw).then(scope=>({scope,held,input:root.readInitialControlInstallationInput(scope,held)}));}'+
      'export function assertInitialControlHostPreparation(){};'),
    'package.json': Buffer.from(JSON.stringify({name: '@actql/local-node', type: 'module',
      exports: {'.': './index.mjs', './selected-infer-startup': './selected-infer-startup.cjs'}})),
    'selected-infer-startup.cjs': readFileSync(new URL('../../packages/local-node/selected-infer-startup.cjs', import.meta.url)),
    'initial-control-public-dispatch.cjs': readFileSync(new URL('../../packages/local-node/initial-control-public-dispatch.cjs', import.meta.url))};
  for (const name of ['infer-trusted-node-preload.cjs', 'initial-control-installation-owner.cjs',
    'initial-control-package-custody.cjs', 'initial-control-image-source.cjs', 'initial-control-image-loader.cjs',
    'initial-control-phase-envelope.cjs', 'source-managed-phase-envelope.cjs', 'initial-control-host-input.mjs']) {
    sources['adapters/host-node/'+name] = actual(name);
  }
  const inventory = {...f.inventory, engine: {node: process.versions.node, v8: process.versions.v8,
    openssl: process.versions.openssl, platform: process.platform, arch: process.arch,
    eager: true, libraries: {...process.versions}},
    images: Object.entries(sources).map(([path, bytes]) => fact(path, bytes))};
  if (route === 'node') {
    const node = join(f.directory, 'node_modules/@actql/node');
    mkdirSync(node, {recursive: true});
    const originals = {'package.json': Buffer.from(JSON.stringify({name: '@actql/node',
      version: '1.0.0', type: 'module', exports: {'.': './index.mjs',
        './selected-infer-startup': './selected-infer-startup.cjs'}})),
    'selected-infer-startup.cjs': readFileSync(new URL('../../packages/node/selected-infer-startup.cjs', import.meta.url)),
    'initial-control-public-dispatch.cjs': readFileSync(new URL('../../packages/node/initial-control-public-dispatch.cjs', import.meta.url)),
    'index.mjs': Buffer.from('import{originalLocal}from"@actql/local-node";'+
      'import{createRequire}from"node:module";'+
      'globalThis.originalNodeDelivery=createRequire(import.meta.url)("./selected-infer-startup.cjs");'+
      'globalThis.originalNodeDispatch=createRequire(import.meta.url)("./initial-control-public-dispatch.cjs");'+
      'globalThis.actualPublicNodeValue=originalLocal;')};
    for (const [path, bytes] of Object.entries(originals)) writeFileSync(join(node, path), bytes);
    inventory.publicNode = {name: '@actql/node', version: '1.0.0',
      images: Object.entries(originals).map(([path, bytes]) => fact(path, bytes)),
      dependencies: [{name: '@actql/local-node', local: true}]};
    inventory.publicNodeCoverage = 'prepared';
  }
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
    // This selected eager recipe has a narrower runtime premise than the
    // ordinary Host. Other platforms must refuse before fixture compilation
    // or raw input observation, rather than claim successful eager admission.
    'if(process.version!=="v22.22.0"||process.platform!=="darwin"||process.arch!=="arm64"||process.versions.openssl!=="3.5.4"){',
    'for(const name of ["actualHostImageValue","originalDelivery","originalLocalDispatch","initialDispatchReads","initialDispatchCause","actualConsumerCalls","localPublicInitializations","originalNodeDelivery","originalNodeDispatch","actualPublicNodeValue"]){assert.equal(Object.hasOwn(globalThis,name),false,name);}',
    'const delivery=require("@actql/'+route+'/selected-infer-startup");',
    'assert.ok(Object.isFrozen(delivery));assert.equal(Object.getPrototypeOf(delivery),null);',
    'let reads=0;const raw=new Proxy({},{get(){reads++;throw new Error("RawInput");},ownKeys(){reads++;throw new Error("RawInput");}});',
    'assert.throws(()=>delivery.selectedInitialControlHostPreparation("open",raw),{code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.equal(reads,0);',
    'assert.equal(Object.hasOwn(globalThis,"actualHostImageValue"),false);',
    'assert.equal(Object.hasOwn(globalThis,"actualConsumerCalls"),false);',
    '}else{',
    'assert.equal(actualHostImageValue,"original");',
    'assert.equal(originalDelivery,require("@actql/local-node/selected-infer-startup"));',
    'assert.equal(Object.getPrototypeOf(originalDelivery),null);',
    'assert.equal(initialDispatchReads,0);assert.equal(initialDispatchCause,"NodeInitialControlAdmissionUnavailable");',
    'assert.ok(Object.isFrozen(originalLocalDispatch));',
    'assert.equal(typeof originalLocalDispatch.selectedInitialControlHostPreparation,"function");',
    ...(route === 'node' ? [
      'assert.equal(originalNodeDelivery,require("@actql/node/selected-infer-startup"));',
      'assert.equal(actualPublicNodeValue,"original-local-public");',
      'assert.equal(typeof originalNodeDispatch.selectedInitialControlHostPreparation,"function");',
    ] : []),
    'const rootFile=require.resolve('+JSON.stringify(join(local, 'adapters/host-node/infer-trusted-node-preload.cjs'))+');const root=require(rootFile);',
    'const view={};assert.equal(root.associateHost(view,{runtime:process,host:{},installation:{},generation:{},supplier(){}}),view);',
    'let reads=0;const raw=new Proxy({},{ownKeys(){reads++;throw new Error("RawInput");}});',
    'assert.throws(()=>root.beginInitialControlInstallation({},raw),{code:"NodeInitialControlOriginalChanged"});',
    'assert.throws(()=>root.connectInitialControlHostPreparation("open",raw),{code:"NodeInitialControlInputUnavailable"});',
    'assert.throws(()=>originalLocalDispatch.selectedInitialControlHostPreparation("open",raw),{code:"NodeInitialControlInputUnavailable"});',
    ...(route === 'node' ? ['assert.throws(()=>originalNodeDispatch.selectedInitialControlHostPreparation("open",raw),{code:"NodeInitialControlInputUnavailable"});'] : []),
    'assert.equal(actualConsumerCalls,0);',
    'assert.equal(root.connectInitialControlHostPreparation("connect",{mode:"remote"}),undefined);',
    'assert.equal(root.connectInitialControlHostPreparation("connect",{get mode(){throw new Error("UnselectedGetter");}}),undefined);',
    'assert.equal(root.connectInitialControlHostPreparation("connect",raw),undefined);',
    'const packet={mode:"local",installation:{directory:".actql"},profile:"mock"};',
    'assert.throws(()=>root.connectInitialControlHostPreparation("connect",{...packet,unknown:true}),{code:"NodeInitialControlInputUnavailable"});',
    'assert.throws(()=>root.connectInitialControlHostPreparation("connect",{...packet,installation:{directory:".actql",resolveSecret(){throw new Error("CallbackMustNotRun");}}}),{code:"NodeInitialControlInputUnavailable"});',
    'const pending=root.connectInitialControlHostPreparation("connect",packet);',
    'packet.profile="replacement";packet.installation.directory="replacement";',
    'const admitted=await pending;assert.equal(admitted.input.profile,"mock");assert.equal(admitted.input.installation.directory,".actql");',
    'assert.ok(Object.isFrozen(admitted.input));assert.ok(Object.isFrozen(admitted.input.installation));',
    'assert.equal(actualConsumerCalls,1);',
    'assert.equal((await admitted.scope.close()).pending,false);',
    'assert.equal(root.connectInitialControlHostPreparation("connect",{mode:"remote"}),undefined);',
    'assert.throws(()=>root.connectInitialControlHostPreparation("connect",{mode:"local",installation:{directory:".actql"},profile:"mock"}),{code:"NodeInitialControlInputUnavailable"});',
    'let fakeCalls=0;',
    'require.cache[require.resolve("@actql/'+route+'/selected-infer-startup")].exports={selectedInitialControlHostPreparation(){fakeCalls++;}};',
    'require.cache[rootFile].exports={connectInitialControlHostPreparation(){fakeCalls++;}};',
    'assert.throws(()=>originalLocalDispatch.selectedInitialControlHostPreparation("open",raw),{code:"InitialControlImageLoaderChanged"});',
    ...(route === 'node' ? ['assert.throws(()=>originalNodeDispatch.selectedInitialControlHostPreparation("open",raw),{code:"InitialControlImageLoaderChanged"});'] : []),
    'assert.equal(fakeCalls,0);',
    'assert.equal(reads,0);',
    'assert.equal(actualConsumerCalls,1);',
    '}',
  ].join('\n'));
  const result = spawnSync(process.execPath,
    ['--no-lazy', '--require', '@actql/'+route+'/selected-infer-startup', entry], {
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

test('an import uses the named dependency edge of its own captured package', t => {
  const f = fixture(t, [
    'import {readResource} from "fixture-owner";',
    'export {readResource};',
    'export const readUnselected = () => import("@fixture/resource/value");',
    'export function assertInitialControlHostPreparation(){};',
  ].join('\n'));
  function install(name: string, main: string, exports: string | Record<string, string>, dependencies = {}) {
    const directory = join(f.root, 'node_modules', name);
    mkdirSync(directory, {recursive: true});
    const files = {'package.json': Buffer.from(JSON.stringify({name, version: '1.0.0', exports, dependencies})),
      'index.mjs': Buffer.from(main)};
    for (const [path, bytes] of Object.entries(files)) writeFileSync(join(directory, path), bytes);
    return Object.entries(files).map(([path, bytes]) => fact(path, bytes));
  }
  const owner = install('fixture-owner', 'export const readResource = () => import("@fixture/resource/value");',
    './index.mjs', {'@fixture/resource': '1.0.0'});
  const resource = install('@fixture/resource', 'export const value = "declared-resource";',
    {'.': './index.mjs', './value': './index.mjs'});
  const result = f.run([
    'import assert from "node:assert/strict";',
    'assert.equal((await originalHostNamespace.readResource()).value,"declared-resource");',
    'await assert.rejects(originalHostNamespace.readUnselected(),{code:"UncapturedInitialControlDependency"});',
    'packageImageCustody.assertCurrent();',
  ].join('\n'), '', '', inventory => {
    inventory.dependencies = [{name:'fixture-owner', package:0}];
    inventory.packages = [{name:'fixture-owner', version:'1.0.0', images:owner,
      dependencies:[{name:'@fixture/resource', package:1}]},
    {name:'@fixture/resource', version:'1.0.0', images:resource, dependencies:[]}];
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

test('ordinary external adapters share only the exact installed dependency under their own locks', t => {
  const f = fixture(t);
  admitFixtureUndici(f).include(f.inventory);
  function install(name: string, sources: Record<string, string>) {
    const directory = join(f.directory, 'node_modules', name);
    mkdirSync(directory, {recursive: true});
    return Object.entries(sources).map(([path, source]) => {
      const bytes = Buffer.from(source);
      writeFileSync(join(directory, path), bytes);
      return fact(path, bytes);
    });
  }
  const sdkName = 'external-language-model';
  const sdk = install(sdkName, {
    'package.json': JSON.stringify({name: sdkName, version: '1.0.0', exports: './index.mjs'}),
    'index.mjs': 'export function build() {return "same physical SDK";}',
  });
  const selected = ['independent-adapter-one', 'independent-adapter-two', 'adapter-with-wrong-lock'].map((name, index) => {
    const images = install(name, {
      'package.json': JSON.stringify({name, version: '1.0.0', exports: './index.mjs',
        dependencies: {[sdkName]: '1.0.0'}}),
      'npm-shrinkwrap.json': JSON.stringify({lockfileVersion: 3, packages: {
        '': {name, version: '1.0.0'}, ['node_modules/' + sdkName]: {version: index === 2 ? '2.0.0' : '1.0.0'},
      }}),
      'index.mjs': 'import {build} from "external-language-model";' +
        'globalThis.externalAdapterStarts=(globalThis.externalAdapterStarts??0)+1; export const factory = build;',
    });
    const image = (source: ImageFact, packageName: string) => ({path: source.path, packageName,
      version: '1.0.0', cid: 'sha256:' + source.sha256});
    return {adapter: image(images[2], name), lock: image(images[1], name), sdk: image(sdk[1], sdkName),
      packageImages: [{name, version: '1.0.0', images, dependencies: [{name: sdkName, package: 1}]},
        {name: sdkName, version: '1.0.0', images: sdk, dependencies: []}]};
  });
  const entry = join(f.directory, 'ordinary-entry.mjs');
  writeFileSync(entry, [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const custody=createRequire(import.meta.url)(' + JSON.stringify(custody) + ');',
    'function freeze(value){if(value !== null && typeof value === "object"){for(const member of Object.values(value))freeze(member);Object.freeze(value);}return value;}',
    'const inventory=freeze(' + JSON.stringify(f.inventory) + ');',
    'const registrations=freeze(' + JSON.stringify(selected) + ');',
    'const bad=freeze({...registrations[0],lock:{...registrations[0].lock,cid:"sha256:"+"0".repeat(64)}});',
    'const open=choices=>custody.captureOrdinaryInitialControlPackageCustody(inventory,' + JSON.stringify(f.root) +
      ',process.argv[1],undefined,choices);',
    'assert.throws(()=>open([bad]),{code:"InvalidInstalledModelSdkInstallation"});',
    'assert.throws(()=>open([registrations[2]]),{code:"InvalidInstalledModelSdkInstallation"});',
    'assert.equal(globalThis.externalAdapterStarts,undefined);',
    'const selected=open(registrations.slice(0,2));',
    'assert.equal(globalThis.externalAdapterStarts,undefined);',
    'const a=custody.readVerifiedSdkImages(selected,registrations[0]);',
    'const b=custody.readVerifiedSdkImages(selected,registrations[1]);',
    'assert.equal(a.sdk,b.sdk);',
    'assert.equal(a.adapter.factory,b.adapter.factory);',
    'assert.notEqual(a.adapter,b.adapter);',
    'assert.equal(globalThis.externalAdapterStarts,2);',
    'assert.equal(a.sdk.build(),"same physical SDK");',
    'selected.initializeHostNamespace(); selected.assertCurrent();',
  ].join('\n'));
  const result = spawnSync(process.execPath, [entry], {cwd: f.directory, env: {PATH: process.env.PATH},
    encoding: 'utf8', timeout: 30000});
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
});

const sharedImageSource = 'exports.value="captured-local-shared";';
function selectPreparedOptionalSdk(inventory: FixtureInventory) {
  const image = (name: string, dependencies: Dependency[] = []): FixturePackage => {
    const manifest = Buffer.from(JSON.stringify({name, version: '1.0.0', main: './index.cjs'}));
    return {name, version: '1.0.0', images: [fact('package.json', manifest),
      fact('index.cjs', Buffer.from(sharedImageSource))], dependencies};
  };
  inventory.optionalSdk = 0;
  inventory.optionalSdkCoverage = 'prepared';
  inventory.packages = [image('@actql/provider-ai-sdk', [
    {name: '@fixture/sdk-only', package: 1}, {name: '@fixture/shared', package: 2},
  ]), image('@fixture/sdk-only'), image('@fixture/shared')];
}

test('ordinary Local uses its own shared image with a prepared but uninstalled SDK graph', t => {
  const f = fixture(t, 'import {value} from "@fixture/shared";globalThis.actualHostImageValue=value;' +
    'export function assertInitialControlHostPreparation(){};');
  const undici = admitFixtureUndici(f);
  const shared = join(f.directory, 'node_modules/@fixture/shared');
  mkdirSync(shared, {recursive: true});
  writeFileSync(join(shared, 'package.json'), JSON.stringify({name: '@fixture/shared', version: '1.0.0', main: './index.cjs'}));
  writeFileSync(join(shared, 'index.cjs'), sharedImageSource);
  const cid = 'sha256:' + fact('index.cjs', Buffer.from(sharedImageSource)).sha256;
  const code = [
    'import assert from "node:assert/strict";',
    'assert.equal(actualHostImageValue,"captured-local-shared");',
    'const foreign={packageName:"@fixture/shared",version:"1.0.0",path:"index.cjs",cid:' + JSON.stringify(cid) + '};',
    'assert.throws(()=>readVerifiedSdkImages(packageImageCustody,{adapter:foreign,sdk:foreign,lock:foreign}),' +
      '{code:"InitialControlSdkImageUnavailable"});',
    'packageImageCustody.assertCurrent();',
  ].join('\n');
  const graph = (selected: FixtureInventory) => {
    selectPreparedOptionalSdk(selected);
    selected.dependencies = [{name: '@fixture/shared', package: 2}];
    undici.include(selected);
  };
  const missing = f.run(code, '', '', graph, true, undefined, true);
  assert.equal(missing.status, 0, missing.stderr);
  // If either optional package is resolved, this physical package metadata
  // refuses immediately. The same Local original remains available.
  for (const name of ['@actql/provider-ai-sdk', '@fixture/sdk-only']) {
    const optional = join(f.directory, 'node_modules', name);
    mkdirSync(optional, {recursive: true});
    writeFileSync(join(optional, 'package.json'), '{');
  }
  const unusable = f.run(code, '', '', graph, true, undefined, true);
  assert.equal(unusable.status, 0, unusable.stderr);

  writeFileSync(join(shared, 'index.cjs'), sharedImageSource.replace('local', 'fake!'));
  const changed = f.run('throw Error("UnreachableConsumer");', '', '', graph, true, undefined, true);
  assert.notEqual(changed.status, 0);
  assert.match(changed.stderr, /code: 'InitialControlImageChanged'/u);
  assert.doesNotMatch(changed.stderr, /UnreachableConsumer/u);
});

test('ordinary Local refuses dangling or unowned optional SDK graph members without resolving a package', t => {
  const f = fixture(t);
  const undici = admitFixtureUndici(f);
  for (const mutate of [
    (data: FixtureInventory) => { data.packages[0].dependencies[0].package = 99; },
    (data: FixtureInventory) => { data.packages[0].dependencies[0].name = '@foreign/name'; },
    (data: FixtureInventory) => { data.packages.push({...data.packages[1], name: '@foreign/unreachable'}); },
  ]) {
    const result = f.run('throw Error("UnreachableConsumer");', '', '', inventory => {
      selectPreparedOptionalSdk(inventory);
      undici.include(inventory);
      mutate(inventory);
    }, true, undefined, true);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /InvalidInitialControlPackageImage/u);
    assert.doesNotMatch(result.stderr, /Cannot find module|UnreachableConsumer/u);
  }
});

test('ordinary Local seals the pinned Undici and both real llhttp original buffers before entry', t => {
  const f = fixture(t);
  const undici = admitFixtureUndici(f);
  const parserPaths = ['lib/llhttp/llhttp-wasm.js', 'lib/llhttp/llhttp_simd-wasm.js'];
  const body = [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const originalRequire = createRequire(import.meta.url);',
    'const loaded = originalRequire.cache[originalRequire.resolve("undici")];',
    'assert.equal(loaded?.loaded, true);',
    'assert.equal(typeof loaded.exports.Client, "function");',
    'const transport = originalRequire("@actql/local-node/_internal/model-http-transport");',
    'assert.equal(typeof transport.createOriginalUndiciFetch, "function");',
    'assert.equal(typeof transport.prepareOriginalUndiciFetch, "function");',
    'for (const path of ' + JSON.stringify(parserPaths) + ') {',
    '  const filename = originalRequire.resolve("undici/" + path);',
    '  const parser = originalRequire.cache[filename];',
    '  assert.equal(parser?.loaded, true);',
    '  assert.equal(Object.getOwnPropertyDescriptor(parser, "exports").writable, false);',
    '  assert.deepEqual([...parser.exports.subarray(0, 4)], [0, 97, 115, 109]);',
    '  assert.equal(originalRequire(filename), parser.exports);',
    '}',
    'packageImageCustody.assertCurrent();',
  ].join('\n');
  const accepted = f.run(body, '', '', undici.include, true, undefined, true);
  assert.equal(accepted.status, 0, accepted.stderr);
  for (const omitted of parserPaths) {
    const refused = f.run('throw Error("UnreachableConsumer");', '', '', inventory => {
      const index = undici.include(inventory);
      inventory.packages[index].images = inventory.packages[index].images.filter(image => image.path !== omitted);
    }, true, undefined, true);
    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, /code: 'InitialControlLocalTransportImageUnavailable'/u);
    assert.doesNotMatch(refused.stderr, /UnreachableConsumer/u);
  }
});

test('a selected ordinary SDK must use the same original Undici root as Local', t => {
  const f = fixture(t);
  const undici = admitFixtureUndici(f);
  const directory = join(f.directory, 'node_modules/@actql/provider-ai-sdk');
  mkdirSync(directory, {recursive: true});
  const adapterName = '@actql/provider-ai-sdk', sdkName = '@fixture/sdk';
  const sdkDirectory = join(f.directory, 'node_modules', sdkName);
  mkdirSync(sdkDirectory, {recursive: true});
  const files = {
    'package.json': JSON.stringify({name: adapterName, version: '1.0.0', type: 'module', main: './index.mjs',
      dependencies: {undici: '7.30.0', [sdkName]: '1.0.0'},
      peerDependencies: {'@actql/local-node': '1.0.0'}}),
    'index.mjs': 'export {}',
    'adapter.mjs': 'import {createRequire} from "node:module";const originalRequire=createRequire(import.meta.url);' +
      'export function original(){return originalRequire("@actql/local-node/_internal/model-http-transport");}',
    'npm-shrinkwrap.json': '{}',
  };
  const sdkFiles = {
    'package.json': JSON.stringify({name: sdkName, version: '1.0.0', type: 'module', main: './index.mjs'}),
    'index.mjs': 'export const sdkOriginal = true;',
  };
  function images(root: string, originals: Record<string, string>) {
    return Object.entries(originals).map(([path, bytes]) => {
      writeFileSync(join(root, path), bytes);
      return fact(path, Buffer.from(bytes));
    });
  }
  const adapterImages = images(directory, files), sdkImages = images(sdkDirectory, sdkFiles);
  const select = (packageName: string, original: ImageFact) => ({
    packageName, version: '1.0.0', path: original.path, cid: 'sha256:' + original.sha256,
  });
  const selection = [{adapter: select(adapterName, adapterImages[2]), sdk: select(sdkName, sdkImages[1]),
    lock: select(adapterName, adapterImages[3])}];
  const include = (inventory: FixtureInventory, separateRoot = false) => {
    let index = undici.include(inventory);
    if (separateRoot) index = inventory.packages.push({...inventory.packages[index]}) - 1;
    const sdkIndex = inventory.packages.push({name: sdkName, version: '1.0.0',
      images: sdkImages, dependencies: []}) - 1;
    inventory.optionalSdk = inventory.packages.push({name: adapterName, version: '1.0.0',
      images: adapterImages, dependencies: [{name: 'undici', package: index}, {name: sdkName, package: sdkIndex},
        {name: '@actql/local-node', local: true}]}) - 1;
    inventory.optionalSdkCoverage = 'prepared';
  };
  const readSdk = 'globalThis.sdkOriginal=readVerifiedSdkImages(packageImageCustody,' +
    JSON.stringify(selection[0]) + ');';
  const body = [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'assert.equal(sdkOriginal.sdk.sdkOriginal, true);',
    'assert.equal(sdkOriginal.adapter.original(), createRequire(import.meta.url)("@actql/local-node/_internal/model-http-transport"));',
    'packageImageCustody.assertCurrent();',
  ].join('\n');
  for (const duplicate of [false, true]) {
    const accepted = f.run(body, '', readSdk, inventory => include(inventory, duplicate),
      true, undefined, true, selection);
    assert.equal(accepted.status, 0, accepted.stderr);
  }
  for (const changed of [
    (original: FixturePackage) => {original.images[0]!.sha256 = '0'.repeat(64);},
    (original: FixturePackage) => {original.version = '7.30.1';},
    (original: FixturePackage) => {original.dependencies.push({name: '@fixture/foreign', package: 0});},
  ]) {
    const unauthorized = f.run('throw Error("UnreachableConsumer");', '', '', inventory => {
      include(inventory, true);
      const binding = inventory.packages[inventory.optionalSdk!]?.dependencies.find(edge => edge.name === 'undici');
      assert(typeof binding?.package === 'number');
      const alias = binding.package, original = inventory.packages[alias];
      assert(original);
      const replacement = {...original, images: structuredClone(original.images), dependencies: [...original.dependencies]};
      changed(replacement);
      inventory.packages[alias] = replacement;
    }, true, undefined, true, selection);
    assert.notEqual(unauthorized.status, 0);
    assert.match(unauthorized.stderr, /code: 'InitialControlPackageImageChanged'/u);
    assert.doesNotMatch(unauthorized.stderr, /UnreachableConsumer/u);
  }
  mkdirSync(join(directory, 'node_modules'), {recursive: true});
  cpSync(undici.original, join(directory, 'node_modules/undici'), {recursive: true});
  const refused = f.run('throw Error("UnreachableConsumer");', '', '', inventory => include(inventory, true),
    true, undefined, true, selection);
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /code: 'InvalidInstalledModelSdkInstallation'/u);
  assert.doesNotMatch(refused.stderr, /UnreachableConsumer/u);
});

test('an ordinary released package alias retains both manifest variants and the same physical dependencies', t => {
  const f = fixture(t);
  const undici = admitFixtureUndici(f).include(f.inventory);
  const module = Buffer.from('export const original=true;');
  const releaseVersion = '1.0.1', version = '1.0.0';
  const manifest = (name: string, dependencies: Record<string, string>) =>
    ({name, type: 'module', exports: './index.mjs', version, dependencies});
  const bytes = (value: unknown) => Buffer.from(JSON.stringify(value));
  const existingLocal = JSON.parse(readFileSync(join(f.root, 'package.json'), 'utf8'));
  const localManifest = {...existingLocal, version,
    dependencies: {...existingLocal.dependencies, '@fixture/left': releaseVersion, '@fixture/right': releaseVersion}};
  const publishedLocal = bytes({...localManifest, version: releaseVersion});
  f.inventory.localReleaseVersion = releaseVersion;
  f.inventory.images = f.inventory.images.map(item => item.path === 'package.json'
    ? {...fact('package.json', bytes(localManifest)), npmRelease: releaseFact(releaseVersion, publishedLocal)} : item);
  writeFileSync(join(f.root, 'package.json'), publishedLocal);

  function add(name: string, deps: Dependency[], dependencies: Record<string, string>) {
    const directory = join(f.directory, 'node_modules', name);
    mkdirSync(directory, {recursive: true});
    const declared = manifest(name, dependencies), released = bytes({...declared, version: releaseVersion});
    writeFileSync(join(directory, 'package.json'), released);
    writeFileSync(join(directory, 'index.mjs'), module);
    return f.inventory.packages.push({name, version, releaseVersion, dependencies: deps,
      images: [{...fact('package.json', bytes(declared)), npmRelease: releaseFact(releaseVersion, released)},
        fact('index.mjs', module)]}) - 1;
  }
  const name = '@fixture/shared';
  const original = add(name, [{name: 'undici', package: undici}], {'undici': '7.30.0'});
  const alias = f.inventory.packages.push(structuredClone(f.inventory.packages[original]!)) - 1;
  for (const [nameOfParent, selected] of [['@fixture/left', original], ['@fixture/right', alias]] as const) {
    const index = add(nameOfParent, [{name, package: selected}], {[name]: releaseVersion});
    f.inventory.dependencies.push({name: nameOfParent, package: index});
  }

  const accepted = f.run('packageImageCustody.assertCurrent();', '', '', undefined, true, undefined, true);
  assert.equal(accepted.status, 0, accepted.stderr);
  for (const changed of [
    (record: FixturePackage) => {record.images[0]!.npmRelease!.sha256 = 'f'.repeat(64);},
    (record: FixturePackage) => {record.releaseVersion = '1.0.2';},
    (record: FixturePackage) => {record.dependencies[0]!.name = '@fixture/unselected';},
  ]) {
    const refused = f.run('throw Error("UnreachableConsumer");', '', '',
      inventory => changed(inventory.packages[alias]!), true, undefined, true);
    assert.notEqual(refused.status, 0);
    assert.match(refused.stderr, /code: 'InitialControlPackageImageChanged'/u);
    assert.doesNotMatch(refused.stderr, /UnreachableConsumer/u);
  }
});

test('the public Local factory enters the selected direct Chat module after the package seal', t => {
  const f = fixture(t, 'export function assertInitialControlHostPreparation(){};' +
    'export function connectEmbeddedLocal(){};export function publishInstalledEffect(){};export function publishInstalledSource(){};');
  const original = admitFixtureUndici(f);
  const index = readFileSync(new URL('../../packages/local-node/index.mjs', import.meta.url));
  const connectors = 'adapters/host-node/installed-connectors.mjs';
  const connectorsSource = Buffer.from('export function createInstalledConnectorTable(){}');
  writeFileSync(join(f.root, 'index.mjs'), index);
  writeFileSync(join(f.root, connectors), connectorsSource);
  const sdk = join(f.directory, 'node_modules/@actql/sdk');
  mkdirSync(sdk, {recursive:true});
  const sdkManifest = Buffer.from(JSON.stringify({name:'@actql/sdk',version:'1.0.0',type:'module',main:'./index.mjs'}));
  const sdkIndex = Buffer.from('export class ClientError extends Error {}');
  writeFileSync(join(sdk, 'package.json'), sdkManifest);
  writeFileSync(join(sdk, 'index.mjs'), sdkIndex);
  const result = f.run([
    'import assert from "node:assert/strict";',
    'import {createHttpChatProvider} from "@actql/local-node";',
    'const configure=createHttpChatProvider({});',
    'const cause=Error("SelectedOriginalHostContext");let calls=0;',
    'const context={prepareConfiguration(){calls++;throw cause;}};',
    'await assert.rejects(configure({},context), actual=>actual===cause);',
    'await assert.rejects(configure({},context), {code:"InstalledHttpChatProviderConfigurationReused"});',
    'assert.equal(calls,1);packageImageCustody.assertCurrent();',
  ].join('\n'), '', '', inventory => {
    original.include(inventory);
    inventory.images = inventory.images.map(image => image.path === 'index.mjs' ? fact('index.mjs', index) : image);
    inventory.images.push(fact(connectors, connectorsSource));
    const binding = inventory.packages.push({name:'@actql/sdk',version:'1.0.0',dependencies:[],
      images:[fact('package.json', sdkManifest),fact('index.mjs', sdkIndex)]}) - 1;
    inventory.dependencies.push({name:'@actql/sdk',package:binding});
  }, true, undefined, true);
  assert.equal(result.status, 0, result.stderr);
});
