import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {localFilesLookupExecutionPolicy, localResourceLookupExecutionPolicy, snapshotHostLookupExecutionPolicy,
  selectInstalledHostEnvironment} from './installed-host-policy.mjs';

import {LOCAL_FILES_DEFAULT_LIMITS} from '../connectors/local/host/installed-project-files.mjs';

// Execute the actual finite Host projection with explicit nominal-Owner ports.
// This is not a public Host, Common execution, backing or permission fixture.
const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function visit(node){
  if(node===null||typeof node!=='object')return;
  nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(visit);
    else if(value!==null&&typeof value==='object')visit(value);
  }
}
visit(ast);
const choice=nodes.filter(node=>node.type==='VariableDeclarator'&&node.id.name==='selectedLookupPolicy');
assert.equal(choice.length,1);
const choose=new Function('hostLookupExecutionPolicy','preparation','moon',
  'return '+source.slice(choice[0].init.start,choice[0].init.end));
const methods=nodes.filter(node=>node.type==='Property'&&node.method&&node.key.name==='localFilesLookupExecutionPolicy');
assert.equal(methods.length,1);
const method=methods[0].value;
function hostProjection({moon,projectSourcePreparation,mockPreparation,sourceManaged,originals,assertCurrent}){
  return new Function('moon','projectSourcePreparation','mockPreparation','sourceManaged','originals',
    'assertSourceManagedInstallationCurrent','clientOperationError','localFilesLookupExecutionPolicy',
    'localResourceLookupExecutionPolicy','LOCAL_FILES_DEFAULT_LIMITS',
    'return function'+source.slice(method.start,method.end))(
      moon,projectSourcePreparation,mockPreparation,sourceManaged,originals,assertCurrent,
      code=>Object.assign(new Error(code),{code}),localFilesLookupExecutionPolicy,
      localResourceLookupExecutionPolicy,LOCAL_FILES_DEFAULT_LIMITS);
}
const limits={maxFiles:1000,maxPages:64,maxPageBytes:1048576,maxDurationMs:30000};

test('ordinary Local finite lookup policy covers declared keys and pages without claiming capacity or retries',()=>{
  const value=localFilesLookupExecutionPolicy([limits]);
  assert.deepEqual(value,{version:'actql-lookup-execution-policy/0.1',
    max_network_attempts_per_request:1,max_request_bytes_per_attempt:1048576,
    max_total_request_bytes:67108864000,max_total_response_bytes:67108864000,
    max_total_decoded_response_bytes:67108864000,max_total_duration_ms:30000});
  assert(Object.isFrozen(value));
  assert.strictEqual(snapshotHostLookupExecutionPolicy(value),value);
  assert.equal(value.Account,undefined);assert.equal(value.cleanup,undefined);
});

test('Local lookup arithmetic stays exact and refuses invalid or unrepresentable service bounds before selection',()=>{
  for(const value of [[],Array(129).fill(limits),[undefined],[{...limits,maxFiles:0}],
    [{...limits,maxPages:-1}],[{...limits,maxPageBytes:1.5}],
    [{...limits,maxFiles:2147483647,maxPages:2147483647,maxPageBytes:2147483647}]]){
    assert.throws(()=>localFilesLookupExecutionPolicy(value),TypeError);
  }
  let reads=0;
  assert.throws(()=>localFilesLookupExecutionPolicy([{...limits,get maxFiles(){reads++;return 1000;}}]),TypeError);
  assert.equal(reads,0);
  const second={maxFiles:2,maxPages:2,maxPageBytes:100,maxDurationMs:40000};
  assert.deepEqual(localFilesLookupExecutionPolicy([limits,second]),
    {...localFilesLookupExecutionPolicy([limits]),max_total_duration_ms:40000});
});

test('actual Host default selection retains the same Project Source receiver runtime and current original',()=>{
  const policyOriginal={};
  const moon={clientLocalResourcePolicyOriginal:()=>policyOriginal,
    clientLocalPreparationResourceLimits:original=>original===policyOriginal ? [1,1,1,100000000000n,1,1] : []},
    sourceManaged={},originals={},bundle={sources:[{limits}]};
  let current=true,observed=0;
  const projectSourcePreparation={originalsForRuntime(runtime){
    assert.strictEqual(this,projectSourcePreparation);assert.strictEqual(runtime,moon);observed++;return bundle;
  }};
  const project=hostProjection({moon,sourceManaged,originals,projectSourcePreparation,
    assertCurrent(manager,value){assert.strictEqual(manager,sourceManaged);assert.strictEqual(value,originals);
      if(!current)throw new Error('OriginalProjectChanged');}});
  assert.deepEqual(project(moon),localFilesLookupExecutionPolicy([limits]));assert.equal(observed,1);
  current=false;assert.throws(()=>project(moon),/OriginalProjectChanged/u);assert.equal(observed,1);
  assert.throws(()=>project({}),{code:'ForeignInstalledProjectSourcePreparation'});assert.equal(observed,1);
});

