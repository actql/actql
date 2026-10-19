import assert from 'node:assert/strict';
import {cpSync, lstatSync, mkdirSync, readdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {localModuleGraphInputs} from '../../scripts/adapter-module-graph.mjs';
import {initialControlPackageOriginal, renderInitialControlPackageOriginal}
  from '../../scripts/initial-control-package-images.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const entries = ['adapters/host-node/client-request-journal.mjs',
  'adapters/store-local/publication-store.mjs', 'adapters/host-node/host-root-format.mjs',
  'adapters/host-node/node-host-journal-installation.mjs',
  'adapters/host-node/node-public-initial-control-bootstrap.cjs',
  'adapters/host-node/node-initial-control-installation.mjs',
  'adapters/host-node/initial-control-host-input.mjs'];
const closure = localModuleGraphInputs(repository, entries);
const nativeRoot = process.env.ACTQL_DIRECTORY_NATIVE_DIAGNOSTIC_ROOT;

async function fixture(label, {replaceBeforeJournalCapture} = {}) {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-journal-ordinary-service-', label});
  const root = join(scratch.path, 'node_modules/@actql/local-node');
  const hostRoot = join(scratch.path, 'host');
  const sources = new Map(closure.map(path => [path, readFileSync(join(repository, path))]));
  // The actual SDK/Wire sources keep their own package scopes (# imports).
  // Their installed copies are also captured by the normal inventory writer.
  for (const name of ['sdk', 'client-wire']) {
    const source = join(repository, 'packages', name);
    const manifest = JSON.parse(readFileSync(join(source, 'package.json'), 'utf8'));
    const destination = join(scratch.path, 'node_modules/@actql', name);
    mkdirSync(destination, {recursive: true});
    mkdirSync(join(root, 'packages', name), {recursive: true});
    const retain = path => {
      const selected = join(source, path);
      const info = lstatSync(selected);
      assert.equal(info.isSymbolicLink(), false);
      if (info.isDirectory()) {
        for (const child of readdirSync(selected)) retain(join(path, child));
      } else {
        assert.equal(info.isFile(), true);
        sources.set(join('packages', name, path), readFileSync(selected));
      }
    };
    for (const path of ['package.json', ...manifest.files]) {
      retain(path);
      cpSync(join(source, path), join(destination, path), {recursive: true});
      cpSync(join(source, path), join(root, 'packages', name, path), {recursive: true});
    }
  }
  sources.set('package.json', Buffer.from(JSON.stringify({name: '@actql/local-node',
    version: '1.0.0', type: 'module', dependencies: {
      '@actql/sdk': '0.0.0-development', '@actql/client-wire': '0.0.0-development'},
    exports: {'.': './index.mjs',
      './_internal/initial-control-public-dispatch': './initial-control-public-dispatch.cjs'},
    files: ['index.mjs', 'initial-control-public-dispatch.cjs', 'adapters', 'packages']})));
  sources.set('index.mjs', Buffer.from('import delivery from "./initial-control-public-dispatch.cjs";'+
    'export function connect(raw){return delivery.selectedInitialControlHostPreparation("connect",raw);}'));
  sources.set('initial-control-public-dispatch.cjs',
    readFileSync(join(repository, 'packages/local-node/initial-control-public-dispatch.cjs')));
  // Controlled Host candidate/subject only. All prefix, private adapter,
  // Journal, SQLite, Store exclusion and native directory bodies are actual.
  // This is deliberately not the complete embedded Host/Common or N0 fixture.
  sources.set('adapters/host-node/embedded-local.mjs', Buffer.from(`
    ${replaceBeforeJournalCapture === undefined ? '' : "import './fixture-journal-native-replacement.mjs';"}
    import {join} from 'node:path';
    import {beginInitialControlInstallation} from './node-initial-control-installation.mjs';
    import {prepareHostJournalInstallation} from './node-host-journal-installation.mjs';
    export {snapshotInitialControlHostInput as readInitialControlHostInput} from './initial-control-host-input.mjs';
    export {openClientRequestJournal as openOriginalHostRequestJournal,
      observeOriginalClientRequestJournalCustody as observeOriginalHostRequestJournalCustody,
      assertOriginalClientRequestJournalFacilityCurrent as assertOriginalHostRequestJournalFacilityCurrent}
      from './client-request-journal.mjs';
    export {prepareLocalPublicationStoreOwnership as prepareOriginalHostPublicationOwnership,
      assertOriginalPreparedLocalPublicationStoreOwnership as assertOriginalHostPublicationOwnershipCurrent,
      closePreparedLocalPublicationStoreOwnership as closeOriginalHostPublicationOwnership}
      from '../store-local/publication-store.mjs';
    export {admitHostRootFormat as admitOriginalHostRootFormat} from './host-root-format.mjs';
    const root=${JSON.stringify(hostRoot)}; let originals;
    export function assertInitialControlHostPreparation(value) {
      if(!originals||['host','installation','generation','supplier','moduleLifetime']
        .some(name=>value[name]!==originals[name]))throw new Error('ForeignControlledHostOriginal');
    }
    export function readHostJournalPreparation(value) {
      assertInitialControlHostPreparation(value);
      return Object.freeze({root,principalId:'controlled Host original',journalDirectory:join(root,'requests'),
        assertCurrent(){assertInitialControlHostPreparation(value);}});
    }
    export async function connectInitialControlHostPreparation(kind,raw) {
      originals=Object.freeze({host:{},installation:{},generation:{},
        supplier:connectInitialControlHostPreparation,moduleLifetime:import.meta});
      const scope=await beginInitialControlInstallation(originals,raw);
      return Object.freeze({scope,root,originals,prepareJournal(){return prepareHostJournalInstallation(originals);}});
    }
  `));
  if (replaceBeforeJournalCapture !== undefined) {
    assert.ok(['prepare', 'iterate'].includes(replaceBeforeJournalCapture));
    sources.set('adapters/host-node/fixture-journal-native-replacement.mjs', Buffer.from(`
      import {DatabaseSync, StatementSync} from 'node:sqlite';
      const prototype = ${replaceBeforeJournalCapture === 'prepare' ? 'DatabaseSync' : 'StatementSync'}.prototype;
      const name = ${JSON.stringify(replaceBeforeJournalCapture)};
      prototype[name] = function () { throw new Error('ReplacedNativeMustNotRun'); };
    `));
  }
  for (const [path, bytes] of sources) {
    mkdirSync(dirname(join(root, path)), {recursive: true});
    writeFileSync(join(root, path), bytes);
  }
  assert.equal(typeof nativeRoot, 'string', 'a matching retained native package is required');
  const nativePaths = ['_build/native/directory-darwin-arm64.node', '_build/native/directory-original.json'];
  const nativeOutputs = new Map(nativePaths.map(path => [path, readFileSync(join(nativeRoot, path))]));
  for (const [path, bytes] of nativeOutputs) {
    mkdirSync(dirname(join(root, path)), {recursive: true});
    writeFileSync(join(root, path), bytes);
  }
  const inventory = renderInitialControlPackageOriginal({root: scratch.path, destination: root,
    inputs: {runtimeFiles: []}, outputs: sources, nativeOutputs});
  writeFileSync(join(root, initialControlPackageOriginal), inventory);
  return {scratch, root, run(body) {
    const entry = join(scratch.path, 'entry.mjs');
    writeFileSync(entry, body);
    const result = spawnSync(process.execPath, [entry], {cwd: scratch.path,
      env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 30000});
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr + result.stdout);
    return result;
  }};
}

