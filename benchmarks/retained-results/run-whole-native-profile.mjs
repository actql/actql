// Fixed local synthetic experiment. No CI, export, public cancellation or retry.
import assert from 'node:assert/strict';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {join,resolve,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {cpus,release,loadavg} from 'node:os';
import {retainedCase} from './fixtures.mjs';
import {profileDigest} from './local-performance-profile.mjs';
import {sha256File} from './release-artifacts.mjs';
import {prepareNativeDirectProduct,executeNativeDirectProduct,admitNativeDirectProduct} from './native-direct-product.mjs';
import {wholeRunScope,wholeRunLimits,loadWholeRunProfile,loadWholeRunCreationCost,wholeRunTemplate,admitWholeRunTrajectory} from './whole-run-profile.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const [destinationArg,stage,planArg,profileArg]=process.argv.slice(2),destination=resolve(destinationArg??'');
assert((stage==='comparison'&&process.argv.length===5)||(stage==='evaluation'&&process.argv.length===6));
assert(destination!==root&&!destination.startsWith(root+sep),'ExternalOwnedDirectoryRequired');
assert.notEqual(process.env.ACTQL_NATIVE_PROBE_PROFILE,'debug');
const git=args=>execFileSync('git',args,{cwd:root,encoding:'utf8'}).trim();
const revision=git(['rev-parse','HEAD']);assert.equal(git(['status','--porcelain']),'','WholeRunRequiresCleanSource');
const plan=JSON.parse(await readFile(resolve(planArg),'utf8'));
assert.equal(plan.version,'actql-local-whole-run-plan/0.1');assert.equal(plan.revision,revision);
assert.equal(plan.concurrency,1);assert.equal(plan.rounds,3);
const fixture=retainedCase(plan.fixture.workload,plan.fixture.layout,plan.fixture.rows);
const positions=plan.candidates.body[5].map(a=>a[0]);
assert(positions.length>1&&positions.length<=wholeRunLimits.positions,'WholeRunFiniteCandidateLimit');
assert.equal(new Set(positions).size,positions.length);
assert.equal(plan.candidates.cid,profileDigest(JSON.stringify(plan.candidates.body)));
const binary=join(root,'_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const binaryDigest='sha256:'+await sha256File(binary);
const witness=JSON.parse(await readFile(join(root,'_build/local-whole-native-build.json'),'utf8'));
assert.equal(witness.revision,revision);assert.equal(witness.binaryDigest,binaryDigest);assert.equal(witness.exitCode,0);
const inputDigest='sha256:'+await sha256File(plan.database);
assert.equal(inputDigest,plan.inputDigest);
const instrumentationFiles=['run-whole-native-profile.mjs','whole-run-profile.mjs','native-direct-product.mjs','native-owner-observations.mjs','native-physical-phases.mjs'];
const instrumentationRevision=profileDigest(await Promise.all(instrumentationFiles.map(async p=>[p,'sha256:'+await sha256File(join(root,'benchmarks/retained-results',p))])));
const environment={platform:process.platform,arch:process.arch,osRelease:release(),cpuModels:[...new Set(cpus().map(c=>c.model))],
  logicalCpus:cpus().length,node:process.version,competingLoad:'uncontrolled',osCache:'uncontrolled',
  libraryDigest:'sha256:'+await sha256File(plan.library),toolchain:JSON.parse(await readFile(join(root,'toolchain.json'),'utf8'))};
const legacyNativeConditions={host:'native',realization:'resident',captureMode:'metadata-only',runtimeRevision:revision,binaryDigest,inputDigest,
  programDigest:profileDigest(fixture.program()),inputRows:fixture.rows,schemaLayout:fixture.layout,limitsDigest:profileDigest(fixture.limits),
  instrumentationRevision,measurementScopeRevision:profileDigest(wholeRunScope),environmentDigest:profileDigest(environment),
  controlDigest:profileDigest(plan.controls),concurrency:1,processState:'new-process-and-environment',osCache:'uncontrolled',
  authorizedScope:'local-synthetic-fixture-only; no export/sharing'};
const nativeConditions=plan.normalHost?plan.normalHost.conditions:legacyNativeConditions;
if(plan.normalHost) {
  assert.equal(nativeConditions.runtimeRevision,revision);
  assert.equal(nativeConditions.binaryDigest,binaryDigest);
  assert.equal(nativeConditions.captureMode,'metadata-only');
  assert.equal(nativeConditions.concurrency,1);
}
const conditions={runtimeRevision:revision,binaryDigest,measurementScope:wholeRunScope,nativeConditions};
const schedule=stage==='comparison'?[0,1,2].flatMap(round=>(round%2?[...positions].reverse():positions)
  .map(position=>({round,arm:'forced',position})))
  : [['offline','first-use','reuse'],['reuse','offline','first-use'],['first-use','reuse','offline']]
    .flatMap((arms,round)=>arms.map(arm=>({round,arm})));
assert(schedule.length<=wholeRunLimits.observations);
await mkdir(destination,{mode:0o700});
const report={version:'actql-local-whole-run-profile/0.1',revision,binaryDigest,buildWitness:witness,
  stage,caseId:fixture.id,fixture:plan.fixture,expected:fixture.identity(),conditions,measurementScope:wholeRunScope,
  limits:fixture.limits,concurrency:1,schedule,planDigest:profileDigest(plan),controls:plan.controls,
  fixturePreparationMs:plan.fixturePreparationMs,observations:[],accepted:false,
  creationMs:null,profileOriginal:null,osCache:'uncontrolled',
  intervalRules:'enclosing elapsed clock is primary; nested preparation, import, task, observer and release intervals are never added',
  normalHost:plan.normalHost??null,
  cache:'one validated immutable local profile; no cached request, authority or deadline; no persistence across experiment processes'};
const encode=value=>JSON.stringify(value,(_key,value)=>typeof value==='bigint'?String(value):value);
const checkpoint=()=>writeFile(join(destination,'whole-run.json'),encode(report)+'\n',{mode:0o600});
await checkpoint();
const campaignStarted=performance.now();let cache=null,creationCost=null;
for(const [index,step] of schedule.entries()) {
  const trial=join(destination,'trial-'+index);
  const item={index,step,conditions,observedAt:Date.now(),outcome:'unobserved',ownerAccepted:false,
    profileReadbackMs:0,templateMs:0,profileOriginal:null};
  const started=performance.now();
  item.loadObservation={sampledAt:Date.now(),systemLoadAverage:loadavg(),logicalCpus:cpus().length,
    applicationConcurrency:1,competingProcesses:'unknown',memoryPressure:'unknown',
    applicability:'unknown-uncontrolled',causalPerformanceAttribution:'unknown'};
  item.memoryBefore=process.memoryUsage();let execution;
  try {
    await mkdir(trial,{mode:0o700});
    if(step.arm==='first-use') {
      const loadStarted=performance.now();cache=await loadWholeRunProfile(resolve(profileArg));
      item.profileReadbackMs=performance.now()-loadStarted;
    }
    if(step.arm==='reuse') assert(cache,'ReuseWithoutAdmittedFirstUse');
    if(step.arm==='first-use'||step.arm==='reuse') {
      assert.equal(cache.report.revision,revision);assert.equal(cache.report.binaryDigest,binaryDigest);
      assert.equal(cache.report.accepted,true);assert.equal(cache.report.stage,'comparison');
      assert.equal(cache.report.caseId,fixture.id);
      assert.deepEqual(cache.report.conditions,conditions,'WholeRunProfileConditionsChanged');
      if(report.profileOriginal!==null) assert.equal(report.profileOriginal,cache.profileRevision,'WholeRunOriginalDrift');
      report.profileOriginal=cache.profileRevision;item.profileOriginal=cache.profileRevision;
    }
    let invocation=await prepareNativeDirectProduct({root,fixture,database:plan.database,directory:trial,
      ...plan.controls,phaseObserver:true});
    assert.equal(invocation.binary,binary);
    if(step.arm!=='offline' && (!plan.normalHost || stage==='comparison')) {
      const extra=['--empirical-mode',step.arm==='forced'?'forced':'empirical','--empirical-objective','run-caller-elapsed',
        '--empirical-fallback','offline','--sqlite-library','/usr/lib/libsqlite3.dylib'];
      if(step.arm==='forced') extra.push('--empirical-position',String(step.position));
      else {
        const templateStart=performance.now();
        const candidates={canonical_json:JSON.stringify(plan.candidates.body),cid:plan.candidates.cid};
        const template=wholeRunTemplate({profile:cache,conditions,candidates,now:Date.now()});
        const bytes=JSON.stringify(template);
        await writeFile(join(trial,'task-1.json'),bytes,{flag:'wx',mode:0o600});
        extra.push('--empirical-profile-root',trial,'--empirical-profile-revision',cache.profileRevision,
          '--empirical-template-pin',profileDigest(bytes));
        item.templateMs=performance.now()-templateStart;
      }
      invocation={...invocation,arguments:[...invocation.arguments,...extra]};
    }
    if(plan.normalHost) {
      let templateBytes,mode='diagnostic-reference';
      if(stage==='evaluation'&&step.arm!=='offline') {
        mode='select-reference';
        const templateStart=performance.now();
        templateBytes=JSON.stringify(wholeRunTemplate({profile:cache,conditions,
          candidates:{canonical_json:JSON.stringify(plan.candidates.body),cid:plan.candidates.cid},now:Date.now()}));
        await writeFile(join(trial,'normal-template.json'),templateBytes,{flag:'wx',mode:0o600});
        item.templateMs=performance.now()-templateStart;
      }
      if(templateBytes&&creationCost===null) creationCost=await loadWholeRunCreationCost(resolve(profileArg),cache);
      const settings={...plan.normalHost.settings,mode,
        profile_file:templateBytes?'normal-template.json':'-',
        profile_digest:templateBytes?profileDigest(templateBytes).slice(7):'-',
        profile_revision:templateBytes?cache.profileRevision:'-',
        profile_creation_ms:templateBytes?creationCost.profileCreationMs:null};
      await writeFile(join(trial,'normal-settings.json'),JSON.stringify(settings),{flag:'wx',mode:0o600});
      // Offline is genuinely unconfigured: no profile or input identity work.
      // Its Source/profile input identity is separately pinned by this producer.
      invocation={...invocation,environment:stage==='evaluation'&&step.arm==='offline'?{}:
        {ACTQL_NATIVE_HOST_PROFILE_SETTINGS:'normal-settings.json'}};
    }
    const processStart=performance.now();
    execution=await executeNativeDirectProduct(invocation,{root,timeoutMs:fixture.limits.timeoutMs});
    item.processCycleMs=performance.now()-processStart;
    const product=admitNativeDirectProduct(fixture,invocation,execution);
    assert.deepEqual(product.ownerCorrespondence.observations.candidates[0].body,plan.candidates.body,'WholeRunInitialSnapshotDrift');
    assert.deepEqual(execution.resultSchemaFields,fixture.workload==='fixed-join-count-shrinking-intermediate'?['n','present']:fixture.fields,'IndependentResultSchemaFieldsMismatch');
    item.invocation=invocation;item.owner=product.ownerCorrespondence;item.finalUsage=product.record.usage;
    item.operator={preparation:product.preparation,physicalPhases:product.physicalPhases,
      taskIntervals:product.taskIntervals,holdings:product.taskHoldings,usage:product.taskUsages,
      expectedResult:fixture.identity(),result:product.record.rows_cid};
    const normalDecisions=execution.stdout.split('\n').filter(l=>l.startsWith('normal-host-decision:')).map(l=>JSON.parse(l.slice('normal-host-decision:'.length)));
    item.normalDecisions=normalDecisions;
    item.normalProfileCosts={decisions:normalDecisions.map(d=>d.costs),creationCost,
      creationScope:'comparison campaign and final original validation once; not added to first-use latency',
      nativeReuse:'same immutable template across requests in this Run; process restart loads anew',
      additionalTelemetryOverhead:'unknown-no-off-comparison'};
    item.fallback=normalDecisions.length?normalDecisions[0].mode==='select-reference'&&normalDecisions[0].selected_position===null:
      execution.stdout.includes('empirical-fallback:1:incomplete-reference')||execution.stdout.includes('empirical-fallback:1:freshness-insufficient');
    if(plan.normalHost && !(stage==='evaluation'&&step.arm==='offline')) {
      const line=execution.stdout.split('\n').find(l=>l.startsWith('normal-host-conditions:'));
      assert(line,'MissingNormalHostOwnedConditions');
      assert.deepEqual(JSON.parse(line.slice('normal-host-conditions:'.length)),nativeConditions,'NormalHostOwnedConditionsChanged');
    }
    if(step.arm!=='offline'&&!item.fallback) item.trajectory=admitWholeRunTrajectory(execution,product);
    if(step.arm==='forced') assert.equal(item.owner.observations.choices[0].position,step.position);
    item.outcome='succeeded';item.ownerAccepted=true;
  } catch(error) {
    item.outcome=error.signal?'interrupted':'failed';item.ownerAccepted=false;
    item.failure={code:typeof error.code==='number'||typeof error.code==='string'?error.code:null,signal:error.signal??null,
      assertion:error.code==='ERR_ASSERTION'?error.message:null,cleanup:'unknown'};
    execution={stdout:execution?.stdout??error.stdout??'',stderr:execution?.stderr??error.stderr??''};
  }
  const stdout=execution.stdout,stderr=execution.stderr;
  assert(Buffer.byteLength(stdout)<=wholeRunLimits.memberBytes&&Buffer.byteLength(stderr)<=wholeRunLimits.memberBytes);
  await writeFile(join(trial,'stdout.log'),stdout,{flag:'wx',mode:0o600});
  await writeFile(join(trial,'stderr.log'),stderr,{flag:'wx',mode:0o600});
  item.stdoutDigest=profileDigest(stdout);item.stderrDigest=profileDigest(stderr);
  item.memoryAfter=process.memoryUsage();
  const recordingStarted=performance.now(),bytes=encode(item)+'\n';
  assert(Buffer.byteLength(bytes)<=wholeRunLimits.memberBytes);
  await writeFile(join(trial,'observation.json'),bytes,{flag:'wx',mode:0o600});
  assert.equal(await readFile(join(trial,'observation.json'),'utf8'),bytes);
  item.originalDigest=profileDigest(bytes);item.recordingMs=performance.now()-recordingStarted;
  item.callerElapsedMs=performance.now()-started;
  report.observations.push(item);const checkpointStart=performance.now();await checkpoint();
  item.checkpointMs=performance.now()-checkpointStart;
  item.callerElapsedMs=performance.now()-started;
  console.log(JSON.stringify({case:fixture.id,index,arm:step.arm,outcome:item.outcome,elapsedMs:item.callerElapsedMs}));
  if(!item.ownerAccepted) break; // Preserve unresolved responsibility; no replacement or new admission.
}
report.accepted=report.observations.length===schedule.length&&report.observations.every(o=>o.ownerAccepted);
if(stage==='comparison') report.creationMs=performance.now()-campaignStarted;
await checkpoint();
assert(report.accepted,'WholeRunCampaignIncomplete');
const admissionStart=performance.now();await loadWholeRunProfile(destination);
const originalAdmissionMs=performance.now()-admissionStart;
await writeFile(join(destination,'cost-receipt.json'),JSON.stringify({originalDigest:profileDigest(await readFile(join(destination,'whole-run.json'))),
  originalAdmissionMs,profileCreationMs:stage==='comparison'?report.creationMs+originalAdmissionMs:null,
  scope:'creation includes the comparison campaign and final validation once; fixture DB construction is separate; no overlapping phase sum'},null,2)+'\n',{flag:'wx',mode:0o600});
console.log(JSON.stringify({accepted:true,stage,executions:report.observations.length,originalAdmissionMs}));
