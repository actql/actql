import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';

const source=readFileSync(new URL('./installed-composed-infer-run.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const run=ast.body.map(node=>node.declaration??node).find(node=>node.type==='FunctionDeclaration'&&node.id.name==='runInstalledComposedInfers');
const cleanup=run.body.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='cleanup');
const issuance=run.body.body.find(node=>node.type==='IfStatement'&&source.slice(node.test.start,node.test.end).startsWith('originalPreparation === undefined'));
assert.ok(cleanup);assert.ok(issuance);
// Execute the installed caller's exact cleanup and issuer-selection statements
// with explicit Core/physical ports. This is not a funded or installed Host.
const construct=compileFunction(`
  let {children,originalPreparation,modelController}=context;
  let released=false,pendingSetup,holding,publication,issuance,execution,restoredSource,sourceContinuation;
  let preflightCleanup=context.preflightCleanup;
  let closeAttempted=false,completeOriginal=context.completeOriginal===true,publicationOwner=context.publicationOwner;
  ${source.slice(cleanup.start,cleanup.end)}
  return {cleanup,pending:()=>!released};`,['context','checked']);
const selectIssuance=compileFunction(`let issuance=originalIssuer,issuanceComplete=originalIssuer!==undefined;
  ${source.slice(issuance.start,issuance.end)}\nreturn issuance;`,
  ['children','originalPreparation','input','moon','calls','startCompleteInferObservation','checked','originalIssuer']);

function fixture(count=1,{shared=false}={}) {
  const events=[],flags={aliases:false,release:false,issue:undefined,blockedAliases:new Set()};
  const children=Array.from({length:count},(_,index)=>{
    let borrowed=shared?index===count-1:true,closed=false;
    const operation={physicalStopped:()=>true,publicationCapacityPending:()=>borrowed,
      releaseOriginalPublicationCapacity() {
        events.push(`release${index}`);
        if(flags.release)borrowed=false;
        return flags.release;
      }};
    const physical={
      async retirePublication() {
        events.push(`aliases${index}`);
        if(flags.issue!==undefined)throw flags.issue;
        return flags.aliases&&!flags.blockedAliases.has(index);
      },
      async close() {events.push(`close${index}`);closed=!borrowed;return closed;},
      async cleanup() {events.push(`cleanup${index}`);closed=!borrowed;return closed;},
      cleanupPending:()=>!closed};
    return {operation,capture:{custody:physical}};
  });
  const owner=construct({children,modelController:{},completeOriginal:shared,publicationOwner:shared?children.at(-1).operation:undefined,originalPreparation:{async retire(){events.push('parent');return true;}}},checked);
  return {owner,events,flags,children};
}

test('composed original cleanup retires publication aliases and exact borrow before parent Model cleanup',async()=>{
  const f=fixture();
  assert.equal(await f.owner.cleanup(),false);
  assert.deepEqual(f.events,['aliases0']);assert.equal(f.owner.pending(),true);
  f.flags.aliases=true;
  assert.equal(await f.owner.cleanup(),false);
  assert.deepEqual(f.events,['aliases0','aliases0','release0']);
  f.flags.release=true;
  assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.events,['aliases0','aliases0','release0','aliases0','release0','close0','parent']);
  assert.equal(f.owner.pending(),false);
  const before=f.events.slice();assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.events,before,'retirement does not repeat after successful owner cleanup');
});

test('composed original cleanup retains failed alias retirement and retries that same owner',async()=>{
  const f=fixture(),issue=new Error('OriginalPublicationStillOwned');f.flags.issue=issue;
  await assert.rejects(f.owner.cleanup(),error=>error===issue);
  assert.deepEqual(f.events,['aliases0']);assert.equal(f.owner.pending(),true);
  f.flags.issue=undefined;f.flags.aliases=true;f.flags.release=true;
  assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.events,['aliases0','aliases0','release0','close0','parent']);
});

test('composed cleanup retires each sibling publication borrow independently',async()=>{
  const f=fixture(2);f.flags.aliases=true;f.flags.release=true;
  assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.events,['aliases0','release0','close0','aliases1','release1','close1','parent']);
});

