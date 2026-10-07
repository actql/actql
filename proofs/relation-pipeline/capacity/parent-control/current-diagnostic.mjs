import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,existsSync,unlinkSync,copyFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {root,environment,toolchain} from '../../execute.mjs';
import {snapshot,hash} from '../../inventory.mjs';
import {artifacts} from '../../../bounded-session/evidence.mjs';
import {checkNativeRuntime} from '../backing/source.mjs';
import {checkChainCensus} from './bounds.mjs';
import {inspectProviderConstruction} from './provider-construction.mjs';
import {currentOverlay,currentPaths,currentHelper,currentStub,currentFixture} from './current-overlay.mjs';
import {inspectCurrentChain} from './current-inspect.mjs';
const git=args=>{const r=spawnSync('git',args,{cwd:root,encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
assert.equal(git(['status','--porcelain']),'','Requires clean submitted source');
const revision=git(['rev-parse','HEAD']),source=snapshot(root),read=p=>readFileSync(join(root,p));
checkChainCensus(read);
const runtime=checkNativeRuntime(environment.MOON_HOME,toolchain);
const originals=Object.fromEntries(currentPaths.map(p=>[p,read(p)]));
const overlays=currentOverlay(read),temporary=[currentHelper,currentStub,currentFixture];
assert(temporary.every(p=>!existsSync(join(root,p))),'Foreign diagnostic overlay');
const directory='.artifacts/relation-pipeline/current-chain-native';mkdirSync(join(root,directory),{recursive:true});
const logPath=join(root,directory,'native.log'), inputPath=join(root,directory,'source.json');
let result,records,executedSource,executedArtifacts,archives={};
try {
  for(const p of temporary)writeFileSync(join(root,p),overlays[p],{flag:'wx'});
  for(const p of currentPaths)writeFileSync(join(root,p),overlays[p]);
  executedSource=snapshot(root);writeFileSync(inputPath,JSON.stringify(executedSource,null,2)+'\n');
  const command=[process.execPath,'--input-type=module','-e',
    `import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode=runFocusedTests('moon',['--target','native','${currentFixture}','--deny-warn'],{cwd:process.cwd()});`];
  const run=spawnSync(command[0],command.slice(1),{cwd:root,env:environment,encoding:'utf8',maxBuffer:32*1024*1024});
  const log=`${run.stdout ?? ''}${run.stderr ?? ''}`;writeFileSync(logPath,log);
  assert.equal(run.status,0,`Focused Native execution failed; ${logPath}\n${log}`);
  records=log.split('\n').filter(l=>l.startsWith('ACTQL_CHAIN_NATIVE:')).map(l=>JSON.parse(l.slice(19)));
  assert(records.length>0,'Missing actual Native chain observations');
  executedArtifacts=artifacts(root,'native','connectors/local');
  mkdirSync(join(root,directory,'binaries'),{recursive:true});
  for(const [p,digest] of Object.entries(executedArtifacts)) {
    const archive=`${directory}/binaries/${digest}`;
    if(!existsSync(join(root,archive)))copyFileSync(join(root,p),join(root,archive));
    assert.equal(hash(read(archive)),digest);archives[p]=archive;
  }
  assert.deepEqual(checkNativeRuntime(environment.MOON_HOME,toolchain),runtime);
  const providerFacts=log.split('\n').filter(l=>l.startsWith('ACTQL_PIPELINE_FAULT:')).map(l=>JSON.parse(l.slice(21)));
  const providerConstruction=inspectProviderConstruction(providerFacts.filter(f=>f.kind==='provider construction observation'),p=>originals[p] ?? read(p),'native');
  result={providerConstruction,focused:{exit:run.status,command,logPath:directory+'/native.log',logDigest:hash(log)},claim:inspectCurrentChain(records)};
  // Reject actual-report substitutions; no second Native campaign is needed.
  const reject=(edit,pattern)=>{const bad=structuredClone(records);edit(bad);assert.throws(()=>inspectCurrentChain(bad),pattern);};
  reject(r=>r.find(x=>x.kind==='startup').callbacks[0].captures.pop(),/pointer fields|capture identities/);
  reject(r=>r.find(x=>x.kind==='startup').environments[0].captures[0].id='1',/environment/);
  reject(r=>r.find(x=>x.kind==='phase'&&x.phase===3).preparation=null,/retain observed preparation/);
  reject(r=>r.find(x=>x.kind==='phase'&&x.phase===4).completed.elements[0]=null,/occurrence custody/);
  reject(r=>r.find(x=>x.kind==='phase'&&x.phase===5).preparation=structuredClone(r.find(x=>x.kind==='phase'&&x.phase===1).preparation),/retain observed preparation/);
  result.substitutionsRejected=5;
} finally {
  for(const [p,bytes] of Object.entries(originals))writeFileSync(join(root,p),bytes);
  for(const p of temporary)if(existsSync(join(root,p))){assert.equal(read(p).toString(),overlays[p],'Owned overlay changed');unlinkSync(join(root,p));}
  assert.deepEqual(snapshot(root),source,'Byte-for-byte restoration failed');
}
const report={version:'actql-current-chain-native-diagnostic/0.1',revision,source,runtime,toolchain,
  authority:'local-physical-finite-correspondence',reuseAuthorized:false,
  command:['node','proofs/relation-pipeline/capacity/parent-control/current-diagnostic.mjs'],
  overlayDigests:Object.fromEntries(Object.entries(overlays).map(([p,t])=>[p,hash(t)])),
  executedSource,executedArtifacts,archives,records,result,restored:true};
writeFileSync(join(root,directory,'report.json'),JSON.stringify(report,null,2)+'\n');
console.log('Native: one real long-name chain; actual state/callback/preparation identities, false/error/retry custody, five report substitutions rejected, source restored');
