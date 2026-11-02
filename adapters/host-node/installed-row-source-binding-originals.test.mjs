import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';

// Exact original binding/current/close statements with explicit Core/Account
// ports. These counts are completed calls and real canonical SHA work at this
// boundary, not Common admission, provider I/O or public latency evidence.
const source = await readFile(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const create = ast.body.find(node => node.declaration?.id?.name === 'createInstalledRowSource').declaration;
const slice = node => source.slice(node.start, node.end);
function nodes(root, matches) {
  const found = [];
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (matches(node)) found.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  }
  visit(root);return found;
}
function one(root, matches) {const found = nodes(root, matches);assert.equal(found.length, 1);return found[0];}
const functionBody = name => slice(one(ast, node => node.type === 'FunctionDeclaration' && node.id?.name === name));
const variable = name => 'const ' + slice(one(create, node => node.type === 'VariableDeclarator' && node.id?.name === name)) + ';';
const setupIndex = create.body.body.findIndex(node => node.declarations?.some(value => value.id.name === 'immutableTargets'));
assert(setupIndex >= 0);
const setup = create.body.body.slice(setupIndex, setupIndex + 3).map(slice).join('\n');
assert.match(setup, /physicalTarget = immutableTargets.prepare/u);
assert.match(setup, /let physicalTargetGeneration/u);
const ownerInsertion = slice(one(create, node => node.type === 'CallExpression' &&
  node.callee.type === 'MemberExpression' && node.callee.object.name === 'preparations' && node.callee.property.name === 'set')) + ';';
const installed = one(create, node => node.type === 'VariableDeclarator' && node.id?.name === 'installedSource');
const close = installed.init.arguments[0].properties.find(node => node.key?.name === 'close');assert(close);
const compile = new Function('physicalTarget', 'ports', 'nodeTypes', 'checked', 'validInstallationBinding',
  'checkpointApprovalFacts', 'canonicalJson', 'createHash', `
const counts={bindingGenerations:0,bindingHashes:0,subjectHashes:0,targetReads:0,authorizations:0,completedChecks:0,
 readerRetirements:0,siteCloses:0,constructionCloses:0};
const fail=code=>{throw Object.assign(new Error(code),{code});};
const text=value=>typeof value==='string'&&value.length>0;
const cidPattern=/^sha256:[0-9a-f]{64}$/u;
const valueCid=value=>{counts.bindingHashes++;return 'sha256:'+createHash('sha256').update(canonicalJson(value,{dataKeys:true})).digest('hex');};
const cid=value=>{counts.subjectHashes++;return 'sha256:'+createHash('sha256').update(canonicalJson(value)).digest('hex');};
${functionBody('prepareImmutablePhysicalTargets')}
${setup}
const originalTarget=physicalTarget;
physicalTarget=(resource,fields)=>{counts.bindingGenerations++;return originalTarget(resource,fields);};
const declaration={},requirement={},acquisition={},preparations=new WeakMap();
const installationBinding=Object.freeze({connectorId:'original',connectorRegistration:'fixture',
 connectorRevision:'fixture/0.1',bindingCid:'sha256:'+'a'.repeat(64)});
const state={resource:'records',fields:['id','score'],wholeInput:ports.wholeInput===true,retireAllowed:true};
const site={connection:'fixture:records',close(){counts.siteCloses++;return ports.siteClose?.();}};
const authorization={async authorize(boundary,tuple,options){counts.authorizations++;
 assert.equal(boundary,'acquisition');assert.equal(tuple.connection,'fixture:records');
 if(options.signal)options.signal.throwIfAborted();
 return await (ports.authorize?.({state,site,tuple,options})??{action:'dispatch'});}};
const sourceAccess={authorization,connection:site.connection};
const directReadIdentity=undefined;
const moon={clientProgramRowSourceTarget(actual,selected){assert.equal(actual,declaration);assert.equal(selected,requirement);
 counts.targetReads++;return {$tag:1,_0:[state.resource,...state.fields]};},
 clientProgramWholeSourceTarget(actual){assert.equal(actual,acquisition);counts.targetReads++;return [state.resource,...state.fields];}};
${functionBody('ordinaryRecoveryBinding')}
${variable('ordinarySubject')}
${variable('decideRead')}
${variable('currentRead')}
function initial(){
 const resource=state.resource,fields=[...state.fields],access=sourceAccess,wholeInput=state.wholeInput;
 const checkedOwner={},effectful=false,occurrence=Object.freeze({stage:0,input:0,task:0});
 const providerCaptureCapacity=undefined,originalRead=undefined,managedRun=undefined;
 const prepared=Object.freeze({checkedSource:Object.freeze({requirementCid:'sha256:'+'b'.repeat(64)}),
  readTuple:Object.freeze({connection:site.connection,resource,operation:'read'}),physicalBinding:physicalTarget(resource,fields)});
 const physicalBindingCid=valueCid(prepared.physicalBinding);
 ${ownerInsertion}
 ordinaryRecoveryBinding(prepared);return prepared;
}
const preparingSourceReads=new Set();
let originalReader=ports.readerRetirement?{receiver:{},retire(){counts.readerRetirements++;return state.retireAllowed;}}:undefined;
const sourceInitialization=ports.sourceInitialization?{}:undefined;
let constructionClosed=false,acquisitionContracts={};
function closeInstalledSourceConstruction(actual,owner){assert.equal(actual,sourceInitialization);assert.equal(owner,installedSource);counts.constructionCloses++;}
const installedSource=Object.freeze({${slice(close)}});
return {inventoryOriginal:immutableTargets?.inventory,initial,state,site,counts,ordinaryRecoveryBinding,close:()=>installedSource.close(),
 async verify(prepared,signal){const result=await currentRead(prepared,sourceAccess,signal);counts.completedChecks++;return result;}};
`.replaceAll('assert.', 'ports.assert.'));

