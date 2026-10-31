// Full inert Native archive + synthetic public-consumer claims + actual bounded
// read owners/injected GitHub mutation. No Native executable, public registry,
// owner credential/approval, real Latest mutation or runtime acceptance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmod,mkdir,mkdtemp,readFile,readdir,realpath,rm,writeFile,lstat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {inertNativeStandaloneFixture} from './fixtures/release-native-standalone.mjs';
import {freezeReleaseSet,prepareReleaseReview,nativeReleaseDraftRequest,prepareReleasePromotionReview,
  verifyReleasePromotionReview,releasePromotionReviewSummary} from './release-set.mjs';
import {observeNativeLatestTarget} from './release-registry.mjs';
import {nativeLatestPromotionPlan} from './release-channels.mjs';
import {promoteNativeReleaseLatest,promoteNpmReleaseChannels} from './publish-package-release.mjs';
import {runRelease} from './release.mjs';
const api='https://api.github.com/repos/actql/actql',registry='https://registry.npmjs.org/';
const wire=value=>Buffer.from(`${JSON.stringify(value,null,2)}\n`),sha=bytes=>createHash('sha256').update(bytes).digest('hex');

async function fixture(t,{mode='initial',version='0.0.7',defer=false}={}){
  const own=await mkdtemp(join(tmpdir(),'actql-native-latest-'));t.after(()=>rm(own,{recursive:true}));
  const native=await inertNativeStandaloneFixture(t,false,'darwin-arm64',version);
  const preparation=join(own,'preparation'),input=join(own,'input');await mkdir(input);
  const request={schemaVersion:'actql-release-request/0.1',releaseId:'inert-native-latest-only',version,
    source:{repository:'https://github.com/actql/actql',commit:'a'.repeat(40),branch:'main'},
    targets:[{id:'native',ecosystem:'native',packages:['actql-darwin-arm64','actql-checksums'],platforms:['darwin-arm64'],
      profiles:['remote'],destination:'https://github.com/actql/actql',channels:['download','latest']}],
    notes:{summary:'INERT Native Latest, not a selected release',breakingChanges:[],migration:[],knownLimitations:['No actual runtime/owner/API']}};
  const policy={schemaVersion:'actql-release-policy/0.1',allowedLines:['0.0'],publicationAuthority:'external-owner-approval-required'};
  const frozen=await freezeReleaseSet({request,policy,cohorts:[{targetId:'native',kind:'native-standalone',directory:native.destination}],destination:preparation});
  // Independent cold Node Host bytes; never a full Node producer/acceptance.
  const manifest=structuredClone(frozen.manifest),hostArtifacts=[];await mkdir(join(preparation,'host'));
  for(const name of ['client-wire','sdk','local-node','node']){
    const bytes=Buffer.from(`INERT Host ${name}`),file=`actql-${name}-${version}.tgz`;await writeFile(join(preparation,'host',file),bytes);
    hostArtifacts.push({targetId:'host',ecosystem:'npm',name:`@actql/${name}`,version,file,bytes:bytes.length,sha256:sha(bytes),
      integrity:`sha512-${createHash('sha512').update(bytes).digest('base64')}`,path:`host/${file}`});
  }
  manifest.request.targets.push({id:'host',ecosystem:'npm',packages:hostArtifacts.map(item=>item.name),platforms:['darwin-arm64'],
    profiles:['local'],destination:registry,channels:['candidate-inert']});
  const child=wire({version:'actql-package-release/0.1',sourceSha:request.source.commit,
    cohort:{packageVersion:version,registry,tag:'candidate-inert'},packages:hostArtifacts});
  await writeFile(join(preparation,'host/release.json'),child);
  manifest.cohorts.push({targetId:'host',kind:'node-npm',path:'host/release.json',bytes:child.length,sha256:sha(child),verification:'INERT cold Host only'});
  manifest.artifacts.push(...hostArtifacts);const raw=wire(manifest);await writeFile(join(preparation,'release-set.json'),raw);
  await writeFile(join(preparation,'release-set.sha256'),`${sha(raw)}  release-set.json\n`);
  const evidence=[];for(const kind of ['recipe','toolchain','build']){const bytes=Buffer.from(`INERT ${kind}`),file=`${kind}.txt`;
    await writeFile(join(input,file),bytes);evidence.push({id:kind,kind,file,bytes:bytes.length,sha256:sha(bytes)});}
  const review={schemaVersion:'actql-release-review-request/0.1',manifestSha256:sha(raw),evidence,
    provenance:['native','host'].map(targetId=>({targetId,recipeEvidence:'recipe',toolchainEvidence:'toolchain',build:{kind:'local',run:'inert',artifactId:null,evidence:'build'}})),
    environments:manifest.request.targets.map(target=>({targetId:target.id,platforms:target.platforms,profiles:target.profiles,node:null,python:null,abi:'INERT',limitations:['No actual executable']})),
    acceptance:manifest.request.targets.flatMap(target=>['prepublication-install','public-install'].map(phase=>({targetId:target.id,phase,status:'not-run',evidence:[],limitations:['No actual run']}))),
    changes:{previousSource:null,diffEvidence:null},executionScope:{publish:['native','host'],promote:[{targetId:'native',channel:'latest'}],resumeIdenticalMissing:['native','host']}};
  const originalReview=join(input,'original.json');await writeFile(originalReview,wire(review));const directory=join(own,'fixed');
  const fixed=await prepareReleaseReview({directory:preparation,expectedSha256:sha(raw),reviewFile:originalReview,destination:directory});
  const spec=nativeReleaseDraftRequest(fixed,'native'),artifacts=fixed.manifest.artifacts.filter(value=>value.targetId==='native');
  const bodies=new Map(),assets=[];for(const [index,item]of artifacts.entries()){
    const id=81+index;bodies.set(id,await readFile(join(directory,item.path)));assets.push({id,name:item.file,state:'uploaded',size:item.bytes,
      digest:`sha256:${item.sha256}`,browser_download_url:`https://github.com/actql/actql/releases/download/${spec.tag_name}/${encodeURIComponent(item.file)}`});
  }
  const release={...spec,id:71,draft:false,immutable:true,upload_url:`https://uploads.github.com/repos/actql/actql/releases/71/assets{?name,label}`};
  const old={id:60,tag_name:'v0.0.6',draft:false,prerelease:false,immutable:false};
  const drafts=[{id:30,tag_name:'old-unpublished-handoff',draft:true,prerelease:false}];
  let latest=mode==='initial'?null:mode==='same'?release:old;
  const control={unavailable:false,extraEligible:false,duplicate:false,still404:false,noChange:false,throwAfterSend:false,
    badTerminal:false,badIdentity:false,corrupt:false,mutatePresentation:false,replaceRelease:false,inconsistentLatest:false};
  const commands=[],requests=[];
  const rows=()=>[release,...drafts,...(mode==='old'?[old]:[]),...(control.extraEligible?[{id:90,tag_name:'v0.0.8',draft:false,prerelease:false}]:[])];
  const fetchOwner=async(url,options)=>{
    requests.push(url);assert.equal(options.method,'GET');assert.equal(options.body,undefined);assert.equal(options.headers.authorization,undefined);
    if(control.unavailable)return new Response('',{status:403});
    if(url===`${api}/immutable-releases`)return Response.json({enabled:true,enforced_by_owner:false});
    if(url.includes('/releases?per_page='))return Response.json(control.duplicate?[...rows(),release]:rows());
    if(url===`${api}/releases/latest`)return !latest||control.still404?new Response('',{status:404})
      :Response.json(control.inconsistentLatest?{...latest,immutable:false}:latest);
    if(url===`${api}/releases/71`||url===`${api}/releases/tags/${spec.tag_name}`)return Response.json(release);
    if(url===`${api}/git/ref/tags/${spec.tag_name}`)return Response.json({ref:`refs/tags/${spec.tag_name}`,object:{type:'commit',sha:request.source.commit}});
    if(url.startsWith(`${api}/releases/71/assets?`))return Response.json(assets);
    const id=Number(url.slice(`${api}/releases/assets/`.length));assert(bodies.has(id),url);
    return new Response(control.corrupt?Buffer.alloc(bodies.get(id).length,88):bodies.get(id));
  };
  const fetchResponse=async(url,options)=>{
    if(url.startsWith(api))return fetchOwner(url,options);
    const metadata=hostArtifacts.find(item=>url===`${registry}${encodeURIComponent(item.name)}/${item.version}`);
    if(metadata)return Response.json({name:metadata.name,version:metadata.version,
      dist:{integrity:metadata.integrity,tarball:`${registry}${metadata.name}/-/${metadata.file}`}});
    const item=hostArtifacts.find(value=>url===`${registry}${value.name}/-/${value.file}`);assert(item,url);
    return new Response(await readFile(join(directory,item.path)));
  };
  const observe=()=>observeNativeLatestTarget(directory,fixed.sha256,'native',{fetchOwner,fetchCdn:fetchOwner});
  const reportFile=join(input,'latest.json'),planFile=join(input,'plan.json'),publicFile=join(input,'public.json'),reviewFile=join(input,'promotion-request.json');
  const promotionDirectory=join(own,'promotion');let observed,plan;
  const body={schemaVersion:'actql-native-public-install/0.1',manifestSha256:fixed.sha256,targetId:'native',hostTargetId:'host',platform:'darwin-arm64',
    download:{schemaVersion:'actql-native-public-download/0.1',manifestSha256:fixed.sha256,targetId:'native',status:'verified',
      files:artifacts.map(item=>({file:item.file,expectedBytes:item.bytes,expectedSha256:item.sha256,retainedBytes:item.bytes,status:'verified'}))},
    installed:{binarySha256:native.record.binarySha256,binaryBytes:native.record.binaryBytes,payloadFiles:native.staged.files.length},
    nativeEnvironment:{PATH:'',HOME:'/inert/home',TMPDIR:'/inert/tmp'},nodeSupervisor:'v22.22.0',
    records:[{command:'/inert/native',args:['--version'],stdout:`${version}\n`,code:0,signal:null}],
    acceptedScope:'only completed direct Native --version/help/refusal and original Remote Host fixture; Node-free Native child PATH; separate public Node Host installation',
    unverified:['Local execution/bootstrap/approval','standard Project/README CLI','other platforms','npm Native launcher installation','full fault matrix','owner approval/publication authority']};
  const requestReview={schemaVersion:'actql-release-promotion-review-request/0.1',manifestSha256:fixed.sha256,
    publicInstallEvidence:[{id:'native-public',targetId:'native',kind:'native-public-install',file:'public.json',bytes:1,sha256:'b'.repeat(64)}],
    limitations:['INERT receipt and API only; no trusted acceptance']};
  const save=async()=>{const bytes=wire(body);await writeFile(publicFile,bytes);Object.assign(requestReview.publicInstallEvidence[0],{bytes:bytes.length,sha256:sha(bytes)});await writeFile(reviewFile,wire(requestReview));};
  const prepare=async()=>{
    observed=await observe();plan=nativeLatestPromotionPlan(fixed,{targetId:'native',before:observed.current},observed,sha(wire(observed)));
    await writeFile(reportFile,wire(observed));await writeFile(planFile,wire(plan));await save();
    return prepareReleasePromotionReview({directory,expectedSha256:fixed.sha256,planFile,channelReportFile:reportFile,reviewFile,destination:promotionDirectory});
  };
  let bundle;if(!defer)bundle=await prepare();
  const receiptsDirectory=join(own,'receipts');
  const runGitHub=async(patch,context)=>{
    assert(Object.isFrozen(patch)&&Object.isFrozen(patch.body)&&Object.isFrozen(context));
    assert.deepEqual(patch,{method:'PATCH',url:`${api}/releases/71`,body:{make_latest:'true'}});
    assert.equal(context.manifestSha256,fixed.sha256);assert.equal(context.promotionReviewSha256,bundle.sha256);
    const root=join(receiptsDirectory,fixed.sha256,bundle.sha256,'native-latest');let intent;
    for(const attempt of await readdir(root)){try{const path=join(root,attempt,'intent.json');intent=JSON.parse(await readFile(path));
      assert.equal((await lstat(path)).mode&0o777,0o600);}catch(failure){if(failure.code!=='ENOENT')throw failure;}}
    assert(intent);assert.equal(intent.state,'outcome-unknown');assert.deepEqual(intent.request,patch);commands.push(patch);
    if(!control.noChange)latest=release;
    if(control.mutatePresentation)release.name='changed after command';
    if(control.replaceRelease)release.id=99;
    if(control.throwAfterSend){control.throwAfterSend=false;throw Error('Original Latest response lost');}
    if(control.badTerminal)return {code:0};
    return {code:0,signal:null,status:200,stdout:JSON.stringify(control.badIdentity?{...release,id:90}:release),stderr:''};
  };
  const options={directory,expectedSha256:fixed.sha256,reviewDirectory:promotionDirectory,expectedReviewSha256:bundle?.sha256,
    receiptsDirectory,fetchOwner,fetchCdn:fetchOwner,fetchResponse,runGitHub};
  return {own,directory,fixed,native,release,old,control,body,requestReview,commands,requests,options,save,prepare,observe,
    setLatest:value=>{latest=value;},bundle,reportFile,planFile,promotionDirectory,
    run:extra=>promoteNativeReleaseLatest({...options,...extra})};
}

