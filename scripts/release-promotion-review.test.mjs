// Inert cold bytes and supplied receipt DATA. No archive producer, public
// install, trusted job/approval, registry/current channel or mutation is tested.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {releaseVersion} from './release-version.mjs';
import {promotionPlan} from './release-channels.mjs';
import {prepareReleaseReview, prepareReleasePromotionReview, verifyReleasePromotionReview,
  releasePromotionReviewSummary, verifyReleaseSet} from './release-set.mjs';
import {runRelease} from './release.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const wire = body => Buffer.from(`${JSON.stringify(body, null, 2)}\n`);

async function fixture(t, {scope = true} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-promotion-review-')); t.after(() => rm(root, {recursive: true}));
  const preparation = join(root, 'preparation'), oldInput = join(root, 'original-review-input'), inputs = join(root, 'post-input');
  for (const path of [join(preparation, 'node'), oldInput, inputs]) await mkdir(path, {recursive: true});
  const version = '0.0.7', source = 'a'.repeat(40), artifacts = [];
  for (const name of ['client-wire', 'sdk', 'local-node', 'node']) {
    const bytes = Buffer.from(`Independent inert ${name}; not an archive or runtime\n`), file = `actql-${name}-${version}.tgz`;
    await writeFile(join(preparation, 'node', file), bytes);
    artifacts.push({targetId: 'node', ecosystem: 'npm', name: `@actql/${name}`, version, file, bytes: bytes.length,
      sha256: sha(bytes), integrity: `sha512-${createHash('sha512').update(bytes).digest('base64')}`, path: `node/${file}`});
  }
  const target = {id: 'node', ecosystem: 'npm', packages: artifacts.map(value => value.name), platforms: ['darwin-arm64'],
    profiles: ['local', 'remote'], destination: 'https://registry.npmjs.org/', channels: ['candidate-fixture', 'latest']};
  const child = wire({version: 'actql-package-release/0.1', sourceSha: source,
    cohort: {packageVersion: version, registry: target.destination, tag: 'candidate-fixture'}, packages: artifacts});
  await writeFile(join(preparation, 'node/release.json'), child);
  const manifest = {schemaVersion: 'actql-release-set/0.1', release: releaseVersion(version),
    request: {schemaVersion: 'actql-release-request/0.1', releaseId: 'inert-post-freeze-review', version,
      source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'}, targets: [target],
      notes: {summary: 'Independent cold review only', breakingChanges: [], migration: [], knownLimitations: ['Not a real archive/runtime']}},
    policy: {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'], publicationAuthority: 'external-owner-approval-required'},
    cohorts: [{targetId: 'node', kind: 'node-npm', path: 'node/release.json', bytes: child.length, sha256: sha(child),
      verification: 'Independent inert cold bytes only'}], artifacts, acceptance: 'unaccepted', qualification: 'Inert metadata review only'};
  const original = wire(manifest); await writeFile(join(preparation, 'release-set.json'), original);
  await writeFile(join(preparation, 'release-set.sha256'), `${sha(original)}  release-set.json\n`);
  const oldEvidence = [];
  for (const kind of ['recipe','toolchain','build']) {const bytes = Buffer.from(`INERT ${kind}`), file = `${kind}.txt`;
    await writeFile(join(oldInput, file), bytes); oldEvidence.push({id:kind,kind,file,bytes:bytes.length,sha256:sha(bytes)});}
  const oldRequest = {schemaVersion:'actql-release-review-request/0.1',manifestSha256:sha(original),evidence:oldEvidence,
    provenance:[{targetId:'node',recipeEvidence:'recipe',toolchainEvidence:'toolchain',build:{kind:'local',run:'inert',artifactId:null,evidence:'build'}}],
    environments:[{targetId:'node',platforms:target.platforms,profiles:target.profiles,node:'inert declaration only',python:null,abi:'inert',limitations:['No product']}],
    acceptance:['prepublication-install','public-install'].map(phase=>({targetId:'node',phase,status:'not-run',evidence:[],limitations:['No product']})),
    changes:{previousSource:null,diffEvidence:null},executionScope:{publish:['node'],promote:scope?[{targetId:'node',channel:'latest'}]:[],resumeIdenticalMissing:[]}};
  const oldFile = join(oldInput,'request.json'); await writeFile(oldFile,wire(oldRequest)); const directory = join(root,'fixed');
  const fixed = await prepareReleaseReview({directory:preparation,expectedSha256:sha(original),reviewFile:oldFile,destination:directory});
  const report = {schemaVersion:'actql-release-channels/0.1',manifestSha256:fixed.sha256,
    startedAt:'2000-01-01T00:00:00Z',endedAt:'2000-01-01T00:00:01Z',
    observations:artifacts.flatMap(value=>target.channels.map(channel=>({targetId:'node',name:value.name,channel,state:'present',version:channel==='latest'?'0.0.6':version}))),
    issues:[],requests:[],qualification:'INERT historical DATA only'};
  const moves = artifacts.map(value=>({targetId:'node',name:value.name,channel:'latest',expectedVersion:'0.0.6'}));
  let plan = promotionPlan(fixed,moves,report,sha(wire(report)));
  const planFile = join(inputs,'plan.json'), channelReportFile = join(inputs,'channels.json');
  await writeFile(planFile,wire(plan)); await writeFile(channelReportFile,wire(report));
  const body = {version:'actql-release-install-acceptance/0.1',sourceSha:source,
    artifacts:artifacts.map(({name,version,sha256,integrity})=>({name,version,sha256,integrity})),
    consumer:'/inert/no-real-consumer',node:'v22.22.0',platform:'darwin',arch:'arm64',registry:target.destination,
    publicRegistryPublication:'exact-original-bytes-observed-anonymously',cohortManifestSha256:sha(child),
    releaseSetBinding:{manifestSha256:fixed.sha256,targetId:'node',cohortManifestSha256:sha(child),sourceSha:source,version,
      requestedPlatforms:target.platforms,requestedProfiles:target.profiles,
      artifacts:artifacts.map(({name,version,file,bytes,sha256,integrity})=>({name,version,file,bytes,sha256,integrity}))},
    publicObservationFile:'inert-before.json',publicObservationAfterFile:'inert-after.json',publicRuntimeScope:'INERT claims only; no runtime',
    approvalAcceptance:{status:'incomplete',reason:'INERT supplied scope, never accepted'},results:[]};
  const publicFile = join(inputs,'public.json'), reviewFile = join(inputs,'request.json'), destination = join(root,'promotion');
  const request = {schemaVersion:'actql-release-promotion-review-request/0.1',manifestSha256:fixed.sha256,
    publicInstallEvidence:[{id:'public-node',targetId:'node',kind:'node-public-install',file:'public.json',bytes:1,sha256:'b'.repeat(64)}],
    limitations:['All synthetic receipt claims; no actual public job or install']};
  const save = async () => {const bytes=wire(body);await writeFile(publicFile,bytes);Object.assign(request.publicInstallEvidence[0],{bytes:bytes.length,sha256:sha(bytes)});await writeFile(reviewFile,wire(request));};
  await save();
  const options={directory,expectedSha256:fixed.sha256,planFile,channelReportFile,reviewFile,destination};
  return {root,inputs,directory,destination,fixed,manifest,artifacts,target,report,moves,body,request,publicFile,reviewFile,planFile,channelReportFile,options,save,
    prepare:()=>prepareReleasePromotionReview(options),
    verify:review=>verifyReleasePromotionReview({directory,expectedSha256:fixed.sha256,reviewDirectory:destination,expectedReviewSha256:review.sha256})};
}

test('promotion review: separate acyclic bundle binds original upper plan and receipt without changing artifact or earlier acceptance',async t=>{
  const f=await fixture(t),before=await readFile(join(f.directory,'release-set.json')),files=await readdir(f.directory);
  const checked=await f.prepare();assert.notEqual(checked.sha256,f.fixed.sha256);assert.equal(checked.acceptance,'unaccepted');
  assert.deepEqual(await readFile(join(f.directory,'release-set.json')),before);assert.deepEqual(await readdir(f.directory),files);
  assert.equal(checked.fixed.review.acceptance.find(value=>value.phase==='public-install').status,'not-run');
  assert.equal(checked.publicEvidence[0].declaredApprovalAcceptance.status,'incomplete');
  assert.deepEqual((await readdir(f.destination)).sort(),['channel-report.json','evidence','plan.json','promotion-review.json','promotion-review.sha256','request.json']);
  assert.deepEqual(await f.verify(checked),checked);
  const summary=releasePromotionReviewSummary(checked);assert.equal(summary.manifestSha256,f.fixed.sha256);
  assert.equal(summary.promotionReviewSha256,checked.sha256);assert(summary.markdown.includes('Acceptance: unaccepted'));
  assert(summary.markdown.includes('not promoted'));assert(summary.markdown.includes('0.0.6'));assert(summary.markdown.includes('0.0.7'));
});

test('promotion review: existing CLI prepares and cold verifies summaries but never promotes',async t=>{
  const f=await fixture(t),o=f.options;
  const checked=await runRelease(['promotion-review',o.directory,o.expectedSha256,o.planFile,o.channelReportFile,o.reviewFile,o.destination]);
  const summary=await runRelease(['promotion-summary',o.directory,o.expectedSha256,o.destination,checked.sha256]);
  assert.equal(summary.acceptance,'unaccepted');assert.equal(summary.plan.execution,'unavailable');
  await assert.rejects(runRelease(['promote',o.destination]),/unavailable/u);
});

test('promotion review: legacy foreign or changed receipt identity cannot be bound to the selected upper and target',async t=>{
  for(const kind of ['legacy','upper','target','child','source','version','sri','origin','after']) {
    const f=await fixture(t);
    if(kind==='legacy')f.body.releaseSetBinding=null;
    else if(kind==='upper')f.body.releaseSetBinding.manifestSha256='f'.repeat(64);
    else if(kind==='target')f.body.releaseSetBinding.targetId='other';
    else if(kind==='child')f.body.cohortManifestSha256='f'.repeat(64);
    else if(kind==='source')f.body.sourceSha='b'.repeat(40);
    else if(kind==='version')f.body.releaseSetBinding.version='0.0.8';
    else if(kind==='sri')f.body.artifacts[0].integrity='sha512-other';
    else if(kind==='origin')f.body.registry='http://127.0.0.1:9/';
    else delete f.body.publicObservationAfterFile;
    await f.save();await assert.rejects(f.prepare());await assert.rejects(lstat(f.destination),{code:'ENOENT'});
  }
});

test('promotion review: exact original plan report and bound proposed channel scope are required',async t=>{
  const outside=await fixture(t,{scope:false});await assert.rejects(outside.prepare(),/exceeds/u);
  for(const kind of ['plan','report','unknown-plan-field']) {
    const f=await fixture(t),plan=JSON.parse(await readFile(f.planFile));
    if(kind==='plan')plan.transitions[0].toVersion='0.0.8';
    else if(kind==='report'){f.report.observations[0].version='0.0.5';await writeFile(f.channelReportFile,wire(f.report));}
    else plan.approved=true;
    await writeFile(f.planFile,wire(plan));await assert.rejects(f.prepare());await assert.rejects(lstat(f.destination),{code:'ENOENT'});
  }
});

test('promotion review: missing changed linked or traversing raw evidence refuses before output',async t=>{
  for(const kind of ['missing','changed','link','traversal','unknown-kind','actor']) {
    const f=await fixture(t);
    if(kind==='missing')await rm(f.publicFile);
    else if(kind==='changed')await writeFile(f.publicFile,'Changed actual bytes');
    else if(kind==='link'){const target=join(f.inputs,'keeper.json');await writeFile(target,await readFile(f.publicFile));await rm(f.publicFile);await symlink(target,f.publicFile);}
    else {if(kind==='traversal')f.request.publicInstallEvidence[0].file='../public.json';
      else if(kind==='unknown-kind')f.request.publicInstallEvidence[0].kind='native-public-install';else f.request.approved=true;
      await writeFile(f.reviewFile,wire(f.request));}
    await assert.rejects(f.prepare());await assert.rejects(lstat(f.destination),{code:'ENOENT'});
  }
});

test('promotion review: cold original receipt plan or original artifact mutation cannot retain the bundle identity',async t=>{
  for(const kind of ['evidence','plan','artifact']) {
    const f=await fixture(t),checked=await f.prepare();
    const path=kind==='evidence'?join(f.destination,'evidence/public-node'):kind==='plan'?join(f.destination,'plan.json'):join(f.directory,f.artifacts[0].path);
    const bytes=await readFile(path);await writeFile(path,Buffer.alloc(bytes.length,65));await assert.rejects(f.verify(checked));
  }
});

test('promotion review: self-written passed header is refused even with a new supplied digest',async t=>{
  const f=await fixture(t),checked=await f.prepare(),header={...checked.header,acceptance:'passed'},bytes=wire(header),digest=sha(bytes);
  await writeFile(join(f.destination,'promotion-review.json'),bytes);await writeFile(join(f.destination,'promotion-review.sha256'),`${digest}  promotion-review.json\n`);
  await assert.rejects(verifyReleasePromotionReview({directory:f.directory,expectedSha256:f.fixed.sha256,reviewDirectory:f.destination,expectedReviewSha256:digest}),/unaccepted/u);
});

test('promotion review: new historical expected values need a distinct bundle while the fixed artifact digest stays original',async t=>{
  const f=await fixture(t),first=await f.prepare();
  for(const value of f.report.observations)if(value.channel==='latest')value.version='0.0.5';
  const moves=f.moves.map(value=>({...value,expectedVersion:'0.0.5'}));
  await writeFile(f.channelReportFile,wire(f.report));await writeFile(f.planFile,wire(promotionPlan(f.fixed,moves,f.report,sha(wire(f.report)))));
  const second=await prepareReleasePromotionReview({...f.options,destination:join(f.root,'promotion-two')});
  assert.notEqual(second.sha256,first.sha256);assert.equal(second.fixed.sha256,first.fixed.sha256);
  assert.equal((await verifyReleaseSet(f.directory,{expectedSha256:f.fixed.sha256})).sha256,f.fixed.sha256);
  assert.equal((await f.verify(first)).sha256,first.sha256); // Historical DATA, never current CAS.
  await assert.rejects(f.prepare(),{code:'EEXIST'});
});

test('promotion review: destination cannot mutate the original fixed directory through a parent alias',async t=>{
  const f=await fixture(t),alias=join(f.root,'fixed-alias');await symlink(f.directory,alias);
  await assert.rejects(prepareReleasePromotionReview({...f.options,destination:join(alias,'new-review')}),/outside the original/u);
  await assert.rejects(lstat(join(f.directory,'new-review')),{code:'ENOENT'});
});

test('promotion review: duplicate absent unselected or oversized evidence declarations cannot create output',async t=>{
  for(const kind of ['duplicate','missing-target','foreign-target','oversized']) {
    const f=await fixture(t);
    if(kind==='duplicate')f.request.publicInstallEvidence.push({...f.request.publicInstallEvidence[0]});
    else if(kind==='missing-target')f.request.publicInstallEvidence=[];
    else if(kind==='foreign-target')f.request.publicInstallEvidence[0].targetId='other';
    else f.request.publicInstallEvidence[0].bytes=64*1024*1024+1;
    await writeFile(f.reviewFile,wire(f.request));await assert.rejects(f.prepare());await assert.rejects(lstat(f.destination),{code:'ENOENT'});
  }
});

test('promotion review: summaries retain every post-freeze digest and limitation while escaping untrusted receipt claims',async t=>{
  const f=await fixture(t);f.body.publicRuntimeScope='UNTRUSTED <b>claim</b>';
  f.request.limitations=['post-scope-marker <owner-control>'];await f.save();
  const checked=await f.prepare(),summary=releasePromotionReviewSummary(checked);
  assert(summary.markdown.includes(f.request.publicInstallEvidence[0].sha256),'Public receipt digest must be visible for owner review');
  assert(summary.markdown.includes(checked.header.plan.sha256));assert(summary.markdown.includes(checked.header.channelReport.sha256));
  assert(summary.markdown.includes('post-scope-marker'));assert(!summary.markdown.includes('<b>claim</b>'));
  assert(!summary.markdown.includes('<owner-control>'));assert.equal(summary.header.plan.sha256,checked.header.plan.sha256);
  assert.equal(summary.acceptance,'unaccepted');
});
