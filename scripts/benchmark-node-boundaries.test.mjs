import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {arch, cpus, platform, release, tmpdir, totalmem} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nodeOperationProtocol, nodeWarmProtocol} from './benchmark-node-operations.mjs';
import {runNodeUsedMaterialBoundary} from './benchmark-node-boundaries.mjs';
import {assessPerformanceEvidence} from './operation-performance.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
async function fixture(t, fault = '') {
  const root = await mkdtemp(join(tmpdir(), 'actql-boundary-collector-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const base = join(root, 'consumer/node_modules/@actql/node'); await mkdir(base, {recursive: true});
  // A synthetic public-port double exercises only collector sequencing and
  // fault safety. It is not ordinary product execution or a latency sample.
  const code = Buffer.from(`import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {appendFile,link,mkdir,readFile,symlink,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
await writeFile(${JSON.stringify(join(root, 'imported'))},'yes');
export async function open({stateDir}) {
 const directories=['indexes','contracts','objects'];
 for(const name of directories)await mkdir(join(stateDir,'publication',name),{recursive:true});
 const ref={namespaceId:'synthetic',authorityScopeCid:'sha256:'+'a'.repeat(64),runDefinitionCid:'sha256:'+'b'.repeat(64)};
 const bindingCid='sha256:'+'c'.repeat(64),definitionCid='sha256:'+'d'.repeat(64);
 const payload=Buffer.from('one original test-owned row frame');
 const cid='sha256:'+createHash('sha256').update(payload).digest('hex');
 const material=join(stateDir,'publication/objects',cid.slice(7));
 let reads=0;
 const event=kind=>appendFile(stateDir+'/events',kind+'\\n');
 const run={ref,wait:async()=>({status:'succeeded'}),result:()=>({all:async()=>{
   await event('read');reads++;
   ${fault === 'allow' ? '' : "if(reads>1&&!payload.equals(await readFile(material)))throw Object.assign(new Error('refused'),{code:'ClientHostFailure'});"}
   return[{id:1}];
 }})};
 return{startSource:async(text,options)=>{
  assert.equal(text,'SELECT 1 AS id');assert.equal(options.format,'sql');await event('submit');
  const h=createHash('sha256').update('actql-local-public-index-key/0.1\\0');
  for(const value of[ref.namespaceId,ref.authorityScopeCid,ref.runDefinitionCid]){const b=Buffer.from(value),n=Buffer.alloc(8);n.writeBigUInt64BE(BigInt(b.length));h.update(n).update(b);}
  await writeFile(material,payload);
  ${fault === 'hardlink' ? `await link(material,${JSON.stringify(join(root, 'outside-original'))});` : ''}
  await writeFile(join(stateDir,'publication/indexes',h.digest('hex')+'.json'),JSON.stringify({namespace_id:ref.namespaceId,authority_scope_cid:ref.authorityScopeCid,run_definition_cid:ref.runDefinitionCid,durable_result_binding_cids:${fault === 'ambiguous' ? '[bindingCid,bindingCid]' : '[bindingCid]'}}));
  const bindingWire=JSON.stringify({run_definition_cid:ref.runDefinitionCid,result_definition_cid:definitionCid,material_generation_cid:cid,byte_count:payload.length});
  const definitionWire=JSON.stringify({result_name:'main'});
  ${fault === 'native' ? `const {DatabaseSync}=await import('node:sqlite');
  const database=new DatabaseSync(join(stateDir,'publication/delivery-attempts.sqlite3'));
  try {
   database.exec('CREATE TABLE publication_contracts (semantic_cid TEXT PRIMARY KEY,name TEXT,wire TEXT,byte_count INTEGER) WITHOUT ROWID');
   const insert=database.prepare('INSERT INTO publication_contracts VALUES(?,?,?,?)');
   insert.run(bindingCid,'durable_result_binding',bindingWire,Buffer.byteLength(bindingWire));
   insert.run(definitionCid,'result_definition',definitionWire,Buffer.byteLength(definitionWire));
   insert.run('sha256:'+'e'.repeat(64),'unrelated','not JSON',8);
  } finally {database.close();}` : `await writeFile(join(stateDir,'publication/contracts',bindingCid.slice(7)+'.json'),bindingWire);
  await writeFile(join(stateDir,'publication/contracts',definitionCid.slice(7)+'.json'),definitionWire);`}
  ${fault === 'symlink' ? `await import('node:fs/promises').then(async fs=>{await fs.rename(join(stateDir,'publication/objects'),join(stateDir,'original-objects'));await symlink(join(stateDir,'original-objects'),join(stateDir,'publication/objects'));});` : ''}
  return run;},close:async()=>{await event('close');${fault === 'close' ? "throw new Error('cleanup pending');" : ''}}};
}`);
  await writeFile(join(base, 'index.mjs'), code, {mode: 0o644});
  const tar = Buffer.from('synthetic archive identity, never an ordinary tarball');
  await writeFile(join(root, 'test.tgz'), tar);
  const manifestPath = join(root, 'release.json');
  await writeFile(manifestPath, JSON.stringify({sourceSha: 'a'.repeat(40), packages: [{name: '@actql/node',
    file: 'test.tgz', bytes: tar.length, sha256: hash(tar), integrity: 'sha512-' + createHash('sha512').update(tar).digest('base64'),
    files: [{path: 'index.mjs', bytes: code.length, mode: 0o644, sha256: hash(code)}]}]}));
  const controlsPath = join(root, 'controls.json');
  await writeFile(controlsPath, JSON.stringify({sourceSha: 'a'.repeat(40), cohortSha256: hash(await readFile(manifestPath)),
    environment: {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
      cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()},
    historyProtocolSha256: hash(Buffer.from(JSON.stringify(nodeOperationProtocol('diagnostic'))))}));
  return {manifestPath, consumer: join(root, 'consumer'), controlsPath, output: join(root, 'new-boundary'),
    importMarker: join(root, 'imported'), outsideOriginal: join(root, 'outside-original')};
}
const events = async options => (await readFile(join(options.output, 'new-state/events'), 'utf8')).trim().split('\n');

test('selected material refusal records one boundary and leaves every other release gate incomplete', async t => {
  const options = await fixture(t), report = await runNodeUsedMaterialBoundary(options);
  assert.equal(report.selectedBoundaryPassed, true, JSON.stringify(report.firstFailure)); assert.equal(report.cleanup.closed, true);
  assert.equal(report.boundaries.rows.length, 1);
  assert.equal(report.boundaries.rows[0].outcome, 'rejected');
  assert.equal(report.boundaries.rows[0].error.code, 'ClientHostFailure');
  assert.deepEqual(await events(options), ['submit', 'read', 'read', 'close']);
  assert.equal((await readFile(join(options.output, 'original-selected-generation.bin'))).toString(), 'one original test-owned row frame');
  assert.equal(report.latencyMeasured, false); assert.equal(report.fullAcceptance, false);
  assert.equal(assessPerformanceEvidence(report).status, 'incomplete');
  assert(report.assessment.missing.includes('commit-unknown'));
});
test('a successful read of changed material remains a failing boundary, with awaited close', async t => {
  const options = await fixture(t, 'allow'), report = await runNodeUsedMaterialBoundary(options);
  assert.equal(report.selectedBoundaryPassed, false); assert.equal(report.cleanup.closed, true);
  assert.equal(report.boundaries.rows[0].outcome, 'succeeded');
  assert.equal(report.assessment.status, 'failed');
  assert.deepEqual(await events(options), ['submit', 'read', 'read', 'close']);
});
test('native indexed contracts select the original material without legacy shadows or unrelated rows', async t => {
  const options = await fixture(t, 'native'), report = await runNodeUsedMaterialBoundary(options);
  assert.equal(report.selectedBoundaryPassed, true, JSON.stringify(report.firstFailure));
  assert.deepEqual(report.mutation.metadataStorage, {binding: 'sqlite', definition: 'sqlite'});
  assert.equal(report.observedBoundary.outcome, 'rejected');
  assert.equal(report.cleanup.closed, true);
  assert.deepEqual(await events(options), ['submit', 'read', 'read', 'close']);
  assert.equal((await readFile(join(options.output, 'original-selected-generation.bin'))).toString(), 'one original test-owned row frame');
});
test('cleanup failure cannot qualify a rejected material read or overwrite its observation', async t => {
  const options = await fixture(t, 'close'), report = await runNodeUsedMaterialBoundary(options);
  assert.equal(report.observedBoundary.outcome, 'rejected'); assert.equal(report.selectedBoundaryPassed, false);
  assert.equal(report.cleanup.closed, false); assert.match(report.cleanup.failure.message, /cleanup pending/u);
  assert.deepEqual(report.boundaries.rows, []);
  assert.equal(report.assessment.status, 'incomplete');
});
for (const fault of ['ambiguous', 'symlink']) {
  test(`${fault} selected storage refuses before mutation or a second public read`, async t => {
    const options = await fixture(t, fault), report = await runNodeUsedMaterialBoundary(options);
    assert.equal(report.selectedBoundaryPassed, false); assert.equal(report.cleanup.closed, true);
    assert.equal(report.firstFailure.step, 'selected test-owned material mutation');
    assert.equal(report.mutation, undefined); assert.deepEqual(report.boundaries.rows, []);
    assert.deepEqual(await events(options), ['submit', 'read', 'close']);
    await assert.rejects(readFile(join(options.output, 'original-selected-generation.bin')), {code: 'ENOENT'});
  });
}
test('warm-only or foreign experiment metadata refuses before public import or new state', async t => {
  const options = await fixture(t), controls = JSON.parse(await readFile(options.controlsPath));
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodeWarmProtocol('diagnostic'))));
  await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeUsedMaterialBoundary(options), /complete shared experiment protocol/u);
  controls.historyProtocolSha256 = hash(Buffer.from(JSON.stringify(nodeOperationProtocol('diagnostic'))));
  controls.environment.node = 'different runtime'; await writeFile(options.controlsPath, JSON.stringify(controls));
  await assert.rejects(runNodeUsedMaterialBoundary(options));
  await assert.rejects(readFile(options.importMarker), {code: 'ENOENT'});
  await assert.rejects(readFile(join(options.output, 'new-state/events')), {code: 'ENOENT'});
});
test('an existing output is never reused for initialization or fault injection', async t => {
  const options = await fixture(t); await mkdir(options.output);
  await assert.rejects(runNodeUsedMaterialBoundary(options), {code: 'EEXIST'});
  await assert.rejects(readFile(options.importMarker), {code: 'ENOENT'});
});
test('hardlinked selected material refuses before mutation and leaves the outside original unchanged', async t => {
  const options = await fixture(t, 'hardlink'), report = await runNodeUsedMaterialBoundary(options);
  assert.equal(report.selectedBoundaryPassed, false); assert.equal(report.cleanup.closed, true);
  assert.equal(report.firstFailure.step, 'selected test-owned material mutation');
  assert.match(report.firstFailure.message, /unshared bounded material/u);
  assert.equal(report.mutation, undefined); assert.deepEqual(report.boundaries.rows, []);
  assert.deepEqual(await events(options), ['submit', 'read', 'close']);
  assert.equal((await lstat(options.outsideOriginal)).nlink, 2);
  assert.equal((await readFile(options.outsideOriginal)).toString(), 'one original test-owned row frame');
  await assert.rejects(readFile(join(options.output, 'original-selected-generation.bin')), {code: 'ENOENT'});
});
