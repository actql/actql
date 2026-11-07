import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

const source=readFileSync(new URL('./installed-composed-infer-run.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const run=ast.body.map(node=>node.declaration??node).find(node=>node.type==='FunctionDeclaration'&&node.id.name==='runInstalledComposedInfers');
const declaration=run.body.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='retainCompleted');
const properties=[];
function collect(node) {
  if(node===null||typeof node!=='object')return;
  if(node.type==='Property'&&node.key.name==='retainCompleted')properties.push(node);
  for(const value of Object.values(node)) {
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(run.body);assert.equal(properties.length,1);
// Execute the actual Local completion callback and its actual owned helper,
// if present. Explicit Core ports simulate the legitimate later upstream
// handoff; no Host, Store, Model response or resource grant is fabricated.
const construct=compileFunction(`
  const {child,children,originalPreparation,moon,startCompleteInferObservation,completeOriginal=false}=context;
  let issuance,issuanceComplete=false,publicationOwner;
  ${declaration===undefined?'':source.slice(declaration.start,declaration.end)}
  const callback=${source.slice(properties[0].value.start,properties[0].value.end)};
  return {callback,issuer:()=>issuance,sealed:()=>issuanceComplete};`,['context','checked','runtimeField']);

function fixture(options={}) {
  const {legacy=false,startIssue,advanceIssue,neverComplete=false}=options;
  const count=Object.hasOwn(options,'count')?options.count:2;
  const events=[],issuer={};let current=true,advances=0;
  const child={capture:{retainCompleted(){events.push('capture');return true;},
    completedCallCount(){events.push('count');return count;}},operation:{}};
  const context={child,children:[child],originalPreparation:legacy?undefined:{},
    moon:{clientProgramAdvanceInferObservationIssuance(actual,quantum) {
      assert.strictEqual(actual,issuer);assert.equal(quantum,1);
      assert.equal(current,true,'every issuance step precedes the dependent Local output handoff');
      events.push('advance');advances++;
      if(advanceIssue!==undefined)return {$tag:0,_0:advanceIssue};
      return {$tag:1,_0:{_0:!neverComplete&&advances===count+2,_1:BigInt(advances)}};
    }},
    startCompleteInferObservation(options) {
      assert.equal(current,true);assert.strictEqual(options.operations[0],child.operation);
      assert.equal(options.operations.length,1);assert.equal(options.ledger,undefined);
      assert.deepEqual([options.maxSlots,options.maxWireBytes,options.maxWork],[count,16384,count+2]);
      events.push('start');if(startIssue!==undefined)throw startIssue;return issuer;
    }};
  const owner=construct(context,checked,runtimeField);
  return {owner,events,issuer,context,handoff(){current=false;}};
}

test('original Model observation seals at completion before the Local output ownership handoff',()=>{
  const f=fixture();
  assert.equal(f.owner.callback(),true);
  assert.equal(f.owner.sealed(),true);assert.strictEqual(f.owner.issuer(),f.issuer);
  assert.deepEqual(f.events,['capture','count','start','advance','advance','advance','advance']);
  f.handoff();
  assert.equal(f.owner.callback(),true,'a repeated completion observes the same already sealed issuer');
  assert.equal(f.events.filter(value=>value==='start').length,1);
  assert.equal(f.events.filter(value=>value==='advance').length,4);
});

test('original Model observation constructor refusal remains exact before Local handoff',()=>{
  const issue=new Error('OriginalObservationCurrentRefused'),f=fixture({startIssue:issue});
  assert.throws(()=>f.owner.callback(),error=>error===issue);
  assert.equal(f.owner.issuer(),undefined);assert.equal(f.owner.sealed(),false);
  assert.deepEqual(f.events,['capture','count','start']);
});

test('original Model observation retains zero and maximum slot inventories under the existing bound',()=>{
  for(const count of [0,128]) {
    const f=fixture({count});assert.equal(f.owner.callback(),true);
    assert.equal(f.owner.sealed(),true);
    assert.equal(f.events.filter(value=>value==='advance').length,count+2);
  }
});

test('original Model observation failed advance retains the same partial issuer for cleanup',()=>{
  const issue={},f=fixture({advanceIssue:issue});
  assert.throws(()=>f.owner.callback(),error=>error.cause===issue);
  assert.strictEqual(f.owner.issuer(),f.issuer);assert.equal(f.owner.sealed(),false);
  assert.deepEqual(f.events,['capture','count','start','advance']);
});

test('original Model observation uses the existing finite work bound without an unbounded completion loop',()=>{
  const f=fixture({neverComplete:true});
  assert.throws(()=>f.owner.callback(),/InstalledComposedInferOriginalObservationUnavailable/);
  assert.strictEqual(f.owner.issuer(),f.issuer);assert.equal(f.owner.sealed(),false);
  assert.equal(f.events.filter(value=>value==='advance').length,4);
});

test('original Model observation rejects missing or malformed call inventory without issuing metadata',()=>{
  for(const count of [undefined,-1,129,1.5]) {
    const f=fixture({count});
    assert.throws(()=>f.owner.callback(),/InstalledComposedInferOriginalObservationUnavailable/);
    assert.equal(f.events.includes('start'),false);assert.equal(f.owner.sealed(),false);
  }
});

test('legacy composed completion retains its existing later observation issuance',()=>{
  const f=fixture({legacy:true});
  assert.equal(f.owner.callback(),true);
  assert.deepEqual(f.events,['capture']);assert.equal(f.owner.issuer(),undefined);
});

// Actual callback/helper, two distinct original children. Explicit issuer ports
// prove ordering and retention only, not the Common ABI or parent admission.
test('multi original observation seals once at the last retained component before handoff',()=>{
  const events=[],issued={},children=Array.from({length:2},(_,index)=>({
    operation:{index},capture:{retainCompleted(){events.push(`retain${index}`);return true;},
      completedCallCount(){events.push(`count${index}`);return index+1;}}}));
  let starts=0,advances=0;
  const context={children,child:children[0],originalPreparation:{},completeOriginal:true,moon:{
    clientProgramAdvanceInferObservationIssuance(original,quantum){
      assert.strictEqual(original,issued);assert.equal(quantum,1);advances++;
      return {$tag:1,_0:{_0:advances===5,_1:BigInt(advances)}};
    }},startCompleteInferObservation(options){
      assert.deepEqual(options.operations,children.map(child=>child.operation));
      assert.equal(options.ledger,undefined);assert.deepEqual(
        [options.maxSlots,options.maxWireBytes,options.maxWork],[3,16384,5]);
      starts++;return issued;
    }};
  // Keep the same helper state while selecting each actual original child.
  const run=compileFunction(`
    const {children,originalPreparation,moon,startCompleteInferObservation,completeOriginal}=context;
    let issuance,issuanceComplete=false,publicationOwner;
    ${source.slice(declaration.start,declaration.end)}
    return {complete:retainCompleted,sealed:()=>issuanceComplete};`,['context','checked','runtimeField'])(context,checked,runtimeField);
  assert.equal(run.complete(children[0]),true);assert.equal(run.sealed(),false);
  assert.deepEqual(events,['retain0']);assert.equal(starts,0);
  assert.equal(run.complete(children[1]),true);assert.equal(run.sealed(),true);
  assert.deepEqual(events,['retain0','retain1','count0','count1']);
  assert.equal(starts,1);assert.equal(advances,5);
  assert.equal(run.complete(children[0]),true);assert.equal(starts,1);
});