test('Native Latest: conditional first promotion is not 404 absence and positively confirms exact immutable id',async t=>{
  const f=await fixture(t);const report=await f.observe();assert.equal(report.current.state,'unassigned-or-selected');
  assert.equal(report.inventory.filter(item=>!item.draft&&!item.prerelease).length,1);
  const summary=releasePromotionReviewSummary(f.bundle);assert(summary.markdown.includes('conditional: unassigned or release 71'));
  assert(summary.markdown.includes('standard Project/README CLI'));assert(summary.markdown.includes(f.native.record.binarySha256));
  const result=await f.run();assert.equal(result.operationCount,1);assert.equal(result.releaseId,71);assert.equal(f.commands.length,1);
  assert.equal((await f.observe()).current.state,'present');assert.equal((await f.run()).operationCount,0);assert.equal(f.commands.length,1);
});

test('Native Latest: explicit known prior release uses original version owner and minimal pointer-only PATCH',async t=>{
  const f=await fixture(t,{mode:'old'});const value=await f.run();assert.equal(value.operationCount,1);assert.equal(value.tag,'v0.0.7');
  const move=join(f.own,'move.json');await writeFile(move,wire({targetId:'native',before:{state:'present',releaseId:60,tag:'v0.0.6'}}));
  const plan=await runRelease(['native-latest-plan',f.directory,f.fixed.sha256,move,f.reportFile]);assert.equal(plan.transitions[0].expectedVersion,'0.0.6');
  await assert.rejects(runRelease(['native-latest-promote',f.directory]),/unavailable/u);
});

