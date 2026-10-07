import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const member = 'x'.repeat(513);
const names = ['published', 'consumed_a', 'consumed_b'];
const expected = [{id:1, value:7}, {id:2, value:null}];
function program(id) {
  return {version:'actql/0.1', id, stages:[
    {id:'source', inputs:{}, steps:[{values:{schema:{
      id:{type:'number',nullable:false}, payload:{type:'object',nullable:true,
        fields:{[member]:{type:'number',nullable:false}}}},
      rows:[{id:1,payload:{[member]:7}}, {id:2,payload:null}]},as:'out'}],
      results:{rows:{from:'out',fields:['id','payload']}}},
    {id:'producer',inputs:{rows:{result:{stage:'source',result:'rows'}}},steps:[
      {derive:{value:{property:{value:{field:'payload'},name:member}}},as:'derived'},
      {select:['id','value'],as:'out'}],results:{rows:{from:'out',fields:['id','value']}}},
    ...['consumer_a','consumer_b'].map(stage=>({id:stage,
      inputs:{rows:{result:{stage:'producer',result:'rows'}}},steps:[
        {select:['id','value'],as:'out'}],results:{rows:{from:'out',fields:['id','value']}}})),
  ],results:Object.fromEntries(['producer','consumer_a','consumer_b'].map((stage,index)=>
    [names[index],{from:{stage,result:'rows'}}]))};
}

function fieldProgram(id) {
  const value=program(id);
  value.stages[0].steps[0].values={schema:{
    id:{type:'number',nullable:false},[member]:{type:'number',nullable:true}},
    rows:[{id:1,[member]:7},{id:2,[member]:null}]};
  value.stages[0].results.rows.fields=['id',member];
  value.stages[1].steps[0].derive.value={field:member};
  return value;
}

function objectProgram(id) {
  const value=program(id);
  value.stages[0].steps[0].values={schema:{
    id:{type:'number',nullable:false},payload:{type:'number',nullable:true}},
    rows:[{id:1,payload:7},{id:2,payload:null}]};
  value.stages[1].steps[0].derive.value={object:{[member]:{field:'payload'},
    [`${member}z`]:{literal:9}}};
  return value;
}
const objectExpected=[{id:1,value:{[member]:7,[`${member}z`]:9}},
  {id:2,value:{[member]:null,[`${member}z`]:9}}];
const objectContract={type:'object',nullable:false,additional_properties:false,fields:{
  [member]:{type:'number',nullable:true},[`${member}z`]:{type:'number',nullable:false}}};

const rawText='x'.repeat(1024)+'😀e\u0301\r\n';
function textObjectProgram(id) {
  const value=program(id);
  value.stages[0].steps[0].values={schema:{id:{type:'number',nullable:false},
    payload:{type:'string',nullable:true}},rows:[{id:1,payload:rawText},{id:2,payload:null}]};
  value.stages[1].steps[0].derive.value={object:{p:{field:'payload'}}};
  return value;
}
const textObjectExpected=[{id:1,value:{p:rawText}},{id:2,value:{p:null}}];
const textObjectContract={type:'object',nullable:false,additional_properties:false,
  fields:{p:{type:'string',nullable:true}}};
