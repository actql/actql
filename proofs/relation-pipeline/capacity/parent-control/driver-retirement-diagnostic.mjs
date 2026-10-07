import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync} from 'node:fs';
import {join} from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {root, environment, toolchain} from '../../execute.mjs';
import {snapshot, hash} from '../../inventory.mjs';
import {artifacts} from '../../../bounded-session/evidence.mjs';
import {checkNativeRuntime} from '../backing/source.mjs';
import {retirementOverlay, retirementPaths, retirementHelper, retirementStub, retirementFixture,retirementExecutionArtifacts} from './driver-retirement-overlay.mjs';
import {acceptDriverRetirement} from './driver-retirement-consumer.mjs';
import {holdingTemporary} from './holding-custody-overlay.mjs';
assert(process.argv.slice(2).every(a=>a==='--holding-custody') && process.argv.length<=3,'Unknown diagnostic option');
const holdingCustody=process.argv.includes('--holding-custody');
const git = args => {
  const r = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr); return r.stdout.trim();
};
assert.equal(git(['status', '--porcelain']), '', 'Requires clean submitted HEAD');
const revision = git(['rev-parse', 'HEAD']), source = snapshot(root), read = p => readFileSync(join(root,p));
const runtime = checkNativeRuntime(environment.MOON_HOME, toolchain);
const {overlay, boundary, buildIdentity} = retirementOverlay(read,source,{holdingCustody});
const temporary = [retirementHelper, retirementStub, retirementFixture,...(holdingCustody?holdingTemporary:[])];
assert(temporary.every(p => !existsSync(join(root,p))), 'Foreign observation overlay');
const changedPaths = Object.keys(overlay).filter(p => !temporary.includes(p));
assert(retirementPaths.every(p => changedPaths.includes(p)));
const originals = Object.fromEntries(changedPaths.map(p => [p,read(p)]));
const directory = '.artifacts/relation-pipeline/driver-retirement-native';
mkdirSync(join(root,directory), {recursive:true});
function archive(bytes, group, extension = '') {
  const path = directory+'/'+group+'/'+hash(bytes)+extension;
  mkdirSync(join(root,directory,group),{recursive:true});
  if (!existsSync(join(root,path))) writeFileSync(join(root,path),bytes,{flag:'wx'});
  assert.equal(hash(read(path)),hash(bytes)); return path;
}
let log, exit, executedSource, binaries;
async function executeFixture() {
  const child = spawn(process.execPath,['--input-type=module','-e',
    `import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode=runFocusedTests('moon',['--target','native','${retirementFixture}','--deny-warn'],{cwd:process.cwd()});`],
    {cwd:root,env:environment,stdio:['ignore','pipe','pipe']});
  let text = '', exceeded = false, interrupted = false;
  const capture = bytes => {
    if (text.length + bytes.length > 32*1024*1024) { exceeded = true; child.kill('SIGTERM'); }
    else text += bytes.toString();
  };
  child.stdout.on('data',capture); child.stderr.on('data',capture);
  const terminate = () => { interrupted = true; child.kill('SIGTERM'); };
  // The bounded guard signals the process group. Keep this producer alive long
  // enough to restore owned source after the compiler terminates.
  process.once('SIGTERM',terminate);
  try {
    const status = await new Promise((resolve,reject) => {
      child.once('error',reject); child.once('close',code => resolve(code));
    });
    return {text,status,exceeded,interrupted};
  } finally { process.removeListener('SIGTERM',terminate); }
}
try {
  for (const p of temporary) writeFileSync(join(root,p),overlay[p],{flag:'wx'});
  for (const p of changedPaths) writeFileSync(join(root,p),overlay[p]);
  executedSource = snapshot(root);
  const r = await executeFixture(), text = r.text;
  log = {path:archive(Buffer.from(text),'logs','.log'),digest:hash(text)};
  assert(!r.interrupted && !r.exceeded, `Interrupted/incomplete Native fixture; ${log.path}`);
  assert.equal(r.status,0,`Focused Native Host fixture failed; ${log.path}\n${text}`);
  exit = r.status;
  binaries = Object.fromEntries(Object.entries(retirementExecutionArtifacts(artifacts(root,'native','query_integration'))).map(([p,digest]) =>
    [p,{digest,path:archive(read(p),'binaries')} ]));
  assert.deepEqual(checkNativeRuntime(environment.MOON_HOME,toolchain),runtime);
} finally {
  for (const [p,bytes] of Object.entries(originals)) writeFileSync(join(root,p),bytes);
  for (const p of temporary) if (existsSync(join(root,p))) {
    assert.equal(read(p).toString(),overlay[p],'Owned overlay changed'); unlinkSync(join(root,p));
  }
  assert.deepEqual(snapshot(root),source,'Byte-for-byte restoration failed');
}
const receipt = {version:'actql-native-driver-retirement/0.1',authority:'local Native finite correspondence; no Actions identity',
  revision,source,runtime,target:'native',boundary,buildIdentity,executedSource,log,binaries,exit,restored:true,reuseAuthorized:false,holdingCustody};
const originalPath = archive(Buffer.from(JSON.stringify(receipt,null,2)+'\n'),'originals','.json');
const accepted = acceptDriverRetirement(receipt,{root,revision,runtime,read,holdingCustody});
const negativeChanges = [r=>{r.target='js';},r=>{r.revision='0'.repeat(40);},r=>{r.restored=false;},
  r=>{r.source.digest='0'.repeat(64);},r=>{r.buildIdentity='0'.repeat(64);},r=>{r.executedSource.digest='0'.repeat(64);},
  r=>{r.log.digest='0'.repeat(64);},r=>{r.binaries={};},r=>{r.reuseAuthorized=true;},r=>{r.exit=1;},r=>{r.holdingCustody=!holdingCustody;}];
for (const change of negativeChanges) {
  const bad = structuredClone(receipt); change(bad);
  assert.throws(()=>acceptDriverRetirement(bad,{root,revision,runtime,read,holdingCustody}),'Negative original substitution accepted');
}
const final = {...accepted,originalPath,originalReceiptDigest:hash(read(originalPath)),consumerNegativeCases:negativeChanges.length};
const acceptedPath = archive(Buffer.from(JSON.stringify(final,null,2)+'\n'),'accepted','.json');
console.log(JSON.stringify({originalPath,acceptedPath,...final},null,2));
