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
  'adapters/host-node/node-host-result-installation.mjs',
  'adapters/host-node/node-source-managed-installation.mjs',
  'adapters/host-node/source-managed-original-input.mjs',
  'adapters/host-node/node-public-initial-control-bootstrap.cjs',
  'adapters/host-node/node-initial-control-installation.mjs',
  'adapters/host-node/initial-control-host-input.mjs'];
const closure = localModuleGraphInputs(repository, entries);
const nativeRoot = process.env.ACTQL_DIRECTORY_NATIVE_DIAGNOSTIC_ROOT;

async function fixture(label, {replaceBeforeJournalCapture, managedCompute = false,
  resultPublication = false, localMockModel = false} = {}) {
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
    ${!resultPublication ? '' : `
    import {prepareHostResultPublicationInstallation} from './node-host-result-installation.mjs';
    const resultRuntime=Object.freeze({controlled:true});
    const resultControl=Object.freeze(Object.fromEntries(['admit','recordTransition','deliveryTransition',
      'deliverySuccessValid','trustedClockNotBefore','recordAllowsCommit','effectFreeCommitValid']
      .map(name=>[name,()=>{throw new Error(name+' unused');}])));
    export {openLocalPublicationStore as openOriginalHostPublicationStore,
      assertOriginalLocalPublicationStoreFacilityCurrent as assertOriginalHostPublicationStoreFacilityCurrent}
      from '../store-local/publication-store.mjs';
    export function readHostResultPublicationPreparation(value) {
      const journal=readHostJournalPreparation(value);
      return Object.freeze({runtime:resultRuntime,control:resultControl,root:journal.root,
        principalId:journal.principalId,storeAuthorityCid:'sha256:'+'a'.repeat(64)});
    }
    export function readHostResultPublicationRunRequirements(value, prepared) {
      assertInitialControlHostPreparation(value);
      originalSourceManagedHostRequest(value,prepared);
      return Object.freeze({resultCount:1,maxRows:1});
    }
    `}
    ${!managedCompute ? '' : `
    import {prepareManagedComputeInstallation, assertManagedComputePreparationCurrent,
      assertManagedComputeInstallationCurrent, assertSourceManagedInstallationCurrent}
      from './node-source-managed-installation.mjs';
    export {readSourceManagedOriginalInput} from './source-managed-original-input.mjs';
    export {assertInitialControlHostPreparation as assertSourceManagedHostPreparation};
    const preparedRequests = new WeakMap();
    export function originalSourceManagedHostRequest(value, prepared) {
      assertInitialControlHostPreparation(value);
      const request=preparedRequests.get(prepared);
      if(request===undefined)throw new Error('ForeignControlledPreparedRequest');
      return request;
    }
    export function readManagedComputeRunRequirements(value, prepared) {
      originalSourceManagedHostRequest(value,prepared);
      return Object.freeze({planningWork:100000,attempts:1,holdings:1,
        transferBytes:1000000n,retainedBytes:200000000n,executionBytes:536870912n});
    }
    export function managedComputeSubmittedIntentCid(value, original, body) {
      assertInitialControlHostPreparation(value);
      assertManagedComputePreparationCurrent(original,value);
      return 'sha256:'+'a'.repeat(64);
    }
    `}
    ${!localMockModel ? '' : `
    let modelCandidate;
    export function readHostLocalMockModelRunRequirements(value, prepared, candidate, recipe) {
      originalSourceManagedHostRequest(value,prepared);
      if(candidate!==modelCandidate||recipe.kind!=='selected-node-local-original-mock-model-service')
        throw new Error('ForeignControlledModelCandidate');
      return Object.freeze({planningWork:100000,attempts:3,holdings:3,
        transferBytes:1000000n,retainedBytes:252808192n,executionBytes:536870912n});
    }
    export function assertHostLocalMockModelRunCurrent(value,prepared,candidate) {
      originalSourceManagedHostRequest(value,prepared);
      if(candidate!==modelCandidate)throw new Error('ForeignControlledModelCandidate');
    }
    `}
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
      originals=Object.freeze({host:{},installation:{${!resultPublication ? '' : 'projectRuntime:resultRuntime'}},generation:{},
        supplier:connectInitialControlHostPreparation,moduleLifetime:import.meta});
      const scope=await beginInitialControlInstallation(originals,raw);
      return Object.freeze({scope,root,originals,prepareJournal(){return prepareHostJournalInstallation(originals);}
        ${!resultPublication ? '' : ',resultControl,prepareResult(){return prepareHostResultPublicationInstallation(originals);}'}
        ${!managedCompute ? '' : `,
        prepareCompute(){return prepareManagedComputeInstallation(originals);},
        assertCompute(view){assertManagedComputeInstallationCurrent(view,originals);},
        assertSource(view){assertSourceManagedInstallationCurrent(view,originals);},
        bindPrepared(prepared,request){preparedRequests.set(prepared,request);}`}
        ${!localMockModel ? '' : ',bindModelCandidate(candidate){modelCandidate=candidate;}'}
      });
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

test('ordinary Journal service cleanup retains original native close after current refusal', async () => {
  const f = await fixture('ordinary Journal actual service retirement and original close');
  f.run(`
    import assert from 'node:assert/strict'; import {join} from 'node:path';
    import {DatabaseSync} from 'node:sqlite';
    import {connect} from '@actql/local-node';
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const duty=await client.prepareJournal(); await duty.admitRootFormat(client.root);
    const journal=await duty.openRequestJournal(join(client.root,'requests'),{});
    journal.observationStorage();
    const original=DatabaseSync.prototype.close; let replacementCalls=0;
    DatabaseSync.prototype.close=function(){replacementCalls++;throw new Error('ReplacementClose');};
    try {
      assert.throws(()=>duty.assertCurrent(),{code:'HostJournalPreparationUnavailable'});
      const closed=await duty.close();
      assert.equal(closed.pending,false);
      assert.equal(closed.physicalBackingReleased,false);
      assert.equal(replacementCalls,0);
    } finally {DatabaseSync.prototype.close=original;}
    assert.throws(()=>duty.assertCurrent(),{code:'HostJournalPreparationUnavailable'});
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('ordinary Journal cold reopening uses fresh startup custody for the same saved test state', async () => {
  const f = await fixture('ordinary Journal actual service fresh-process cold reopen');
  const openAndClose = expected => `
    import assert from 'node:assert/strict'; import {join} from 'node:path';
    import {connect} from '@actql/local-node';
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const duty=await client.prepareJournal();
    assert.equal(await duty.admitRootFormat(client.root),${JSON.stringify(expected)});
    const journal=await duty.openRequestJournal(join(client.root,'requests'),{});
    journal.observationStorage();
    assert.equal((await duty.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `;
  // Both children operate only on this newly created test's own state. No
  // historical Run/DB/key is restored, repaired or replayed between processes.
  f.run(openAndClose('new'));
  f.run(openAndClose('current'));
  f.scratch.passed();
});

// Actual selected prefix/private adapter, but controlled request lineage and
// explicit unaccounted quota/intent fixtures. No Resource Ledger is started,
// no Common execution is claimed, and no Source or business I/O is acquired.
test('source-free Compute original precedes SDK snapshot and cannot issue Source children', async () => {
  const f = await fixture('ordinary prefix separate source-free Compute original', {managedCompute: true});
  f.run(`
    import assert from 'node:assert/strict'; import {createRequire} from 'node:module';
    import {connect} from '@actql/local-node'; const require=createRequire(import.meta.url);
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const root=require(${JSON.stringify(join(f.root, 'adapters/host-node/node-public-initial-control-bootstrap.cjs'))});
    await assert.rejects(()=>client.prepareCompute());
    const journalDuty=await client.prepareJournal();
    await journalDuty.admitRootFormat(client.root);
    await journalDuty.openRequestJournal(client.root+'/requests',{});
    const compute=await client.prepareCompute();
    client.assertCompute(compute);
    assert.throws(()=>client.assertSource(compute));
    const receipt=compute.beforeSourceSnapshot('aql','SELECT 1',{format:'sql',parameters:null});
    const body=Object.freeze({kind:'aql',input:Object.freeze({text:'SELECT 1',format:'sql'}),parameters:null});
    compute.bindSourceSnapshot(receipt,body);
    const request=Object.freeze({originalPendingRequest:true});
    compute.bindSourceRequest(receipt,body,request);
    assert.equal(compute.intentCid(receipt,body),'sha256:'+'a'.repeat(64));
    const prepared=Object.freeze({controlledCheckedPrepared:true});
    client.bindPrepared(prepared,request);
    const original=compute.prepareRun(prepared);
    assert.equal(root.prepareOriginalManagedRunPorts(original,{}),null);
    const ports=root.prepareOriginalManagedRunPorts(original,prepared);
    assert.equal(ports.limit(0),100000n);
    assert.equal(ports.limit(3),1000000n);
    assert.equal(root.prepareOriginalSourceChildPorts(original,prepared),null);
    assert.throws(()=>compute.prepareRead(prepared,{},original));
    compute.finishSourceProducer(receipt,'returned');
    assert.equal((await compute.close()).pending,false);
    assert.notEqual(ports.status(0),0);
    assert.throws(()=>root.prepareManagedComputeInstallation(client.originals));
    assert.equal((await journalDuty.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

// Actual prefix/SQLite/native custody with a controlled semantic Host. These
// private-port cases do not execute Common Model code, issue permission, or
// establish installed INFER/co-phase supply for the full embedded Host.
test('separate local Mock service binds one same-Host request without converting Compute ports', async () => {
  const f = await fixture('same original separate local Mock service',
    {managedCompute: true, localMockModel: true});
  f.run(`
    import assert from 'node:assert/strict'; import {createRequire} from 'node:module';
    import {connect} from '@actql/local-node'; const require=createRequire(import.meta.url);
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const root=require(${JSON.stringify(join(f.root, 'adapters/host-node/node-public-initial-control-bootstrap.cjs'))});
    const journal=await client.prepareJournal(); await journal.admitRootFormat(client.root);
    await journal.openRequestJournal(client.root+'/requests',{});
    const original=root.prepareManagedComputeInstallation(client.originals);
    const receipt=root.beforeManagedComputeSnapshot(original,client.originals,'aql','SELECT 1',
      Object.freeze({format:'sql',parameters:null}));
    const body=Object.freeze({kind:'aql',input:Object.freeze({text:'SELECT 1',format:'sql'}),parameters:null});
    root.bindManagedComputeSnapshot(original,client.originals,receipt,body);
    const request=Object.freeze({originalPendingRequest:true});
    root.bindManagedComputeRequest(original,client.originals,receipt,body,request);
    const prepared=Object.freeze({controlledCheckedPrepared:true}); client.bindPrepared(prepared,request);
    const candidate=Object.freeze({controlledCompiledModel:true}); client.bindModelCandidate(candidate);
    const run=root.prepareSourceLocalMockModelRun(original,client.originals,prepared,candidate);
    assert.equal(root.prepareOriginalManagedRunPorts(run,prepared),null);
    assert.equal(root.prepareOriginalLocalMockModelRunPorts(run,{}),null);
    const ports=root.prepareOriginalLocalMockModelRunPorts(run,prepared);
    assert.equal(ports.limit(1),3n);
    assert.equal(root.prepareOriginalLocalMockModelRunPorts(run,prepared),null);
    assert.throws(()=>root.prepareManagedComputeRun(original,client.originals,prepared));
    assert.match(root.readLocalMockModelNow(client.originals),/^\\d{4}-.*Z$/);
    assert.equal(ports.cancelUnpublished(),0);
    root.finishManagedComputeProducer(original,client.originals,receipt,'returned');
    assert.equal((await root.closeManagedComputeInstallation(original,client.originals)).pending,false);
    assert.equal((await journal.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('local Mock service clock substitution retires the same original without blocking unpublished cleanup', async () => {
  const f = await fixture('same local Mock clock original and partial cleanup',
    {managedCompute: true, localMockModel: true});
  f.run(`
    import assert from 'node:assert/strict'; import {createRequire} from 'node:module';
    import {connect} from '@actql/local-node'; const require=createRequire(import.meta.url);
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const root=require(${JSON.stringify(join(f.root, 'adapters/host-node/node-public-initial-control-bootstrap.cjs'))});
    const journal=await client.prepareJournal(); await journal.admitRootFormat(client.root);
    await journal.openRequestJournal(client.root+'/requests',{});
    const original=root.prepareManagedComputeInstallation(client.originals);
    const receipt=root.beforeManagedComputeSnapshot(original,client.originals,'aql','SELECT 1',
      Object.freeze({format:'sql',parameters:null}));
    const body=Object.freeze({kind:'aql',input:Object.freeze({text:'SELECT 1',format:'sql'}),parameters:null});
    root.bindManagedComputeSnapshot(original,client.originals,receipt,body);
    const request=Object.freeze({originalPendingRequest:true});
    root.bindManagedComputeRequest(original,client.originals,receipt,body,request);
    const prepared=Object.freeze({controlledCheckedPrepared:true}); client.bindPrepared(prepared,request);
    const candidate=Object.freeze({controlledCompiledModel:true}); client.bindModelCandidate(candidate);
    const run=root.prepareSourceLocalMockModelRun(original,client.originals,prepared,candidate);
    const ports=root.prepareOriginalLocalMockModelRunPorts(run,prepared);
    const iso=Date.prototype.toISOString; let entered=0;
    Date.prototype.toISOString=function(){entered++;throw new Error('ReplacementMustNotRun');};
    assert.throws(()=>root.readLocalMockModelNow(client.originals),{code:'LocalMockModelPreparationUnavailable'});
    Date.prototype.toISOString=iso;
    assert.throws(()=>root.readLocalMockModelNow(client.originals),{code:'LocalMockModelPreparationUnavailable'});
    assert.equal(entered,0); assert.notEqual(ports.status(1),0);
    assert.equal(ports.cancelUnpublished(),0);
    root.finishManagedComputeProducer(original,client.originals,receipt,'failed');
    assert.equal((await root.closeManagedComputeInstallation(original,client.originals)).pending,false);
    assert.equal((await journal.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('source-free Compute snapshot refusal retains its one original close without entering getters', async () => {
  const f = await fixture('ordinary source-free Compute rejected original intake', {managedCompute: true});
  f.run(`
    import assert from 'node:assert/strict'; import {existsSync} from 'node:fs';
    import {connect} from '@actql/local-node';
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const journalDuty=await client.prepareJournal();
    await journalDuty.admitRootFormat(client.root);
    await journalDuty.openRequestJournal(client.root+'/requests',{});
    const compute=await client.prepareCompute(); let entered=0;
    assert.throws(()=>compute.beforeSourceSnapshot('aql','SELECT 1',
      {get parameters(){entered++;return null;}}));
    assert.equal(entered,0); assert.equal(existsSync(client.root),true);
    assert.equal((await compute.close()).pending,false);
    assert.equal((await journalDuty.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('actual SDK submission projection binds the same Compute receipt and request', async () => {
  const f = await fixture('ordinary Compute actual SDK submission projection', {managedCompute: true});
  f.run(`
    import assert from 'node:assert/strict'; import {connect} from '@actql/local-node';
    import {connectInProcess} from '@actql/sdk/host-port';
    import {sourcePreparationPort} from ${JSON.stringify(new URL('file://' + join(f.scratch.path,
      'node_modules/@actql/sdk/internal/private-source-preparation.mjs')).href)};
    const host=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const journal=await host.prepareJournal();await journal.admitRootFormat(host.root);
    await journal.openRequestJournal(host.root+'/requests',{});
    const compute=await host.prepareCompute();let request,sends=0;
    const cid=letter=>'sha256:'+letter.repeat(64);
    const epoch={version:'actql-submission-epoch/0.1',authorityScopeCid:cid('a'),
      epochNonce:'b'.repeat(64),authenticator:'c'.repeat(64),notBefore:1800000000000,expiresAt:1800000001000};
    const ref={namespaceId:'original-projection',authorityScopeCid:cid('a'),runDefinitionCid:cid('b')};
    const profile={version:'actql-client-host/0.1',mode:'local',owner:'local',durability:'volatile',
      scopeRef:'original-projection',capabilities:['aql-document'],submissionEpoch:epoch,
      limits:{maxReadWireBytes:65536,maxRowWireBytes:1024,maxRowRetainedValueBytes:1024,
        maxRetainedValueBytes:65536,maxRows:256,maxBatchRows:3,maxBatchRetainedValueBytes:4096}};
    const sdk=await connectInProcess({mode:'local',owner:'local'},
      {[sourcePreparationPort]:compute,async perform(operation,packet){
        if(operation==='connect')return profile;
        assert.equal(operation,'submit-intent');request=packet;sends++;
        assert.deepEqual(packet.input,{text:'SELECT 1',format:'sql'});
        const prepared=Object.freeze({controlled:true});host.bindPrepared(prepared,packet);
        assert.equal(typeof compute.prepareRun(prepared),'object');
        return {kind:'recorded',attemptRef:packet.attemptRef,outcome:{kind:'ready',
          submissionRef:packet.submissionRef,intentCid:packet.intentCid,
          admission:{ref,durability:'volatile',revision:0}}};
      }});
    const execution=await sdk.startSource('SELECT 1',{format:'sql',readOnly:true});
    assert.deepEqual(execution.ref,ref);assert.equal(sends,1);
    await sdk.close();assert.equal((await compute.close()).pending,false);
    assert.equal((await journal.close()).pending,false);assert.equal((await host.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('query intake refuses unsupported raw originals before getters and reuses its one receipt', async () => {
  const f = await fixture('ordinary Compute original raw query intake', {managedCompute: true});
  f.run(`
    import assert from 'node:assert/strict';import {connect} from '@actql/local-node';
    const host=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const journal=await host.prepareJournal();await journal.admitRootFormat(host.root);
    await journal.openRequestJournal(host.root+'/requests',{});
    const compute=await host.prepareCompute();let reads=0;
    const raw=new Proxy({},{get(){reads++;},ownKeys(){reads++;return [];}});
    assert.throws(()=>compute.beforeSourceQuery('sql','SELECT 1',undefined,raw));
    assert.equal(reads,0);
    const receipt=compute.beforeSourceQuery('sql','SELECT 1',undefined,undefined);
    assert.throws(()=>compute.beforeSourceSnapshot('aql','SELECT 1',{format:'sql'}));
    assert.throws(()=>compute.beforeSourceQuery('sql','SELECT 1',null,undefined));
    const body=Object.freeze({kind:'aql',input:Object.freeze({text:'SELECT 1',format:'sql'}),
      parameters:null,readOnly:true});
    assert.throws(()=>compute.bindSourceSnapshot({...receipt},body));
    assert.throws(()=>compute.bindSourceSnapshot(receipt,Object.freeze({...body,
      input:Object.freeze({text:'SELECT 2',format:'sql'})})));
    let entered=0;
    assert.throws(()=>compute.bindSourceSnapshot(receipt,Object.freeze({...body,
      input:Object.freeze({get text(){entered++;return 'SELECT 1';},format:'sql'})})));
    assert.equal(entered,0);
    compute.bindSourceSnapshot(receipt,body);
    assert.throws(()=>compute.intentCid(receipt,Object.freeze({...body})));
    assert.equal(compute.intentCid(receipt,body),'sha256:'+'a'.repeat(64));
    compute.finishSourceProducer(receipt,'failed');
    assert.equal((await compute.close()).pending,false);
    assert.throws(()=>compute.beforeSourceQuery('sql','SELECT 1',undefined,undefined));
    assert.equal((await journal.close()).pending,false);assert.equal((await host.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('actual SDK query and all retain one Root producer and its separate Result read original', async () => {
  const f = await fixture('ordinary actual SDK query and Result original', {managedCompute:true,resultPublication:true});
  f.run(`
    import assert from 'node:assert/strict';import {connect} from '@actql/local-node';
    import {connectInProcess} from '@actql/sdk/host-port';
    import {sourcePreparationPort} from ${JSON.stringify(new URL('file://' + join(f.scratch.path,
      'node_modules/@actql/sdk/internal/private-source-preparation.mjs')).href)};
    const host=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const journal=await host.prepareJournal();await journal.admitRootFormat(host.root);
    await journal.openRequestJournal(host.root+'/requests',{});
    const result=await host.prepareResult(),compute=await host.prepareCompute();
    const cid=letter=>'sha256:'+letter.repeat(64),ref={namespaceId:'query-original',
      authorityScopeCid:cid('a'),runDefinitionCid:cid('b')};
    const epoch={version:'actql-submission-epoch/0.1',authorityScopeCid:cid('a'),epochNonce:'b'.repeat(64),
      authenticator:'c'.repeat(64),notBefore:1800000000000,expiresAt:1800000001000};
    const profile={version:'actql-client-host/0.1',mode:'local',owner:'local',durability:'volatile',
      scopeRef:'query-original',capabilities:['aql-document'],submissionEpoch:epoch,
      limits:{maxReadWireBytes:65536,maxRowWireBytes:1024,maxRowRetainedValueBytes:1024,
        maxRetainedValueBytes:65536,maxRows:256,maxBatchRows:3,maxBatchRetainedValueBytes:4096}};
    const operations=[];
    const sdk=await connectInProcess({mode:'local',owner:'local'},
      {[sourcePreparationPort]:compute,async perform(operation,packet){
        operations.push(operation);if(operation==='connect')return profile;
        if(operation==='submit-intent'){
          assert.deepEqual(packet.input,{text:'SELECT 1 AS n',format:'sql'});
          const prepared=Object.freeze({controlled:true});host.bindPrepared(prepared,packet);
          compute.prepareRun(prepared);
          return {kind:'recorded',attemptRef:packet.attemptRef,outcome:{kind:'ready',
            submissionRef:packet.submissionRef,intentCid:packet.intentCid,
            admission:{ref,durability:'volatile',revision:0}}};
        }
        if(operation==='wait')return {version:'actql-run-state/0.1',run_id:'query-original',revision:1,
          status:'succeeded',updated_at:'2026-10-07T00:00:00.000Z',next_action:{kind:'read_result',results:['answer']},
          result_available:true,result_availability:{answer:{state:'available',
            observed_at:'2026-10-07T00:00:00.000Z',reason:'confirmed_present'}}};
        assert.equal(operation,'read');return {kind:'rows',frames:(async function*(){
          yield {value:{n:1},byteLength:8};})()};
      }});
    const query=sdk.sql('SELECT 1 AS n');const rows=await query.all();
    assert.deepEqual(rows,[{n:1}]);assert.deepEqual(operations,['connect','submit-intent','wait','read']);
    assert.throws(()=>compute.beforeSourceQuery('sql','SELECT 1 AS n',undefined,undefined));
    await sdk.close();assert.equal((await compute.close()).pending,false);
    assert.equal((await result.close()).pending,false);assert.equal((await journal.close()).pending,false);
    assert.equal((await host.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('actual ordinary Result service adopts the same prepared Store and retains joint Journal ACK', async () => {
  const f = await fixture('ordinary selected Result Store original', {managedCompute:true,resultPublication:true});
  f.run(`
    import assert from 'node:assert/strict'; import {existsSync} from 'node:fs';
    import {connect} from '@actql/local-node'; import {createRequire} from 'node:module';
    const require=createRequire(import.meta.url);
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const root=require(${JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))});
    await assert.rejects(client.prepareResult());
    const journal=await client.prepareJournal(); await journal.admitRootFormat(client.root);
    await journal.openRequestJournal(client.root+'/requests',{});
    const result=await client.prepareResult(); result.assertCurrent();
    assert.throws(()=>root.prepareHostResultPublicationInstallation(client.originals));
    assert.throws(()=>root.assertHostResultPublicationInstallationCurrent({},client.originals));
    const control=client.resultControl;
    const options={directory:client.root+'/publication',storeAuthorityCid:'sha256:'+'a'.repeat(64),
      capacityBytes:536870912,maxObjectBytes:10000000,maxObjects:10000,maxContractNodes:10000,maxContractDepth:64};
    const store=await result.openStore(options,control);
    assert.equal(store.status().closed,false); assert.equal(existsSync(client.root+'/checkpoints'),false);
    assert.throws(()=>result.openStore(options,control));
    // Store cannot return the shared token while its SAME Journal is open.
    await assert.rejects(store.close()); assert.equal(store.status().closed,false);
    assert.equal((await journal.close()).pending,true);
    await store.close(); assert.equal(store.status().closed,true);
    assert.equal((await result.close()).pending,false);
    assert.equal((await journal.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('Result operation history does not refill and changed originals cannot revive', async () => {
  const f = await fixture('ordinary Result cumulative operation history', {resultPublication:true});
  f.run(`
    import assert from 'node:assert/strict'; import {connect} from '@actql/local-node';
    import {createRequire} from 'node:module'; const require=createRequire(import.meta.url);
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const journal=await client.prepareJournal(); await journal.admitRootFormat(client.root);
    await journal.openRequestJournal(client.root+'/requests',{});
    const result=await client.prepareResult();
    for(let index=0;index<128;index++)result.beforeOperation('result-description');
    assert.throws(()=>result.beforeOperation('result-description'));
    assert.throws(()=>result.beforeOperation('result-description'));
    const crypto=require('node:crypto'), original=crypto.createCipheriv;
    crypto.createCipheriv=()=>assert.fail('replacement must not execute');
    try{assert.throws(()=>result.assertCurrent());}finally{crypto.createCipheriv=original;}
    assert.throws(()=>result.assertCurrent());
    assert.equal((await result.close()).pending,false);
    assert.equal((await journal.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('Result business candidate binds only its same admitted managed Run', async () => {
  const f = await fixture('ordinary Result same managed candidate', {managedCompute:true,resultPublication:true});
  f.run(`
    import assert from 'node:assert/strict'; import {connect} from '@actql/local-node';
    import {createRequire} from 'node:module'; const require=createRequire(import.meta.url);
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const owner=require(${JSON.stringify(join(f.root,'adapters/host-node/node-public-initial-control-bootstrap.cjs'))});
    const journal=await client.prepareJournal(); await journal.admitRootFormat(client.root);
    await journal.openRequestJournal(client.root+'/requests',{});
    const result=await client.prepareResult(), compute=await client.prepareCompute();
    assert.equal(compute.beforeResultRead(undefined,undefined),undefined);
    compute.assertResultReadCurrent();compute.assertResultReadCurrent();
    let traps=0;const unsupported=new Proxy({}, {ownKeys(){traps++;throw new Error('must not enumerate');}});
    assert.throws(()=>compute.beforeResultRead(unsupported,undefined));assert.equal(traps,0);
    const receipt=compute.beforeSourceSnapshot('aql','SELECT 1',{format:'sql',parameters:null});
    const body=Object.freeze({kind:'aql',input:Object.freeze({text:'SELECT 1',format:'sql'}),parameters:null});
    compute.bindSourceSnapshot(receipt,body);
    const request=Object.freeze({originalPendingRequest:true});compute.bindSourceRequest(receipt,body,request);
    const prepared=Object.freeze({controlledCheckedPrepared:true});client.bindPrepared(prepared,request);
    const original=compute.prepareRun(prepared);
    assert.throws(()=>result.admitRun(prepared));
    const ports=owner.prepareOriginalManagedRunPorts(original,prepared);
    assert.equal(ports.status(0),0);
    result.admitRun(prepared); result.admitRun(prepared);
    assert.throws(()=>result.admitRun({}));
    compute.finishSourceProducer(receipt,'returned');
    // Explicit diagnostic report, not an actual Common Ledger/usage claim.
    assert.equal(ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n),0);assert.equal(ports.status(2),0);
    assert.equal((await compute.close()).pending,false);
    assert.equal((await result.close()).pending,false);
    assert.equal((await journal.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('Result Store work history bounds repeated calls without blocking its original close', async () => {
  const f = await fixture('ordinary Result Store cumulative service work', {resultPublication:true});
  f.run(`
    import assert from 'node:assert/strict'; import {connect} from '@actql/local-node';
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const journal=await client.prepareJournal(); await journal.admitRootFormat(client.root);
    await journal.openRequestJournal(client.root+'/requests',{});
    const result=await client.prepareResult();
    const control=client.resultControl;
    const store=await result.openStore({directory:client.root+'/publication',storeAuthorityCid:'sha256:'+'a'.repeat(64),
      capacityBytes:536870912,maxObjectBytes:10000000,maxObjects:10000,maxContractNodes:10000,maxContractDepth:64},control);
    const requirement={requiredBytes:1,objectCount:1,maxObjectBytes:1};
    // Constructor/internal checks already consume part of this SAME budget;
    // do not assume only the two outer constructor calls reached active().
    let supported=0;
    for(;supported<4096;supported++){
      try{assert.equal(store.publicationCapacitySupports(requirement),true);}
      catch(error){assert.equal(error.code,'HostResultPublicationUnavailable');break;}
    }
    assert(supported>0&&supported<4096);
    assert.throws(()=>store.publicationCapacitySupports(requirement));
    result.assertCurrent();assert.throws(()=>store.publicationCapacitySupports(requirement));
    assert.equal((await journal.close()).pending,true);await store.close();
    assert.equal((await result.close()).pending,false);assert.equal((await journal.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('Result failed actual Store construction keeps original cleanup until the same Journal closes', async () => {
  const f = await fixture('ordinary Result actual failed Store constructor', {resultPublication:true});
  f.run(`
    import assert from 'node:assert/strict'; import {connect} from '@actql/local-node';
    import {mkdir,writeFile} from 'node:fs/promises';
    const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
    const journal=await client.prepareJournal(); await journal.admitRootFormat(client.root);
    await journal.openRequestJournal(client.root+'/requests',{});
    const result=await client.prepareResult();
    // A known exact format passes the original format boundary; the owned
    // fault below is then reached inside actual Store initialization.
    await writeFile(client.root+'/publication/store.json',JSON.stringify({version:'actql-local-publication-store/0.1',
      isolation:'execution-namespace',store_authority_cid:'sha256:'+'a'.repeat(64)}),{mode:0o600});
    await mkdir(client.root+'/publication/staging',{recursive:true});
    await writeFile(client.root+'/publication/staging/invalid-staging-entry','new fixture only');
    const control=client.resultControl;
    const options={directory:client.root+'/publication',storeAuthorityCid:'sha256:'+'a'.repeat(64),
      capacityBytes:536870912,maxObjectBytes:10000000,maxObjects:10000,maxContractNodes:10000,maxContractDepth:64};
    let original;
    await assert.rejects(result.openStore(options,control),error=>{
      original=error;return error.code==='HostResultPublicationCleanupPending'&&error.cleanupHandle.status().pending;});
    assert.equal((await result.close()).pending,true);
    assert.throws(()=>result.openStore(options,control));
    assert.equal((await journal.close()).pending,false);
    assert.equal((await original.cleanupHandle.retry()).pending,false);
    assert.equal((await result.close()).pending,false);
    assert.equal((await client.scope.close()).pending,false);
  `);
  f.scratch.passed();
});

test('Result Store rejects a foreign control or authority before creating its format', async () => {
  for (const wrong of ['control','authority']) {
    const f = await fixture('ordinary Result original '+wrong+' refusal', {resultPublication:true});
    f.run(`
      import assert from 'node:assert/strict';import {existsSync} from 'node:fs';import {connect} from '@actql/local-node';
      const client=await connect({mode:'local',installation:{directory:'.actql'},profile:'mock'});
      const journal=await client.prepareJournal();await journal.admitRootFormat(client.root);
      await journal.openRequestJournal(client.root+'/requests',{});
      const result=await client.prepareResult();
      const options={directory:client.root+'/publication',storeAuthorityCid:'sha256:'+${JSON.stringify(wrong === 'authority' ? 'b' : 'a')}.repeat(64),
        capacityBytes:536870912,maxObjectBytes:10000000,maxObjects:10000,maxContractNodes:10000,maxContractDepth:64};
      await assert.rejects(result.openStore(options,${wrong === 'control' ? '{...client.resultControl}' : 'client.resultControl'}));
      assert.equal(existsSync(client.root+'/publication/store.json'),false);
      assert.equal((await result.close()).pending,false);assert.equal((await journal.close()).pending,false);
      assert.equal((await client.scope.close()).pending,false);
    `);
    f.scratch.passed();
  }
});