const wire = value => canonicalJson(value, {dataKeys: true});
const hash = value => 'sha256:' + createHash('sha256').update(wire(value)).digest('hex');
const targetData = Object.freeze({connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
  catalogCid: 'sha256:' + 'c'.repeat(64), originalStringsCid: 'sha256:' + 'd'.repeat(64),
  origin: 'https://fixture.invalid', path: 'e\u0301/%2F', resource: 'records', fields: Object.freeze(['id', 'score'])});
const inventory = () => Object.freeze([targetData]);
const legacyTarget = (resource, fields) => Object.freeze({...targetData, resource, fields: Object.freeze([...fields])});
function fixture(input = inventory(), ports = {}) {
  return compile(input, {...ports, assert}, nodeTypes, checked, validInstallationBinding,
    checkpointApprovalFacts, canonicalJson, createHash);
}

test('standard target snapshot retains complete original wire/CID and ordered fields', async () => {
  const f = fixture(), prepared = f.initial();
  assert.equal(wire(prepared.physicalBinding), wire(legacyTarget('records', ['id', 'score'])));
  assert.equal(hash(prepared.physicalBinding), hash(legacyTarget('records', ['id', 'score'])));
  assert(Object.isFrozen(prepared.physicalBinding));assert(Object.isFrozen(prepared.physicalBinding.fields));
  assert.equal(prepared.physicalBinding.path, 'e\u0301/%2F');
  await f.verify(prepared);assert.equal(f.counts.completedChecks, 1);
});

test('same immutable binding removes generation/hash work without removing Account or Core target observations', async t => {
  for (const wholeInput of [false, true]) {
    const fast = fixture(inventory(), {wholeInput}), full = fixture(legacyTarget, {wholeInput});
    const original = fast.initial(), custom = full.initial();
    for (let index = 0; index < 10; index++) {await fast.verify(original);await full.verify(custom);}
    assert.deepEqual([fast.counts.completedChecks, fast.counts.authorizations, fast.counts.targetReads], [10, 10, 21]);
    assert.deepEqual([full.counts.completedChecks, full.counts.authorizations, full.counts.targetReads], [10, 10, 21]);
    assert.deepEqual([fast.counts.bindingGenerations, fast.counts.bindingHashes], [1, 1]);
    assert.deepEqual([full.counts.bindingGenerations, full.counts.bindingHashes], [22, 43]);
    assert.equal(fast.counts.subjectHashes, 10);assert.equal(full.counts.subjectHashes, 10);
    t.diagnostic(JSON.stringify({wholeInput, immutable: fast.counts, callback: full.counts,
      countScope: 'Selected physicalTarget calls and valueCid hashes, plus separate Account/Core-port observations; installation inventory copies excluded',
      qualification: 'Explicit Core/Account ports; not Common admission work, provider I/O, CPU partition or latency'}));
  }
});

test('frozen callback target still performs full checks and detects mutable closure changes', async () => {
  let generation = 'one';
  const f = fixture((resource, fields) => Object.freeze({...legacyTarget(resource, fields), generation}));
  const original = f.initial();await f.verify(original);generation = 'two';
  await assert.rejects(f.verify(original), {code: 'InstalledSourcePreparationMismatch'});
  assert.equal(f.counts.authorizations, 1);assert.equal(f.counts.completedChecks, 1);
  assert(f.counts.bindingGenerations > 1);assert(f.counts.bindingHashes > 1);
});

