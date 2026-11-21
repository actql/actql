import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import type {AnyNode, AssignmentExpression, ConditionalExpression, Identifier, Property, VariableDeclarator} from 'acorn';

type JournalView = {
  assertCurrent?(): void;
  close(): {pending: boolean};
  openRequestJournal?(directory: string, options: object): object;
  admitRootFormat?(root: string): object;
};
type Preparation = {
  prepareHostJournal(): Promise<JournalView>;
  openRequestJournal(directory: string, options: object): object;
  admitRootFormat(root: string): object;
};

const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes: AnyNode[]=[];
function collect(node: unknown){
  if(node===null||typeof node!=='object')return;nodes.push(node as AnyNode);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const method=(name: string)=>{
  const found=nodes.filter((node): node is Property=>node.type==='Property'&&node.method&&(node.key as Identifier).name===name);
  assert.equal(found.length,1);return source.slice(found[0].start,found[0].end);
};
const make=compileFunction(`
  let hostJournal,hostJournalClose,hostJournalOpen,hostJournalOwnership,hostJournalFlight;
  let hostJournalAdmitRootFormat;
  let hostJournalOpenAttempted=false;
  const record={};return {${method('prepareHostJournal')},${method('openRequestJournal')},
    ${method('admitRootFormat')}};`,
  ['originals','prepareHostJournalInstallation','assertInitialControlHostPreparation','clientOperationError']) as
  (original: object, prepare: (original: object) => JournalView,
    assertCurrent: (original: object) => void, error: (code: string) => Error) => Preparation;
const failure=(code: string)=>Object.assign(new Error(code),{code});
function fixture(view: JournalView){
  const original=Object.freeze({}),observed: string[]=[];
  const preparation=make(original,value=>{assert.strictEqual(value,original);return view;},
    value=>{assert.strictEqual(value,original);observed.push('current');},failure);
  return {preparation,observed};
}

// The actual Host factory/consumer statements with explicit stopping facility
// ports. These counters do not supply native SQLite capacity or an issuer.
test('selected Journal uses the captured original factory and receiver exactly once',async()=>{
  let calls=0,replacements=0;
  const journal={},options={},view={assertCurrent(){},close(){return {pending:false};},
    openRequestJournal(directory: string,actual: object){assert.strictEqual(this,view);
      assert.equal(directory,'/original/requests');assert.strictEqual(actual,options);calls++;return journal;}};
  const f=fixture(view);await f.preparation.prepareHostJournal();
  view.openRequestJournal=()=>{replacements++;return {};};
  assert.strictEqual(f.preparation.openRequestJournal('/original/requests',options),journal);
  assert.throws(()=>f.preparation.openRequestJournal('/original/requests',options),
    {code:'HostJournalPreparationUnavailable'});
  assert.equal(calls,1);assert.equal(replacements,0);
});

test('failed selected Journal construction retains its attempt without fallback or replacement',async()=>{
  let calls=0;const original=new Error('OriginalPartialNativeOpen');
  const f=fixture({assertCurrent(){},close(){return {pending:false};},
    openRequestJournal(){calls++;throw original;}});
  assert.throws(()=>f.preparation.openRequestJournal('/original/requests',{}),
    {code:'HostJournalPreparationUnavailable'});
  await f.preparation.prepareHostJournal();
  assert.throws(()=>f.preparation.openRequestJournal('/original/requests',{}),error=>error===original);
  assert.throws(()=>f.preparation.openRequestJournal('/original/requests',{}),
    {code:'HostJournalPreparationUnavailable'});
  assert.equal(calls,1);
});

test('actual selected Host assignment awaits its original opening flight without an unselected fallback',async()=>{
  const assignments=nodes.filter((node): node is AssignmentExpression=>node.type==='AssignmentExpression'&&(node.left as Identifier).name==='journal'&&
    node.right.type==='ConditionalExpression');
  assert.equal(assignments.length,1);
  const invoke=compileFunction(`return (async()=>{let journal;${source.slice(assignments[0].start,assignments[0].end)};return journal;})();`,
    ['preparation','openClientRequestJournal','journalDirectory','journalOptions','publicationOwnership']) as
    (preparation: object | undefined, open: (directory: string, options: object, owner: object) => object,
      directory: string, options: object, owner: object) => Promise<unknown>;
  const options={},journal={},owner={};let selected=0,ordinary=0;
  const open=(directory: string,actual: object,ownership: object)=>{assert.equal(directory,'/original/requests');
    assert.strictEqual(actual,options);assert.strictEqual(ownership,owner);ordinary++;return journal;};
  let release: () => void;
  const preparation={openRequestJournal(directory: string,actual: object){assert.strictEqual(this,preparation);
    assert.equal(directory,'/original/requests');assert.strictEqual(actual,options);selected++;
    return new Promise(resolve=>{release=()=>resolve(journal);});}};
  let returned=false;
  const pending=invoke(preparation,open,'/original/requests',options,owner).then(value=>{returned=true;return value;});
  assert.equal(returned,false);
  assert.equal(selected,1);assert.equal(ordinary,0);
  release!();
  assert.strictEqual(await pending,journal);
  assert.strictEqual(await invoke(undefined,open,'/original/requests',options,owner),journal);
  assert.equal(ordinary,1);
  await assert.rejects(invoke({},open,'/original/requests',options,owner),TypeError);
  assert.equal(ordinary,1);
});

test('selected Host retains its original root-format receiver before later current checks',async()=>{
  const result={},failure=new Error('OriginalRootFormatPending');let calls=0,replaced=0;
  const view: JournalView={close(){return {pending:false};},admitRootFormat(root: string){
    assert.strictEqual(this,view);assert.equal(root,'/original');calls++;throw failure;
  },assertCurrent(){view.admitRootFormat=()=>{replaced++;return result;};}};
  const f=fixture(view);await f.preparation.prepareHostJournal();
  assert.throws(()=>f.preparation.admitRootFormat('/original'),error=>error===failure);
  assert.equal(calls,1);assert.equal(replaced,0);
});

test('missing selected root-format port refuses without an unselected fallback',async()=>{
  const f=fixture({assertCurrent(){},close(){return {pending:false};}});
  await f.preparation.prepareHostJournal();
  assert.throws(()=>f.preparation.admitRootFormat('/original'),
    {code:'HostJournalPreparationUnavailable'});
});

test('actual root-format choice awaits the selected original and preserves the unprepared path',async()=>{
  const choices=nodes.filter((node): node is VariableDeclarator & {init: ConditionalExpression}=>
    node.type==='VariableDeclarator'&&(node.id as Identifier).name==='rootCreation'&&
    node.init?.type==='ConditionalExpression'&&node.init.alternate.type==='AwaitExpression'&&
    source.slice(node.init.alternate.start,node.init.alternate.end)==='await preparation.admitRootFormat(root)');
  assert.equal(choices.length,1);
  const invoke=compileFunction(`return (async()=>(${source.slice(choices[0].init.start,choices[0].init.end)}))();`,
    ['preparation','admitHostRootFormat','root']) as
    (preparation: object | undefined, ordinary: (root: string) => object, root: string) => Promise<unknown>;
  let selected=0,ordinary=0,release: () => void,done=false;
  const ordinaryResult={},selectedResult={};
  const old=(root: string)=>{assert.equal(root,'/original');ordinary++;return ordinaryResult;};
  const preparation={admitRootFormat(root: string){assert.strictEqual(this,preparation);
    assert.equal(root,'/original');selected++;return new Promise<object>(resolve=>{release=()=>resolve(selectedResult);});}};
  const flight=invoke(preparation,old,'/original').then(result=>{done=true;return result;});
  assert.equal(selected,1);assert.equal(ordinary,0);assert.equal(done,false);
  release!();assert.strictEqual(await flight,selectedResult);assert.equal(done,true);
  assert.strictEqual(await invoke(undefined,old,'/original'),ordinaryResult);assert.equal(ordinary,1);
  await assert.rejects(invoke({},old,'/original'),TypeError);
  assert.equal(ordinary,1);
});
