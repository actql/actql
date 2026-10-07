import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {hash} from '../../inventory.mjs';
import {encodeCoreBound,retainedParentCoreBound} from './bounds.mjs';
import {auditCurrentChain} from './current-audit.mjs';
import {auditParentStartup} from './audit.mjs';
import {rejectParentSubstitutions} from './regression.mjs';

// This seals existing execution bytes. It never executes, relabels the source,
// or grants reuse/Actions authority. The caller supplies the actual source
// reader for that execution; a current consumer separately checks freshness.
export function sealCurrentExecution(input,read) {
  const {root,revision,source,runtime,toolchain,boundary,buildIdentity,model,
    logPath,runExit,overlays,executedSource,executedArtifacts,archives,records}=input;
  const directory='.artifacts/relation-pipeline/current-chain-native';
  // logPath is the producer's actual filesystem path; do not prepend root to
  // an absolute path a second time. Receipt paths below are relative to root.
  const log=readFileSync(logPath),digest=hash(log);
  const storagePrefix='ACTQL_PREPARATION_STORAGE:';
  const preparationStorageFacts=log.toString().split('\n').filter(l=>l.startsWith(storagePrefix)).map(l=>JSON.parse(l.slice(storagePrefix.length)));
  const archivedLog=`${directory}/logs/${digest}.log`;mkdirSync(join(root,directory,'logs'),{recursive:true});
  if(!existsSync(join(root,archivedLog)))writeFileSync(join(root,archivedLog),log,{flag:'wx'});
  else assert.deepEqual(readFileSync(join(root,archivedLog)),log);
  const report={version:'actql-current-chain-native-diagnostic/0.1',target:'native',revision,source,runtime,toolchain,
    authority:'local-physical-finite-correspondence',reuseAuthorized:false,unconditionalAllocationBytes:false,
    command:['moon','test','--target','native','src/connectors/local/current_chain_capacity_wbtest.mbt','--deny-warn'],
    exit:runExit,boundary,buildIdentity,model,retainedCore:encodeCoreBound(retainedParentCoreBound(2)),
    logPath:archivedLog,logDigest:digest,
    overlayDigests:Object.fromEntries(Object.entries(overlays).map(([p,t])=>[p,hash(t)])),
    executedSource,artifacts:executedArtifacts,archives,records,preparationStorageFacts,restored:true};
  mkdirSync(join(root,directory,'originals'),{recursive:true});
  const save=()=>{const path=`${directory}/originals/${hash(JSON.stringify(report))}.json`;
    if(!existsSync(join(root,path)))writeFileSync(join(root,path),JSON.stringify(report,null,2)+'\n',{flag:'wx'});return path;};
  const original=save();
  report.providerConstruction=auditCurrentChain(report,source,read).providerConstruction;
  const accepted=auditParentStartup(report,source,read);
  const negatives=rejectParentSubstitutions(report,source,read);
  const acceptedOriginal=save();
  const destination='.artifacts/relation-pipeline/capacity/parent-control-probe/all.json';
  mkdirSync(join(root,'.artifacts/relation-pipeline/capacity/parent-control-probe'),{recursive:true});
  if(existsSync(join(root,destination))) {
    const prior=readFileSync(join(root,destination)),path=`${directory}/originals/prior-${hash(prior)}.json`;
    if(!existsSync(join(root,path)))writeFileSync(join(root,path),prior,{flag:'wx'});
  }
  writeFileSync(join(root,destination),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({original,acceptedOriginal,negatives,accepted}));
  return {report,original,acceptedOriginal,accepted,negatives};
}
