import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {moon,originalBigQueryRowOwner,queryLimits,jobBody,resultBody,decimal38,statement} from './bigquery-read.fixture.mjs';

async function original(t) {
 const row=await originalBigQueryRowOwner();
 t.after(()=>row.close());
 const job=checked(moon.clientProgramBigQueryOriginalJob('acme-project',row.requestId,'EU',1024));
 const read=checked(moon.clientProgramBigQueryBorrowRead(row.prepared,row.run,job,queryLimits(),4));
 checked(moon.clientProgramBigQueryBindReadTransport(read,()=>true));
 const session=checked(moon.clientProgramBigQueryPrepareJob(read,1000000n,2,0,8,4096));
 return {row,job,read,session};
}
function accept(session,body,status=200) {
 const request=checked(moon.clientProgramBigQueryNextRequest(session));
 checked(moon.clientProgramBigQueryAttemptRequest(session,request));
 const response=checked(moon.clientProgramBigQueryChargeResponse(session,request,status,body));
 checked(moon.clientProgramBigQueryAcceptResponse(session,response,body));
 return request;
}

test('compiled normal Node bridge retains original Job material and actual Common capture',async t=>{
 const f=await original(t);
 const post=accept(f.session,jobBody(f.row.requestId));
 const material=moon.clientProgramBigQueryRequestMaterial(post);
 assert.equal(runtimeField(material,0),'POST');
 assert.equal(runtimeField(material,1),'/bigquery/v2/projects/acme-project/jobs');
 assert.deepEqual(JSON.parse(runtimeField(material,2)),{
  configuration:{query:{maximumBytesBilled:'1000000',query:statement,useLegacySql:false}},
  jobReference:{jobId:f.row.requestId,location:'EU',projectId:'acme-project'}});
 const get=accept(f.session,resultBody(f.row.requestId));
 assert.equal(runtimeField(moon.clientProgramBigQueryRequestMaterial(get),0),'GET');
 assert.equal(moon.clientProgramBigQueryJobComplete(f.session),true);
 assert.equal(moon.clientProgramBigQueryJobRemoteDone(f.session),true);
 f.row.assertNoCapture();
 const rows=f.row.captureRows();assert.equal(rows.length,2);
 assert.ok(rows[0].includes(decimal38));assert.ok(rows[1].includes('null'));
 const originalData=moon.clientProgramBigQueryJobOriginal(f.session);
 assert.deepEqual([0,1,2].map(n=>runtimeField(originalData,n)),['acme-project',f.row.requestId,'EU']);
});

test('same runtime nominal response cannot be consumed by a foreign original Read',async t=>{
 const f=await original(t),foreign=await original(t);
 const request=checked(moon.clientProgramBigQueryNextRequest(f.session));
 checked(moon.clientProgramBigQueryAttemptRequest(f.session,request));
 const body=jobBody(f.row.requestId);
 const response=checked(moon.clientProgramBigQueryChargeResponse(f.session,request,200,body));
 assert.throws(()=>checked(moon.clientProgramBigQueryAcceptResponse(foreign.session,response,body)),{code:'MoonBitHostFailure'});
 checked(moon.clientProgramBigQueryAcceptResponse(f.session,response,body));
 assert.equal(f.row.usage()[3],BigInt(body.byteLength));
 assert.equal(foreign.row.usage()[3],0n);
 f.row.assertNoCapture();foreign.row.assertNoCapture();
});

test('running Job followed by refused GET does not become remote stop or reusable POST',async t=>{
 const f=await original(t);accept(f.session,jobBody(f.row.requestId,{state:'RUNNING'}));
 const request=checked(moon.clientProgramBigQueryNextRequest(f.session));
 checked(moon.clientProgramBigQueryAttemptRequest(f.session,request));
 const denied=Buffer.from('{"error":{"code":403}}');
 const response=checked(moon.clientProgramBigQueryChargeResponse(f.session,request,403,denied));
 assert.throws(()=>checked(moon.clientProgramBigQueryAcceptResponse(f.session,response,denied)),{code:'MoonBitHostFailure'});
 assert.equal(moon.clientProgramBigQueryJobRemoteDone(f.session),false);
 assert.throws(()=>checked(moon.clientProgramBigQueryNextRequest(f.session)),{code:'MoonBitHostFailure'});
 f.row.assertNoCapture();
});

test('recorded original response loss is Unit only for that original one-shot request',async t=>{
 const f=await original(t),foreign=await original(t);
 const request=checked(moon.clientProgramBigQueryNextRequest(f.session));
 checked(moon.clientProgramBigQueryAttemptRequest(f.session,request));
 assert.throws(()=>checked(moon.clientProgramBigQueryRecordResponseLoss(foreign.session,request)),{code:'MoonBitHostFailure'});
 checked(moon.clientProgramBigQueryRecordResponseLoss(f.session,request));
 assert.equal(moon.clientProgramBigQueryJobRemoteDone(f.session),false);
 assert.throws(()=>checked(moon.clientProgramBigQueryNextRequest(f.session)),{code:'MoonBitHostFailure'});
 assert.equal(f.row.usage()[3],0n);f.row.assertNoCapture();
});
