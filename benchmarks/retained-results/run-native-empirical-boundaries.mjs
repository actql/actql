// Two functional negatives, separate from the twelve fixed performance slots.
import assert from 'node:assert/strict';
import {execFile,execFileSync} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {retainedCase,workloads} from './fixtures.mjs';
import {loadLocalOperationalProfile} from './operational-estimates.mjs';
import {profileDigest} from './local-performance-profile.mjs';
import {prepareNativeDirectProduct} from './native-direct-product.mjs';
import {nativeOwnerObservations} from './native-owner-observations.mjs';
import {sha256File} from './release-artifacts.mjs';
assert.equal(process.argv.length,4);
const root=process.cwd(),original=resolve(process.argv[2]),destination=resolve(process.argv[3]);
const profile=await loadLocalOperationalProfile(original), revision=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
assert.equal(profile.report.revision,revision);assert.equal(execFileSync('git',['status','--porcelain'],{encoding:'utf8'}).trim(),'');
const fixture=retainedCase(workloads[2],'text-1024',1000),receipts=[];
await mkdir(destination,{mode:0o700});
for (const boundary of ['stop','expiry']) {
  const directory=join(destination,boundary);await mkdir(directory,{mode:0o700});
  const settings=profile.report.controls.resident;
  const invocation=await prepareNativeDirectProduct({root,fixture,database:join(original,'source.duckdb'),directory,
    ...settings,phaseObserver:true,...(boundary==='stop'?{stopAfterTask:1}:{})});
  assert.equal(profile.report.binaryDigest,'sha256:'+await sha256File(invocation.binary));
  const args=[...invocation.arguments,'--empirical-mode',boundary==='stop'?'forced':'expiry',
    '--empirical-position','7','--empirical-fallback','offline','--sqlite-library','/usr/lib/libsqlite3.dylib'];
  let stdout,stderr;
  try {({stdout,stderr}=await promisify(execFile)(invocation.binary,args,{cwd:root,timeout:fixture.limits.timeoutMs,maxBuffer:1024*1024}));}
  catch(error) {await writeFile(join(directory,'failed-stdout.log'),error.stdout??'');
    await writeFile(join(directory,'failed-stderr.log'),error.stderr??'');throw error;}
  await writeFile(join(directory,'stdout.log'),stdout,{flag:'wx',mode:0o600});
  await writeFile(join(directory,'stderr.log'),stderr,{flag:'wx',mode:0o600});
  const terminal=JSON.parse(stdout.trim().split('\n').at(-1));
  assert.deepEqual(terminal,{status:boundary==='stop'?'stopped-between-tasks':'rejected-expired-request',completed_tasks:boundary==='stop'?1:0});
  const observations=nativeOwnerObservations(stdout),[held,closed,twice]=observations.owners.slice(-3);
  for (const key of ['heldBytes','reservedExecutionBytes','reservedRetentionBytes','reservedTransferBytes','uncertainTransferBytes']) assert.equal(closed[key],0);
  assert.equal(closed.attempts,held.attempts);assert.equal(closed.holdings,held.holdings);
  assert.deepEqual(twice,{...closed,boundary:'duplicate-close'});
  if(boundary==='stop') {
    assert.equal(observations.choices.length,1);assert.equal(observations.choices[0].position,7);
    assert.equal(held.attempts,3);assert.equal(held.holdings,1);assert(held.heldBytes>0&&held.reservedExecutionBytes>0);
    assert(stdout.includes('empirical-stop-retains-responsibility:1'));
  } else {
    assert.equal(observations.choices.length,0);assert.equal(held.attempts,0);assert.equal(held.holdings,0);
    const actual=JSON.parse(stdout.split('\n').find(line=>line.startsWith('empirical-expired-request:')).slice('empirical-expired-request:'.length));
    assert(BigInt(actual.observed_ms)>BigInt(actual.deadline_ms));
  }
  receipts.push({boundary,accepted:true,terminal,command:[invocation.binary,...args],stdoutDigest:profileDigest(stdout),
    owners:observations.owners,scope:boundary==='stop'?'Native dispatch stop retains completed holding until confirmed close; not public Run Cancelled':'actual durable clock expired original pending request; zero Compute dispatch'});
}
await writeFile(join(destination,'acceptance.json'),JSON.stringify({revision,binaryDigest:profile.report.binaryDigest,
  receipts,scope:'functional negatives; no performance samples or refill'},null,2)+'\n',{flag:'wx',mode:0o600});
console.log(JSON.stringify({accepted:true,boundaries:receipts.length}));