test('Native Latest: 404 with another eligible full release stays unknown and cannot initialize',async t=>{
  const f=await fixture(t);f.control.extraEligible=true;const value=await f.observe();assert.equal(value.state,'unknown');
  await assert.rejects(f.run());assert.equal(f.commands.length,0);
});

test('Native Latest: prerelease Draft mutable incomplete or duplicate candidates never become Latest',async t=>{
  const rc=await fixture(t,{version:'0.0.7-rc.1',defer:true});await assert.rejects(rc.observe(),/prerelease/u);assert.equal(rc.requests.length,0);
  for(const kind of ['draft','mutable','bytes','duplicate','denied']){
    const f=await fixture(t);if(kind==='draft')f.release.draft=true;if(kind==='mutable')f.release.immutable=false;
    if(kind==='bytes')f.control.corrupt=true;if(kind==='duplicate')f.control.duplicate=true;if(kind==='denied')f.control.unavailable=true;
    await assert.rejects(f.run());assert.equal(f.commands.length,0);
  }
});

test('Native Latest: changed prior or newer channel cannot be overwritten by old plan or maintenance version',async t=>{
  const f=await fixture(t,{mode:'old'});f.old.tag_name='v0.1.0';
  const report=await f.observe();assert.throws(()=>nativeLatestPromotionPlan(f.fixed,{targetId:'native',before:report.current},report,sha(wire(report))),/roll.*backward/u);
  await assert.rejects(f.run());assert.equal(f.commands.length,0);
});

