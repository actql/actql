import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {root, environment, toolchain} from '../../execute.mjs';
import {snapshot, hash} from '../../inventory.mjs';
import {artifacts} from '../../../bounded-session/evidence.mjs';
import {checkNativeRuntime} from '../backing/source.mjs';
import {retirementOverlay, retirementPaths, retirementHelper, retirementStub, retirementFixture} from './driver-retirement-overlay.mjs';
import {acceptDriverRetirement} from './driver-retirement-consumer.mjs';
const git = args => {
  const r = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr); return r.stdout.trim();
};
assert.equal(git(['status', '--porcelain']), '', 'Requires clean submitted HEAD');
const revision = git(['rev-parse', 'HEAD']), source = snapshot(root), read = p => readFileSync(join(root,p));
const runtime = checkNativeRuntime(environment.MOON_HOME, toolchain);
const originals = Object.fromEntries(retirementPaths.map(p => [p,read(p)]));
const {overlay, boundary, buildIdentity} = retirementOverlay(read,source);
const temporary = [retirementHelper, retirementStub, retirementFixture];
assert(temporary.every(p => !existsSync(join(root,p))), 'Foreign observation overlay');
const directory = '.artifacts/relation-pipeline/driver-retirement-native';
mkdirSync(join(root,directory), {recursive:true});
function archive(bytes, group, extension = '') {
  const path = directory+'/'+group+'/'+hash(bytes)+extension;
  mkdirSync(join(root,directory,group),{recursive:true});
  if (!existsSync(join(root,path))) writeFileSync(join(root,path),bytes,{flag:'wx'});
  assert.equal(hash(read(path)),hash(bytes)); return path;
}
let log, exit, executedSource, binaries;
try {
  for (const p of temporary) writeFileSync(join(root,p),overlay[p],{flag:'wx'});
  for (const p of retirementPaths) writeFileSync(join(root,p),overlay[p]);
  executedSource = snapshot(root);
  const r = spawnSync(process.execPath,['--input-type=module','-e',
    `import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode=runFocusedTests('moon',['--target','native','${retirementFixture}','--deny-warn'],{cwd:process.cwd()});`],
    {cwd:root,env:environment,encoding:'utf8',maxBuffer:32*1024*1024});
  const text = (r.stdout ?? '')+(r.stderr ?? '');
  log = {path:archive(Buffer.from(text),'logs','.log'),digest:hash(text)};
  assert.equal(r.status,0,`Focused Native Host fixture failed; ${log.path}\n${text}`);
  exit = r.status;
  binaries = Object.fromEntries(Object.entries(artifacts(root,'native','query_integration')).map(([p,digest]) =>
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
  revision,source,runtime,target:'native',boundary,buildIdentity,executedSource,log,binaries,exit,restored:true,reuseAuthorized:false};
const originalPath = archive(Buffer.from(JSON.stringify(receipt,null,2)+'\n'),'originals','.json');
const accepted = acceptDriverRetirement(receipt,{root,revision,runtime,read});
const negativeChanges = [r=>{r.target='js';},r=>{r.revision='0'.repeat(40);},r=>{r.restored=false;},
  r=>{r.source.digest='0'.repeat(64);},r=>{r.buildIdentity='0'.repeat(64);},r=>{r.executedSource.digest='0'.repeat(64);},
  r=>{r.log.digest='0'.repeat(64);},r=>{r.binaries={};},r=>{r.reuseAuthorized=true;},r=>{r.exit=1;}];
for (const change of negativeChanges) {
  const bad = structuredClone(receipt); change(bad);
  assert.throws(()=>acceptDriverRetirement(bad,{root,revision,runtime,read}),'Negative original substitution accepted');
}
const final = {...accepted,originalPath,consumerNegativeCases:negativeChanges.length};
const acceptedPath = archive(Buffer.from(JSON.stringify(final,null,2)+'\n'),'accepted','.json');
console.log(JSON.stringify({originalPath,acceptedPath,...final},null,2));
