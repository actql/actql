import assert from 'node:assert/strict';
import test from 'node:test';
import {issueNodeClientSubmissionEpoch,installNodeClientSubmission} from './client-submission.mjs';
import {submissionEpoch} from '../../packages/sdk/submission-fixture.mjs';
const scope={authorityScopeCid:submissionEpoch.authorityScopeCid,namespaceId:'original'};
const deferred=()=>{let resolve;const promise=new Promise(done=>{resolve=done;});return {promise,resolve};};

// The real submission adapter with explicit Journal/authentication ports.
// No epoch authenticator, Account grant, Run or physical Journal is issued.
test('bootstrap epoch uses the original immutable authenticated request and same Journal receiver',async()=>{
  const entered=deferred(),released=deferred(),moon={};let calls=0,observed;
  const journal={issueSubmissionEpoch(fields,runtime){
    assert.strictEqual(this,journal);assert.strictEqual(runtime,moon);
    assert.deepEqual(fields,{...scope,currentAuthorization:true});calls++;return submissionEpoch;}};
  const request={principalId:'original',connection:{mode:'local'}};
  const pending=issueNodeClientSubmissionEpoch({journal,moon,async authorizedScope(value){
    observed=value;entered.resolve();await released.promise;return scope;}},request);
  await entered.promise;request.principalId='replacement';request.connection.mode='remote';
  assert.deepEqual(observed,{principalId:'original',connection:{mode:'local'}});
  assert.ok(Object.isFrozen(observed)&&Object.isFrozen(observed.connection));
  assert.equal(calls,0);released.resolve();
  assert.strictEqual(await pending,submissionEpoch);assert.equal(calls,1);
});

test('bootstrap epoch refuses missing or malformed current scope before Journal issuance',async()=>{
  let calls=0;
  const journal={issueSubmissionEpoch(){calls++;assert.fail('No authenticated scope');}};
  for(const selected of [undefined,{...scope,authorityScopeCid:'same-looking'},
    {...scope,namespaceId:''}]){
    await assert.rejects(issueNodeClientSubmissionEpoch({journal,moon:{},
      authorizedScope:()=>selected},{principalId:'original'}),{code:'ClientRequestLookupDenied'});
  }
  assert.equal(calls,0);
});

test('ordinary submission service retains the same epoch operation without starting preparation',async()=>{
  let epochs=0;
  const moon={clientSubmittedIntent(){assert.fail('No submitted intent');}};
  const journal={recordSubmittedIntent(){},checkSubmittedIntent(){},
    issueSubmissionEpoch(fields,runtime){assert.strictEqual(runtime,moon);
      assert.deepEqual(fields,{...scope,currentAuthorization:true});epochs++;return submissionEpoch;}};
  const unused=()=>assert.fail('Epoch issuance starts no Program or Run');
  const service=installNodeClientSubmission({journal,moon,authorizedScope:()=>scope,
    prepareSubmit:unused,submit:unused,lookupRequest:unused});
  assert.strictEqual(await service.issueEpoch({principalId:'original'}),submissionEpoch);
  assert.equal(epochs,1);
});


