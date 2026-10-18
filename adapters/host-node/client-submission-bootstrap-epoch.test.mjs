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
