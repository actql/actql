// Finite whole-Run references. No Source access, authority or candidate creation.
import assert from 'node:assert/strict';
import {open, constants} from 'node:fs/promises';
import {join} from 'node:path';
import {performance} from 'node:perf_hooks';
import {profileDigest} from './local-performance-profile.mjs';
import {retainedCase} from './fixtures.mjs';
import {readNativeDirectProductExecution, admitNativeDirectProduct} from './native-direct-product.mjs';

export const wholeRunScope = 'trusted-local-call-before-profile-access-through-result-readback-owner-release-and-original-record-write/0.1';
export const wholeRunLimits = Object.freeze({reportBytes: 24 * 1024 * 1024, memberBytes: 2 * 1024 * 1024,
  observations: 54, positions: 18, minimumSamples: 3, maxAgeMs: 86400000});
const finite = v => Number.isFinite(v) && v >= 0;
const freeze = v => {if (v && typeof v === 'object') {Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
const describe = values => {
  assert(values.every(finite));
  const s = [...values].sort((a,b)=>a-b), m = Math.floor(s.length/2);
  return {count:s.length, median:s.length ? (s.length%2 ? s[m] : (s[m-1]+s[m])/2) : null,
    minimum:s.length ? s[0] : null, maximum:s.length ? s.at(-1) : null};
};

export function projectedRealization(offer) {
  assert(Array.isArray(offer) && offer.length === 10 && Number.isSafeInteger(offer[0]) && typeof offer[1] === 'string');
  return [offer[0], offer[1], offer[9] !== null];
}

export function admitWholeRunTrajectory(execution, product) {
  const lines = execution.stdout.split('\n');
  const initial = lines.filter(l=>l.startsWith('whole-run-initial-assignment:'));
  assert.equal(initial.length,1,'MissingWholeRunAssignment');
  const assignment = JSON.parse(initial[0].slice('whole-run-initial-assignment:'.length));
  const requests = lines.filter(l=>l.startsWith('empirical-current-request:'))
    .map(l=>JSON.parse(l.slice('empirical-current-request:'.length)));
  const choices = product.ownerCorrespondence.observations.choices;
  const snapshots = product.ownerCorrespondence.observations.candidates;
  assert.equal(requests.length,choices.length,'MissingCurrentWholeRunRequest');
  assert.deepEqual(assignment,snapshots[0].body[5].find(a=>a[0]===choices[0].position));
  for (let i=0;i<choices.length;i++) {
    const choice=choices[i], snapshot=snapshots[i].body, request=requests[i];
    assert.equal(request.candidate_set_cid,profileDigest(JSON.stringify(snapshot)),'RequestSnapshotMismatch');
    assert.equal(request.revision,choice.revision,'RequestRevisionMismatch');
    assert.equal(request.generation,snapshot[2]); assert.equal(request.revision,snapshot[3]);
    if(i) {assert(request.generation>requests[i-1].generation);assert(request.revision>requests[i-1].revision);}
    const current=snapshot[5].find(a=>a[0]===choice.position);
    assert(current,'UnpresentedWholeRunPosition');
    for(let task=choice.task;task<assignment[5].length;task++) {
      assert.deepEqual(projectedRealization(current[5][task]),projectedRealization(assignment[5][task]),
        'ResidualAssignmentChanged');
    }
    assert.equal(choice.source,'ExternalPolicy');
  }
  return {initialAssignment:assignment,requests,realizations:assignment[5].filter(Boolean).map(projectedRealization),
    attribution:'current task/registration/resident realization on this single configured Native site; opaque attempt/environment identities unknown'};
}

async function boundedRead(path,maximum) {
  const f=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);
  try {const st=await f.stat();assert(st.isFile()&&st.size<=maximum,'WholeRunReadLimit');
    const bytes=await f.readFile();assert(bytes.length<=maximum,'WholeRunReadLimit');return bytes;
  } finally {await f.close();}
}

// The caller supplies a trusted local directory and pin; the payload is not an issuer.
export async function loadWholeRunProfile(directory,expectedDigest) {
  const started=performance.now(), bytes=await boundedRead(join(directory,'whole-run.json'),wholeRunLimits.reportBytes);
  const digest=profileDigest(bytes);
  if(expectedDigest!==undefined) assert.equal(digest,expectedDigest,'WholeRunProfilePinMismatch');
  const report=JSON.parse(bytes);
  assert.equal(report.version,'actql-local-whole-run-profile/0.1');
  assert.equal(report.measurementScope,wholeRunScope);
  assert(['comparison','evaluation'].includes(report.stage));
  assert.equal(report.concurrency,1);assert(report.observations.length<=wholeRunLimits.observations);
  const fixture=retainedCase(report.fixture.workload,report.fixture.layout,report.fixture.rows);
  assert.equal(fixture.id,report.caseId);assert.deepEqual(report.expected,fixture.identity());
  const originalDigests=new Set();
  for(const [index,item] of report.observations.entries()) {
    assert.equal(item.index,index);assert.deepEqual(item.step,report.schedule[index]);
    assert.equal(item.conditions.runtimeRevision,report.revision);
    assert.equal(item.conditions.binaryDigest,report.binaryDigest);
    assert.equal(item.conditions.measurementScope,wholeRunScope);
    const raw=await boundedRead(join(directory,'trial-'+index,'observation.json'),wholeRunLimits.memberBytes);
    assert.equal(profileDigest(raw),item.originalDigest,'WholeRunOriginalChanged');
    assert(!originalDigests.has(item.originalDigest),'RepeatedWholeRunOriginal');originalDigests.add(item.originalDigest);
    const projected=structuredClone(item);delete projected.originalDigest;delete projected.callerElapsedMs;delete projected.recordingMs;delete projected.checkpointMs;
    assert.deepEqual(JSON.parse(raw),projected,'WholeRunOriginalProjectionChanged');
    assert(['succeeded','failed','interrupted','unobserved'].includes(item.outcome));
    assert(finite(item.callerElapsedMs)&&finite(item.recordingMs));
    if(item.outcome!=='succeeded') {assert.equal(item.ownerAccepted,false);continue;}
    assert.equal(item.ownerAccepted,true);
    const stdout=await boundedRead(join(directory,'trial-'+index,'stdout.log'),wholeRunLimits.memberBytes);
    const stderr=await boundedRead(join(directory,'trial-'+index,'stderr.log'),wholeRunLimits.memberBytes);
    assert.equal(profileDigest(stdout),item.stdoutDigest);assert.equal(profileDigest(stderr),item.stderrDigest);
    const execution=readNativeDirectProductExecution(item.invocation,{stdout:stdout.toString(),stderr:stderr.toString(),processCycleMs:item.processCycleMs});
    const product=admitNativeDirectProduct(fixture,item.invocation,execution);
    assert.deepEqual(execution.resultSchemaFields,fixture.workload==='fixed-join-count-shrinking-intermediate'?['n','present']:fixture.fields,'WholeRunResultSchemaChanged');
    assert.deepEqual(product.ownerCorrespondence,item.owner);
    if(item.step.arm!=='offline'&&!item.fallback) assert.deepEqual(admitWholeRunTrajectory(execution,product),item.trajectory);
    assert.deepEqual(product.record.usage,item.finalUsage);
  }
  const reportValue=freeze(report);
  return freeze({report:reportValue,profileRevision:digest,readbackMs:performance.now()-started});
}

export function wholeRunTemplate({profile,conditions,candidates,now,maxAgeMs=86400000}) {
  assert(Number.isSafeInteger(now)&&now>=0&&maxAgeMs>0&&maxAgeMs<=wholeRunLimits.maxAgeMs);
  const body=JSON.parse(candidates.canonical_json);
  assert.equal(profileDigest(candidates.canonical_json),candidates.cid,'WholeRunCandidateBytesChanged');
  assert.equal(body[0],'actql-policy-candidates/0.1');
  assert.equal(profile.report.stage,'comparison');
  assert(profile.report.observations.length>0,'EmptyWholeRunProfile');
  const compatible=profile.report.observations.filter(o=>profileDigest(o.conditions)===profileDigest(conditions));
  const selected=compatible.length?compatible:profile.report.observations;
  const oldest=Math.min(...selected.map(o=>o.observedAt)),newest=Math.max(...selected.map(o=>o.observedAt));
  const common=!compatible.length?'conditions-mismatch':now<newest||now-oldest>maxAgeMs?'freshness-insufficient':null;
  const entries=body[5].map(assignment=>{
    const attempted=compatible.filter(o=>o.step.position===assignment[0]);
    const attributed=attempted.filter(o=>o.outcome==='succeeded'&&o.ownerAccepted&&o.trajectory&&
      profileDigest(JSON.stringify(o.owner.observations.candidates[0].body))===candidates.cid&&
      profileDigest(o.trajectory.initialAssignment)===profileDigest(assignment)&&finite(o.callerElapsedMs));
    const reason=common??(attempted.length!==3||attributed.length!==3?'candidate-attribution-insufficient':null);
    const d=describe(reason?[]:attributed.map(o=>o.callerElapsedMs));
    return {position:assignment[0],task:1,quantity:'run-caller-elapsed',status:reason?'unknown':'reference',reason:reason??'',
      median_ms:d.median,minimum_ms:d.minimum,maximum_ms:d.maximum,sample_count:attributed.length};
  });
  assert(entries.length<=64,'WholeRunEstimateEntryLimit');
  const template={version:'actql-operational-estimate/0.1',profile_revision:profile.profileRevision,
    candidate_snapshot_cid:candidates.cid,conditions:conditions.nativeConditions,
    oldest_ms:String(oldest),newest_ms:String(newest),max_age_ms:String(maxAgeMs),capture_ms:null,
    overhead:'unknown-no-off-comparison',entries};
  assert(Buffer.byteLength(JSON.stringify(template))<=60*1024,'WholeRunEstimateTemplateLimit');
  return template;
}

export function wholeRunValue({creationMs,firstUseMs,offlineMs,reusedMs}) {
  assert([creationMs,firstUseMs,offlineMs,reusedMs].every(finite));
  const reusedSavingMs=offlineMs-reusedMs,initialExtraMs=firstUseMs-offlineMs;
  const unrecoveredMs=Math.max(0,creationMs+initialExtraMs);
  return {creationMs,initialExtraMs,reusedSavingMs,conditionalRecoveryUses:reusedSavingMs>0?Math.ceil(unrecoveredMs/reusedSavingMs):null,
    assumption:'observed reuse saving continues at unchanged revision/conditions; recollection invalidates this reference',eta:null,p90:null};
}

export {describe as describeWholeRun};