test('Native Latest: lost response preserves Unknown and explicit same-digest recovery skips exact current candidate',async t=>{
  const f=await fixture(t);f.control.throwAfterSend=true;await assert.rejects(f.run(),/outcome unknown/u);assert.equal(f.commands.length,1);
  const root=join(f.options.receiptsDirectory,f.fixed.sha256,f.bundle.sha256,'native-latest'),[attempt]=await readdir(root);
  assert.equal(JSON.parse(await readFile(join(root,attempt,'unknown.json'))).state,'unknown');
  await assert.rejects(lstat(join(root,attempt,'summary.json')),{code:'ENOENT'});
  const recovered=await f.run();assert.equal(recovered.operationCount,0);assert.equal(f.commands.length,1);
});

test('Native Latest: missing terminal or wrong response identity stops without a success record',async t=>{
  for(const flag of ['badTerminal','badIdentity']){const f=await fixture(t);f.control[flag]=true;await assert.rejects(f.run(),/outcome unknown/u);assert.equal(f.commands.length,1);}
});

test('Native Latest: conditional readback still404 is not confirmation and presentation drift remains Unknown',async t=>{
  for(const flag of ['still404','mutatePresentation','replaceRelease']){
    const f=await fixture(t);f.control[flag]=true;
    await assert.rejects(f.run(),flag==='replaceRelease'?/outcome unknown/u:/readback unknown/u);assert.equal(f.commands.length,1);
  }
});

