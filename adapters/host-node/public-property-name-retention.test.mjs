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

test('public retained property names publish NULL and deliver cancellation after progress',
  {timeout:90_000}, async t=>{
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
          if(cancelling && detail.task===1 && BigInt(detail.work)>0n){
            reached.resolve();await release.promise;
          }
        },
      }}});
    const source=JSON.stringify(program('property-name-success'));
    const run=await client.aql(source,{format:'json',requestId:'property-name-success'});
    const status=await run.wait({signal:AbortSignal.timeout(45_000)});
    assert.equal(status.status,'succeeded',JSON.stringify(status));
    assert.deepEqual(Object.keys(status.result_availability).sort(),names.toSorted());
    for(const name of names)assert.deepEqual(await run.result(name).all(),expected);
    assert.deepEqual((await run.result('published').describe()).columns,
      [{name:'id',contract:{type:'number',nullable:false}},
        {name:'value',contract:{type:'number',nullable:true}}]);
    const count=dispatches;
    assert.deepEqual((await client.aql(source,{format:'json',requestId:'property-name-success'})).ref,run.ref);
    assert.equal(dispatches,count);
    cancelling=true;
    const cancel=await client.aql(JSON.stringify(program('property-name-cancel')),
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
  });