test('actual ordinary prefix issues its one original Journal for the same controlled Host', async () => {
  const f = await fixture('ordinary prefix actual Journal service original');
  f.run(`
    import assert from 'node:assert/strict'; import {join} from 'node:path';
    import {createRequire} from 'node:module'; const require=createRequire(import.meta.url);
    const {connect}=await import('@actql/local-node');
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const owner=require(${JSON.stringify(join(f.root, 'adapters/host-node/node-public-initial-control-bootstrap.cjs'))});
    assert.throws(()=>owner.prepareHostJournalInstallation({...client.originals,generation:{}}));
    const duty=await client.prepareJournal();
    assert.equal(await duty.admitRootFormat(client.root),'new');
    const journal=await duty.openRequestJournal(join(client.root,'requests'),{});
    journal.observationStorage();
    assert.throws(()=>owner.prepareHostJournalInstallation(client.originals));
    const closed=await duty.close(); assert.equal(closed.pending,false);
    assert.equal(closed.physicalBackingReleased,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('ordinary Journal service detects a replaced original and restoration cannot revive it', async () => {
  const f = await fixture('ordinary Journal service captured temporary-directory original');
  f.run(`
    import assert from 'node:assert/strict'; import {existsSync} from 'node:fs';
    import {createRequire} from 'node:module'; const require=createRequire(import.meta.url);
    const {connect}=await import('@actql/local-node');
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const os=require('node:os'), original=os.tmpdir; let called=0;
    os.tmpdir=()=>{called++;return '/replacement-must-not-run';};
    try{await assert.rejects(client.prepareJournal(),{code:'HostJournalPreparationUnavailable'});}
    finally{os.tmpdir=original;}
    await assert.rejects(client.prepareJournal(),{code:'HostJournalPreparationUnavailable'});
    assert.equal(called,0); assert.equal(existsSync(client.root),false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('pre-namespace SQLite method originals cannot be replaced by the later namespace baseline', async () => {
  for (const replaceBeforeJournalCapture of ['prepare', 'iterate']) {
    const f = await fixture('ordinary Journal pre-namespace SQLite operation original',
      {replaceBeforeJournalCapture});
    f.run(`
      import assert from 'node:assert/strict'; import {DatabaseSync, StatementSync} from 'node:sqlite';
      import {existsSync} from 'node:fs';
      const receiver=${replaceBeforeJournalCapture === 'prepare' ? 'DatabaseSync' : 'StatementSync'}.prototype;
      const name=${JSON.stringify(replaceBeforeJournalCapture)}, original=receiver[name];
      const {connect}=await import('@actql/local-node');
      try {
        await assert.rejects(async()=>connect({mode:'local',installation:{directory:'.actql'},profile:'mock'}),
          {code:'HostJournalPreparationUnavailable'});
        assert.equal(existsSync(${JSON.stringify(join(f.scratch.path, 'host'))}),false);
      } finally {receiver[name]=original;}
      await assert.rejects(async()=>connect({mode:'local',installation:{directory:'.actql'},profile:'mock'}),
        {code:'HostJournalPreparationUnavailable'});
    `);
    f.scratch.passed();
  }
});