function textArrayProgram(id) {
  const value=textObjectProgram(id);
  // Ordered aggregation needs the Program's explicit input key proof.
  value.stages[0].steps.push({assert_rows:{unique_by:['id']},as:'keyed'});
  value.stages[0].results.rows.from='keyed';
  value.stages[1].steps[0]={group:{by:['id'],aggregates:{value:{fn:'array_agg',
    field:'payload',order_by:[{field:'id',dir:'asc',nulls:'first'}],max_items:2}}},as:'derived'};
  return value;
}
const textArrayExpected=[{id:1,value:[rawText]},{id:2,value:[]}];
const textArrayContract={type:'array',nullable:false,items:{type:'string',nullable:false}};
const aggregateDelimiter='d'.repeat(256);
function textStringProgram(id) {
  const value=textArrayProgram(id);
  value.stages[0].steps[0].values.schema.bucket={type:'number',nullable:false};
  value.stages[0].steps[0].values.rows=[{id:1,bucket:1,payload:rawText},
    {id:2,bucket:1,payload:'end'},{id:3,bucket:2,payload:null}];
  value.stages[0].results.rows.fields=['id','bucket','payload'];
  value.stages[1].steps=[
    {group:{by:['bucket'],aggregates:{value:{fn:'string_agg',field:'payload',
      order_by:[{field:'id',dir:'asc',nulls:'first'}],delimiter:aggregateDelimiter,max_bytes:4096}}},as:'aggregated'},
    {rename:{bucket:'id'},as:'renamed'},
    {select:['id','value'],as:'out'}];
  return value;
}
const textStringExpected=[{id:1,value:rawText+aggregateDelimiter+'end'},
  {id:2,value:null}];
function wideSnapshotProgram(id) {
  const value=program(id);
  const schema={id:{type:'number',nullable:false}},rows=[{id:1},{id:2}];
  // Nine total fields exceed the bounded small-row lane. Keep Values inside
  // the producer Program; no extra wide public intermediate is required.
  for(let index=0;index<8;index++){
    const name='x'.repeat(63)+String.fromCharCode(97+index);
    schema[name]={type:'number',nullable:false};
    rows[0][name]=index;rows[1][name]=index+10;
  }
  const producer=value.stages[1];
  producer.inputs={};
  producer.steps[0].derive.value={field:'id'};
  producer.steps.unshift({values:{schema,rows},as:'seed'});
  value.stages.shift();
  return value;
}

function orderedMetadataProgram(id) {
  const value=fieldProgram(id);
  value.stages[0].steps[0].values.rows=[
    {id:2,[member]:null},{id:3,[member]:7},{id:1,[member]:7}];
  // The ordinary Program supplies the key proof required for ordered take.
  value.stages[0].steps.push({assert_rows:{unique_by:['id']},as:'keyed'});
  value.stages[0].results.rows.from='keyed';
  value.stages[1].steps=[
    {sort:[{field:member,dir:'desc',nulls:'last'},{id:'asc'}],as:'ordered'},
    {take:{count:3},as:'taken'},
    {derive:{value:{field:member}},as:'derived'},
    {select:['id','value'],as:'out'}];
  return value;
}