test('Native Latest: complete Native public-consumer identity and original unverified scope are required',async t=>{
  for(const kind of ['upper','host','binary','download','scope','version','node-fallback']){
    const f=await fixture(t,{defer:true});
    if(kind==='upper')f.body.manifestSha256='f'.repeat(64);if(kind==='host')f.body.hostTargetId='native';
    if(kind==='binary')f.body.installed.binarySha256='f'.repeat(64);if(kind==='download')f.body.download.files[0].expectedSha256='f'.repeat(64);
    if(kind==='scope')f.body.unverified=[];if(kind==='version')f.body.records[0].stdout='0.0.8\n';if(kind==='node-fallback')f.body.nativeEnvironment.PATH='/bin';
    await assert.rejects(f.prepare());await assert.rejects(lstat(f.promotionDirectory),{code:'ENOENT'});
  }
});

test('Native Latest: both exact digests and correct runner kind required; no forged authority or default CLI',async t=>{
  const f=await fixture(t);
  await assert.rejects(f.run({approved:true}),/Unexpected/u);await assert.rejects(f.run({runGitHub:undefined}),/mutation port/u);
  await assert.rejects(f.run({expectedReviewSha256:'f'.repeat(64)}));
  await assert.rejects(promoteNpmReleaseChannels({directory:f.directory,expectedSha256:f.fixed.sha256,
    reviewDirectory:f.promotionDirectory,expectedReviewSha256:f.bundle.sha256,receiptsDirectory:f.options.receiptsDirectory,
    fetchResponse:f.options.fetchResponse,npmVersion:'11.21.0',runNpm:async()=>{throw Error('Must not run');}}),/only the original npm/u);
  assert.equal(f.commands.length,0);
  const verified=await verifyReleasePromotionReview({directory:f.directory,expectedSha256:f.fixed.sha256,
    reviewDirectory:f.promotionDirectory,expectedReviewSha256:f.bundle.sha256});assert.equal(verified.acceptance,'unaccepted');
});

test('Native Latest: original inert fixture default remains RC while explicit final fixture never executes a binary',async t=>{
  const f=await inertNativeStandaloneFixture(t);assert.equal(f.manifest.packageVersion,'0.0.7-rc.1');
  assert.equal(f.record.packageVersionObservation.stdout,'0.0.7-rc.1\n');assert.equal(f.binary.length,64);
});

test('Native Latest: contradictory candidate immutability at the actual Latest endpoint stays Unknown',async t=>{
  const f=await fixture(t,{mode:'same'});f.control.inconsistentLatest=true;
  const value=await f.observe();assert.equal(value.state,'unknown');assert.match(value.reason,/contradicts/u);
  await assert.rejects(f.run());assert.equal(f.commands.length,0);
});

// Own returned DATA only. Mutation is scheduled at the consumer's first
// following await; no API, product module or filesystem port is patched.
function latestTerminalMutation(initial,later) {
  const current={...initial},reads={code:0,signal:0,status:0,stdout:0,stderr:0},reply={};let mutated=false;
  for(const field of Object.keys(reads))Object.defineProperty(reply,field,{enumerable:true,get(){
    reads[field]++;
    if(field==='stdout'&&reads[field]===1)queueMicrotask(()=>{Object.assign(current,later);mutated=true;});
    return current[field];
  }});
  return {reply,reads,mutated:()=>mutated};
}

async function latestOriginalAttempt(f) {
  const target=join(f.options.receiptsDirectory,f.fixed.sha256,f.bundle.sha256,'native-latest'),names=await readdir(target);
  assert.equal(names.length,1);return realpath(join(target,names[0]));
}

