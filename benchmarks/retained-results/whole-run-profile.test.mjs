import test from 'node:test';
import assert from 'node:assert/strict';
import {wholeRunTemplate,wholeRunValue,projectedRealization,wholeRunScope} from './whole-run-profile.mjs';
import {profileDigest} from './local-performance-profile.mjs';

const offer=(task,resident)=>[task,'duckdb',1,1,'0','1','2','0',[],resident?['configured-profile']:null];
const assignment=(position,resident)=>[position,1,'0','1','2',[null,offer(1,resident),offer(2,resident)]];
const body=['actql-policy-candidates/0.1','program',0,1,true,[assignment(12,false),assignment(4,true)]];
const candidates={canonical_json:JSON.stringify(body),cid:profileDigest(JSON.stringify(body))};
const conditions={runtimeRevision:'current',measurementScope:wholeRunScope,nativeConditions:{captureMode:'metadata-only'}};
const observations=body[5].flatMap(a=>[0,1,2].map(i=>({conditions,step:{position:a[0]},outcome:'succeeded',
  ownerAccepted:true,observedAt:1000,callerElapsedMs:(a[0]===4?10:20)+i,
  owner:{observations:{candidates:[{body:structuredClone(body)}]}},trajectory:{initialAssignment:structuredClone(a)}})));
const profile={profileRevision:'pinned',report:{stage:'comparison',observations}};
const template=(changes={})=>wholeRunTemplate({profile:structuredClone(profile),conditions,candidates,now:1100,...changes});

test('whole-Run references use complete enclosing intervals and every currently offered assignment',()=>{
  const value=template();
  assert.deepEqual(value.entries.map(e=>[e.position,e.quantity,e.median_ms,e.sample_count]),
    [[12,'run-caller-elapsed',21,3],[4,'run-caller-elapsed',11,3]]);
  assert.equal(value.candidate_snapshot_cid,candidates.cid);
  assert.equal(value.overhead,'unknown-no-off-comparison');
});
test('a failed slot or changed realized suffix stays unknown without dropping the candidate',()=>{
  for(const change of [o=>{o.outcome='failed';o.ownerAccepted=false;},
    o=>{o.trajectory.initialAssignment=assignment(4,false);},o=>{o.owner.observations.candidates[0].body[3]++;}]) {
    const changed=structuredClone(profile);change(changed.report.observations[5]);
    const entries=template({profile:changed}).entries;
    assert.equal(entries.length,2);assert.equal(entries[0].status,'reference');
    assert.equal(entries[1].status,'unknown');assert.equal(entries[1].median_ms,null);
  }
});
test('revision, instrumentation, capture and scope changes cannot borrow the old whole-Run observations',()=>{
  for(const key of ['runtimeRevision','instrumentationRevision','captureMode','measurementScope']) {
    const changed={...conditions,[key]:'different'};
    assert(template({conditions:changed}).entries.every(e=>e.reason==='conditions-mismatch'));
  }
  assert(template({now:900}).entries.every(e=>e.reason==='freshness-insufficient'));
  assert(template({now:2000,maxAgeMs:1}).entries.every(e=>e.reason==='freshness-insufficient'));
  assert.throws(()=>template({candidates:{...candidates,cid:'wrong'}}),/WholeRunCandidateBytesChanged/);
});
test('registration/realization matching does not treat positions or changing cost as identities',()=>{
  const first=offer(1,true), changed=[...first];changed[2]=999;changed[4]='500';
  assert.deepEqual(projectedRealization(first),projectedRealization(changed));
  assert.notDeepEqual(projectedRealization(first),projectedRealization(offer(1,false)));
  assert.notDeepEqual(projectedRealization(first),projectedRealization(offer(2,true)));
});
test('conditional recovery counts creation and first-use extra once, never invents an amortization frequency',()=>{
  const value=wholeRunValue({creationMs:100,firstUseMs:30,offlineMs:20,reusedMs:15});
  assert.equal(value.initialExtraMs,10);assert.equal(value.conditionalRecoveryUses,22);
  assert.equal(value.eta,null);assert.equal(value.p90,null);
  assert.equal(wholeRunValue({creationMs:100,firstUseMs:30,offlineMs:20,reusedMs:20}).conditionalRecoveryUses,null);
  assert.equal(wholeRunValue({creationMs:100,firstUseMs:30,offlineMs:20,reusedMs:25}).conditionalRecoveryUses,null);
});

test('normal Host trajectory consumes actual current decisions and rejects unknown or changed positions', async()=>{
  const {admitWholeRunTrajectory}=await import('./whole-run-profile.mjs');
  const snapshots=[{body}];
  const product={ownerCorrespondence:{observations:{candidates:snapshots,choices:[{
    task:1,position:4,revision:1,source:'ExternalPolicy',
  }]}}};
  const decision={mode:'select-reference',selected_position:4,load_applicability:'unknown-uncontrolled',net_benefit:'unknown',
    request_json:JSON.stringify({candidate_set_cid:candidates.cid,generation:0,revision:1})};
  const stdout='normal-host-decision:'+JSON.stringify(decision)+'\n';
  assert.equal(admitWholeRunTrajectory({stdout},product).initialAssignment[0],4);
  assert.throws(()=>admitWholeRunTrajectory({stdout:'normal-host-decision:'+JSON.stringify({...decision,selected_position:null})},product),/UnknownNormalHostRanking/);
  assert.throws(()=>admitWholeRunTrajectory({stdout:'normal-host-decision:'+JSON.stringify({...decision,selected_position:12})},product),/NormalDecisionExecutionChanged/);
});
