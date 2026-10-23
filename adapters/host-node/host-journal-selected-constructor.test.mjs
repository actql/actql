import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';

const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function collect(node){
  if(node===null||typeof node!=='object')return;nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const method=name=>{
  const found=nodes.filter(node=>node.type==='Property'&&node.method&&node.key.name===name);
  assert.equal(found.length,1);return source.slice(found[0].start,found[0].end);
};
const make=compileFunction(`
  let hostJournal,hostJournalClose,hostJournalOpen,hostJournalOwnership,hostJournalFlight;
  let hostJournalAdmitRootFormat;
  let hostJournalOpenAttempted=false;
  const record={};return {${method('prepareHostJournal')},${method('openRequestJournal')},
    ${method('admitRootFormat')}};`,
  ['originals','prepareHostJournalInstallation','assertInitialControlHostPreparation','clientOperationError']);
const failure=code=>Object.assign(new Error(code),{code});
function fixture(view){
  const original=Object.freeze({}),observed=[];
  const preparation=make(original,value=>{assert.strictEqual(value,original);return view;},
    value=>{assert.strictEqual(value,original);observed.push('current');},failure);
  return {preparation,observed};
}

// The actual Host factory/consumer statements with explicit stopping facility
// ports. These counters do not supply native SQLite capacity or an issuer.
test('selected Journal uses the captured original factory and receiver exactly once',async()=>{
  let calls=0,replacements=0;
  const journal={},options={},view={assertCurrent(){},close(){return {pending:false};},
    openRequestJournal(directory,actual){assert.strictEqual(this,view);
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
  const assignments=nodes.filter(node=>node.type==='AssignmentExpression'&&node.left.name==='journal'&&
    node.right.type==='ConditionalExpression');
  assert.equal(assignments.length,1);
  const invoke=compileFunction(`return (async()=>{let journal;${source.slice(assignments[0].start,assignments[0].end)};return journal;})();`,
    ['preparation','openClientRequestJournal','journalDirectory','journalOptions']);
  const options={},journal={};let selected=0,ordinary=0;
  const open=(directory,actual)=>{assert.equal(directory,'/original/requests');
    assert.strictEqual(actual,options);ordinary++;return journal;};
  let release;
  const preparation={openRequestJournal(directory,actual){assert.strictEqual(this,preparation);
    assert.equal(directory,'/original/requests');assert.strictEqual(actual,options);selected++;
    return new Promise(resolve=>{release=()=>resolve(journal);});}};
  let returned=false;
  const pending=invoke(preparation,open,'/original/requests',options).then(value=>{returned=true;return value;});
  assert.equal(returned,false);
  assert.equal(selected,1);assert.equal(ordinary,0);
  release();
  assert.strictEqual(await pending,journal);
  assert.strictEqual(await invoke(undefined,open,'/original/requests',options),journal);
  assert.equal(ordinary,1);
  await assert.rejects(invoke({},open,'/original/requests',options),TypeError);
  assert.equal(ordinary,1);
});

test('selected Host retains its original root-format receiver before later current checks',async()=>{
  const result={},failure=new Error('OriginalRootFormatPending');let calls=0,replaced=0;
  const view={close(){return {pending:false};},admitRootFormat(root){
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
  const choices=nodes.filter(node=>node.type==='IfStatement'&&
    node.test.type==='BinaryExpression'&&
    source.slice(node.start,node.end).includes('await preparation.admitRootFormat(root)'));
  assert.equal(choices.length,1);
  const invoke=compileFunction(`return (async()=>{${source.slice(choices[0].start,choices[0].end)}})();`,
    ['preparation','admitHostRootFormat','root']);
  let selected=0,ordinary=0,release,done=false;
  const old=root=>{assert.equal(root,'/original');ordinary++;};
  const preparation={admitRootFormat(root){assert.strictEqual(this,preparation);
    assert.equal(root,'/original');selected++;return new Promise(resolve=>{release=resolve;});}};
  const flight=invoke(preparation,old,'/original').then(()=>{done=true;});
  assert.equal(selected,1);assert.equal(ordinary,0);assert.equal(done,false);
  release();await flight;assert.equal(done,true);
  await invoke(undefined,old,'/original');assert.equal(ordinary,1);
  await assert.rejects(invoke({},old,'/original'),TypeError);
  assert.equal(ordinary,1);
});
