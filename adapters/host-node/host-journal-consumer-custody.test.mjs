import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';

const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function collect(node){
  if(node===null||typeof node!=='object')return;
  nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const methods=nodes.filter(node=>node.type==='Property'&&node.method&&
  node.key.name==='prepareHostJournal');
const controls=nodes.filter(node=>node.type==='VariableDeclarator'&&
  node.id.name==='initialControl'&&node.init?.type==='CallExpression'&&
  source.slice(node.start,node.end).includes('hostJournal'));
assert.equal(methods.length,1);assert.equal(controls.length,1);
const make=compileFunction(`
  let hostJournal,hostJournalClose,hostJournalOpen,hostJournalOwnership,hostJournalFlight,observedClose;
  let sourceManaged=input.source,sourceManagedClose=input.source?.close;
  let control={},controlClose=input.controlClose,originals=input.originals;
  let originalInstallation={},duty;
  const record={},adopted=true,host={};
  const profiles={retirePreparation(){throw Error('AlreadyAdoptedFixture');}};
  const retirePreparationReferences=input.retire;
  const initialControl=${source.slice(controls[0].init.start,controls[0].init.end)};
  const preparation={${source.slice(methods[0].start,methods[0].end)}};
  return {preparation,initialControl,held:()=>record.hostJournal};`,
  ['input','prepareHostJournalInstallation','assertInitialControlHostPreparation',
    'clientOperationError']);

// Exact actual Host consumer/lifecycle statements, with explicit stopping
// supplier/child ports. These tests issue no SQLite facility or resource grant.
function fixture({view,source:child,prepare,retire=()=>{},controlClose=()=>({pending:false})}){
  const originals=Object.freeze({}),input={source:child,originals,retire,controlClose};
  let prepares=0;
  const f=make(input,held=>{assert.strictEqual(held,originals);prepares++;
    return prepare===undefined?view:prepare();},held=>assert.strictEqual(held,originals),
    code=>Object.assign(new Error(code),{code}));
  return {...f,prepares:()=>prepares};
}

test('actual Host awaits the Journal facility after subject retention and before first root-format I/O',()=>{
  const host=ast.body.map(node=>node.declaration??node).find(node=>
    node.type==='FunctionDeclaration'&&node.id.name==='openInstalledHost');
  const statements=host.body.body.find(node=>node.type==='TryStatement').block.body;
  const held=statements.findIndex(node=>source.slice(node.start,node.end)
    .includes('preparation?.retainHostJournalPreparation('));
  const prepared=statements.findIndex(node=>node.type==='IfStatement'&&
    source.slice(node.start,node.end).includes('await preparation.prepareHostJournal()'));
  const written=statements.findIndex(node=>node.type==='ExpressionStatement'&&
    source.slice(node.start,node.end).startsWith('await admitHostRootFormat('));
  assert.ok(held>=0&&prepared>held&&written>prepared);
});

test('Host retains the same Journal facility before final current refusal and does not reprepare',async()=>{
  const failure=new Error('OriginalCurrentRefused');let closes=0;
  const view={assertCurrent(){assert.strictEqual(this,view);throw failure;},
    close(){assert.strictEqual(this,view);closes++;return {pending:false};}};
  const f=fixture({view});
  const first=f.preparation.prepareHostJournal();
  assert.strictEqual(f.preparation.prepareHostJournal(),first);
  await assert.rejects(first,error=>error===failure);
  assert.strictEqual(f.held(),view);assert.equal(f.prepares(),1);
  await assert.rejects(f.preparation.prepareHostJournal(),error=>error===failure);
  assert.equal((await f.initialControl.close()).pending,false);
  assert.equal(closes,1);assert.equal(f.held(),undefined);
});

test('Host captures the original Journal close before preceding Source child awaits',async()=>{
  const order=[];let release,replaced=0;
  const view={assertCurrent(){assert.strictEqual(this,view);},close(){
    assert.strictEqual(this,view);order.push('journal');return {pending:false};}};
  const child={async close(){order.push('source');await new Promise(resolve=>{release=resolve;});
    order.push('source-closed');return {pending:false};}};
  const f=fixture({view,source:child,retire:()=>order.push('retire'),
    controlClose:()=>{order.push('control');return {pending:false};}});
  await f.preparation.prepareHostJournal();
  const closing=f.initialControl.close();
  view.close=()=>{replaced++;return {pending:false};};release();
  assert.equal((await closing).pending,false);
  assert.equal(replaced,0);
  assert.deepEqual(order,['source','source-closed','journal','retire','control']);
});

test('Host Journal pending observation retains the same facility and original cleanup on retry',async()=>{
  let closes=0,replaced=0,controls=0;
  const view={assertCurrent(){},close(){closes++;return {pending:closes===1};}};
  const f=fixture({view,controlClose:()=>{controls++;return {pending:false};}});
  await f.preparation.prepareHostJournal();
  await assert.rejects(f.initialControl.close(),{code:'HostJournalInstallationCleanupPending'});
  assert.strictEqual(f.held(),view);assert.equal(controls,0);
  view.close=()=>{replaced++;return {pending:false};};
  assert.equal((await f.initialControl.close()).pending,false);
  assert.equal(closes,2);assert.equal(replaced,0);assert.equal(controls,1);
});

test('unobserved Journal close getter failure retains the original until its own cleanup can be observed',async()=>{
  let gets=0,closes=0;
  const failure=new Error('OriginalCloseGetterRefused');
  const view={assertCurrent(){},get close(){if(++gets===1)throw failure;
    return function(){assert.strictEqual(this,view);closes++;return {pending:false};};}};
  const f=fixture({view});
  await assert.rejects(f.preparation.prepareHostJournal(),error=>error===failure);
  assert.strictEqual(f.held(),view);
  assert.equal((await f.initialControl.close()).pending,false);
  assert.equal(gets,2);assert.equal(closes,1);
});
