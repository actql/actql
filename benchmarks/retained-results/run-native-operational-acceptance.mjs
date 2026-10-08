// Two functional receive cases, not additional performance samples.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, writeFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {performance} from 'node:perf_hooks';
import {loadLocalOperationalProfile, localOperationalTemplate} from './operational-estimates.mjs';
import {profileDigest} from './local-performance-profile.mjs';
import {sha256File} from './release-artifacts.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct, admitNativeDirectProduct} from './native-direct-product.mjs';
import {retainedCase, workloads} from './fixtures.mjs';
assert.equal(process.argv.length,5,'ExpectedProfileDirectoryDestinationAndSQLiteLibrary');
const root=process.cwd(), directory=resolve(process.argv[2]), destination=resolve(process.argv[3]);
const sqlite=resolve(process.argv[4]);
const started=performance.now(), profile=await loadLocalOperationalProfile(directory);
const readAndAggregateMs=performance.now()-started;
const report=profile.report;
const revision=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
assert.equal(execFileSync('git',['status','--porcelain'],{encoding:'utf8'}).trim(),'','RequiresCleanSource');
assert.equal(report.revision,revision,'RuntimeRevisionMismatch');
const binary=join(root,'_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
assert.equal(report.binaryDigest,'sha256:'+await sha256File(binary),'RuntimeBinaryMismatch');
const database=join(directory,'source.duckdb'), inputDigest='sha256:'+await sha256File(database);
assert(report.observations.every(o=>o.conditions.inputDigest===inputDigest),'SourceRevisionMismatch');
assert.equal(report.scheduleKind,'operational-six');assert.equal(report.observations.length,6);
assert(report.observations.every(o=>o.conditions.captureMode==='metadata-only'));
const fixture=retainedCase(workloads[2],'text-1024',1000);
await mkdir(destination,{mode:0o700});
const receipts=[];
for (const realization of ['fresh','resident']) {
  const member=report.observations.find(o=>o.conditions.realization===realization);
  assert(member?.ownerAccepted);
  const conditions={...member.conditions,runtimeRevision:revision,binaryDigest:report.binaryDigest,inputDigest,
    inputRows:fixture.rows,programDigest:profileDigest(fixture.program()),limitsDigest:profileDigest(fixture.limits),
    controlDigest:profileDigest(report.controls[realization])};
  const current=join(destination,realization);await mkdir(current,{mode:0o700});
  const pins=[],unknownPins=[];
  for (const task of [1,2,3]) {
    const projection=member.mapping.candidateProjections.find(p=>p.task===task);
    const candidates={canonical_json:JSON.stringify(projection.body),cid:profileDigest(JSON.stringify(projection.body))};
    const template=localOperationalTemplate({profile,conditions,task,candidates,now:Date.now()});
    assert(template.entries.some(e=>e.quantity==='task-processing'&&e.status==='reference'),'MissingTaskReference');
    const bytes=JSON.stringify(template);pins.push(profileDigest(bytes));
    await writeFile(join(current,`task-${task}.json`),bytes,{flag:'wx',mode:0o600});
    const unknown=localOperationalTemplate({profile,conditions:{...conditions,inputDigest:'different-input'},task,candidates,now:Date.now()});
    assert(unknown.entries.every(e=>e.status==='unknown'));
    const missing=JSON.stringify(unknown);unknownPins.push(profileDigest(missing));
    await writeFile(join(current,`task-${task}-unknown.json`),missing,{flag:'wx',mode:0o600});
  }
  const invocation=await prepareNativeDirectProduct({root,fixture,database,directory:current,
    ...report.controls[realization],phaseObserver:true});
  const configured={...invocation,arguments:[...invocation.arguments,'--operational-estimate-root',current,
    '--operational-profile-revision',profile.profileRevision,'--operational-template-pins',[...pins,...unknownPins].join(','),
    '--sqlite-library',sqlite]};
  let execution;
  try { execution=await executeNativeDirectProduct(configured,{root,timeoutMs:fixture.limits.timeoutMs}); }
  catch(error) {
    await writeFile(join(current,'failed-stdout.log'),error.stdout??'');
    await writeFile(join(current,'failed-stderr.log'),error.stderr??'');
    throw error; // No replacement or performance sample.
  }
  await writeFile(join(current,'stdout.log'),execution.stdout,{flag:'wx',mode:0o600});
  await writeFile(join(current,'stderr.log'),execution.stderr,{flag:'wx',mode:0o600});
  const product=admitNativeDirectProduct(fixture,configured,execution);
  const lines=prefix=>execution.stdout.split('\n').filter(line=>line.startsWith(prefix));
  assert.equal(lines('operational-estimate:').length,3);
  assert.equal(lines('operational-unknown:').length,3);
  assert.equal(lines('operational-refusals:').length,3);
  assert.equal(lines('operational-after-commit-refused:').length,3);
  assert.deepEqual(product.ownerCorrespondence.observations.candidates,member.mapping.candidateProjections);
  assert.deepEqual(product.ownerCorrespondence.observations.choices,member.mapping.choices);
  assert.deepEqual(product.ownerCorrespondence.attempts,member.mapping.attempts);
  assert.deepEqual(product.acquisitionChoice,member.mapping.acquisition);
  receipts.push({realization,accepted:true,taskReferences:3,unknownReceives:3,bindingRefusals:30,afterCommitRefusals:3,
    stdoutDigest:profileDigest(execution.stdout),acquisition:product.acquisitionChoice,usage:product.record.usage,
    admissionScope:'template read/pinning, normal and unknown receive plus ten refusal checks; not normal one-sidecar overhead',
    admissionMicroseconds:lines('operational-admission-us:').map(line=>Number(line.split(':').at(-1))),
    command:[configured.binary,...configured.arguments]});
}
assert.equal(inputDigest,'sha256:'+await sha256File(database),'SourceChanged');
assert.equal(report.binaryDigest,'sha256:'+await sha256File(binary),'BinaryChanged');
const receipt={version:'actql-operational-estimate-acceptance/0.1',revision,binaryDigest:report.binaryDigest,
  profileRevision:profile.profileRevision,profileOriginal:directory,readAndAggregateMs,receipts,
  comparativeOverhead:'unknown-no-off-comparison',eta:null,p90:null,
  scope:'functional Native admission, no new performance samples or planner ranking'};
await writeFile(join(destination,'acceptance.json'),JSON.stringify(receipt,null,2)+'\n',{flag:'wx',mode:0o600});
console.log(JSON.stringify({accepted:true,receipts:receipts.length,readAndAggregateMs,receipt:join(destination,'acceptance.json')}));
