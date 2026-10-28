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

test('actual Root funds header and 9900-cell scan then aborts same child', async()=>{
 const s=await import('./closed-values-own-data-scan.mjs');
 const fields=Array.from({length:100},(_,i)=>`c${i}`);
 const p={version:'actql/0.1',id:'root-scan',stages:[{id:'main',inputs:{},steps:[{as:'v',values:{schema:Object.fromEntries(fields.map(n=>[n,{type:'number',nullable:false}])),rows:Array.from({length:99},(_,r)=>Object.fromEntries(fields.map((n,c)=>[n,r*100+c])))}}],results:{rows:{from:'v',fields}}}],results:{answer:{from:{stage:'main',result:'rows'}}}};
 const input=Object.freeze({}),policy=moon.clientLocalResourcePolicyOriginal();
 const [planning,attempts,holdings,transfer,retained,execution]=moon.clientLocalPreparationResourceLimits(policy);
 const original=resources.retainOrdinaryManagedRun(input,{planningWork:Number(planning),attempts:Number(attempts),holdings:Number(holdings),transferBytes:transfer,retainedBytes:retained,executionBytes:execution},()=>{},()=>false,'local-preparation');
 const admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(original,input));
 assert.equal(Object.hasOwn(moon,'clientProgramBeginClosedValuesPreparation'),false);
 const parent=checked(moon.clientProgramBeginRequestPreparation(admission,input,policy));
 const owner=checked(moon.clientProgramSelectClosedValuesPreparation(parent,input));
 const headerWork=checked(moon.clientProgramBeginClosedValuesHeader(owner));
 const phase=token=>({spendWork(n){checked(moon.clientProgramSpendPreparationPhaseWork(token,n));}});
 const header=s.probeClosedValuesOwnDataHeader(p,undefined,phase(headerWork));assert.ok(header);
 const work=checked(moon.clientProgramBeginClosedValuesScan(owner,s.closedValuesOwnDataHeaderFields(header,p),s.closedValuesOwnDataHeaderRows(header,p)));
 const facts=s.scanClosedValuesOwnData(p,undefined,phase(work),header);assert.ok(facts);
 assert.equal(facts.inspectionWork,71836);assert.equal(facts.rowCount,99);assert.equal(facts.fieldCount,100);
 checked(moon.clientProgramFinishClosedValuesScan(owner));
 const textWork=checked(moon.clientProgramBeginClosedValuesTextCheck(owner,facts.quotedUtf16Units));
 const eligible=s.scanClosedValuesOwnDataAscii(p,undefined,phase(textWork));assert.ok(eligible);
 assert.equal(eligible.inspectionWork,facts.inspectionWork+facts.quotedUtf16Units);
 checked(moon.clientProgramFinishClosedValuesTextCheck(owner));
 assert.throws(()=>checked(moon.clientProgramSpendPreparationPhaseWork(work,1)));
 checked(moon.clientProgramAbortClosedValuesPreparationAfterCleanup(owner));
 assert.equal(resources.ordinaryManagedRunStatus(original).stopped,true);
 console.log(JSON.stringify({actualBytes:Buffer.byteLength(JSON.stringify(p)),rows:99,fields:100,work:facts.inspectionWork,sameChildStopped:true}));
});

test('actual preparation accounting observes one original reservation and zero after same-child cleanup',()=>{
 const input=Object.freeze({}),policy=moon.clientLocalResourcePolicyOriginal();
 const [planning,attempts,holdings,transfer,retained,execution]=moon.clientLocalPreparationResourceLimits(policy);
 const original=resources.retainOrdinaryManagedRun(input,{planningWork:Number(planning),attempts:Number(attempts),holdings:Number(holdings),transferBytes:transfer,retainedBytes:retained,executionBytes:execution},()=>{},()=>false,'local-preparation');
 const admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(original,input));
 assert.equal(Object.hasOwn(moon,'clientProgramBeginClosedValuesPreparation'),false);
 const parent=checked(moon.clientProgramBeginRequestPreparation(admission,input,policy));
 const owner=checked(moon.clientProgramSelectClosedValuesPreparation(parent,input));
 const fields=()=>{const q=checked(moon.clientProgramClosedValuesPreparationAccounting(owner));return Array.from({length:6},(_,i)=>q[`_${i}`]);};
 const initial=fields();
 assert.ok(initial.every(v=>typeof v==='bigint'));
 assert.ok(initial[0]>0n);assert.ok(initial[1]>0n);assert.equal(initial[2],0n);
 assert.equal(initial[0],initial[4]);assert.equal(initial[1],initial[5]);
 assert.ok(initial[3]>=initial[0]);
 checked(moon.clientProgramAbortClosedValuesPreparationAfterCleanup(owner));
 const stopped=fields();
 assert.deepEqual([stopped[0],stopped[1],stopped[2],stopped[4],stopped[5]],[0n,0n,0n,0n,0n]);
 assert.ok(stopped[3]>=initial[0]);assert.equal(resources.ordinaryManagedRunStatus(original).stopped,true);
});
