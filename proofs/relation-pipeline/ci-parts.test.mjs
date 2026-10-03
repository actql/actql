import assert from 'node:assert/strict';
import test from 'node:test';
import {hash} from './inventory.mjs';
import {partIds,planDigest,plan} from './proof-parts.mjs';
import {partSchema,partStages,capacityPartExecutions,validatePartEnvelope,validatePartInputs,requireValidation} from './ci-parts.mjs';
const digest='a'.repeat(64);
const expected={context:{repository:'actql/actql',runId:'1',runAttempt:'1',testedSha:'b'.repeat(40),prHeadSha:null},
 source:{digest},foundation:{digest},exploration:{required:true},toolchain:{moonbit:{moonc:'pin'}},
 workflow:{ref:'actql/actql/.github/workflows/ci.yml@refs/heads/main',sha:'b'.repeat(40)},planDigest};
function envelope(partId='L-C0') {
 const path=`${partId}-123-45-0000-normal-js.json`,boundary={workspace:`owner-${partId}`,target:'js',role:'normal'};
 return {schema:partSchema,partId,...structuredClone(expected),completedStages:[...partStages[partId]],
 restoration:{sourceRestored:true,fixtureClosed:true,workspacesClosed:true},
 files:[{path,kind:'file',size:1,sha256:digest}],evidence:{reports:[{path,sha256:digest}],owners:[boundary.workspace],
 receipts:[{path,sha256:digest,target:'js',boundary,buildIdentity:hash(JSON.stringify(boundary))}],
 observations:[{id:`${partId}-observation`,receipt:path,target:'js',owner:boundary.workspace,caseDigest:digest}]}};
}
const inputs=()=>partIds.map((partId,index)=>({partId,result:'success',artifactId:String(index+1),artifactDigest:digest,archiveDigest:digest,manifestDigest:digest}));
test('fixed plan names exactly two capacity and two mutation producers',()=>{
 assert.deepEqual(partIds,['L-C0','L-C1','L-M0','L-M1']);
 assert.equal(Object.keys(plan.parts).length,4);
 assert.equal(plan.parts['L-C0'].obligations.finalNormal.caseCount,86);
 assert.equal(plan.parts['L-C1'].obligations.ownerLocalRestoration.caseCount,5);
 assert.equal(plan.parts['L-C1'].obligations.finalNormal,undefined);
});
for(const partId of partIds) test(`${partId} has distinct truthful PART envelope`,()=>{
 assert.doesNotThrow(()=>validatePartEnvelope(envelope(partId),expected,partId));
});
for(const [label,change] of Object.entries({
 missingStage:m=>m.completedStages.pop(),sealBeforeClose:m=>m.restoration.fixtureClosed=false,
 unrestored:m=>m.restoration.sourceRestored=false,liveWorkspace:m=>m.restoration.workspacesClosed=false,
 foreignRun:m=>m.context.runId='2',foreignAttempt:m=>m.context.runAttempt='2',headInsteadOfMerge:m=>m.context.testedSha='c'.repeat(40),
 wrongPlan:m=>m.planDigest='c'.repeat(64),foreignWorkflow:m=>m.workflow.sha='c'.repeat(40),
 foreignSource:m=>m.source.digest='c'.repeat(64),foreignFoundation:m=>m.foundation.digest='c'.repeat(64),
 duplicateReceipt:m=>m.evidence.receipts.push(m.evidence.receipts[0]),duplicateObservation:m=>m.evidence.observations.push(m.evidence.observations[0]),
 foreignOwner:m=>m.evidence.observations[0].owner='other',foreignTarget:m=>m.evidence.observations[0].target='native',
 unknownReceipt:m=>m.evidence.observations[0].receipt='missing',foreignPart:m=>m.partId='L-C1',unknownField:m=>m.fullSuccess=true,
 swappedCompiledOwner:m=>m.evidence.receipts[0].boundary.workspace='other',
 alteredFile:m=>m.files[0].sha256='c'.repeat(64),traversal:m=>m.files[0].path='../bad',
})) test(`part seal rejects ${label}`,()=>{
 const m=envelope();change(m);assert.throws(()=>validatePartEnvelope(m,expected,'L-C0'));
});
test('aggregate accepts exactly four successful distinct immutable inputs',()=>assert.doesNotThrow(()=>validatePartInputs(inputs())));
for(const [label,change] of Object.entries({missing:x=>x.pop(),duplicate:x=>x[1]=x[0],extra:x=>x.push(x[0]),wrongOrder:x=>x.reverse(),
 failure:x=>x[2].result='failure',skipped:x=>x[3].result='skipped',cancelled:x=>x[0].result='cancelled',
 foreignPart:x=>x[0].partId='L-C2',duplicateArtifact:x=>x[1].artifactId=x[0].artifactId,
 noDigest:x=>delete x[0].archiveDigest,noManifest:x=>delete x[0].manifestDigest,noArtifact:x=>delete x[0].artifactId,
})) test(`aggregate rejects ${label}`,()=>{const x=inputs();change(x);assert.throws(()=>validatePartInputs(x));});
const validation=()=>({result:'success',outputs:{'tested-sha':expected.context.testedSha,'source-digest':expected.source.digest,'plan-digest':planDigest}});
test('synthetic validation is mandatory and bound to exact source and plan',()=>{
 assert.doesNotThrow(()=>requireValidation(validation(),expected));
 for(const result of ['failure','skipped','cancelled',undefined]) assert.throws(()=>requireValidation({...validation(),result},expected));
 for(const key of ['tested-sha','source-digest','plan-digest']){const v=validation();v.outputs[key]='foreign';assert.throws(()=>requireValidation(v,expected));}
 assert.throws(()=>requireValidation(undefined,expected));
});

test('capacity transport includes independent native-parent receipt without duplicating recovery receipts',()=>{
 const primary={path:'primary'},parent={path:'parent'},restored={path:'restored'};
 assert.deepEqual(capacityPartExecutions({part:'L-C0',executions:[primary],parentStartup:{execution:parent}}),[primary,parent]);
 assert.deepEqual(capacityPartExecutions({part:'L-C1',executions:[primary,restored],postRestore:{executions:[restored]}}),[primary,restored]);
 assert.throws(()=>capacityPartExecutions({part:'L-C0',executions:[primary]}));
});