for(const [name,code,signal,status]of [['nonzero',1,null,200],['signalled',0,'SIGTERM',200],
  ['unexpected HTTP',0,null,201],['unreported',undefined,undefined,undefined]])
test(`Native Latest terminal custody: original ${name} cannot become confirmed during receipt IO`,async t=>{
  const f=await fixture(t),original=f.options.runGitHub;
  const initial={code,signal,status,stdout:JSON.stringify(f.release),stderr:'ORIGINAL inert stderr\n'};
  const captured=latestTerminalMutation(initial,{code:0,signal:null,status:200,stdout:initial.stdout,stderr:'LATER stderr\n'});
  await assert.rejects(f.run({runGitHub:async(...args)=>{await original(...args);return captured.reply;}}),failure=>{
    assert.match(failure.message,/outcome unknown/u);assert.match(failure.originalMutationFailure.message,/command did not confirm completion/u);
    assert.equal(Object.getOwnPropertyDescriptor(failure,'originalMutationFailure').enumerable,false);return true;});
  assert(captured.mutated());assert.deepEqual(captured.reads,{code:1,signal:1,status:1,stdout:1,stderr:1});
  const attempt=await latestOriginalAttempt(f);assert.deepEqual(JSON.parse(await readFile(join(attempt,'terminal.json'))),JSON.parse(JSON.stringify(initial)));
  assert.equal(f.commands.length,1);assert.equal(JSON.parse(await readFile(join(attempt,'unknown.json'))).reason,'original-mutation-unconfirmed');
  await assert.rejects(lstat(join(attempt,'public-after.json')),{code:'ENOENT'});await assert.rejects(lstat(join(attempt,'summary.json')),{code:'ENOENT'});
});

for(const [name,changed]of [['id',{id:99}],['tag',{tag_name:'v0.0.8'}],['immutability',{immutable:false}],['JSON',null]])
test(`Native Latest terminal custody: original invalid ${name} cannot be replaced by later valid response`,async t=>{
  const f=await fixture(t),original=f.options.runGitHub,valid=JSON.stringify(f.release);
  const initial={code:0,signal:null,status:200,stdout:changed?JSON.stringify({...f.release,...changed}):'not JSON',stderr:''};
  const captured=latestTerminalMutation(initial,{stdout:valid});
  await assert.rejects(f.run({runGitHub:async(...args)=>{await original(...args);return captured.reply;}}),failure=>{
    assert.match(failure.message,/outcome unknown/u);assert(failure.originalMutationFailure);return true;});
  assert(captured.mutated());assert.deepEqual(captured.reads,{code:1,signal:1,status:1,stdout:1,stderr:1});
  const attempt=await latestOriginalAttempt(f);assert.deepEqual(JSON.parse(await readFile(join(attempt,'terminal.json'))),initial);
  assert.equal(f.commands.length,1);await assert.rejects(lstat(join(attempt,'summary.json')),{code:'ENOENT'});
});

test('Native Latest terminal custody: original success and exact identity survive later mutation',async t=>{
  const f=await fixture(t),original=f.options.runGitHub;
  const initial={code:0,signal:null,status:200,stdout:JSON.stringify(f.release),stderr:'ORIGINAL stderr\n'};
  const captured=latestTerminalMutation(initial,{code:1,signal:'SIGTERM',status:503,stdout:'{"id":99}',stderr:'LATER stderr\n'});
  const result=await f.run({runGitHub:async(...args)=>{await original(...args);return captured.reply;}});
  assert(captured.mutated());assert.deepEqual(captured.reads,{code:1,signal:1,status:1,stdout:1,stderr:1});
  assert.equal(result.state,'exact-original-latest-observed');assert.equal(result.releaseId,71);assert.equal(f.commands.length,1);
  assert.deepEqual(JSON.parse(await readFile(join(result.receiptDirectory,'terminal.json'))),initial);
});

test('Native Latest terminal custody: unrelated returned getters stay unread and absent from terminal receipt',async t=>{
  const f=await fixture(t),original=f.options.runGitHub;let extraReads=0;
  const initial={code:0,signal:null,status:200,stdout:JSON.stringify(f.release),stderr:''},captured=latestTerminalMutation(initial,{});
  Object.defineProperty(captured.reply,'unselected',{enumerable:true,get(){extraReads++;return 'INERT extra DATA';}});
  const result=await f.run({runGitHub:async(...args)=>{await original(...args);return captured.reply;}});
  assert.equal(extraReads,0);assert(captured.mutated());assert.deepEqual(captured.reads,{code:1,signal:1,status:1,stdout:1,stderr:1});
  assert.deepEqual(JSON.parse(await readFile(join(result.receiptDirectory,'terminal.json'))),initial);
});

