import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,existsSync,unlinkSync,copyFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {root,environment,toolchain} from '../../execute.mjs';
import {snapshot,hash} from '../../inventory.mjs';
import {artifacts} from '../../../bounded-session/evidence.mjs';
import {checkNativeRuntime} from '../backing/source.mjs';
import {checkChainCensus} from './bounds.mjs';
import {encodeCoreBound,retainedParentCoreBound} from './bounds.mjs';
import {inspectProviderConstruction} from './provider-construction.mjs';
import {boundCurrentOverlay,currentPaths,currentHelper,currentStub,currentFixture} from './current-overlay.mjs';

const git=args=>{const r=spawnSync('git',args,{cwd:root,encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
assert.equal(git(['status','--porcelain']),'','Requires clean submitted source');
const revision=git(['rev-parse','HEAD']),source=snapshot(root),read=p=>readFileSync(join(root,p));
checkChainCensus(read);
const runtime=checkNativeRuntime(environment.MOON_HOME,toolchain);
const originals=Object.fromEntries(currentPaths.map(p=>[p,read(p)]));
const {overlay:overlays,boundary,buildIdentity}=boundCurrentOverlay(read,source),temporary=[currentHelper,currentStub,currentFixture];
assert(temporary.every(p=>!existsSync(join(root,p))),'Foreign diagnostic overlay');
const directory='.artifacts/relation-pipeline/current-chain-native';mkdirSync(join(root,directory),{recursive:true});
const logPath=join(root,directory,'native.log'), inputPath=join(root,directory,'source.json');
const modelCommand=['node','proofs/relation-pipeline/capacity/parent-control/check.mjs'];
const modelRun=spawnSync(process.execPath,modelCommand.slice(1),{cwd:root,env:environment,encoding:'utf8',timeout:120000});
const modelLog=`${modelRun.stdout ?? ''}${modelRun.stderr ?? ''}`;assert.equal(modelRun.status,0,modelLog);
const modelDirectory='.artifacts/relation-pipeline/capacity/parent-control-probe/models';mkdirSync(join(root,modelDirectory),{recursive:true});
const modelLogPath=`${modelDirectory}/${hash(modelLog)}.log`;writeFileSync(join(root,modelLogPath),modelLog);
const model={command:modelCommand,exit:0,sourceDigest:source.digest,logPath:modelLogPath,logDigest:hash(modelLog)};
const modelReceiptPath=`${modelDirectory}/${hash(JSON.stringify(model))}.json`;writeFileSync(join(root,modelReceiptPath),JSON.stringify(model,null,2)+'\n');
let records,executedSource,executedArtifacts,runExit,archives={};
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
  inspectProviderConstruction(providerFacts.filter(f=>f.kind==='provider construction observation'),p=>originals[p] ?? read(p),'native');
  runExit=run.status;
} finally {
  for(const [p,bytes] of Object.entries(originals))writeFileSync(join(root,p),bytes);
  for(const p of temporary)if(existsSync(join(root,p))){assert.equal(read(p).toString(),overlays[p],'Owned overlay changed');unlinkSync(join(root,p));}
  assert.deepEqual(snapshot(root),source,'Byte-for-byte restoration failed');
}
const log=read(logPath), digest=hash(log);
const archivedLog=`${directory}/logs/${digest}.log`;mkdirSync(join(root,directory,'logs'),{recursive:true});
if(!existsSync(join(root,archivedLog)))writeFileSync(join(root,archivedLog),log,{flag:'wx'});
const report={version:'actql-current-chain-native-diagnostic/0.1',target:'native',revision,source,runtime,toolchain,
  authority:'local-physical-finite-correspondence',reuseAuthorized:false,unconditionalAllocationBytes:false,
  command:['moon','test','--target','native',currentFixture,'--deny-warn'],exit:runExit,boundary,buildIdentity,
  model:{...model,receiptPath:modelReceiptPath},retainedCore:encodeCoreBound(retainedParentCoreBound(2)),
  logPath:archivedLog,logDigest:digest,
  overlayDigests:Object.fromEntries(Object.entries(overlays).map(([p,t])=>[p,hash(t)])),
  executedSource,artifacts:executedArtifacts,archives,records,restored:true};
const original=`${directory}/originals/${hash(JSON.stringify(report))}.json`;
mkdirSync(join(root,directory,'originals'),{recursive:true});
if(!existsSync(join(root,original)))writeFileSync(join(root,original),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
const {auditCurrentChain}=await import('./current-audit.mjs');
report.providerConstruction=auditCurrentChain(report,source,read).providerConstruction;
const {auditParentStartup}=await import('./audit.mjs');
const accepted=auditParentStartup(report,source,read);
const {rejectParentSubstitutions}=await import('./regression.mjs');
console.log(rejectParentSubstitutions(report,source,read));
mkdirSync(join(root,'.artifacts/relation-pipeline/capacity/parent-control-probe'),{recursive:true});
const acceptedOriginal=`${directory}/originals/${hash(JSON.stringify(report))}.json`;
if(!existsSync(join(root,acceptedOriginal)))writeFileSync(join(root,acceptedOriginal),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
writeFileSync(join(root,'.artifacts/relation-pipeline/capacity/parent-control-probe/all.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({original,accepted}));