async function verifyRetainedNames(t,label,makeProgram,rows=expected,
  valueContract={type:'number',nullable:true},producerTask=1){
    const directory=await mkdtemp(join(tmpdir(),'actql-property-name-'));
    const reached=Promise.withResolvers(),release=Promise.withResolvers();
    let client, cancelling=false, dispatches=0, advances=0, completions=0;
    t.after(async()=>{release.resolve();await client?.close();
      await rm(directory,{recursive:true,force:true});});
    const keys=generateKeyPairSync('ed25519');
    client=await connectEmbeddedLocal({mode:'local',owner:'local',installation:{
      directory,retainedRelationOutput:true,authorization:{
        accountConfiguration:canonicalJson({version:'actql-execution-account-config/0.1',
          account_id:'property-name',entries:[{entry_id:'allow',outcome:'allow',
            principal:{all:true},connection:{all:true},resource:{all:true},
            operation:{all:true},exclusions:[]}]}),
        hostKey:{keyId:'host',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
        reviewers:[{keyId:'reviewer',reviewerId:'reviewer',principalId:userInfo().username,
          publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
        observe(name,detail){if(name==='computed'){
          completions++;
          assert.ok(detail.outputRepresentations.some(entry=>entry.representation==='retained-file'));
          if(cancelling)reached.reject(new Error('property finished before progress barrier'));}},
        async faultInjection(name,detail){
          if(name==='dispatch_reserved')dispatches++;
          if(name!=='local_compute_advanced')return;
          advances++;
          if(cancelling && detail.task===producerTask && BigInt(detail.work)>0n){
            reached.resolve();await release.promise;
          }
        },
      }}});
    const source=JSON.stringify(makeProgram(`${label}-name-success`));
    const run=await client.aql(source,{format:'json',requestId:'property-name-success'});
    const status=await run.wait({signal:AbortSignal.timeout(45_000)});
    assert.equal(status.status,'succeeded',JSON.stringify(status));
    assert.deepEqual(Object.keys(status.result_availability).sort(),names.toSorted());
    for(const name of names)assert.deepEqual(await run.result(name).all(),rows);
    assert.deepEqual((await run.result('published').describe()).columns,
      [{name:'id',contract:{type:'number',nullable:false}},
        {name:'value',contract:valueContract}]);
    const count=dispatches;
    assert.deepEqual((await client.aql(source,{format:'json',requestId:'property-name-success'})).ref,run.ref);
    assert.equal(dispatches,count);
    cancelling=true;
    const cancel=await client.aql(JSON.stringify(makeProgram(`${label}-name-cancel`)),
      {format:'json',requestId:'property-name-cancel'});
    await Promise.race([reached.promise,cancel.wait({signal:AbortSignal.timeout(15_000)})
      .then(state=>{throw new Error(`property progress barrier missed: ${JSON.stringify(state)}`);})]);
    const before=advances,held=await readdir(join(directory,'carrier-snapshots'));
    try{await cancel.cancel();const pending=await cancel.status();
      assert.equal(pending.control.cancellation_requested,true);
      assert.notEqual(pending.control.physical_stop,'confirmed');
      assert.notEqual(pending.status,'cancelled');
      assert.equal(completions,1);
      assert.deepEqual(await readdir(join(directory,'carrier-snapshots')),held);
    }finally{release.resolve();}
    const stopped=await cancel.wait({signal:AbortSignal.timeout(15_000)});
    assert.equal(stopped.status,'cancelled',JSON.stringify(stopped));
    assert.equal(stopped.control.physical_stop,'confirmed');
    for(const name of names){assert.equal(stopped.result_availability[name].state,'unavailable');
      await assert.rejects(cancel.result(name).all());}
    assert.equal(completions,1);assert.equal(advances,before);assert.equal(dispatches,2);
    assert.deepEqual(await readdir(join(directory,'carrier-snapshots')),[]);
}
test('public retained property names publish NULL and deliver cancellation after progress',
  {timeout:90_000},t=>verifyRetainedNames(t,'property',program));
test('public retained field names publish NULL and deliver cancellation after progress',
  {timeout:90_000},t=>verifyRetainedNames(t,'field',fieldProgram));
test('public retained constructed object names publish NULL and deliver cancellation after progress',
  {timeout:90_000},t=>verifyRetainedNames(t,'object',objectProgram,objectExpected,objectContract));
test('public retained raw Text Object children preserve data and post-progress custody',
  {timeout:90_000},t=>verifyRetainedNames(t,'text-object',textObjectProgram,textObjectExpected,textObjectContract));
test('public retained raw Text array aggregation preserves data and post-progress custody',
  {timeout:90_000},t=>verifyRetainedNames(t,'text-array',textArrayProgram,textArrayExpected,textArrayContract));
test('public retained string aggregation preserves delimiters data and post-progress custody',
  {timeout:90_000},t=>verifyRetainedNames(t,'text-string',textStringProgram,textStringExpected,
    {type:'string',nullable:true}));
test('public retained wide indexed snapshots preserve rows and post-progress custody',
  {timeout:90_000},t=>verifyRetainedNames(t,'wide-snapshot',wideSnapshotProgram,
    [{id:1,value:1},{id:2,value:2}],{type:'number',nullable:false},0));
test('public retained ordered metadata preserves ties NULL and post-progress custody',
  {timeout:90_000},t=>verifyRetainedNames(t,'ordered-metadata',orderedMetadataProgram,
    [{id:1,value:7},{id:3,value:7},{id:2,value:null}]));
