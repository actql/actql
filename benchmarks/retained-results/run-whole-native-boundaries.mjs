// Fixed functional faults, separate from every comparison/evaluation sample.
import assert from 'node:assert/strict';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {execFile,execFileSync} from 'node:child_process';
import {promisify} from 'node:util';
import {performance} from 'node:perf_hooks';
import {resolve,join,sep} from 'node:path';
import {retainedCase} from './fixtures.mjs';
import {profileDigest} from './local-performance-profile.mjs';
import {sha256File} from './release-artifacts.mjs';
import {loadWholeRunProfile,wholeRunTemplate,admitWholeRunTrajectory} from './whole-run-profile.mjs';
import {prepareNativeDirectProduct,executeNativeDirectProduct,readNativeDirectProductExecution,admitNativeDirectProduct} from './native-direct-product.mjs';
import {nativeOwnerObservations} from './native-owner-observations.mjs';

const root=process.cwd(),[planArg,profileArg,destinationArg,selectionArg]=process.argv.slice(2);
assert([5,6].includes(process.argv.length));
const destination=resolve(destinationArg);assert(destination!==root&&!destination.startsWith(root+sep));
const git=args=>execFileSync('git',args,{encoding:'utf8'}).trim();
const revision=git(['rev-parse','HEAD']);assert.equal(git(['status','--porcelain']),'');
const plan=JSON.parse(await readFile(resolve(planArg),'utf8'));
const profile=await loadWholeRunProfile(resolve(profileArg));
assert.equal(plan.revision,revision);assert.equal(profile.report.revision,revision);
assert.equal(profile.report.stage,'comparison');assert.equal(profile.report.accepted,true);
const fixture=retainedCase(plan.fixture.workload,plan.fixture.layout,plan.fixture.rows);
assert.equal(profile.report.caseId,fixture.id);
const witness=JSON.parse(await readFile(join(root,'_build/local-whole-native-build.json'),'utf8'));
assert.equal(witness.revision,revision);assert.equal(witness.exitCode,0);
const candidates={canonical_json:JSON.stringify(plan.candidates.body),cid:plan.candidates.cid};
const assignment=plan.candidates.body[5].find(a=>a[5][1]?.[9]!==null);
assert(assignment,'ResidentBoundaryRequiresPresentedResidentAssignment');
const registered=['all-unknown','partial-unknown','conditions-mismatch','stale','single-candidate',
  'binding','stop','expiry','cleanup','normal-diagnostic-no-permission','normal-select-no-permission'];