test('immutable targets retain actual next-operation Deny and cancellation', async () => {
  let allowed = true;
  const f = fixture(inventory(), {authorize: () => ({action: allowed ? 'dispatch' : 'deny'})}), original = f.initial();
  await f.verify(original);allowed = false;
  await assert.rejects(f.verify(original), {code: 'ExecutionAuthorizationDenied'});
  const controller = new AbortController();controller.abort();
  await assert.rejects(f.verify(original, controller.signal), {name: 'AbortError'});
  assert.equal(f.counts.authorizations, 3);assert.equal(f.counts.completedChecks, 1);
  assert.equal(f.counts.bindingGenerations, 1);assert.equal(f.counts.bindingHashes, 1);
});

test('fresh exact Core target and connection are checked again after authorization awaits', async () => {
  for (const change of [({state}) => {state.fields = ['score', 'id'];},
    ({state}) => {state.resource = 'foreign';}, ({site}) => {site.connection = 'foreign';}]) {
    const f = fixture(inventory(), {authorize: async original => {await Promise.resolve();change(original);return {action: 'dispatch'};}});
    await assert.rejects(f.verify(f.initial()), {code: 'InstalledSourcePreparationMismatch'});
    assert.equal(f.counts.authorizations, 1);assert.equal(f.counts.targetReads, 3);assert.equal(f.counts.completedChecks, 0);
  }
});

test('authorization callback reentry into original close invalidates immutable selection before dispatch returns', async () => {
  let f;
  f=fixture(inventory(),{sourceInitialization:true,authorize:async()=>{
    await f.close();return{action:'dispatch'};
  }});
  await assert.rejects(f.verify(f.initial()),{code:'InstalledSourcePreparationMismatch'});
  assert.equal(f.counts.authorizations,1);assert.equal(f.counts.completedChecks,0);
  assert.equal(f.counts.siteCloses,1);assert.equal(f.counts.constructionCloses,1);
});

test('copied/restored Prepared and another installation cannot reuse original target custody', async () => {
  const f = fixture(), original = f.initial(), other = fixture();
  assert.throws(() => f.ordinaryRecoveryBinding({...original}), {code: 'InstalledSourcePreparationMismatch'});
  assert.throws(() => f.ordinaryRecoveryBinding(JSON.parse(JSON.stringify(original))), {code: 'InstalledSourcePreparationMismatch'});
  assert.throws(() => other.ordinaryRecoveryBinding(original), {code: 'InstalledSourcePreparationMismatch'});
  assert.equal(f.counts.authorizations, 0);assert.equal(other.counts.authorizations, 0);
});

test('unbound resumed approval still requires its original complete approval facts', async () => {
  const f = fixture(inventory(), {authorize: () => ({action: 'dispatch', basis: 'resumed_approval'})});
  await assert.rejects(f.verify(f.initial()), {code: 'InstalledSourceReadApprovalMismatch'});
  assert.equal(f.counts.authorizations, 1);assert.equal(f.counts.completedChecks, 0);
});

test('retirement invalidates selection before pending physical cleanup without inventing ACK', async () => {
  const f = fixture(inventory(), {readerRetirement: true, sourceInitialization: true}), original = f.initial();
  await f.verify(original);f.state.retireAllowed = false;
  assert.throws(f.close, {code: 'InstalledSourceReaderCleanupPending'});
  await assert.rejects(f.verify(original), {code: 'InstalledSourcePreparationMismatch'});
  assert.equal(f.counts.authorizations, 1);assert.equal(f.counts.siteCloses, 0);assert.equal(f.counts.constructionCloses, 0);
  f.state.retireAllowed = true;await f.close();
  assert.equal(f.counts.readerRetirements, 2);assert.equal(f.counts.siteCloses, 1);assert.equal(f.counts.constructionCloses, 1);
  await assert.rejects(f.verify(original), {code: 'InstalledSourcePreparationMismatch'});
});

test('immutable target constructor refuses mutable/accessor/proxy and malformed DATA without invoking accessors', () => {
  let accesses = 0;
  const accessor = Object.freeze({...targetData, get path() {accesses++;throw new Error('must not read');}});
  const bad = [[], [targetData], Object.freeze([{...targetData}]), Object.freeze([accessor]),
    Object.freeze([Object.freeze({...targetData, fields: ['id']})]),
    Object.freeze([Object.freeze({...targetData, fields: Object.freeze(['id', 'id'])})]),
    Object.freeze([targetData, targetData]), Object.freeze([Object.freeze({...targetData, extra: {}})]),
    new Proxy(inventory(), {ownKeys() {accesses++;throw new Error('must not enumerate');}})];
  for (const input of bad) assert.throws(() => fixture(input), {code: 'InstalledSourcePreparationMismatch'});
  assert.equal(accesses, 0);
});


