// Independent held-out readback. No execution, profile update or selection grant.
import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {loadLocalOperationalProfile, localOperationalTemplate} from './operational-estimates.mjs';
import {profileDigest} from './local-performance-profile.mjs';

const describe = values => {
  const sorted = [...values].sort((a,b)=>a-b);
  assert(sorted.every(value=>Number.isFinite(value)&&value>=0));
  return {count:sorted.length,median:sorted.length?sorted[Math.floor(sorted.length/2)]:null,
    minimum:sorted.length?sorted[0]:null,maximum:sorted.length?sorted.at(-1):null};
};
export async function compareNativeEmpiricalRuns(comparisonDirectory,evaluationDirectory) {
  const started=performance.now();
  const comparison=await loadLocalOperationalProfile(comparisonDirectory);
  const evaluation=await loadLocalOperationalProfile(evaluationDirectory);
  assert(comparison.report.accepted&&evaluation.report.accepted,'IncompleteEmpiricalAcceptance');
  assert.equal(comparison.report.scheduleKind,'empirical-comparison');
  assert.equal(evaluation.report.scheduleKind,'empirical-evaluation');
  assert.equal(comparison.report.revision,evaluation.report.revision);
  assert.equal(comparison.report.binaryDigest,evaluation.report.binaryDigest);
  assert.equal(evaluation.report.empiricalPlan.profileOriginal,comparison.profileRevision);
  const oldIds=new Set(comparison.report.observations.map(o=>o.originalRecordDigest));
  assert(evaluation.report.observations.every(o=>!oldIds.has(o.originalRecordDigest)),'EvaluationReusedComparisonObservation');
  const initial=comparison.report.observations[0],projection=initial.mapping.candidateProjections.find(p=>p.task===1).body;
  const candidates={canonical_json:JSON.stringify(projection),cid:profileDigest(JSON.stringify(projection))};
  const template=localOperationalTemplate({profile:comparison,conditions:initial.conditions,task:1,candidates,
    // Check the frozen analysis at its original observation point; this does
    // not authorize later reuse after the operational window expires.
    now:Math.max(...comparison.report.observations.map(o=>o.observedAt))});
  const quantities=template.entries.filter(e=>e.quantity==='task-processing');
  assert.equal(quantities.length,projection[5].length);
  assert(quantities.every(e=>e.status==='reference'&&e.sample_count===3),'IncompleteComparedPositions');
  const chosen=[...quantities].sort((a,b)=>a.median_ms-b.median_ms||a.position-b.position)[0].position;
  const groups=Object.fromEntries(['empirical','offline-fallback'].map(arm=>[arm,evaluation.report.observations.filter(o=>o.intervention.arm===arm)]));
  for (const item of evaluation.report.observations) {
    assert.deepEqual(item.conditions,initial.conditions,'EvaluationExposureChanged');
    assert.deepEqual(item.mapping.candidateProjections.find(p=>p.task===1).body,projection);
    assert.equal(item.mapping.choices.length,3);assert.equal(item.mapping.holdings.length,3);
    assert(item.mapping.choices.slice(1).every(c=>['OfflineLatency','BoundedLatency'].includes(c.source)));
    const current=item.mapping.choices[0];
    if(item.intervention.arm==='empirical') {
      assert.equal(current.source,'ExternalPolicy');assert.equal(current.position,chosen);
      assert.equal(item.empirical.rankings[0].selected_position,chosen);
      assert.equal(item.empirical.rankings[0].profile_revision,comparison.profileRevision);
      assert.equal(item.empirical.oldStateRefusals.length,2);
      assert.equal(current.policy.revision,item.empirical.rankings[0].policy_revision);
    } else {
      assert.equal(current.source,'OfflineLatency');assert.equal(current.position,0);
      assert.equal(item.empirical.rankings[0].selected_position,null);
      assert.equal(item.empirical.rankings[0].reason,item.round===2?'freshness-insufficient':'incomplete-reference');
      assert(item.empirical.fallbacks.includes('1:'+item.empirical.rankings[0].reason));
      const missing=item.empirical.sidecars[0].entries.filter(e=>e.quantity==='task-processing'&&e.status==='unknown');
      assert.equal(missing.length,item.round===0?2:item.round===1?1:0);
    }
  }
  const byArm=Object.fromEntries(Object.entries(groups).map(([arm,items])=>{
    assert.equal(items.length,3);
    return [arm,{taskProcessingMs:describe(items.map(o=>o.operatorMeasurements.tasks.find(t=>t.task===1).executionMicroseconds/1000)),
      processCycleMs:describe(items.map(o=>o.metrics.processCycleMs)),coldMs:describe(items.map(o=>o.metrics.coldMs)),
      warmMs:describe(items.map(o=>o.metrics.warmMs)),cleanupMs:describe(items.map(o=>o.metrics.cleanupMs)),
      recordingMs:describe(items.map(o=>o.metrics.recordingMs)),captureMs:describe(items.map(o=>o.metrics.captureMs)),
      rawStreamRecordingAndDigestMs:describe(items.map(o=>o.rawEvidence.recordingAndDigestMs)),
      templatePreparationMs:describe(items.map(o=>o.empirical.templatePreparationMs)),
      observedEndToEndMs:describe(items.map(o=>o.metrics.observedEndToEndMs)),
      consultationMs:describe(items.map(o=>o.empirical.consultationMicroseconds.reduce((a,b)=>a+b,0)/1000)),
      attempts:items.map(o=>o.mapping.attempts),physicalPhases:items.map(o=>o.operatorMeasurements.physicalPhases),
      taskCosts:items.map(o=>o.operatorMeasurements.tasks),preparation:items.map(o=>o.preparation)}];
  }));
  return {version:'actql-empirical-comparison/0.1',revision:comparison.report.revision,
    binaryDigest:comparison.report.binaryDigest,candidateSnapshotCid:candidates.cid,
    comparisonProfileRevision:comparison.profileRevision,evaluationOriginalRevision:evaluation.profileRevision,
    objective:'first-task-processing-median',chosenPosition:chosen,selectedAssignmentScope:'includes subsequent tasks; no whole-assignment optimum',
    comparedReferences:quantities,groups:byArm,selectionChanged:chosen!==0,
    heldOutProcessingMedianDifferenceMs:byArm['offline-fallback'].taskProcessingMs.median-byArm.empirical.taskProcessingMs.median,
    reductionClaim:'descriptive held-out first-task processing only; no causal confidence, whole-cycle fastest or ETA claim',
    baselineScope:'controlled declared estimates prefer position 0; explicit offline fallback with unknown-profile diagnostics, not an uninstrumented default',
    referenceReadbackAndAggregationMs:performance.now()-started,
    evaluationProfileReadbackAndAggregationMs:evaluation.report.empiricalPlan.profileReadbackAndAggregationMs,
    directCostScope:'individual original/raw recording, template construction, capture, consultation and aggregation overlap enclosing intervals; not additive operator costs',
    offComparisonOverhead:'unknown',eta:null,p90:null};
}
