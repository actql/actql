import assert from 'node:assert/strict';
import test from 'node:test';
import {inspectAuthorizedRunState,installRunStateAuthority,installRunStateService}
  from './run-state-access.mjs';

// Physical-port doubles isolate clock enqueue order. Actual Common, encrypted
// Store, Journal and HTTPS coverage is qualified separately in the handoff.
const cid=digit=>'sha256:'+digit.repeat(64);
const request={indexKey:{namespaceId:'clock-order',authorityScopeCid:cid('a'),
  runDefinitionCid:cid('b')},principalId:'reader',purpose:'inspect'};
function fixture({names=['answer'],readRetention,now,authorize,resultPolicy,sampleClock,clockFor}={}){
  const calls=[],samples=[];let serial=0,previous;
  const authority=installRunStateAuthority({
    authorizeRunState:authorize??(facts=>{calls.push(['authorize',facts.stage]);return true;}),
    resultPolicyAvailable:resultPolicy??(()=>true),
  });
  const store={
    async confirmCommittedIndex(){return{public_index_entry_cid:cid('c'),publication_attempt_cid:cid('d'),
      result_manifest_cid:cid('e'),run_definition_cid:cid('b')};},
    async readPublicationContract(identity,kind){
      if(kind==='result_retention_policy'){
        calls.push(['retention_read',identity]);
        if(readRetention)await readRetention(identity);
        return{originalRetention:identity};
      }return{kind};
    },
    async latestRecordContract(){return{};},
    observeTrustedClock(identity,at){
      calls.push(['clock_enqueue',identity,at]);samples.push(at);
      if(previous!==undefined&&at<previous)return Promise.reject(
        Object.assign(new Error('PublicationClockUncertain'),{code:'PublicationClockUncertain'}));
      previous=at;return Promise.resolve({observedAt:at});
    },
    async withCommittedResult(_key,_definition,authorize,use){assert.equal(authorize(),true);return use();},
    async readCommittedResultRetentionExtension(){return undefined;},
  };
  const control={manifestResultNames:()=>names,
    resultReadDefinitionCid:(_manifest,name)=>'definition:'+name,
    resultReadRetentionPolicyCid:(_manifest,name)=>'retention:'+name,
    resultRetentionClockContractCid:retention=>{assert.match(retention.originalRetention,/^retention:/u);
      return clockFor?.(retention.originalRetention)??cid('f');},
    resultReadAvailability:(_manifest,name,retention,at)=>{
      calls.push(['retention_evaluation',name,retention.originalRetention,at]);return'available';},
    resultReadExtendedAvailability(){throw Error('Unexpected extension');},
    runDefinitionRunId:()=> 'same-original-run',projectCommittedPublicationState:()=> 'succeeded',
    issueSucceededRunState({runId,updatedAt,observations}){
      return JSON.stringify({run_id:runId,status:'succeeded',updated_at:updatedAt,
        result_availability:Object.fromEntries(observations.map(value=>[value.name,
          {state:value.state,reason:value.reason,observed_at:value.observedAt}]))});
    },
  };
  if(sampleClock!==undefined){
    store.sampleTrustedClock=sampleClock===null?null:async function(identity,sample){
      assert.strictEqual(this,store);calls.push(['durable_sample',identity]);
      if(typeof sampleClock==='function')return sampleClock(identity,sample);
      const at=sample();samples.push(at);return at;
    };
    control.trustedClockNotBefore=function(before,after){
      assert.strictEqual(this,control);return typeof after==='string'&&
        (before===undefined||after>=before);
    };
  }
  const service=installRunStateService({store,control,authority,
    now:()=>{const at=now?.()??`2026-10-17T00:00:00.${String(serial++).padStart(3,'0')}Z`;
      calls.push(['sample',at]);return at;},limits:{maxWireBytes:65536,maxNodes:4096,maxDepth:64}});
  return{service,calls,samples,store,control};
}

test('one Run observation durably samples each distinct Result clock only once',async()=>{
  const f=fixture({names:['answer','second','third'],sampleClock:true,
    clockFor:retention=>retention==='retention:second'?cid('a'):cid('f')});
  f.store.sampleTrustedClock=()=>assert.fail('Use the captured original Store clock');
  f.control.trustedClockNotBefore=()=>assert.fail('Use the captured original clock predicate');
  const first=await inspectAuthorizedRunState(f.service,request);
  assert.equal(f.calls.filter(value=>value[0]==='durable_sample').length,2);
  assert.equal(f.calls.filter(value=>value[0]==='clock_enqueue').length,0);
  assert.deepEqual(Object.values(first.result_availability).map(value=>value.state),
    ['available','available','available']);
  assert.equal(first.updated_at,first.result_availability.third.observed_at);
  assert.equal(first.result_availability.third.observed_at,'2026-10-17T00:00:00.002Z');
  await inspectAuthorizedRunState(f.service,request);
  assert.equal(f.calls.filter(value=>value[0]==='durable_sample').length,4,
    'A new public operation accepts its own original clock floor');
});

test('Run clock sampling uses the Store accepted time rather than a pre-I/O sample',async()=>{
  let wall='2026-10-17T00:00:00.000Z';
  const f=fixture({sampleClock:async(_identity,sample)=>{
    await Promise.resolve();wall='2026-10-17T00:00:01.000Z';return sample();
  },now:()=>wall});
  const state=await inspectAuthorizedRunState(f.service,request);
  assert.equal(state.result_availability.answer.observed_at,wall);
  assert.equal(state.updated_at,wall);
  assert.equal(f.calls.filter(value=>value[0]==='durable_sample').length,1);
});

