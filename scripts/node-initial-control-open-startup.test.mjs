// Actual public facade, SDK, private dispatch and selected preload Sources.
// The small Host namespace below is an explicit compilation fixture: this
// proves original delivery/refusal, not operational coverage or Host opening.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const fact = (path, bytes) => ({path, bytes: bytes.length,
  sha256: createHash('sha256').update(bytes).digest('hex')});
const put = (root, path, bytes) => {
  mkdirSync(dirname(join(root, path)), {recursive: true});
  writeFileSync(join(root, path), bytes);
};

function originalPackage(name, destination) {
  const source = join(root, 'packages', name);
  const manifest = JSON.parse(readFileSync(join(source, 'package.json')));
  const files = new Map([['package.json', readFileSync(join(source, 'package.json'))]]);
  function visit(path) {
    if (path.endsWith('/')) {
      for (const entry of readdirSync(join(source, path), {withFileTypes: true})) {
        visit(path + entry.name + (entry.isDirectory() ? '/' : ''));
      }
    } else if (/\.(?:[cm]?js|json)$/u.test(path)) files.set(path, readFileSync(join(source, path)));
  }
  for (const file of manifest.files) visit(file);
  for (const [file, bytes] of files) {
    put(destination, file, bytes);
    assert.deepEqual(readFileSync(join(destination, file)), bytes);
  }
  return {name: manifest.name, version: manifest.version,
    images: [...files].map(([file, bytes]) => fact(file, bytes))};
}

async function installation() {
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'node-original-open-startup-', label: 'public selected startup original delivery'});
  const packages = join(scratch.path, 'node_modules/@actql');
  const node = join(packages, 'node'), local = join(packages, 'local-node');
  const nodeOriginal = originalPackage('node', node);
  const sdk = originalPackage('sdk', join(packages, 'sdk'));
  const wire = originalPackage('client-wire', join(packages, 'client-wire'));
  const localSources = new Map([
    ['package.json', Buffer.from(JSON.stringify({name: '@actql/local-node',
      version: nodeOriginal.version, type: 'module', exports: {'.': './index.mjs',
        './selected-infer-startup': './selected-infer-startup.cjs'}}))],
    ['index.mjs', Buffer.from('globalThis.localInitializations=(globalThis.localInitializations??0)+1;' +
      'export function connect(){globalThis.localConnects++;throw new Error("LocalFallbackMustNotRun");}')],
    ['adapters/host-node/embedded-local.mjs', Buffer.from(
      'globalThis.hostInitializations=(globalThis.hostInitializations??0)+1;' +
      'globalThis.hostConsumerCalls=0;globalThis.localConnects=0;' +
      'export function assertInitialControlHostPreparation(){};' +
      'export function connectInitialControlHostPreparation(){hostConsumerCalls++;throw new Error("UnfundedHostMustNotRun");}')],
    ['spec/local-check-environment.json', Buffer.from('{"fixture":"not-an-admission"}\n')],
  ]);
  for (const file of ['selected-infer-startup.cjs', 'initial-control-public-dispatch.cjs']) {
    localSources.set(file, readFileSync(join(root, 'packages/local-node', file)));
  }
  for (const file of ['infer-trusted-node-preload.cjs', 'initial-control-installation-owner.cjs',
    'initial-control-package-custody.cjs', 'initial-control-image-source.cjs', 'initial-control-image-loader.cjs']) {
    localSources.set('adapters/host-node/' + file, readFileSync(join(root, 'adapters/host-node', file)));
  }
  const inventory = {images: [...localSources].map(([file, bytes]) => fact(file, bytes)),
    packages: [{...sdk, dependencies: [{name: '@actql/client-wire', package: 1}]}, {...wire, dependencies: []}],
    dependencies: [], optionalSdk: null, optionalSdkCoverage: 'absent',
    publicNode: {...nodeOriginal, dependencies: [{name: '@actql/local-node', local: true}, {name: '@actql/sdk', package: 0}]},
    publicNodeCoverage: 'prepared', localPublicModule: 'index.mjs',
    hostModule: 'adapters/host-node/embedded-local.mjs', hostValidator: 'assertInitialControlHostPreparation'};
  localSources.set('adapters/host-node/initial-control-package-original.cjs',
    Buffer.from('module.exports=Object.freeze({imageInventory:' + JSON.stringify(inventory) + '});'));
  for (const [file, bytes] of localSources) put(local, file, bytes);
  return {scratch, node, local};
}

for (const flags of [[], ['--no-lazy']]) {
  test('actual public open retains the selected unavailable original before raw observation (' + flags.length + ')', async () => {
    const f = await installation(), entry = join(f.scratch.path, 'entry.mjs');
    writeFileSync(entry, `
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {open} from '@actql/node';
const require=createRequire(import.meta.url);
const table=require(${JSON.stringify(join(f.node, 'initial-control-public-dispatch.cjs'))});
assert.equal(typeof table.selectedInitialControlHostPreparation,'function');
assert.equal(Object.isFrozen(table),true);
let reads=0;
const raw=new Proxy({}, {get(){reads++;throw new Error('RawGet');},
 ownKeys(){reads++;throw new Error('RawKeys');},getPrototypeOf(){reads++;throw new Error('RawPrototype');},
 getOwnPropertyDescriptor(){reads++;throw new Error('RawDescriptor');}});
await assert.rejects(open(),{code:'NodeInitialControlAdmissionUnavailable'});
await assert.rejects(open(raw),{code:'NodeInitialControlAdmissionUnavailable'});
assert.equal(reads,0);assert.equal(hostInitializations,1);assert.equal(localInitializations,1);
assert.equal(hostConsumerCalls,0);assert.equal(localConnects,0);
let replacements=0;
for(const path of [require.resolve('@actql/node/selected-infer-startup'),
 ${JSON.stringify(join(f.node, 'initial-control-public-dispatch.cjs'))},
 ${JSON.stringify(join(f.local, 'selected-infer-startup.cjs'))},
 ${JSON.stringify(join(f.local, 'adapters/host-node/infer-trusted-node-preload.cjs'))}]){
 require.cache[path].exports={selectedInitialControlHostPreparation(){replacements++;return{};},
  connectInitialControlHostPreparation(){replacements++;return{};}};
}
await assert.rejects(open(raw),{code:'NodeInitialControlAdmissionUnavailable'});
assert.equal(reads,0);assert.equal(replacements,0);assert.equal(hostConsumerCalls,0);assert.equal(localConnects,0);
console.log('same original selected refusal; raw observations0; replacement dispatch0');
`);
    const child = spawnSync(process.execPath, [...flags, '--require', '@actql/node/selected-infer-startup', entry],
      {cwd: f.scratch.path, env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024});
    assert.equal(child.error, undefined); assert.equal(child.signal, null);
    assert.equal(child.status, 0, child.stderr);
    assert.match(child.stdout, /same original selected refusal; raw observations0; replacement dispatch0/u);
    f.scratch.passed();
  });
}
