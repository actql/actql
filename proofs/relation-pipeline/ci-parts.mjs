// Four independently owned fresh producers. Original report/receipt bytes are
// immutable; only the complete, audited union is a scientific success claim.
import assert from 'node:assert/strict';
import {constants, copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync, chmodSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {hash, snapshot} from './inventory.mjs';
import {auditFixture, fixturePath} from './fixture.mjs';
import {validate} from './evidence.mjs';
import {fixedCorpus} from './corpus.mjs';
import {baseRegistry, registry} from './registry.mjs';
import {registrations} from './obligations.mjs';
import {canonicalJson, safePath, noLinks, inventory, fileDigest, sourceState, packArchive, verifyArchive, outputs} from './ci-artifacts.mjs';
import {partIds, planDigest, partFamily} from './proof-parts.mjs';
import {validateCapacityPart, unionCapacityParts} from './capacity/parts.mjs';
import {inspectMutationPart, joinMutationParts} from './mutation-parts.mjs';

export const partSchema = 'actql-pipeline-ci-part/0.1';
export const partJobs = Object.freeze({'L-C0':'pipeline-capacity', 'L-C1':'pipeline-capacity-mutants',
  'L-M0':'pipeline-mutations', 'L-M1':'pipeline-mutations-rest'});
export const partStages = Object.freeze({
  'L-C0':['foundation','capacity','final-normal'], 'L-C1':['foundation','capacity'],
  'L-M0':['foundation','baseline','mutations'], 'L-M1':['foundation','baseline','mutations'],
});
const targets = ['js','wasm','native'], prefix = '.artifacts/relation-pipeline/';
const encode = value => `${JSON.stringify(value, null, 2)}\n`;
const hex = /^[0-9a-f]{64}$/u;
const receiptPattern = /^(L-[CM][01])-[0-9a-z]+-[0-9a-z]+-[0-9]{4,5}-[A-Za-z0-9_-]+\.json$/u;
function reader(directory) {
  const local = path => {
    assert(path.startsWith(prefix), 'Non-local evidence reference');
    return join(directory, safePath(path.slice(prefix.length)));
  };
  const read = path => readFileSync(path.startsWith(prefix) ? local(path) : join(fileURLToPath(new URL('../../',import.meta.url)),safePath(path)));
  const report = path => canonicalJson(join(directory, safePath(path)),
    /^capacity\/parts\/L-C[01]\.json$/u.test(path) ? 256 * 1024 ** 2 : 32 * 1024 ** 2);
  return {local, read, report};
}
export function partState(root, env = process.env) {
  const state = sourceState(root);
  assert(typeof env.GITHUB_WORKFLOW_REF === 'string' && env.GITHUB_WORKFLOW_REF.length > 0, 'Missing workflow identity');
  assert(/^[0-9a-f]{40}$/u.test(env.GITHUB_WORKFLOW_SHA), 'Missing workflow source');
  return {...state, workflow: {ref:env.GITHUB_WORKFLOW_REF, sha:env.GITHUB_WORKFLOW_SHA}, planDigest};
}
export function capacityPartExecutions(report) {
  assert(['L-C0','L-C1'].includes(report.part));
  assert(Array.isArray(report.executions));
  if(report.part==='L-C0') {
    assert(report.parentStartup?.execution,'Missing independent native-parent execution');
    return [...report.executions,report.parentStartup.execution];
  }
  return [...report.executions];
}
export function inspectPart(directory, partId, expected) {
  assert(partIds.includes(partId));
  const {local, read, report} = reader(directory);
  const reports = [], refs = [];
  const acceptReport = (path, value = report(path)) => {
    assert.equal(value.revision, expected.context.testedSha, 'Report from another checkout');
    assert.equal(value.source.digest, expected.source.digest, 'Report from another source');
    assert.equal(hash(JSON.stringify(value.source.sources)), expected.source.digest, 'Invalid source inventory');
    assert.deepEqual(value.toolchain, expected.toolchain.moonbit, 'Report toolchain differs');
    reports.push({path, sha256:fileDigest(join(directory,path))});
    return value;
  };
  const normal = (path, selected, target) => {
    const value = acceptReport(path);
    assert.equal(value.target,target); validate(value,value.source,selected);
    for(const execution of value.executions) assert.equal(execution.receipt.boundary.role,'normal','Baseline/final corpus has foreign owner role');
    assert.deepEqual(value.executions.flatMap(e=>e.receipt.cases.map(c=>c.testCase)),fixedCorpus(selected,registrations), 'Incomplete normal corpus');
    refs.push(...value.executions);
  };
  if (partFamily(partId) === 'capacity') {
    const value = acceptReport(`capacity/parts/${partId}.json`);
    validateCapacityPart(value,value.source,targets,read);
    refs.push(...capacityPartExecutions(value));
    if (partId === 'L-C0') {
      // The native-parent child has an independent executor and immutable
      // root-level receipt; it is not one of the capacity primary executions.
      for (const target of targets) normal(`${target}.json`,registry,target);
    }
  } else {
    normal(`base-js-${partId}.json`,baseRegistry,'js');
    assert.deepEqual(report('exploration-decision.json'),expected.exploration);
    let owners;
    for (const mode of expected.exploration.required ? ['fixed','explore'] : ['fixed']) {
      const value = acceptReport(`${mode === 'fixed' ? 'fixed-mutations' : 'mutations'}-${partId}.json`);
      const currentOwners={workspaces:value.workspaces,restorationOwner:value.restorationOwner};
      if(owners) assert.deepEqual(currentOwners,owners,'Fixed/fresh mutation owners differ');
      else owners=currentOwners;
      refs.push(...inspectMutationPart(value,{partId,mode,source:value.source,decision:expected.exploration}));
    }
  }
  const paths = new Set(), ids = new Set(), owners = new Set(), receipts = [], observations = [];
  for (const execution of refs) {
    assert(execution.path.startsWith(prefix)); const path = safePath(execution.path.slice(prefix.length));
    assert(receiptPattern.test(path) && path.startsWith(`${partId}-`), 'Foreign part receipt namespace');
    assert(!paths.has(path),'Repeated receipt obligation'); paths.add(path);
    const receipt = report(path);
    assert.deepEqual(receipt,execution.receipt,'Receipt bytes differ from report');
    assert.equal(hash(JSON.stringify(receipt)),execution.digest);
    assert(targets.includes(receipt.target)); assert.equal(receipt.boundary.target,receipt.target);
    assert.equal(receipt.compiler,expected.toolchain.moonbit.moonc);
    assert.equal(receipt.buildIdentity,hash(JSON.stringify(receipt.boundary)));
    assert.equal(typeof receipt.boundary.workspace,'string'); owners.add(receipt.boundary.workspace);
    auditFixture(receipt,readFileSync(local(receipt.fixturePath)),readFileSync(local(receipt.logPath),'utf8'),receipt.target);
    assert(receipt.cases.length > 0);
    for (const entry of receipt.cases) {
      assert(entry.id.startsWith(`${partId}-`),'Foreign part observation namespace');
      assert(!ids.has(entry.id),'Repeated observation obligation'); ids.add(entry.id);
      observations.push({id:entry.id,receipt:path,target:receipt.target,owner:receipt.boundary.workspace,caseDigest:entry.caseDigest});
    }
    receipts.push({path,sha256:fileDigest(join(directory,path)),target:receipt.target,boundary:receipt.boundary,buildIdentity:receipt.buildIdentity});
  }
  // No hidden unclaimed execution may ride alongside a valid subset.
  for (const file of inventory(directory,{excludeManifest:true})) {
    if (receiptPattern.test(file.path)) assert(paths.has(file.path),'Unclaimed extra execution receipt');
    assert(!/^L-[CM][01]-/u.test(file.path) || file.path.startsWith(`${partId}-`),'Foreign part payload');
    const common=['current-foundation.json','session-model.log','chain-model.log'].includes(file.path)
      || /^sources\/[0-9a-f]{64}\.json$/u.test(file.path)
      || new RegExp(`^${partId}-[0-9a-z]+-[0-9a-z]+-[0-9]{4,5}-[A-Za-z0-9_-]+\\.(json|inputs\\.json|fixture\\.mbt|log)$`,'u').test(file.path);
    const owned=partFamily(partId)==='capacity'
      ? (partId==='L-C0' ? file.path.startsWith('capacity/') : file.path.startsWith('capacity/binaries/') || file.path===`capacity/parts/${partId}.json`) || (partId==='L-C0' && (targets.some(t=>file.path===`${t}.json`) || file.path.startsWith('final-artifacts/')))
      : ['exploration-decision.json',`base-js-${partId}.json`,`fixed-mutations-${partId}.json`,...(expected.exploration.required?[`mutations-${partId}.json`]:[])].includes(file.path);
    assert(common||owned,'Unexpected part evidence file');
    if(file.path.startsWith('capacity/parts/')) assert.equal(file.path,`capacity/parts/${partId}.json`,'Foreign capacity part report');
  }
  assert(receipts.length>0 && owners.size>0);
  return {reports:reports.sort((a,b)=>a.path.localeCompare(b.path)),owners:[...owners].sort(),
    receipts:receipts.sort((a,b)=>a.path.localeCompare(b.path)),observations:observations.sort((a,b)=>a.id.localeCompare(b.id))};
}
export function validatePartEnvelope(manifest, expected, partId) {
  assert.deepEqual(Object.keys(manifest).sort(),['schema','partId','context','source','foundation','exploration','toolchain','workflow','planDigest','completedStages','restoration','files','evidence'].sort());
  assert.equal(manifest.schema,partSchema); assert.equal(manifest.partId,partId); assert(partIds.includes(partId));
  for (const key of ['context','source','foundation','exploration','toolchain','workflow','planDigest']) assert.deepEqual(manifest[key],expected[key],`Different ${key}`);
  assert.equal(manifest.planDigest,planDigest,'Unknown partition plan');
  assert.deepEqual(manifest.completedStages,partStages[partId],'Incomplete part stages');
  assert.deepEqual(manifest.restoration,{sourceRestored:true,fixtureClosed:true,workspacesClosed:true},'Unclosed part');
  assert(Array.isArray(manifest.files)&&manifest.files.length>0&&manifest.files.length<=50000);
  const paths = new Set(); let total=0;
  for (const file of manifest.files) {
    assert.deepEqual(Object.keys(file).sort(),['path','kind','size','sha256'].sort()); safePath(file.path);
    assert.equal(file.kind,'file'); assert(hex.test(file.sha256)); assert(Number.isSafeInteger(file.size)&&file.size>=0&&file.size<=4*1024**3);
    total+=file.size;assert(total<=16*1024**3,'Oversized part evidence');
    assert(file.path!=='ci-seal.json'&&!paths.has(file.path),'Repeated inventory path'); paths.add(file.path);
  }
  assert.deepEqual(manifest.files.map(f=>f.path),[...paths].sort());
  assert.deepEqual(Object.keys(manifest.evidence).sort(),['reports','owners','receipts','observations'].sort());
  for (const key of ['reports','owners','receipts','observations']) assert(Array.isArray(manifest.evidence[key])&&manifest.evidence[key].length>0);
  assert.equal(new Set(manifest.evidence.owners).size,manifest.evidence.owners.length,'Duplicate owner');
  assert.equal(new Set(manifest.evidence.receipts.map(e=>e.path)).size,manifest.evidence.receipts.length,'Duplicate receipt');
  assert.equal(new Set(manifest.evidence.observations.map(e=>e.id)).size,manifest.evidence.observations.length,'Duplicate observation');
  for (const report of manifest.evidence.reports) {
    assert.deepEqual(Object.keys(report).sort(),['path','sha256']);
    assert(paths.has(report.path)); assert.equal(manifest.files.find(f=>f.path===report.path).sha256,report.sha256);
  }
  for (const receipt of manifest.evidence.receipts) {
    assert(paths.has(receipt.path)&&receipt.path.startsWith(`${partId}-`),'Missing/foreign receipt');
    assert(manifest.evidence.owners.includes(receipt.boundary.workspace),'Foreign owner');
    assert(targets.includes(receipt.target)); assert.equal(receipt.boundary.target,receipt.target);
    assert.equal(receipt.buildIdentity,hash(JSON.stringify(receipt.boundary)),'Changed compiled owner');
    assert.equal(manifest.files.find(f=>f.path===receipt.path).sha256,receipt.sha256);
  }
  for (const observation of manifest.evidence.observations) {
    assert.deepEqual(Object.keys(observation).sort(),['id','receipt','target','owner','caseDigest'].sort());
    assert(observation.id.startsWith(`${partId}-`),'Foreign observation');
    const receipt=manifest.evidence.receipts.find(r=>r.path===observation.receipt);
    assert(receipt,'Observation has no receipt');
    assert.equal(observation.owner,receipt.boundary.workspace,'Foreign observation owner');
    assert.equal(observation.target,receipt.target,'Foreign observation target');
    assert(hex.test(observation.caseDigest),'Invalid case identity');
  }
  return manifest;
}
export function sealPart({root,directory,partId,expected,stages}) {
  assert(!existsSync(join(root,fixturePath)),'Executor fixture not closed');
  assert.equal(snapshot(root).digest,expected.source.digest,'Source not restored');
  assert.equal(fileDigest(join(directory,'current-foundation.json')),expected.foundation.digest);
  const evidence = inspectPart(directory,partId,expected);
  const manifest={schema:partSchema,partId,...expected,completedStages:stages,
    restoration:{sourceRestored:true,fixtureClosed:true,workspacesClosed:true},files:inventory(directory,{excludeManifest:true}),evidence};
  validatePartEnvelope(manifest,expected,partId);
  writeFileSync(join(directory,'ci-seal.json'),encode(manifest),{flag:'wx'}); return manifest;
}
export function validatePartInputs(inputs) {
  assert.deepEqual(inputs.map(i=>i.partId),partIds,'Missing, duplicate or extra part');
  const ids=new Set();
  for (const input of inputs) {
    assert.equal(input.result,'success','Part failed/cancelled/skipped');
    assert(/^[1-9][0-9]*$/u.test(input.artifactId),'Invalid artifact ID');
    assert(!ids.has(input.artifactId),'Repeated artifact ID');ids.add(input.artifactId);
    for (const key of ['artifactDigest','archiveDigest','manifestDigest']) assert(hex.test(input[key]),`Invalid ${key}`);
  }
}
export function joinParts({inputs,expected,destination}) {
  validatePartInputs(inputs); assert(!existsSync(destination),'Union destination exists');
  const files=new Map(), owners=new Set(), observations=new Set(), manifests=[];
  const shared=path=>['current-foundation.json','session-model.log','chain-model.log','exploration-decision.json'].includes(path)
    || /^sources\/[0-9a-f]{64}\.json$/u.test(path) || /^capacity\/binaries\/(js|wasm|native)\/[0-9a-f]{64}$/u.test(path);
  for (const input of inputs) {
    const seal=join(input.directory,'ci-seal.json'); assert.equal(fileDigest(seal),input.manifestDigest);
    const manifest=canonicalJson(seal); validatePartEnvelope(manifest,expected,input.partId);
    assert.deepEqual(inventory(input.directory,{excludeManifest:true}),manifest.files,'Transferred inventory differs');
    assert.equal(fileDigest(join(input.directory,'current-foundation.json')),expected.foundation.digest);
    assert.deepEqual(inspectPart(input.directory,input.partId,expected),manifest.evidence,'Transferred obligations differ');
    for (const owner of manifest.evidence.owners) {assert(!owners.has(owner),'Foreign/reused part owner');owners.add(owner);}
    for (const observation of manifest.evidence.observations) {assert(!observations.has(observation.id),'Duplicate observation');observations.add(observation.id);}
    for (const file of manifest.files) {
      if (files.has(file.path)) {assert(shared(file.path),`Part path collision ${file.path}`);assert.deepEqual(files.get(file.path).file,file,'Shared bytes differ');}
      else files.set(file.path,{file,directory:input.directory});
    }
    manifests.push(manifest);
  }
  mkdirSync(dirname(destination),{recursive:true});noLinks(dirname(destination));mkdirSync(destination);
  for (const {file,directory} of files.values()) {
    const to=join(destination,file.path);mkdirSync(dirname(to),{recursive:true});
    copyFileSync(join(directory,file.path),to,constants.COPYFILE_EXCL);chmodSync(to,0o444);
    assert.equal(fileDigest(to),file.sha256);
  }
  const {read,report}=reader(destination);
  const capacity=unionCapacityParts(['L-C0','L-C1'].map(id=>({path:`${prefix}capacity/parts/${id}.json`,report:report(`capacity/parts/${id}.json`)})),read);
  writeFileSync(join(destination,'capacity/all.json'),encode(capacity),{flag:'wx'});
  for (const mode of expected.exploration.required?['fixed','explore']:['fixed']) {
    const name=mode==='fixed'?'fixed-mutations':'mutations';
    const value=joinMutationParts(['L-M0','L-M1'].map(id=>({path:`${prefix}${name}-${id}.json`,report:report(`${name}-${id}.json`)})),
      {mode,source:report(`${name}-L-M0.json`).source,decision:expected.exploration});
    writeFileSync(join(destination,`${name}.json`),encode(value),{flag:'wx'});
  }
  // Derived provenance only. No original report or receipt is altered.
  const result={schema:'actql-pipeline-ci-part-union/0.1',...expected,
    parts:inputs.map(({partId,artifactId,artifactDigest,archiveDigest,manifestDigest})=>({partId,artifactId,artifactDigest,archiveDigest,manifestDigest})),
    fileCount:files.size,expandedBytes:[...files.values()].reduce((sum,{file})=>sum+file.size,0),
    ownerCount:owners.size,observationCount:observations.size,manifests};
  return result;
}
export function requireValidation(job,expected) {
  assert.equal(job?.result,'success','Synthetic validation failed/cancelled/skipped');
  assert.deepEqual(job.outputs,{'tested-sha':expected.context.testedSha,'source-digest':expected.source.digest,'plan-digest':planDigest},'Synthetic validation from another source/plan');
}
async function main() {
  const root=fileURLToPath(new URL('../../',import.meta.url));
  const [command,partId,stage]=process.argv.slice(2), directory=join(root,prefix), stateRoot=join(root,'.artifacts/pipeline-ci');
  if(command==='validation') {
    const state=partState(root);outputs({'tested-sha':state.context.testedSha,'source-digest':state.source.digest,'plan-digest':planDigest});return;
  }
  if(command==='join') {
    const expected=partState(root), needs=JSON.parse(process.env.PIPELINE_NEEDS??'{}');
    assert.deepEqual(Object.keys(needs).sort(),[...Object.values(partJobs),'pipeline-validation'].sort());
    requireValidation(needs['pipeline-validation'],expected);
    const staging=process.env.PIPELINE_STAGING;assert(staging);
    const inputs=partIds.map(partId=>{const job=needs[partJobs[partId]], out=job.outputs;return {partId,result:job.result,
      artifactId:out['artifact-id'],artifactDigest:out['artifact-digest'],archiveDigest:out['archive-digest'],manifestDigest:out['manifest-digest'],directory:join(staging,`${partId}-verified`)};});
    validatePartInputs(inputs);const began=performance.now();
    for(const input of inputs) verifyArchive(join(staging,input.partId),input.directory,input.archiveDigest);
    const result=joinParts({inputs,expected,destination:directory});result.verificationMs=performance.now()-began;
    mkdirSync(stateRoot,{recursive:true});writeFileSync(join(stateRoot,'join.json'),encode(result));
    console.log(`Verified four fresh parts: ${result.fileCount} files, ${result.expandedBytes} bytes, ${Math.round(result.verificationMs)}ms`);return;
  }
  assert(partIds.includes(partId));assert.equal(process.env.ACTQL_PIPELINE_PART,partId,'Part environment differs');
  const output=join(stateRoot,partId);
  if(command==='begin') {
    const state=partState(root);assert(!existsSync(join(root,fixturePath)));assert.equal(fileDigest(join(directory,'current-foundation.json')),state.foundation.digest);
    mkdirSync(output,{recursive:true});writeFileSync(join(output,'start.json'),encode(state),{flag:'wx'});writeFileSync(join(output,'stages.json'),encode(['foundation']),{flag:'wx'});
  } else if(command==='stage') {
    const path=join(output,'stages.json'), stages=canonicalJson(path);assert.equal(stage,partStages[partId][stages.length],'Wrong stage ordering');stages.push(stage);writeFileSync(path,encode(stages));
  } else if(command==='seal') {
    const expected=canonicalJson(join(output,'start.json'));assert.deepEqual(partState(root),expected,'Source/toolchain/foundation changed');
    sealPart({root,directory,partId,expected,stages:canonicalJson(join(output,'stages.json'))});
    outputs({'archive-digest':packArchive(directory,join(output,'evidence.tar')),'manifest-digest':fileDigest(join(directory,'ci-seal.json'))});
  } else assert.fail('Use begin|stage|seal PART, validation, or join');
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) await main();