test('failed Run clock sampling is retained for the observation without a mutating retry',async()=>{
  const f=fixture({names:['answer','second'],sampleClock:async()=>{
    throw Object.assign(new Error('lost clock ACK'),{code:'PublicationClockUncertain'});
  }});
  const state=await inspectAuthorizedRunState(f.service,request);
  assert.deepEqual(Object.values(state.result_availability).map(value=>[value.state,value.reason]),
    [['unknown','clock_uncertain'],['unknown','clock_uncertain']]);
  assert.equal(f.calls.filter(value=>value[0]==='durable_sample').length,1);
  await inspectAuthorizedRunState(f.service,request);
  assert.equal(f.calls.filter(value=>value[0]==='durable_sample').length,2);
});

test('same-observation clock reuse preserves rollback and invalid accepted-time refusal',async()=>{
  const times=['2026-10-17T00:00:02.000Z','2026-10-17T00:00:01.000Z'];
  const f=fixture({names:['answer','second'],sampleClock:true,now:()=>times.shift()});
  const state=await inspectAuthorizedRunState(f.service,request);
  assert.equal(state.result_availability.answer.state,'available');
  assert.equal(state.result_availability.second.reason,'clock_uncertain');
  assert.equal(f.calls.filter(value=>value[0]==='durable_sample').length,1);
  const malformed=fixture({sampleClock:()=>undefined});
  assert.equal((await inspectAuthorizedRunState(malformed.service,request))
    .result_availability.answer.reason,'clock_uncertain');
  assert.throws(()=>fixture({sampleClock:null}),{code:'InvalidRunStateService'});
});

test('original retention completion reordering cannot enqueue a stale pre-read sample',async()=>{
  const held=Promise.withResolvers(),release=Promise.withResolvers();let first=true;
  const f=fixture({readRetention:async()=>{if(first){first=false;held.resolve();await release.promise;}}});
  const delayed=inspectAuthorizedRunState(f.service,request);
  try{
    await held.promise;
    const overtaking=await inspectAuthorizedRunState(f.service,request);
    release.resolve();
    const after=await delayed;
    assert.equal(overtaking.result_availability.answer.state,'available');
    assert.equal(after.result_availability.answer.state,'available');
    assert.deepEqual(f.samples,['2026-10-17T00:00:00.000Z','2026-10-17T00:00:00.001Z']);
    assert.equal(after.updated_at,after.result_availability.answer.observed_at);
  }finally{release.resolve();await delayed;}
});

test('each Result evaluates original retention at its enqueued sample and aggregate uses the last',async()=>{
  const policy=[];
  const f=fixture({names:['answer','second'],resultPolicy:facts=>{policy.push(facts);return true;}});
  const state=await inspectAuthorizedRunState(f.service,request);
  assert.equal(state.result_availability.answer.observed_at,f.samples[0]);
  assert.equal(state.result_availability.second.observed_at,f.samples[1]);
  assert.equal(state.updated_at,f.samples[1]);
  assert.equal(policy.length,2);
  for(let index=0;index<2;index++){
    assert.equal(policy[index].observedAt,f.samples[index]);
    assert.equal(policy[index].retention.originalRetention,'retention:'+['answer','second'][index]);
    const sample=f.calls.findIndex(value=>value[0]==='sample'&&value[1]===f.samples[index]);
    assert.equal(f.calls[sample+1][0],'clock_enqueue','No awaited operation between sample and enqueue');
    assert.deepEqual(f.calls.find(value=>value[0]==='retention_evaluation'&&value[1]===['answer','second'][index]).slice(2),
      ['retention:'+['answer','second'][index],f.samples[index]]);
  }
  assert.deepEqual(f.calls.filter(value=>value[0]==='authorize'),[['authorize','request'],['authorize','response']]);
});

test('genuine trusted clock regression stays Unknown without clamping',async()=>{
  const times=['2026-10-17T00:00:02.000Z','2026-10-17T00:00:01.000Z'];
  const f=fixture({now:()=>times.shift()});
  assert.equal((await inspectAuthorizedRunState(f.service,request)).result_availability.answer.state,'available');
  const regressed=await inspectAuthorizedRunState(f.service,request);
  assert.equal(regressed.result_availability.answer.state,'unknown');
  assert.equal(regressed.result_availability.answer.reason,'clock_uncertain');
  assert.equal(regressed.result_availability.answer.observed_at,'2026-10-17T00:00:01.000Z');
  assert.equal(regressed.updated_at,'2026-10-17T00:00:01.000Z');
});

test('original read failure remains Unknown and response authorization still refuses',async()=>{
  const f=fixture({readRetention:async()=>{throw Object.assign(new Error('EIO'),{code:'EIO'});}});
  const failed=await inspectAuthorizedRunState(f.service,request);
  assert.deepEqual(failed.result_availability.answer,{state:'unknown',reason:'store_query_failed',
    observed_at:'2026-10-17T00:00:00.000Z'});assert.equal(f.samples.length,0);
  const denied=fixture({authorize:facts=>facts.stage!=='response'});
  await assert.rejects(inspectAuthorizedRunState(denied.service,request),{code:'RunStateAccessDenied'});
  const unavailable=fixture({resultPolicy:()=>false});
  assert.equal((await inspectAuthorizedRunState(unavailable.service,request))
    .result_availability.answer.reason,'policy_unavailable');
});

test('empty Result inventory preserves both authorizations and one read clock',async()=>{
  const f=fixture({names:[]});const state=await inspectAuthorizedRunState(f.service,request);
  assert.deepEqual(state.result_availability,{});assert.equal(state.updated_at,'2026-10-17T00:00:00.000Z');
  assert.equal(f.samples.length,0);
  assert.deepEqual(f.calls.filter(value=>value[0]==='authorize'),[['authorize','request'],['authorize','response']]);
});