test('unselected and Mock Hosts keep missing lookup policy distinct without reading a Local source',()=>{
  const moon={};
  for(const selected of [{projectSourcePreparation:undefined},
    {projectSourcePreparation:{},mockPreparation:{}}]){
    const project=hostProjection({moon,...selected,assertCurrent(){assert.fail('No Local source selected');}});
    assert.equal(project(moon),undefined);
  }
  assert.equal(choose(undefined,undefined,moon),undefined);
  assert.equal(snapshotHostLookupExecutionPolicy(undefined),undefined);
});

test('explicit valid Host lookup policy wins and explicit refusal cannot become an omitted default',()=>{
  const moon={},policy=localFilesLookupExecutionPolicy([limits]);let defaults=0;
  const preparation={localFilesLookupExecutionPolicy(runtime){assert.strictEqual(runtime,moon);defaults++;return policy;}};
  assert.strictEqual(choose(undefined,preparation,moon),policy);assert.equal(defaults,1);
  const explicit=snapshotHostLookupExecutionPolicy({...policy,max_total_decoded_response_bytes:1});
  assert.strictEqual(choose(explicit,preparation,moon),explicit);assert.equal(defaults,1);
  for(const invalid of [null,{},[],{...policy,max_network_attempts_per_request:0}]){
    assert.throws(()=>choose(snapshotHostLookupExecutionPolicy(invalid),preparation,moon),
      {code:'InvalidInstalledHostLookupExecutionPolicy'});
  }
  assert.equal(defaults,1);
});

test('selected lookup limits enter the same canonical Environment without changing generic absence',()=>{
  const base={version:'actql-check-environment/0.1',host_policy_profile:{capacity:{original:true}},
    evidence_bundle_cid:'sha256:'+'a'.repeat(64)};
  const wire=JSON.stringify(base),policy=localFilesLookupExecutionPolicy([limits]);let admitted;
  const moon={clientProgramCheckEnvironment(value,cid){admitted=JSON.parse(value);
    assert.equal(admitted.evidence_bundle_cid,cid);return {};}};
  assert.strictEqual(selectInstalledHostEnvironment(moon,wire,undefined,undefined),wire);
  assert.equal(admitted,undefined);
  const selected=JSON.parse(selectInstalledHostEnvironment(moon,wire,undefined,policy));
  assert.deepEqual(selected.host_policy_profile.lookup_execution,policy);
  assert.deepEqual(selected.host_policy_profile.capacity,base.host_policy_profile.capacity);
  assert.notEqual(selected.evidence_bundle_cid,base.evidence_bundle_cid);
});


test('normal and declared Local sources share explicit service policy and nominal transfer narrowing',()=>{
  const policyOriginal={}, moon={clientLocalResourcePolicyOriginal:()=>policyOriginal,
    clientLocalPreparationResourceLimits:original=>original===policyOriginal ? [1,1,1,12345n,1,1] : []};
  const projectSourcePreparation={originalsForRuntime:()=>({sources:[{limits:LOCAL_FILES_DEFAULT_LIMITS}]})};
  const mockPreparation={originalsForRuntime:()=>({physicalKind:'declared-json-document',sources:[]})};
  const common={moon,sourceManaged:{},originals:{},assertCurrent(){}};
  const normal=hostProjection({...common,projectSourcePreparation})(moon);
  const declared=hostProjection({...common,mockPreparation})(moon);
  assert.deepEqual(normal,declared);
  const explicit=localFilesLookupExecutionPolicy([LOCAL_FILES_DEFAULT_LIMITS]);
  assert.deepEqual(normal,{...explicit,max_total_response_bytes:12345});
  assert.equal(normal.max_total_decoded_response_bytes,explicit.max_total_decoded_response_bytes);
  assert.equal(normal.max_total_request_bytes,explicit.max_total_request_bytes);
  assert.equal(normal.max_total_duration_ms,explicit.max_total_duration_ms);
  assert.throws(()=>localResourceLookupExecutionPolicy(moon,{},explicit),/InvalidInstalledHostCapacityPolicy/);
  assert.equal(localResourceLookupExecutionPolicy(moon,{},undefined),undefined);
});

test('declared Local policy requires the exact selected nominal preparation and currentness',()=>{
  const policyOriginal={},moon={clientLocalResourcePolicyOriginal:()=>policyOriginal,
    clientLocalPreparationResourceLimits:()=>[1,1,1,100000000000n,1,1]};
  let current=true,reads=0;
  const mockPreparation={originalsForRuntime(runtime){assert.equal(this,mockPreparation);
    assert.equal(runtime,moon);reads++;return {physicalKind:'declared-json-document'};}};
  const projection=hostProjection({moon,mockPreparation,sourceManaged:{},originals:{},
    assertCurrent(){if(!current)throw Error('RetiredOriginal');}});
  assert.ok(projection(moon));assert.equal(reads,1);
  current=false;assert.throws(()=>projection(moon),/RetiredOriginal/);assert.equal(reads,1);
  assert.throws(()=>projection({}),/ForeignInstalledProjectSourcePreparation/);
});
