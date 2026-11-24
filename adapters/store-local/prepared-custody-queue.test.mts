import test from 'node:test';
import assert from 'node:assert/strict';
import {createPreparedCustodyQueue} from './prepared-custody-queue.mjs';
import {createPreparedObjectOwnership} from './prepared-object-ownership.mjs';
import {createPublicationCommitOwner} from './publication-commit-owner.mjs';

type PreparedGroups = Parameters<typeof createPreparedObjectOwnership>[0];
type PreparedGroup = NonNullable<ReturnType<PreparedGroups['get']>>;
type PreparedPorts = Parameters<typeof createPreparedObjectOwnership>[4];
const key = {namespaceId:'fixture', authorityScopeCid:'scope', runDefinitionCid:'run'};

for (const fail of [false,true]) test(`prepared custody queue retains later same-CID owners across retirement, failure=${fail}`, async () => {
  const run=createPreparedCustodyQueue(), events: string[]=[];
  let resume!: () => void;
  const paused=new Promise<void>(resolve=>{resume=resolve;});
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

function bindCommit(groups: PreparedGroups, selected: Pick<PreparedPorts,
  'verifyObject' | 'confirmCommittedIndex' | 'materialHasLiveReference'>) {
  const ownership = createPreparedObjectOwnership(groups, {
    register() { assert.fail('a pin cannot register another prepared holder'); },
    forgetHolder() { assert.fail('a pin cannot forget an original prepared holder'); },
  }, createPreparedCustodyQueue(), {materialRetentionBusy: Promise.resolve()}, {
    createObjectWriter() { assert.fail('a pin cannot open a replacement writer'); },
    objectPath() { assert.fail('a pin cannot resolve an allocation for deletion'); },
    confirmPhysicalRemovals() { assert.fail('a pin cannot confirm a physical removal'); },
    rememberPhysicalRemoval() { assert.fail('a pin cannot acquire a physical removal'); },
    removeCustodyRecord() { assert.fail('these pins own no custody record to remove'); },
    reclaimCustody() { assert.fail('these pins own no allocation to reclaim'); },
    ...selected,
  });
  return ownership.beginPreparedCommit;
}

test('failed later commit acquisition returns earlier original pins without retiring holders',async()=>{
 const originalHolder = {active: true, releasing: undefined, custody: undefined};
 const group: PreparedGroup = {committed:false,commitOwners:new Set(),holders:new Set([originalHolder]),
   custodies:new Set(),busy:Promise.resolve(),removable:false,pendingUnlink:undefined};
 const groups: PreparedGroups = new Map([['present',group]]);
 const failure=new Error('MissingLaterMaterial'),seen:unknown[]=[];
 const begin=bindCommit(groups, {
   async verifyObject(cid) {seen.push(cid);throw failure;},
   confirmCommittedIndex() {assert.fail('failed acquisition cannot install');},
   materialHasLiveReference() {assert.fail('a surviving holder needs no durable-reference lookup');},
 });
 await assert.rejects(begin(['present','missing'],key,'index'),error=>error===failure);
 assert.deepEqual(seen,['missing']);
 assert.equal(group.commitOwners.size,0);
 assert.deepEqual([...group.holders],[originalHolder]);
 assert.strictEqual([...group.holders][0],originalHolder);
 assert.equal(groups.get('present'),group);
});

for(const refused of [false,true])test(`index install awaits original custody acquisition, refused=${refused}`,async()=>{
 let resume!: () => void, entered!: () => void;
 let installs=0,cancelled=0;
 const gate=new Promise<void>(resolve=>resume=resolve),begun=new Promise<void>(resolve=>entered=resolve);
 const failure=new Error('OriginalPinAcquisitionFailed');
 const input = {entry:{},admitted:{},key:{}};
 const owner=createPublicationCommitOwner<typeof input.entry, typeof input.admitted, typeof input.key>(input,{
  confirm:async()=>undefined,stage:async()=>{},
  async beginCustody(){
    entered();await gate;if(refused)throw failure;
    return {status:()=>({pending:false}),settleAdopted:async()=>{},
      resolveConfirmed(){assert.fail('a preinstall acquisition cannot reconcile');},
      retry(){assert.fail('a preinstall acquisition cannot retry');}};
  },
  cancelStage(){cancelled++;},install:async()=>{installs++;},adopt:async()=>{},
  sameContent(){assert.fail('no existing commit was selected');},
  conflict(){assert.fail('no conflict was selected');},
  verifyExistingInventory(){assert.fail('no existing inventory was selected');},
  adoptObjects(){assert.fail('no existing custody was selected');},
  adoptSchemas(){assert.fail('no existing schemas were selected');},
  makeFailure(){assert.fail('the existing primary must be retained');},
 });
 const committing=owner.commit();committing.catch(()=>{});
 await begun;assert.equal(installs,0);resume();
 if(refused){await assert.rejects(committing,error=>error===failure);assert.equal(cancelled,1);assert.equal(installs,0);}
 else{assert.equal((await committing).committed,true);assert.equal(installs,1);assert.equal(cancelled,0);}
});


test('uncommitted adopted-original pin removes only its exact empty metadata group',async()=>{
 const groups: PreparedGroups = new Map(), references: string[]=[];
 const begin=bindCommit(groups, {
   async verifyObject(cid) {return {cid,bytes:30};},
   async confirmCommittedIndex() {return undefined;},
   async materialHasLiveReference(cid) {references.push(cid);return false;},
 });
 const custody=await begin(['original'],key,'index');
 const group=groups.get('original');
 assert(group);
 assert.equal(group.removable,false);assert.equal(group.custodies.size,0);
 assert.equal(group.commitOwners.size,1);assert.equal(custody.status().pending,true);
 await custody.resolveConfirmed(undefined);
 assert.equal(groups.has('original'),false);assert.equal(custody.status().pending,false);
 assert.deepEqual(references,['original']);
});
