import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {invocationIdentity,receiptBasename,receiptSuffixes} from './execution-names.mjs';
import {mutations} from './capacity/instrument.mjs';
import {variants} from './mutation-registry.mjs';
import {packArchive,unpackArchive,fileDigest} from './ci-artifacts.mjs';
import {minimalRepository,runDriver,successful} from './fixtures/execution-driver.mjs';
const labels=[...mutations.flatMap(v=>['search','shrink','minimal','restored','post-restore'].map(phase=>`capacity-${v.name}-${phase}`)),
 ...variants.flatMap(v=>['search','shrink','minimal','fixed','restored','fixed-post-restore','explore-post-restore'].map(phase=>`${v.name}-${phase}`))];
test('part invocation losslessly encodes timestamp and PID, preserving legacy names',()=>{
 const now=Date.now(),pid=2147483647,value=invocationIdentity('L-C1',now,pid);
 const [time,process]=value.slice('L-C1-'.length).split('-');
 assert.equal(parseInt(time,36),now);assert.equal(parseInt(process,36),pid);
 assert.equal(invocationIdentity('',now,pid),`${now}-${pid}`);
 assert.notEqual(value,invocationIdentity('L-C0',now,pid));
});
test('every actual phase label and longest suffix fits unchanged USTAR limit at large identity bounds',()=>{
 const identity=invocationIdentity('L-C1',Date.UTC(2100,0,1),2147483647);
 for(const label of labels) for(const target of ['js','wasm','native']) for(const serial of [0,9999,99999]) {
  const name=receiptBasename(identity,serial,label,target);
  assert(name.includes(label), 'Scientific label was shortened');
  for(const suffix of receiptSuffixes) assert(Buffer.byteLength(name+suffix)<=100);
 }
});
test('longest real receipt labels round-trip the real strict USTAR writer and reader',t=>{
 const root=mkdtempSync(join(tmpdir(),'actql-receipt-names-'));t.after(()=>rmSync(root,{recursive:true,force:true}));
 const source=join(root,'source');const out=join(root,'unpacked');
 const identity=invocationIdentity('L-C1',Date.UTC(2100,0,1),2147483647);
 const longest=[...labels].sort((a,b)=>b.length-a.length)[0];
 const name=receiptBasename(identity,99999,longest,'native');
 // packArchive retains its existing strict sealed-archive and path checks.
 mkdirSync(source);writeFileSync(join(source,'ci-seal.json'),'{}\n');
 for(const suffix of receiptSuffixes)writeFileSync(join(source,name+suffix),`original ${suffix}\n`);
 const tar=join(root,'evidence.tar'),digest=packArchive(source,tar);assert.equal(digest,fileDigest(tar));
 unpackArchive(tar,out,digest);
 for(const suffix of receiptSuffixes)assert.equal(readFileSync(join(out,name+suffix),'utf8'),`original ${suffix}\n`);
});
test('oversized arbitrary labels still fail before producing an untransportable receipt',()=>{
 assert.throws(()=>receiptBasename(invocationIdentity('L-C1'),0,'x'.repeat(101),'native'),/USTAR/);
 for(const part of ['L-C2','other','../'])assert.throws(()=>invocationIdentity(part));
 assert.throws(()=>receiptBasename(invocationIdentity('L-C1'),100000,'normal','js'),/serial/);
 assert.throws(()=>receiptBasename(invocationIdentity('L-C1'),0,'測'.repeat(40),'native'),/label/);
 assert.throws(()=>receiptBasename(invocationIdentity('L-C1',Number.MAX_SAFE_INTEGER,2147483647),99999,
  'capacity-handoff-copy-without-accounting-post-restore','native'),/USTAR/);
});

test('oversized label fails before workspace checks, fixture writes or Moon execution',t=>{
 const root=minimalRepository(t);
 const result=successful(runDriver(root,`
 const owner=workspaceIdentity(root,'normal');let checked=0;
 const runner=createExecutor({...owner,check(){checked++;return owner.check();}});
 assert.throws(()=>runner.execute([makeCase()],registry,'native',false,'x'.repeat(101)),/USTAR/);
 assert.equal(checked,0);assert.equal(existsSync(join(root,fixture)),false);assert.equal(calls().length,0);
 runner.close();report({checked,calls:calls().length});
 `));assert.deepEqual(result,{checked:0,calls:0});
});
test('real executor preserves longest scientific label and compact part identity in generated receipts',t=>{
 const root=minimalRepository(t),prior=process.env.ACTQL_PIPELINE_PART;
 try {
  process.env.ACTQL_PIPELINE_PART='L-C1';
  successful(runDriver(root,`
 const label='capacity-handoff-copy-without-accounting-post-restore';
 execute([makeCase()],registry,'native',true,label);closeExecutor();
 const actual=executions[0];assert(actual.path.includes(label));
 assert.match(actual.path,/L-C1-[0-9a-z]+-[0-9a-z]+-0000-/);
 assert(actual.receipt.cases[0].id.startsWith('L-C1-'));
 for(const path of [actual.path,actual.receipt.fixturePath,actual.receipt.inputPath,actual.receipt.logPath])
  assert(Buffer.byteLength(path.split('/').at(-1))<=100);
 report({preserved:true});
 `));
 } finally {if(prior===undefined)delete process.env.ACTQL_PIPELINE_PART;else process.env.ACTQL_PIPELINE_PART=prior;}
});
test('part, timestamp, PID, serial and target remain distinct without lossy truncation',()=>{
 const names=new Set();let count=0;
 for(const part of ['L-C0','L-C1','L-M0','L-M1']) for(const now of [0,Date.UTC(2026,0,1),Date.UTC(2100,0,1)])
  for(const pid of [1,99999,4194304,2147483647]) for(const serial of [0,1,9999,99999]) for(const target of ['js','wasm','native']) {
   const value=receiptBasename(invocationIdentity(part,now,pid),serial,'normal',target);
   assert(!names.has(value),'Invocation fields collided');names.add(value);count++;
  }
 assert.equal(names.size,count);
});
