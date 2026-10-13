import test from 'node:test';
import assert from 'node:assert/strict';
import {openNodeInferOperation} from './infer-operation.mjs';
import {retainInferOriginalReadInstallation} from './infer-original-installation.mjs';

// Actual operation code, explicit Common/Resource ports. These DATA amounts
// and mocked terminal Model are not a physical profile or actual reservation.
function fixture({missing=false,reserveIssue,releaseIssue}={}) {
  const active={},consumer={},borrow={},issued={},compiled={},definition={},graph={};
  const calls=[];
  const configuration={bootstrap:{bootstrapRetainedBytes:1n,bootstrapExecutionBytes:0n,
    maxReservations:1,maxHoldings:1,maxDelegations:1},
    modelRetainedBytes:1n,modelExecutionBytes:0n,
    ...(missing?{}:{publicationCapacity:{retainedBytes:123n,workspaceBytes:456n}}),
    nodeInstallation:{layout:{barrier_cid:'barrier',execution_bytes:1n,
      layout_artifact_cid:'layout',parameter_values_cid:'parameters',prepared_rows:1n,
      program_definition_cid:'program',response_profile:{},retained_bytes:1n,
      runtime_artifact_cid:'runtime'},installation:{},layoutArtifactCid:'layout',
      probability:undefined,runtimeArtifactCid:'runtime'}};
  const original=retainInferOriginalReadInstallation(configuration);
  let released=false,releaseComplete=true,stopped=true;
  const ok=_0=>({$tag:1,_0});
  const control={
    claimCheckedClientInferNodePreparationLayout(run,wire,selected,read,node) {
      assert.equal(run,compiled);assert.equal(wire,definition);assert.equal(selected,graph);
      assert.equal(node,original.nodeInstallation);calls.push('claim');return consumer;
    },
    startCheckedClientInferOriginalPreparation(...args) {
      assert.equal(args[8],consumer);calls.push('start');return active;
    },
  };
  const moon={
    clientProgramReserveOriginalInferPublicationCapacity(owner,r,w) {
      assert.equal(owner,active);assert.equal(r,123n);assert.equal(w,456n);
      calls.push('reserve');return reserveIssue===undefined?ok(borrow):{$tag:0,_0:reserveIssue};
    },
    clientProgramStartOriginalInferObservationIssuance(owner,capacity,n,bytes,work,generations) {
      assert.equal(owner,active);assert.equal(capacity,borrow);assert.equal(released,false);
      assert.deepEqual([n,bytes,work],[1,4096,3]);assert.deepEqual(generations,[]);
      calls.push('issue');return ok(issued);
    },
    clientProgramReleaseOriginalInferPublicationCapacity(value) {
      assert.equal(value,borrow);calls.push('release');
      if(releaseIssue!==undefined)return {$tag:0,_0:releaseIssue};
      if(releaseComplete)released=true;
      return ok(releaseComplete);
    },
    clientProgramInferPublicationLedger(){assert.fail('no separate Ledger fallback');},
    clientProgramStartInferObservationIssuance(){assert.fail('no legacy issuer fallback');},
    clientProgramCancelInferExecution(value){assert.equal(value,active);calls.push('stop');stopped=true;},
    clientProgramInferExecutionStopped:()=>stopped,
    clientProgramCleanupInferExecution(value){assert.equal(value,active);calls.push('cleanup');return ok(true);},
  };
  const operation=openNodeInferOperation({moon,preparedProgram:{},graph,provider:{},
    originalPreparation:{compiled,runDefinition:definition,control,scope:{},read:{},
      nodeInstallation:original.nodeInstallation,metadataInstallation:original,
      readRetainedBytes:1n,readExecutionBytes:1n,modelRetainedBytes:1n,modelExecutionBytes:0n}});
  return {operation,calls,borrow,issued,
    releaseComplete(value){releaseComplete=value;},
    releaseIssue(value){releaseIssue=value;}};
}
const limits={maxSlots:1,maxWireBytes:4096,maxWork:3};

test('original publication reserves once and reuses its nominal borrower without exporting a Ledger',()=>{
  const f=fixture();
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.equal(f.operation.reserveOriginalPublicationCapacity(),undefined);
  assert.equal(f.operation.reserveOriginalPublicationCapacity(),undefined);
  assert.equal(f.calls.filter(x=>x==='reserve').length,1);
  assert.equal(f.operation.publicationCapacityPending(),true);
  assert.equal(f.operation.startObservation(limits),f.issued);
  assert.throws(()=>f.operation.startObservation({...limits,ledger:{}}),
    /InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.calls.filter(x=>x==='issue').length,1);
  assert.equal(f.operation.cleanup(),false);
  assert.equal(f.calls.includes('cleanup'),false,'a retained borrower pins parent cleanup');
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.calls.filter(x=>x==='release').length,1);
  assert.equal(f.operation.cleanup(),true);
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),/InferOriginalPublicationCapacityUnavailable/);
});

test('missing original publication declaration cannot invoke reserve or the legacy issuer',()=>{
  const f=fixture({missing:true});
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),
    {code:'InferOriginalPublicationCapacityUnavailable'});
  assert.throws(()=>f.operation.startObservation(limits),/InferOriginalPublicationCapacityUnavailable/);
  assert.deepEqual(f.calls,['claim','start']);
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.equal(f.operation.cleanup(),true);
});

test('Common reservation refusal retains original cleanup with no invented borrower',()=>{
  const issue={kind:'OriginalCapacityExhausted'},f=fixture({reserveIssue:issue});
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),error=>error.cause===issue);
  assert.equal(f.operation.publicationCapacityPending(),false);
  assert.throws(()=>f.operation.startObservation(limits),/InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.calls.includes('issue'),false);
  assert.equal(f.operation.cleanup(),true);
});

test('failed and pending release retain the same borrower until exact settlement succeeds',()=>{
  const issue={kind:'OriginalParked'},f=fixture({releaseIssue:issue});
  f.operation.reserveOriginalPublicationCapacity();
  assert.throws(()=>f.operation.releaseOriginalPublicationCapacity(),error=>error.cause===issue);
  assert.equal(f.operation.publicationCapacityPending(),true);
  assert.equal(f.operation.cleanup(),false);
  f.releaseIssue(undefined);f.releaseComplete(false);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),false);
  assert.equal(f.operation.publicationCapacityPending(),true);
  f.releaseComplete(true);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.calls.filter(x=>x==='reserve').length,1);
  assert.equal(f.operation.cleanup(),true);
});

test('stop retains the original borrower and cleanup release does not request a send grant',async()=>{
  const f=fixture();f.operation.reserveOriginalPublicationCapacity();
  await f.operation.stop();
  assert.equal(f.operation.publicationCapacityPending(),true);
  assert.equal(f.operation.cleanup(),false);
  assert.throws(()=>f.operation.reserveOriginalPublicationCapacity(),/InferOriginalPublicationCapacityUnavailable/);
  assert.equal(f.operation.releaseOriginalPublicationCapacity(),true);
  assert.equal(f.operation.cleanup(),true);
  assert.equal(f.calls.filter(x=>x==='reserve').length,1);
  assert.equal(f.calls.filter(x=>x==='release').length,1);
  assert.equal(f.calls.includes('issue'),false);
});
