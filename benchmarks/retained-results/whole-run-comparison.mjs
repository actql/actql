// Independent held-out consumer. No execution, profile update or policy grant.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {performance} from 'node:perf_hooks';
import {loadWholeRunProfile,wholeRunTemplate,describeWholeRun,wholeRunValue} from './whole-run-profile.mjs';
import {profileDigest} from './local-performance-profile.mjs';
export async function compareWholeNativeProfiles(comparisonDirectory,evaluationDirectory) {
  const started=performance.now();
  const comparison=await loadWholeRunProfile(comparisonDirectory),evaluation=await loadWholeRunProfile(evaluationDirectory);
  const a=comparison.report,b=evaluation.report;
  assert.equal(a.stage,'comparison');assert.equal(b.stage,'evaluation');assert(a.accepted&&b.accepted);
  assert.deepEqual(a.conditions,b.conditions);assert.equal(a.revision,b.revision);assert.equal(a.binaryDigest,b.binaryDigest);
  assert.equal(b.profileOriginal,comparison.profileRevision);
  const old=new Set(a.observations.map(o=>o.originalDigest));
  assert(b.observations.every(o=>!old.has(o.originalDigest)),'HeldOutOriginalOverlap');
  const body=a.observations[0].owner.observations.candidates[0].body;
  const candidates={canonical_json:JSON.stringify(body),cid:profileDigest(JSON.stringify(body))};
  const template=wholeRunTemplate({profile:comparison,conditions:a.conditions,candidates,
    now:Math.max(...a.observations.map(o=>o.observedAt))});
  assert(template.entries.every(e=>e.status==='reference'&&e.sample_count===3),'IncompleteWholeRunComparison');
  const chosen=[...template.entries].sort((x,y)=>x.median_ms-y.median_ms||x.position-y.position)[0].position;
  const groups=Object.fromEntries(['offline','first-use','reuse'].map(arm=>{
    const items=b.observations.filter(o=>o.step.arm===arm);assert.equal(items.length,3);
    for(const o of items) {
      if(arm!=='offline') {assert.equal(o.fallback,false);assert.equal(o.trajectory.initialAssignment[0],chosen);
        assert(o.owner.observations.choices.every(c=>c.source==='ExternalPolicy'));
      } else {assert(o.owner.observations.choices.every(c=>['OfflineLatency','BoundedLatency'].includes(c.source)));assert.equal(o.profileReadbackMs,0);}
    }
    return [arm,{callerElapsedMs:describeWholeRun(items.map(o=>o.callerElapsedMs)),
      processCycleMs:describeWholeRun(items.map(o=>o.processCycleMs)),
      profileReadbackMs:describeWholeRun(items.map(o=>o.profileReadbackMs)),
      templateMs:describeWholeRun(items.map(o=>o.templateMs)),recordingMs:describeWholeRun(items.map(o=>o.recordingMs)),
      choices:items.map(o=>o.owner.observations.choices),attempts:items.map(o=>o.owner.attempts),
      phases:items.map(o=>o.operator),originals:items.map(o=>o.originalDigest)}];
  }));
  const receipt=JSON.parse(await readFile(join(comparisonDirectory,'cost-receipt.json'),'utf8'));
  assert.equal(receipt.originalDigest,comparison.profileRevision);
  const value=wholeRunValue({creationMs:receipt.profileCreationMs,firstUseMs:groups['first-use'].callerElapsedMs.median,
    offlineMs:groups.offline.callerElapsedMs.median,reusedMs:groups.reuse.callerElapsedMs.median});
  return {version:'actql-local-whole-run-comparison/0.1',revision:a.revision,binaryDigest:a.binaryDigest,caseId:a.caseId,
    comparisonOriginal:comparison.profileRevision,evaluationOriginal:evaluation.profileRevision,
    measurementScope:a.measurementScope,comparedReferences:template.entries,chosenPosition:chosen,groups,value,
    firstUseDifferenceMs:groups.offline.callerElapsedMs.median-groups['first-use'].callerElapsedMs.median,
    independentReadbackMs:performance.now()-started,
    fixturePreparationMs:a.fixturePreparationMs,
    reductionClaim:'three held-out runs per arm; descriptive enclosing caller latency only; no causal confidence, ETA, p90 or general workload guarantee',
    recollection:'new revision or changed conditions invalidates references and needs another fixed comparison campaign; its observed creation cost is the only available reference',
    telemetryOverhead:'unknown-no-off-comparison',eta:null,p90:null};
}