for (const [name, input, minimumNodes] of [
  ['encoded text beyond the old one-MiB ceiling', {format:'json', text:'é'.repeat(600000)}, 1],
  ['flat Program beyond the old 65536-node ceiling', {stages:[{values:Array(65537).fill(0)}]}, 65537],
]) {
  test(`submission compatibility codec uses the original finite wire geometry: ${name}`, async()=>{
    const stopped=Object.freeze({stage:'original Journal check'});
    const original=Object.freeze({kind:'original typed intent'});
    const intentCid='sha256:'+'d'.repeat(64);
    const ref={epoch:submissionEpoch,nonce:'e'.repeat(64)};
    let codecs=0,checks=0,releases=0;
    const moon={clientSubmittedIntent(wire,maxBytes,maxNodes,maxDepth){
      codecs++;
      if(minimumNodes>1) assert.ok(maxNodes>=minimumNodes);
      else assert.ok(maxBytes>=Buffer.byteLength(wire,'utf8'));
      assert.equal(maxBytes,3*wire.length);
      assert.equal(maxNodes,wire.length);
      assert.equal(maxDepth,64);
      return original;
    },clientSubmittedIntentCid(value){assert.strictEqual(value,original);return intentCid;}};
    const journal={recordSubmittedIntent(){assert.fail('No durable admission');},
      checkSubmittedIntent(submissionRef,value,fields,runtime){
        checks++;assert.strictEqual(this,journal);assert.deepEqual(submissionRef,ref);
        assert.strictEqual(value,original);assert.strictEqual(runtime,moon);
        assert.equal(fields.actorId,'original');throw stopped;
      },
      retainSubmissionOperation(epoch,runtime,borrowed){
        assert.deepEqual(epoch,submissionEpoch);assert.strictEqual(runtime,moon);
        assert.equal(borrowed,undefined);return ()=>{releases++;};
      }};
    const unused=()=>assert.fail('No preparation, Run or lookup');
    const service=installNodeClientSubmission({journal,moon,authorizedScope:()=>scope,
      prepareSubmit:unused,submit:unused,lookupRequest:unused});
    await assert.rejects(service.submitIntent({principalId:'original',connection:{mode:'local'},
      submissionRef:ref,intentCid,kind:name.startsWith('encoded')?'aql':'program',input,
      parameters:null}),error=>error===stopped);
    assert.equal(codecs,1);assert.equal(checks,1);assert.equal(releases,1);
  });
}


test('submission keeps the original retained intent ahead of every codec', async()=>{
  const original=Object.freeze({kind:'same retained intent'});
  const stopped=Object.freeze({stage:'same Journal check'});
  const intentCid='sha256:'+'d'.repeat(64);
  let retained=0,releases=0,checks=0;
  const moon={clientSubmittedIntent(){assert.fail('No codec for a retained original');},
    clientSubmittedIntentCid(value){assert.strictEqual(value,original);return intentCid;}};
  const journal={recordSubmittedIntent(){assert.fail('No admission');},
    prepareSubmittedIntent(){assert.fail('No second original');},
    retainSubmissionOperation(epoch,runtime,borrowed){assert.strictEqual(borrowed,original);
      return ()=>{releases++;};},
    checkSubmittedIntent(ref,value){checks++;assert.strictEqual(value,original);throw stopped;}};
  const unused=()=>assert.fail('No Program or Run');
  const service=installNodeClientSubmission({journal,moon,authorizedScope:()=>scope,
    submittedIntentOriginal(){retained++;return original;},prepareSubmit:unused,submit:unused,
    lookupRequest:unused});
  await assert.rejects(service.submitIntent({principalId:'original',connection:{mode:'local'},
    submissionRef:{epoch:submissionEpoch,nonce:'e'.repeat(64)},intentCid,kind:'program',
    input:{stages:[]},parameters:null}),error=>error===stopped);
  assert.equal(retained,2);assert.equal(checks,1);assert.equal(releases,1);
});

test('submission keeps the original Journal refusal without compatibility fallback', async()=>{
  const refusal=Object.freeze({stage:'original explicit Journal policy'});
  let calls=0,releases=0;
  const moon={clientSubmittedIntent(){assert.fail('No fallback after original refusal');}};
  const journal={recordSubmittedIntent(){assert.fail('No admission');},
    checkSubmittedIntent(){assert.fail('No original was admitted');},
    retainSubmissionOperation(){return ()=>{releases++;};},
    prepareSubmittedIntent(epoch,wire,runtime){calls++;assert.strictEqual(this,journal);
      assert.deepEqual(epoch,submissionEpoch);assert.strictEqual(runtime,moon);
      assert.equal(JSON.parse(wire).kind,'program');throw refusal;}};
  const unused=()=>assert.fail('No Program or Run');
  const service=installNodeClientSubmission({journal,moon,authorizedScope:()=>scope,
    prepareSubmit:unused,submit:unused,lookupRequest:unused});
  await assert.rejects(service.submitIntent({principalId:'original',connection:{mode:'local'},
    submissionRef:{epoch:submissionEpoch,nonce:'e'.repeat(64)},intentCid:'sha256:'+'d'.repeat(64),
    kind:'program',input:{stages:[]},parameters:null}),error=>error===refusal);
  assert.equal(calls,1);assert.equal(releases,1);
});