test('Native Latest terminal custody: private post-mutation readback failure stays SAME without cause leakage',async t=>{
  const f=await fixture(t),original=f.options.fetchResponse;let statusReads=0,caught;
  const failure=Object.assign(Error('PRIVATE-INERT-LATEST-READBACK'),{originalCleanup:{inertIdentityOnly:true}});
  try{await f.run({fetchResponse:async(...args)=>f.commands.length?{get status(){statusReads++;throw failure;}}:original(...args)});}catch(error){caught=error;}
  assert(caught);assert.equal(caught.originalLatestError,failure);assert.equal(caught.originalMutationFailure,undefined);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalLatestError').enumerable,false);assert.equal(caught.cause,undefined);
  assert(!String(caught).includes('PRIVATE-INERT'));assert(!inspect(caught).includes('PRIVATE-INERT'));
  assert.equal(statusReads,1);assert.equal(f.commands.length,1);const attempt=await latestOriginalAttempt(f);
  assert.equal(JSON.parse(await readFile(join(attempt,'readback-unknown.json'))).reason,'original-public-or-current-readback-unconfirmed');
  for(const file of await readdir(attempt))assert(!(await readFile(join(attempt,file),'utf8')).includes('PRIVATE-INERT'));
  await assert.rejects(lstat(join(attempt,'summary.json')),{code:'ENOENT'});
});

test('Native Latest terminal custody: refused readback-Unknown write retains physical error and SAME private failure',async t=>{
  const f=await fixture(t),original=f.options.fetchResponse;let attempt,statusReads=0,caught;
  const failure=Object.assign(Error('PRIVATE-INERT-LATEST-READBACK-WRITE'),{originalCleanup:{inertIdentityOnly:true}});
  try{await f.run({fetchResponse:async(...args)=>{
    if(!f.commands.length)return original(...args);
    attempt=await latestOriginalAttempt(f);await chmod(attempt,0o500);
    return {get status(){statusReads++;throw failure;}};
  }});}catch(error){caught=error;}finally{if(attempt)await chmod(attempt,0o700);}
  assert.equal(caught.code,'EACCES');assert.equal(caught.path,join(attempt,'readback-unknown.json'));
  assert.equal(caught.originalLatestError,failure);assert.equal(caught.originalAttempt,attempt);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalLatestError').enumerable,false);assert.equal(caught.cause,undefined);
  assert(!inspect(caught).includes('PRIVATE-INERT'));assert.equal(statusReads,1);assert.equal(f.commands.length,1);
  assert.equal(JSON.parse(await readFile(join(attempt,'terminal.json'))).code,0);
  await assert.rejects(lstat(join(attempt,'readback-unknown.json')),{code:'ENOENT'});await assert.rejects(lstat(join(attempt,'summary.json')),{code:'ENOENT'});
});

test('Native Latest terminal custody: both readback receipt errors and original attempt remain held',async t=>{
  const f=await fixture(t),original=f.options.fetchResponse;let attempt,caught;
  try{await f.run({fetchResponse:async(...args)=>{
    if(f.commands.length&&!attempt){attempt=await latestOriginalAttempt(f);await chmod(attempt,0o500);}
    return original(...args);
  }});}catch(error){caught=error;}finally{if(attempt)await chmod(attempt,0o700);}
  assert.equal(caught.code,'EACCES');assert.equal(caught.path,join(attempt,'readback-unknown.json'));
  assert.equal(caught.originalLatestError.code,'EACCES');assert.equal(caught.originalLatestError.path,join(attempt,'public-after.json'));
  assert.notEqual(caught,caught.originalLatestError);assert.equal(caught.originalAttempt,attempt);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalLatestError').enumerable,false);assert.equal(caught.cause,undefined);
  assert.equal(f.commands.length,1);await assert.rejects(lstat(join(attempt,'public-after.json')),{code:'ENOENT'});
  await assert.rejects(lstat(join(attempt,'summary.json')),{code:'ENOENT'});
});
