import assert from 'node:assert/strict';
import test from 'node:test';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {submissionEpoch,originalSubmission,readySubmissionAttempt} from '../../packages/sdk/submission-fixture.mjs';

const connection={mode:'local',owner:'local',durability:'durable',consentRefs:[],runners:[]};
const ref={namespaceId:'original',authorityScopeCid:submissionEpoch.authorityScopeCid,
  runDefinitionCid:'sha256:'+'d'.repeat(64)};
const deferred=()=>{let resolve;const promise=new Promise(done=>{resolve=done;});return {promise,resolve};};

test('deferred ingress keeps the original admitted reference across authentication and installation waits',async()=>{
  const auth=deferred(),install=deferred(),entered=deferred();let observed;
  const port=createNodeInProcessClientHost({authenticate:()=>auth.promise,
    authorizeConnection:({ref:actual})=>actual.runDefinitionCid===ref.runDefinitionCid,
    negotiate:()=>{throw Error('No negotiation');},maxRowBytes:65536,
    async performInstalledRequest(operation,body){
      assert.equal(operation,'attach');observed=body;entered.resolve();await install.promise;return body.ref;
    }});
  const packet={connection:{...connection},ref:{...ref}};
  const flight=port.perform('attach',packet);
  packet.ref.runDefinitionCid='sha256:'+'e'.repeat(64);
  auth.resolve('actor');
  await Promise.race([entered.promise,flight.then(()=>assert.fail('Missing deferred entry'))]);
  packet.ref.namespaceId='replacement';install.resolve();
  const actual=await flight;
  assert.deepEqual(actual,ref);assert.notStrictEqual(actual,packet.ref);
  assert.ok(Object.isFrozen(observed));assert.ok(Object.isFrozen(observed.ref));
});

test('selected deferred copies retain the same original Source lineage through both ingress layers',async()=>{
  const originals=new WeakMap(),seen=[];
  const packet={connection:{...connection},kind:'aql',input:{text:'SELECT 1 AS n',format:'sql'},parameters:null,
    submissionRef:originalSubmission('deferred-original-lineage'),intentCid:'sha256:'+'f'.repeat(64),
    attemptRef:{operation:'submit',attemptId:'original-attempt'}};
  originals.set(packet,packet);
  const bindOwnedRequest=(parent,derived)=>{
    assert.ok(originals.has(parent));originals.set(derived,originals.get(parent));seen.push(derived);
  };
  const handler={authenticate:()=> 'actor',authorizeConnection:()=>true,
    negotiate:()=>{throw Error('No negotiation');},maxRowBytes:65536,bindOwnedRequest};
  const stopped=readySubmissionAttempt(packet,{ref,durability:'durable',revision:0});
  const final=createNodeInProcessClientHost({...handler,submitIntent(body){
    assert.strictEqual(originals.get(body),packet);assert.equal(body.input.text,'SELECT 1 AS n');
    return stopped;
  }});
  const before=deferred(),after=deferred();
  const first=createNodeInProcessClientHost({...handler,
    async performInstalledRequest(operation,body,signal){
      assert.strictEqual(originals.get(body),packet);before.resolve();await after.promise;
      return final.perform(operation,body,signal);
    }});
  const flight=first.perform('submit-intent',packet);
  const observed=flight.catch(error=>error);
  await Promise.race([before.promise,observed.then(()=>assert.fail('Missing Source entry'))]);
  packet.input.text='SELECT 99 AS replaced';after.resolve();
  assert.strictEqual(await observed,stopped);
  assert.ok(seen.length>=3);assert.equal(seen[0].input.text,'SELECT 1 AS n');
  for(const alias of seen)assert.strictEqual(originals.get(alias),packet);
});
