import test from 'node:test';
import assert from 'node:assert/strict';
import resources from './ordinary-node-resource-runtime.cjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';

const originalFor = input => resources.retainOrdinaryManagedRun(input, {
  planningWork: 100, attempts: 100, holdings: 100,
  transferBytes: 1000n, retainedBytes: 1000n, executionBytes: 1000n,
}, () => {}, () => false, 'local-preparation');

test('actual compiled preparation bridge retains unstarted original and cancels same child',()=>{
 const input={},original=originalFor(input);
 assert.throws(()=>checked(moon.clientProgramPrepareLocalPreparationAdmission(original,{})));
 const admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(original,input));
 assert.equal(resources.ordinaryManagedRunStatus(original).admitted,false);
 assert.throws(()=>checked(moon.clientProgramPrepareLocalPreparationAdmission(original,input)));
 checked(moon.clientProgramCleanupLocalPreparationAdmission(admission));
 assert.equal(resources.ordinaryManagedRunStatus(original).stopped,true);
 checked(moon.clientProgramCleanupLocalPreparationAdmission(admission));
});
test('actual compiled preparation bridge refuses same-shaped foreign original and Compute purpose',()=>{
 const input={}, original=resources.retainOrdinaryManagedRun(input,{
 planningWork:100,attempts:100,holdings:100,transferBytes:1000n,retainedBytes:1000n,executionBytes:1000n},()=>{},()=>false);
 assert.throws(()=>checked(moon.clientProgramPrepareLocalPreparationAdmission({},input)));
 assert.throws(()=>checked(moon.clientProgramPrepareLocalPreparationAdmission(original,input)));
 const ports=resources.prepareOriginalManagedRunPorts(original,input);
 assert.ok(ports);assert.equal(ports.cancelUnpublished(),0);
});

test('actual Request snapshot funds the original Unicode document and aborts its same child',async()=>{
 const {snapshotClientRequest}=await import('../../packages/client-wire/index.mjs');
 const input=Object.freeze({}),policy=moon.clientLocalResourcePolicyOriginal();
 const [planning,attempts,holdings,transfer,retained,execution]=moon.clientLocalPreparationResourceLimits(policy);
 const original=resources.retainOrdinaryManagedRun(input,{planningWork:Number(planning),attempts:Number(attempts),holdings:Number(holdings),transferBytes:transfer,retainedBytes:retained,executionBytes:execution},()=>{},()=>false,'local-preparation');
 const admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(original,input));
 const parent=checked(moon.clientProgramBeginRequestPreparation(admission,input,policy));
 const request={kind:'program',input:{text:'日本語😀'},parameters:{value:['é',1,null]}};
 let growths=0;
 const snapshot=snapshotClientRequest(request,(units,_document,values)=>{
  checked(moon.clientProgramReserveRequestSnapshot(parent,input,BigInt(units),BigInt(values)));growths++;
 });
 assert.ok(growths>0);assert.deepEqual(snapshot,request);assert.notEqual(snapshot,request);
 checked(moon.clientProgramAbortRequestPreparation(parent));
 assert.equal(resources.ordinaryManagedRunStatus(original).stopped,true);
 assert.throws(()=>checked(moon.clientProgramReserveRequestSnapshot(parent,input,1n,1n)));
});

test('actual Request snapshot rejects a foreign input without replacing its original parent',()=>{
 const input=Object.freeze({}),policy=moon.clientLocalResourcePolicyOriginal();
 const [planning,attempts,holdings,transfer,retained,execution]=moon.clientLocalPreparationResourceLimits(policy);
 const original=resources.retainOrdinaryManagedRun(input,{planningWork:Number(planning),attempts:Number(attempts),holdings:Number(holdings),transferBytes:transfer,retainedBytes:retained,executionBytes:execution},()=>{},()=>false,'local-preparation');
 const admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(original,input));
 const parent=checked(moon.clientProgramBeginRequestPreparation(admission,input,policy));
 assert.throws(()=>checked(moon.clientProgramReserveRequestSnapshot(parent,{},1n,1n)));
 checked(moon.clientProgramReserveRequestSnapshot(parent,input,1n,1n));
 checked(moon.clientProgramAbortRequestPreparation(parent));
 assert.equal(resources.ordinaryManagedRunStatus(original).stopped,true);
 assert.equal(Object.keys(moon).some(name=>name.includes('ClosedValues')),false);
});
