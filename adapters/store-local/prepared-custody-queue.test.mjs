import test from 'node:test';
import assert from 'node:assert/strict';
import {createPreparedCustodyQueue} from './prepared-custody-queue.mjs';
for (const fail of [false,true]) test(`prepared custody queue retains later same-CID owners across retirement, failure=${fail}`, async () => {
  const run=createPreparedCustodyQueue(), events=[];
  let resume;
  const paused=new Promise(resolve=>{resume=resolve;});
  const retirement=run('same',async()=>{events.push('retire-start');await paused;events.push('retire-end');if(fail)throw new Error('RetirementFailed');});
  const attachment=run('same',()=>events.push('attach'));
  await run('other',()=>events.push('other'));
  assert.deepEqual(events,['retire-start','other']);
  resume();
  if(fail)await assert.rejects(retirement,{message:'RetirementFailed'});else await retirement;
  await attachment;
  assert.deepEqual(events,['retire-start','other','retire-end','attach']);
  await run('same',()=>events.push('next'));
  assert.equal(events.at(-1),'next');
});

// Inspect the actual lexical owner implementation, not a second pin formula.
const {readFileSync}=await import('node:fs');
const {compileFunction}=await import('node:vm');
const source=readFileSync(new URL('./publication-store.mjs',import.meta.url),'utf8');
const start=source.indexOf('  const beginPreparedCommit =');
const end=source.indexOf('  const putBytesInternal =',start);
assert.ok(start>=0&&end>start);
const bindCommit=compileFunction('let materialRetentionBusy = Promise.resolve();\n'+source.slice(start,end)+'\nreturn beginPreparedCommit;',
  ['withPreparedCustody','preparedObjects','verifyObject','adoptPreparedObjects','confirmCommittedIndex']);
test('failed later commit acquisition returns earlier original pins without retiring holders',async()=>{
 const group={committed:false,commitOwners:new Set(),holders:new Set(['original-holder']),custodies:new Set()};
 const groups=new Map([['present',group]]);
 const failure=new Error('MissingLaterMaterial'),seen=[];
 const begin=bindCommit(createPreparedCustodyQueue(),groups,async cid=>{seen.push(cid);throw failure;},
  ()=>assert.fail('failed acquisition cannot adopt'),()=>assert.fail('failed acquisition cannot install'));
 await assert.rejects(begin(['present','missing'],{},'index'),error=>error===failure);
 assert.deepEqual(seen,['missing']);
 assert.equal(group.commitOwners.size,0);
 assert.deepEqual([...group.holders],['original-holder']);
 assert.equal(groups.get('present'),group);
});

const {createPublicationCommitOwner}=await import('./publication-commit-owner.mjs');
for(const refused of [false,true])test(`index install awaits original custody acquisition, refused=${refused}`,async()=>{
 let resume,installs=0,cancelled=0,entered;
 const gate=new Promise(resolve=>resume=resolve),begun=new Promise(resolve=>entered=resolve);
 const failure=new Error('OriginalPinAcquisitionFailed');
 const owner=createPublicationCommitOwner({entry:{},admitted:{},key:{}},{
  confirm:async()=>undefined,stage:async()=>{},
  async beginCustody(){entered();await gate;if(refused)throw failure;return{status:()=>({pending:false}),settleAdopted:async()=>{}};},
  cancelStage(){cancelled++;},install:async()=>{installs++;},adopt:async()=>{},
 });
 const committing=owner.commit();committing.catch(()=>{});
 await begun;assert.equal(installs,0);resume();
 if(refused){await assert.rejects(committing,error=>error===failure);assert.equal(cancelled,1);assert.equal(installs,0);}
 else{assert.equal((await committing).committed,true);assert.equal(installs,1);assert.equal(cancelled,0);}
});


test('uncommitted adopted-original pin removes only its exact empty metadata group',async()=>{
 const groups=new Map();
 const begin=bindCommit(createPreparedCustodyQueue(),groups,async()=>({bytes:30}),
  ()=>assert.fail('uncommitted attempt cannot adopt'),async()=>undefined);
 const custody=await begin(['original'],{},'index');
 const group=groups.get('original');
 assert.equal(group.removable,false);assert.equal(group.custodies.size,0);
 assert.equal(group.commitOwners.size,1);assert.equal(custody.status().pending,true);
 await custody.resolveConfirmed(undefined);
 assert.equal(groups.has('original'),false);assert.equal(custody.status().pending,false);
});