test('composed cleanup keeps a pending original without blocking independent sibling retirement',async()=>{
  const f=fixture(2);f.flags.aliases=true;f.flags.release=true;f.flags.blockedAliases.add(0);
  assert.equal(await f.owner.cleanup(),false);
  assert.deepEqual(f.events,['aliases0','aliases1','release1','close1']);
  assert.equal(f.owner.pending(),true);
  f.flags.blockedAliases.clear();
  assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.events,['aliases0','aliases1','release1','close1','aliases0','release0','close0','parent']);
});

test('composed original issuer selection retains its sealed issuer instead of forwarding Source funding',()=>{
  const operation={},children=[{operation}],input={ledger:{source:true}},originalIssuer={};
  const selected=selectIssuance(children,{},input,{
    clientProgramInferPublicationLedger(){assert.fail('never issue a replacement Ledger');}},1,
    ()=>assert.fail('never replace the original sealed issuer'),checked,originalIssuer);
  assert.strictEqual(selected,originalIssuer);
  assert.throws(()=>selectIssuance(children,{},input,{},1,
    ()=>assert.fail('missing original cannot fall back'),checked),/InstalledComposedInferOriginalObservationUnavailable/);
});

test('composed issuer selection refuses a missing Request instead of creating another Ledger',()=>{
  let issued=0;
  assert.throws(()=>selectIssuance([{operation:{}}],undefined,{ledger:{}},{
    clientProgramInferPublicationLedger(){issued++;throw new Error('NoReplacementLedger');}},
    1,()=>{issued++;throw new Error('NoReplacementIssuer');},checked),
    /InstalledComposedInferOriginalObservationUnavailable/);
  assert.equal(issued,0);
});


test('composed Model retains the entry original partial preflight owner and does not retire Scope while it is pending', async () => {
  const events = [], cause = new Error('OriginalPartialSitePending');
  let siteReady = false, released = false;
  const original = {status: () => ({pending: !released}), retry() {
    events.push('original-retry'); if (!siteReady) throw cause;
    released = true; return {pending: false};
  }};
  const parent = {async retire() {events.push('Scope'); return true;}};
  const owner = construct({children: [], originalPreparation: parent,
    modelController: {}, preflightCleanup: original}, checked);
  await assert.rejects(owner.cleanup(), error => error === cause);
  assert.equal(owner.pending(), true); assert.deepEqual(events, ['original-retry']);
  siteReady = true;
  assert.equal(await owner.cleanup(), true);
  assert.deepEqual(events, ['original-retry', 'original-retry', 'Scope']);
  assert.equal(owner.pending(), false);
});


test('complete group retires every publication alias before releasing its single original borrow',async()=>{
  const f=fixture(2,{shared:true});f.flags.aliases=true;f.flags.release=true;f.flags.blockedAliases.add(0);
  assert.equal(await f.owner.cleanup(),false);
  assert.deepEqual(f.events,['aliases0','aliases1']);
  assert.equal(f.children[1].operation.publicationCapacityPending(),true);
  assert.equal(f.owner.pending(),true);
  f.flags.blockedAliases.clear();assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.events,['aliases0','aliases1','aliases0','aliases1','release1','close0','close1','parent']);
  const before=f.events.slice();assert.equal(await f.owner.cleanup(),true);assert.deepEqual(f.events,before);
});

test('complete group keeps its single original borrow through a sibling alias retirement failure',async()=>{
  const f=fixture(2,{shared:true}),primary=new Error('same sibling publication pending');
  f.flags.issue=primary;
  await assert.rejects(f.owner.cleanup(),error=>error===primary);
  assert.equal(f.children[1].operation.publicationCapacityPending(),true);
  assert.deepEqual(f.events,['aliases0']);
  f.flags.issue=undefined;f.flags.aliases=true;f.flags.release=true;
  assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.events,['aliases0','aliases0','aliases1','release1','close0','close1','parent']);
});