const schedule=selectionArg===undefined?registered:selectionArg.split(',');
assert(schedule.length>0&&new Set(schedule).size===schedule.length);
assert(schedule.every(name=>registered.includes(name)),'UnknownWholeRunBoundary');
const receipts=[];
await mkdir(destination,{mode:0o700});
const unknown=e=>({...e,status:'unknown',reason:'quantity-unobserved',median_ms:null,minimum_ms:null,maximum_ms:null});
for(const boundary of schedule) {
  const directory=join(destination,boundary);await mkdir(directory,{mode:0o700});
  const invocation=await prepareNativeDirectProduct({root,fixture,database:plan.database,directory,
    ...plan.controls,...(boundary==='single-candidate'?{residentPolicy:false}:{}),
    ...(boundary==='stop'?{stopAfterTask:1}:{}),phaseObserver:true});
  assert.equal('sha256:'+await sha256File(invocation.binary),witness.binaryDigest);
  let mode=['binding','stop','cleanup'].includes(boundary)?'forced':boundary==='expiry'?'expiry':'empirical';
  let current=candidates,conditions=profile.report.conditions;
  if(boundary==='single-candidate') {
    // Exposure is a separate functional run, never inserted into the profile.
    const exposed=await executeNativeDirectProduct(invocation,{root,timeoutMs:fixture.limits.timeoutMs});
    await writeFile(join(directory,'exposure-stdout.log'),exposed.stdout,{flag:'wx',mode:0o600});
    await writeFile(join(directory,'exposure-stderr.log'),exposed.stderr,{flag:'wx',mode:0o600});
    const accepted=admitNativeDirectProduct(fixture,invocation,exposed);
    const body=accepted.ownerCorrespondence.observations.candidates[0].body;
    assert.equal(body[5].length,1);
    current={canonical_json:JSON.stringify(body),cid:profileDigest(JSON.stringify(body))};
  }
  if(boundary==='conditions-mismatch') conditions={...conditions,runtimeRevision:'functional-condition-mismatch'};
  let template=wholeRunTemplate({profile,conditions,candidates:current,now:Date.now()});
  if(boundary==='all-unknown') template.entries=template.entries.map(unknown);
  if(boundary==='partial-unknown') {assert(template.entries.length>1);template.entries[0]=unknown(template.entries[0]);}
  if(boundary==='stale') {template.oldest_ms='0';template.newest_ms='0';}
  const bytes=JSON.stringify(template);
  await writeFile(join(directory,'task-1.json'),bytes,{flag:'wx',mode:0o600});
  const extra=['--empirical-mode',mode,'--empirical-objective','run-caller-elapsed','--empirical-fallback','offline',
    '--sqlite-library','/usr/lib/libsqlite3.dylib','--empirical-position',String(assignment[0]),
    '--empirical-profile-root',directory,'--empirical-profile-revision',profile.profileRevision,
    '--empirical-template-pin',profileDigest(bytes)];
  if(boundary==='binding') extra.push('--empirical-validation-probes','true');
  if(boundary==='cleanup') extra.push('--diagnostic-cleanup-failure','true');
  const normalReadonly=['normal-diagnostic-no-permission','normal-select-no-permission'].includes(boundary);
  let selected={...invocation,arguments:[...invocation.arguments,...extra]};
  if(normalReadonly) {
    assert(plan.normalHost,'NormalHostBoundaryRequiresTrustedSettings');
    const settings={...plan.normalHost.settings,
      mode:boundary==='normal-diagnostic-no-permission'?'diagnostic-reference':'select-reference',
      allow_uncontrolled_load:false,profile_file:'task-1.json',
      profile_digest:profileDigest(bytes).slice(7),profile_revision:profile.profileRevision,
      profile_creation_ms:null};
    await writeFile(join(directory,'normal-settings.json'),JSON.stringify(settings),{flag:'wx',mode:0o600});
    selected={...invocation,environment:{ACTQL_NATIVE_HOST_PROFILE_SETTINGS:'normal-settings.json'}};
  }
  let execution;
  try {
    const started=performance.now();
    const streams=await promisify(execFile)(selected.binary,selected.arguments,{cwd:root,
      env:{...process.env,...selected.environment},timeout:fixture.limits.timeoutMs,maxBuffer:1024*1024});
    execution={...streams,processCycleMs:performance.now()-started};
  }
  catch(error) {
    await writeFile(join(directory,'failed-stdout.log'),error.stdout??'',{flag:'wx',mode:0o600});
    await writeFile(join(directory,'failed-stderr.log'),error.stderr??'',{flag:'wx',mode:0o600});
    throw error; // No refill or success inferred from interruption.
  }
  await writeFile(join(directory,'stdout.log'),execution.stdout,{flag:'wx',mode:0o600});
  await writeFile(join(directory,'stderr.log'),execution.stderr,{flag:'wx',mode:0o600});
  const observations=nativeOwnerObservations(execution.stdout);
  if(['stop','expiry'].includes(boundary)) {
    assert.deepEqual(JSON.parse(execution.stdout.trim().split('\n').at(-1)),{
      status:boundary==='stop'?'stopped-between-tasks':'rejected-expired-request',completed_tasks:boundary==='stop'?1:0});
    const [held,closed,twice]=observations.owners.slice(-3);
    for(const key of ['heldBytes','reservedExecutionBytes','reservedRetentionBytes','reservedTransferBytes','uncertainTransferBytes']) assert.equal(closed[key],0);
    assert.equal(closed.attempts,held.attempts);assert.equal(closed.holdings,held.holdings);
    assert.deepEqual(twice,{...closed,boundary:'duplicate-close'});
    assert.equal(observations.choices.length,boundary==='stop'?1:0);
    if(boundary==='stop') {assert(held.heldBytes>0);assert(execution.stdout.includes('empirical-stop-retains-responsibility:1'));}
    else {assert.equal(held.attempts,0);const expired=JSON.parse(execution.stdout.split('\n').find(l=>l.startsWith('empirical-expired-request:')).slice(26));assert(BigInt(expired.observed_ms)>BigInt(expired.deadline_ms));}
  } else {
    // Retain the additional fault observation; validate the ordinary successful
    // lifecycle separately after confirmed retry, without calling it a sample.
    const normal={...execution,stdout:execution.stdout.split('\n').filter(l=>!l.startsWith('owner-observation:')||JSON.parse(l.slice(18)).boundary!=='failed-cleanup').join('\n')};
    if(boundary==='cleanup') {
      const failed=observations.owners.find(o=>o.boundary==='failed-cleanup');assert(failed&&failed.heldBytes>0);
      assert(execution.stdout.includes('whole-run-cleanup-retry-confirmed'));
      // Remove the observer interval belonging to that one extra observation.
      const lines=execution.stdout.split('\n');const index=lines.findIndex(l=>l.startsWith('owner-observation:')&&JSON.parse(l.slice(18)).boundary==='failed-cleanup');
      assert(lines[index+1].startsWith('observer-elapsed-us:'));lines.splice(index,2);normal.stdout=lines.join('\n');
    }
    const parsed=readNativeDirectProductExecution(selected,normal);
    const product=admitNativeDirectProduct(fixture,selected,parsed,{cleanupRetry:boundary==='cleanup'});
    assert.deepEqual(parsed.resultSchemaFields,fixture.workload==='fixed-join-count-shrinking-intermediate'?['n','present']:fixture.fields);
    if(normalReadonly) {
      const decisions=execution.stdout.split('\n').filter(l=>l.startsWith('normal-host-decision:'))
        .map(l=>JSON.parse(l.slice('normal-host-decision:'.length)));
      assert.equal(decisions.length,selected.finalTask,'MissingOrdinaryHostDecision');
      assert(product.ownerCorrespondence.observations.choices.every(c=>['OfflineLatency','BoundedLatency'].includes(c.source)));
      assert(decisions.every(d=>d.selected_position===null&&d.load_applicability==='unknown-uncontrolled'&&
        d.stable_improvement==='unknown'&&d.net_benefit==='unknown'),'DiagnosticChangedAuthorityOrSelection');
      if(boundary==='normal-diagnostic-no-permission') {
        assert.equal(decisions[0].reason,'run-caller-elapsed-median');
        assert.equal(decisions[0].references.length,template.entries.length);
        assert(decisions[0].references.every(r=>r.median_ms!==null),'MissingPermittedDiagnosticReference');
      } else {
        assert.equal(decisions[0].reason,'uncontrolled-load-not-permitted');
      }
    } else if(boundary==='binding'||boundary==='cleanup') {
      admitWholeRunTrajectory(execution,product);
      if(boundary==='binding') {
        const tasks=fixture.program().stages.length-1;
        assert.equal(execution.stdout.split('\n').filter(l=>l.startsWith('empirical-modified-request-refused:')).length,tasks);
        assert.equal(execution.stdout.split('\n').filter(l=>l.startsWith('empirical-old-request-refused:')).length,tasks);
        assert.equal(execution.stdout.split('\n').filter(l=>l.startsWith('empirical-old-state-refused:')).length,tasks-1);
      }
    } else {
      assert(product.ownerCorrespondence.observations.choices.every(c=>['OfflineLatency','BoundedLatency'].includes(c.source)));
      const ranking=JSON.parse(execution.stdout.split('\n').find(l=>l.startsWith('empirical-ranking:')).slice(18));
      assert.equal(ranking.selected_position,null);
      assert.equal(ranking.reason,boundary==='single-candidate'?'single-candidate':boundary==='stale'?'freshness-insufficient':'incomplete-reference');
    }
  }
  receipts.push({boundary,accepted:true,command:[selected.binary,...selected.arguments],
    stdoutDigest:profileDigest(execution.stdout),stderrDigest:profileDigest(execution.stderr),observations,
    scope:'functional only; physical stop is not public Run Cancelled; no performance sample or replacement'});
  await writeFile(join(destination,'acceptance.json'),JSON.stringify({revision,binaryDigest:witness.binaryDigest,schedule,receipts},(_k,v)=>typeof v==='bigint'?String(v):v,2)+'\n',{mode:0o600});
  console.log(JSON.stringify({boundary,accepted:true}));
}