test('immutable target selection borrows the same Source inventory without a second retained snapshot',()=>{
  const input=inventory(),f=fixture(input);
  assert.equal(f.inventoryOriginal,input);assert.equal(f.inventoryOriginal[0],targetData);
  assert.equal(f.inventoryOriginal[0].fields,targetData.fields);
  const prepared=f.initial();assert.deepEqual(prepared.physicalBinding.fields,['id','score']);
});

// The exact installed Source callback below spends the real occurrence branch
// before delegating to the same current. Authority/current are explicit ports;
// this proves no Common/Host/normal funding or physical acknowledgement.
function nativeChildCaller({currentFailure = false} = {}) {
  const original = one(create, node => node.type === 'Property' && node.key?.name === 'authorizeReadChild').value;
  return Function('ports', 'nodeTypes', `
    const fail=code=>{throw Object.assign(new Error(code),{code});};
    const text=value=>typeof value==='string'&&value.length>0;
    const operation='query',prepared={},access={},signal=undefined;
    const owner={resource:'records',originalRead:{}};
    const readerDemand={responses:4,sequence:{operation:'query',maxUses:2,
      children:[{operation:'describe',maxUses:2}]}};
    const limits={maxPages:4},grant={},granted={},nonce='authored-native';
    const directReadIdentity=undefined;
    let readChildIndex=0,rootReadUses=0,propertyOccurrences=0,currentCalls=0,issues=0;
    const readChildOriginals=new WeakMap(),readChildUses=new Map(),readChildGrants=new Map();
    const site={issueReadGrant(){issues++;throw new Error('No second native grant');}};
    const currentRead=async()=>{currentCalls++;if(ports.currentFailure)throw undefined;
      return {basis:'authored-current',action:'dispatch'};};
    const invoke=${slice(original)};
    return {invoke,counts:()=>({readChildIndex,rootReadUses,currentCalls,issues,
      describes:readChildUses.get('describe')??0})};
  `)({currentFailure},nodeTypes);
}

test('installed Source native child forwards the same issued original after one occurrence and current without a second grant',async()=>{
  const f=nativeChildCaller(),occurrence=Object.freeze({});
  const supplied=Object.freeze({originalAuthorization:Object.freeze({}),authorization:Object.freeze({})});
  assert.equal(await f.invoke('describe',0,occurrence,supplied),supplied);
  assert.deepEqual(f.counts(),{readChildIndex:1,rootReadUses:0,currentCalls:1,issues:0,describes:1});
  await assert.rejects(f.invoke('describe',1,occurrence,supplied),{code:'InvalidInstalledSourceReadChild'});
  assert.deepEqual(f.counts(),{readChildIndex:1,rootReadUses:0,currentCalls:1,issues:0,describes:1});
});

test('installed Source native child current refusal keeps the consumed original occurrence and exact thrown undefined',async()=>{
  const f=nativeChildCaller({currentFailure:true}),occurrence=Object.freeze({});
  const supplied=Object.freeze({originalAuthorization:Object.freeze({}),authorization:Object.freeze({})});
  let caught=false;try{await f.invoke('describe',0,occurrence,supplied);}catch(cause){caught=true;assert.equal(cause,undefined);}
  assert.equal(caught,true);
  await assert.rejects(f.invoke('describe',1,occurrence,supplied),{code:'InvalidInstalledSourceReadChild'});
  assert.deepEqual(f.counts(),{readChildIndex:1,rootReadUses:0,currentCalls:1,issues:0,describes:1});
});

test('installed Source typed-cell caller uses the original RowRun charge once without rebuilding values',()=>{
  const original=one(create,node=>node.type==='Property'&&node.key?.name==='consumeValues').value;
  const run={},charge={},columns=Object.freeze(['id']),rows=Object.freeze([Object.freeze([Object.freeze({})])]);
  let calls=0;
  const moon={clientProgramRowSourceAcceptChargedValues(actualRun,actualCharge,actualColumns,actualRows){
    assert.equal(actualRun,run);assert.equal(actualCharge,charge);assert.equal(actualColumns,columns);assert.equal(actualRows,rows);
    calls++;return {$tag:1,_0:1};
  }};
  const callback=Function('moon','run','checked','fail',`return (${slice(original)});`)(moon,run,checked,
    code=>{throw Object.assign(new Error(code),{code});});
  assert.equal(callback(columns,rows,{charge}),1);assert.equal(calls,1);
  assert.throws(()=>callback(columns,rows,{}),{code:'InvalidInstalledSourcePageCharge'});assert.equal(calls,1);
});
