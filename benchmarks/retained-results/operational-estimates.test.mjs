import assert from 'node:assert/strict';
import test from 'node:test';
import {localOperationalTemplate, bindOperationalTemplate} from './operational-estimates.mjs';
import {nativeOperationalSchedule, nativeEmpiricalSchedule, profileDigest, describeObservationOverhead} from './local-performance-profile.mjs';
const conditions = {host:'native',realization:'resident',captureMode:'metadata-only',runtimeRevision:'r',binaryDigest:'b',inputDigest:'i',programDigest:'p',inputRows:1000,schemaLayout:'text-1024',limitsDigest:'l',instrumentationRevision:'o',measurementScopeRevision:'m',environmentDigest:'e',controlDigest:'c',concurrency:1,processState:'new-process-and-environment',osCache:'uncontrolled',authorizedScope:'local-synthetic-fixture-only; no export/sharing'};
const projection = ['actql-policy-candidates/0.1','program',0,0,true,[[0,1,0,1,1,[null,['offer']]]]];
const candidates = {canonical_json:JSON.stringify(projection),cid:profileDigest(JSON.stringify(projection))};
const sample = index => ({observedAt:1000,conditions:{...conditions},outcome:'succeeded',ownerAccepted:true,unknown:[],capture:{status:'complete'},metrics:{captureMs:2},mapping:{candidateProjections:[{task:1,body:projection}],choices:[{task:1,position:0}]},operatorMeasurements:{status:'observed',tasks:[{task:1,executionMicroseconds:1000*(index+1),releaseMicroseconds:500}],physicalPhases:{intervals:[{task:1,phase:'environment',elapsedMicroseconds:100},{task:1,phase:'import',elapsedMicroseconds:200}]}}});
const profile = {profileRevision:'sha256:profile',report:{observations:[0,1,2].map(sample)}};
const reference = changes => localOperationalTemplate({profile:structuredClone(profile),conditions:{...conditions},candidates,task:1,now:1100,...changes});

test('fixed metadata schedule has six runs, concurrency is caller-controlled and no off comparison exists', () => {
  assert.deepEqual(nativeOperationalSchedule().map(x => [x.round,x.realization,x.mode]),[0,1,2].flatMap(round => [[round,'fresh','metadata-only'],[round,'resident','metadata-only']]));
  assert(describeObservationOverhead([]).every(item=>item.status==='unknown'&&item.pairs.length===0));
});
test('measured task processing is a descriptive reference; prep, import and release stay separate', () => {
  const sidecar = reference();
  assert.deepEqual(sidecar.entries.map(x=>[x.quantity,x.median_ms]),[['task-processing',2],['task-release',0.5],['resident-preparation',0.1],['resident-import',0.2]]);
  assert.equal(sidecar.entries[0].sample_count,3);
  assert.equal(sidecar.entries[0].minimum_ms,1);assert.equal(sidecar.entries[0].maximum_ms,3);
  assert.equal(sidecar.overhead,'unknown-no-off-comparison');
  assert(!('eta' in sidecar) && !('p90' in sidecar));
});
for (const key of ['inputDigest','runtimeRevision','binaryDigest','captureMode','instrumentationRevision']) {
  test(`different ${key} has a reasoned unknown, not a prior revision reference`, () => {
    const value = reference({conditions:{...conditions,[key]:'different'}});
    assert(value.entries.every(x=>x.status==='unknown'&&x.reason==='conditions-mismatch'&&x.median_ms===null));
  });
}
test('stale/future or insufficient success cannot be promoted to a reference', () => {
  assert(reference({now:900}).entries.every(x=>x.reason==='freshness-insufficient'));
  assert(reference({now:2000,maxAgeMs:1}).entries.every(x=>x.reason==='freshness-insufficient'));
  for (const outcome of ['failed','cancelled','interrupted','unobserved']) {
    const changed=structuredClone(profile);changed.report.observations[2].outcome=outcome;
    assert(reference({profile:changed}).entries.every(x=>x.reason==='samples-insufficient'));
  }
});
test('unselected candidate, missing phase and changed snapshot cannot borrow a selected task observation', () => {
  const changed=structuredClone(profile);changed.report.observations[2].mapping.choices[0].position=1;
  assert(reference({profile:changed}).entries.every(x=>x.reason==='candidate-attribution-insufficient'));
  const absent=structuredClone(profile);absent.report.observations.forEach(x=>{delete x.operatorMeasurements.physicalPhases;});
  const entries=reference({profile:absent}).entries;
  assert.equal(entries[0].status,'reference');assert(entries.slice(2).every(x=>x.reason==='quantity-unobserved'));
  assert.throws(()=>reference({candidates:{...candidates,canonical_json:'[]'}}),/CandidateBytesMismatch/);
});
test('independent binding refuses another snapshot and does not change candidate bytes or requests', () => {
  const pending={version:'actql-placement-policy/0.1',request_id:'q',run_identity:'r',authority:'a',generation:0,revision:0,deadline_ms:'2000',candidate_set_cid:candidates.cid};
  const original=structuredClone(pending),before=candidates.canonical_json;
  const sidecar=bindOperationalTemplate(reference(),pending);
  assert.deepEqual(pending,original);assert.equal(before,candidates.canonical_json);
  assert.deepEqual(sidecar.binding,pending);
  assert.throws(()=>bindOperationalTemplate(reference(),{...pending,candidate_set_cid:'other'}),/SnapshotBindingMismatch/);
});


test('empirical schedules separate exposure, intervention and held-out evaluation without replacement', () => {
  for (const stage of ['comparison','evaluation']) {
    const schedule=nativeEmpiricalSchedule(stage);
    assert.equal(schedule.length,6);assert(schedule.every(s=>s.realization==='resident'&&s.mode==='metadata-only'));
    assert.deepEqual(schedule.map(s=>s.index),[0,1,2,3,4,5]);
    assert.deepEqual(schedule.map(s=>s.arm),stage==='comparison'
      ? ['position-0','position-7','position-7','position-0','position-0','position-7']
      : ['empirical','offline-fallback','offline-fallback','empirical','empirical','offline-fallback']);
  }
});

test('same exposed snapshot attributes three independent samples to each position, never pools interventions', () => {
  const two=structuredClone(projection);two[5].push([7,1,0,1,1,[null,['other-offer']]]);
  const candidates={canonical_json:JSON.stringify(two),cid:profileDigest(JSON.stringify(two))};
  const observations=[0,7].flatMap(position=>[0,1,2].map(index=>{
    const item=sample(index);item.mapping.candidateProjections[0].body=two;item.mapping.choices[0].position=position;
    item.operatorMeasurements.tasks[0].executionMicroseconds=(position===7?10:20)*1000;
    return item;
  }));
  const template=reference({profile:{profileRevision:'two',report:{observations}},candidates});
  assert.deepEqual(template.entries.filter(e=>e.quantity==='task-processing').map(e=>[e.position,e.median_ms,e.sample_count]),[[0,20,3],[7,10,3]]);
  observations[5].mapping.candidateProjections[0].body=projection;
  const partial=reference({profile:{profileRevision:'two',report:{observations}},candidates});
  assert.equal(partial.entries.find(e=>e.position===0&&e.quantity==='task-processing').status,'reference');
  assert.equal(partial.entries.find(e=>e.position===7&&e.quantity==='task-processing').reason,'candidate-attribution-insufficient');
});
