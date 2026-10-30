// Full inert Native archive + injected owner/API protocol only. No executable,
// authenticated API, GitHub mutation, public install or approval is exercised.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmod, cp, lstat, mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {tmpdir} from 'node:os';
import test, {before, after} from 'node:test';
import {inertNativeStandaloneFixture} from './fixtures/release-native-standalone.mjs';
import {freezeReleaseSet, prepareReleaseReview, nativeReleaseDraftRequest} from './release-set.mjs';
import {nativePublishPlan, publishNativeRelease} from './publish-package-release.mjs';
import {observeNativePublicationTarget} from './release-registry.mjs';
import {runRelease} from './release.mjs';

const sha = value => createHash('sha256').update(value).digest('hex');
const api = 'https://api.github.com/repos/actql/actql';
let root, reviewed, noRecovery, unaccepted;
const cleanups = [];
before(async () => {
  root = await mkdtemp(join(tmpdir(), 'actql-native-publish-'));
  const f = await inertNativeStandaloneFixture({after: callback => cleanups.push(callback)});
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'inert-native-protocol-only', version: '0.0.7-rc.1',
    source: {repository: 'https://github.com/actql/actql', commit: 'a'.repeat(40), branch: 'main'},
    targets: [{id: 'native', ecosystem: 'native', packages: ['actql-darwin-arm64', 'actql-checksums'],
      platforms: ['darwin-arm64'], profiles: ['remote'], destination: 'https://github.com/actql/actql', channels: ['candidate-fixture']}],
    notes: {summary: 'Independent inert protocol, not a candidate', breakingChanges: [], migration: [], knownLimitations: ['No executable/runtime/permission']}};
  const policy = {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'], publicationAuthority: 'external-owner-approval-required'};
  const directory = join(root, 'preparation');
  const fixed = await freezeReleaseSet({request, policy, cohorts: [{targetId: 'native', kind: 'native-standalone', directory: f.destination}], destination: directory});
  const input = join(root, 'review-input'); await mkdir(input); const evidence = [];
  for (const kind of ['recipe','toolchain','build','acceptance']) {
    const file = `${kind}.txt`, bytes = Buffer.from(`INERT ${kind} DATA, not accepted evidence`);
    await writeFile(join(input,file), bytes); evidence.push({id:kind,kind,file,bytes:bytes.length,sha256:sha(bytes)});
  }
  const review = {schemaVersion:'actql-release-review-request/0.1',manifestSha256:fixed.sha256,evidence,
    provenance:[{targetId:'native',recipeEvidence:'recipe',toolchainEvidence:'toolchain',build:{kind:'local',run:'inert',artifactId:null,evidence:'build'}}],
    environments:[{targetId:'native',platforms:['darwin-arm64'],profiles:['remote'],node:null,python:null,abi:'Inert Mach-O header',limitations:['No executable']}],
    acceptance:[{targetId:'native',phase:'prepublication-install',status:'passed',evidence:['acceptance'],limitations:['Supplied DATA only']},
      {targetId:'native',phase:'public-install',status:'not-run',evidence:[],limitations:['No public candidate']}],
    changes:{previousSource:null,diffEvidence:null},executionScope:{publish:['native'],promote:[],resumeIdenticalMissing:['native']}};
  const file = join(input,'review.json'); await writeFile(file,JSON.stringify(review));
  reviewed = await prepareReleaseReview({directory,expectedSha256:fixed.sha256,reviewFile:file,destination:join(root,'reviewed')});
  review.executionScope.resumeIdenticalMissing=[]; await writeFile(file,JSON.stringify(review));
  noRecovery = await prepareReleaseReview({directory,expectedSha256:fixed.sha256,reviewFile:file,destination:join(root,'no-recovery')});
  review.acceptance[0].status='not-run'; review.acceptance[0].evidence=[]; await writeFile(file,JSON.stringify(review));
  unaccepted = await prepareReleaseReview({directory,expectedSha256:fixed.sha256,reviewFile:file,destination:join(root,'unaccepted')});
});
after(async()=>{for(const cleanup of cleanups)await cleanup();if(root)await rm(root,{recursive:true});});

async function fixture(t, variant='reviewed') {
  const own = await mkdtemp(join(root,'case-')); t.after(()=>rm(own,{recursive:true}));
  const directory = join(own,'fixed'); await cp(join(root,variant),directory,{recursive:true});
  const selected = variant==='reviewed'?reviewed:variant==='no-recovery'?noRecovery:unaccepted;
  const spec = nativeReleaseDraftRequest(selected,'native'), artifacts=selected.manifest.artifacts;
  const originals=new Map();for(const item of artifacts)originals.set(item.file,await readFile(join(directory,item.path)));
  let release=null, ref=null, nextAsset=81;
  const assets=[], bodies=new Map(), requests=[], commands=[], control={};
  const setting={enabled:true,enforced_by_owner:false};
  const installAsset = item => {
    const existing=assets.find(value=>value.name===item.file); if(existing)return existing;
    const asset={id:nextAsset++,name:item.file,state:'uploaded',size:item.bytes,digest:`sha256:${item.sha256}`,
      browser_download_url:`https://github.com/actql/actql/releases/download/${spec.tag_name}/${encodeURIComponent(item.file)}`};
    assets.push(asset);bodies.set(asset.id,originals.get(item.file));return asset;
  };
  const create = () => {release={...spec,id:71,draft:true,immutable:false,
    upload_url:'https://uploads.github.com/repos/actql/actql/releases/71/assets{?name,label}'};return release;};
  const publish = () => {release.draft=false;release.immutable=!control.mutablePublished;ref={ref:`refs/tags/${spec.tag_name}`,object:{type:'commit',sha:spec.target_commitish}};};
  const fetchOwner=async(url,options)=>{
    assert(url.startsWith(api+'/'));assert.equal(options.method,'GET');assert.equal(options.redirect,'manual');assert.equal(options.body,undefined);
    assert.equal(options.headers.authorization,undefined);requests.push({url,accept:options.headers.accept});
    if(control.unavailable)return new Response('',{status:403});
    if(url===`${api}/immutable-releases`)return Response.json(setting);
    if(url.includes('/releases?per_page=')) {
      if(control.inventory404)return new Response('',{status:404});
      if(control.pages){const page=Number(new URL(url).searchParams.get('page'));return Response.json(control.pages[page-1]??[]);}
      return Response.json(release?[release]:[]);
    }
    if(url===`${api}/git/ref/tags/${spec.tag_name}`)return ref?Response.json(ref):new Response('',{status:404});
    if(url===`${api}/releases/71`)return Response.json(release);
    if(url.startsWith(`${api}/releases/71/assets?`))return Response.json(assets);
    const id=Number(url.slice(`${api}/releases/assets/`.length));assert(bodies.has(id),url);
    if(control.mutateInventory)assets[0].id=199;
    if(control.disableDuringStream)setting.enabled=false;
    if(control.replaceRelease)release.id=199;
    if(control.cdn)return new Response('',{status:302,headers:{location:`https://release-assets.githubusercontent.com/inert/${id}?signed=secret`}});
    return new Response(bodies.get(id));
  };
  const fetchCdn=async(url,options)=>{
    assert(url.startsWith('https://release-assets.githubusercontent.com/inert/'));assert.deepEqual(options.headers,{accept:'application/octet-stream'});
    assert.equal(options.credentials,'omit');const id=Number(new URL(url).pathname.split('/').at(-1));return new Response(bodies.get(id));
  };
  const receipts=join(own,'receipts');
  const options={directory,expectedSha256:selected.sha256,targetId:'native',receiptsDirectory:receipts,fetchOwner,fetchCdn,
    runGitHub:async(request,context)=>{
      assert(Object.isFrozen(request));if(request.body)assert(Object.isFrozen(request.body));if(request.headers)assert(Object.isFrozen(request.headers));
      assert.equal(context.manifestSha256,selected.sha256);assert.equal(context.targetId,'native');
      const attempts=await readdir(join(receipts,selected.sha256,'native'));
      const latest=join(receipts,selected.sha256,'native',attempts.at(-1));
      const originalIntents=[];
      for(const attempt of attempts)for(const file of await readdir(join(receipts,selected.sha256,'native',attempt)))
        if(file.endsWith(`-${context.kind}-intent.json`))originalIntents.push(JSON.parse(await readFile(join(receipts,selected.sha256,'native',attempt,file))));
      const intent=originalIntents.find(value=>JSON.stringify(value.request)===JSON.stringify(request));assert(intent,'Original synced intent precedes runner');
      assert.equal(intent.state,'outcome-unknown');commands.push({request,kind:context.kind});let id,status;
      if(context.kind==='create') {
        assert.equal(request.method,'POST');assert.equal(request.url,`${api}/releases`);assert.deepEqual(request.body,spec);
        assert.equal(release,null);id=create().id;status=201;
        if(control.alreadyUploaded)for(const item of artifacts)installAsset(item);
      } else if(context.kind==='upload') {
        const item=artifacts.find(value=>value.file===new URL(request.url).searchParams.get('name'));assert(item);
        assert.equal(request.url,`https://uploads.github.com/repos/actql/actql/releases/71/assets?name=${encodeURIComponent(item.file)}`);
        assert.equal(request.method,'POST');assert.equal(request.headers['content-length'],String(item.bytes));
        assert.deepEqual(await readFile(request.file),originals.get(item.file));assert.equal((await lstat(request.file)).mode&0o777,0o400);
        assert.equal(intent.artifact.file,item.file);assert(!assets.some(asset=>asset.name===item.file));
        id=installAsset(item).id;status=201;
        if(control.changePayload){await chmod(request.file,0o600);await writeFile(request.file,'Changed private original');}
      } else {
        assert.equal(context.kind,'publish');assert.equal(request.method,'PATCH');assert.equal(request.url,`${api}/releases/71`);
        assert.equal(request.body.draft,false);assert.equal(request.body.make_latest,'false');assert.equal(request.body.target_commitish,spec.target_commitish);
        assert.equal(assets.length,artifacts.length);publish();id=71;status=200;
      }
      if(control.throwKind===context.kind){delete control.throwKind;throw Error('Original terminal reply lost');}
      if(control.badTerminal)return {code:0};
      return {code:0,signal:null,status,stdout:JSON.stringify({id}),stderr:''};
    }};
  return {own,directory,selected,artifacts,spec,options,control,commands,requests,setting,assets,bodies,originals,create,publish,installAsset,
    setRef:value=>{ref=value;},getRelease:()=>release,
    observe:()=>observeNativePublicationTarget(directory,selected.sha256,'native',{fetchOwner,fetchCdn})};
}

test('Native publish: read-only exact plan uses full original archive and never supplies a mutation runner',async t=>{
  const f=await fixture(t),plan=await nativePublishPlan(f.directory,f.selected.sha256,'native');
  assert.equal(plan.execution,'unavailable');assert.equal(plan.draft.tag_name,'v0.0.7-rc.1');assert.equal(plan.draft.target_commitish,'a'.repeat(40));
  assert.equal(plan.draft.make_latest,'false');assert.equal(plan.draft.generate_release_notes,false);assert.equal(plan.draft.prerelease,true);
  assert(plan.draft.body.includes(f.selected.sha256));assert(plan.draft.body.includes('knownLimitations:'));assert(plan.draft.body.includes(f.artifacts[0].sha256));
  assert.deepEqual((await runRelease(['native-publish-plan',f.directory,f.selected.sha256,'native'])).draft,plan.draft);
  assert.equal(f.commands.length,0);assert.equal(f.requests.length,0);
  await assert.rejects(runRelease(['publish',f.directory]),/unavailable/u);
});

test('Native publish: absent then Draft exact assets then immutable publication, no Latest or asset replacement',async t=>{
  const f=await fixture(t),result=await publishNativeRelease(f.options);
  assert.equal(result.state,'immutable-release-and-original-assets-confirmed');
  assert.deepEqual(f.commands.map(value=>value.kind),['create','upload','upload','publish']);
  assert.equal(f.getRelease().immutable,true);assert.equal(f.getRelease().draft,false);
  const again=await publishNativeRelease(f.options);assert.equal(again.operationCount,0);assert.equal(f.commands.length,4);
});

test('Native publish: lost create upload or publish terminal reply stays failed, next same-byte attempt never resends confirmed work',async t=>{
  for(const kind of ['create','upload','publish']) {
    const f=await fixture(t);f.control.throwKind=kind;
    await assert.rejects(publishNativeRelease(f.options),/terminal reply lost/u);
    const atFailure=f.commands.length;assert(atFailure>=1);
    await publishNativeRelease(f.options);
    assert.deepEqual(f.commands.map(value=>value.kind),['create','upload','upload','publish']);
  }
});

test('Native publish: unknown owner/settings/inventory never becomes absence or an upload',async t=>{
  for(const kind of ['unavailable','disabled','inventory404']) {
    const f=await fixture(t);
    if(kind==='disabled')f.setting.enabled=false;else f.control[kind]=true;
    assert.equal((await f.observe()).state,'unknown');
    await assert.rejects(publishNativeRelease(f.options),/unknown/u);assert.equal(f.commands.length,0);
  }
});

test('Native publish: exact draft presentation/source, tag, unique inventory and actual asset digest remain required',async t=>{
  for(const kind of ['body','source','tag','foreign','duplicate','corrupt','starter']) {
    const f=await fixture(t);f.create();
    if(kind==='body')f.getRelease().body+='changed';
    else if(kind==='source')f.getRelease().target_commitish='b'.repeat(40);
    else if(kind==='tag')f.setRef({ref:`refs/tags/${f.spec.tag_name}`,object:{type:'commit',sha:'b'.repeat(40)}});
    else {const asset=f.installAsset(f.artifacts[0]);
      if(kind==='foreign')f.assets.push({...asset,id:91,name:'foreign.zip'});
      else if(kind==='duplicate')f.assets.push({...asset});
      else if(kind==='starter')asset.state='starter';
      else f.bodies.set(asset.id,Buffer.alloc(f.artifacts[0].bytes,65));}
    assert(['conflict','unknown'].includes((await f.observe()).state));
    await assert.rejects(publishNativeRelease(f.options));assert.equal(f.commands.length,0);
  }
});

test('Native publish: full paginated owner release inventory and separate credential-free CDN reader are used',async t=>{
  const f=await fixture(t);const release=f.create();for(const item of f.artifacts)f.installAsset(item);
  f.control.pages=[Array.from({length:100},(_,i)=>({id:1000+i,tag_name:`old-${i}`})),[release]];
  f.control.cdn=true;
  const result=await f.observe();assert.equal(result.state,'draft');assert(result.observations.every(value=>value.state==='present'));
  assert(result.requests.some(value=>value.url.endsWith('page=2')));assert(!JSON.stringify(result).includes('signed=secret'));
});

test('Native publish: mutable published or immutable incomplete release is never repaired by append/delete',async t=>{
  for(const kind of ['mutable','incomplete']) {
    const f=await fixture(t);f.create();for(const item of f.artifacts)f.installAsset(item);f.publish();
    if(kind==='mutable')f.getRelease().immutable=false;else f.assets.pop();
    assert.equal((await f.observe()).state,'conflict');await assert.rejects(publishNativeRelease(f.options));assert.equal(f.commands.length,0);
  }
});

test('Native publish: changed mutable inventory during original byte stream is unknown',async t=>{
  const f=await fixture(t);f.create();f.installAsset(f.artifacts[0]);f.control.mutateInventory=true;
  assert.equal((await f.observe()).state,'unknown');assert.equal(f.commands.length,0);
});

test('Native publish: original setting and release identity are checked again after asset streams',async t=>{
  for(const kind of ['disableDuringStream','replaceRelease']) {
    const f=await fixture(t);f.create();f.installAsset(f.artifacts[0]);f.control[kind]=true;
    assert.equal((await f.observe()).state,'unknown');assert.equal(f.commands.length,0);
  }
});

test('Native publish: upload uses the original exact release template, absent foreign or changed template refuses',async t=>{
  for(const kind of ['missing','foreign','other-id']) {
    const f=await fixture(t);f.create();
    if(kind==='missing')delete f.getRelease().upload_url;
    else if(kind==='foreign')f.getRelease().upload_url='https://foreign.invalid/assets{?name,label}';
    else f.getRelease().upload_url='https://uploads.github.com/repos/actql/actql/releases/72/assets{?name,label}';
    assert.equal((await f.observe()).state,'unknown');
    await assert.rejects(publishNativeRelease(f.options));assert.equal(f.commands.length,0);
  }
});

test('Native publish: scope and no implicit authority fields are checked before any mutation',async t=>{
  const f=await fixture(t);for(const field of ['approved','actor','token','force'])
    await assert.rejects(publishNativeRelease({...f.options,[field]:true}),/Unexpected/u);
  await assert.rejects(publishNativeRelease({...f.options,runGitHub:undefined}),/No protected/u);
  const no=await fixture(t,'unaccepted');await assert.rejects(publishNativeRelease(no.options),/not even supplied/u);assert.equal(no.commands.length,0);
  const resume=await fixture(t,'no-recovery');resume.control.throwKind='create';await assert.rejects(publishNativeRelease(resume.options));
  await assert.rejects(publishNativeRelease(resume.options),/did not permit/u);assert.equal(resume.commands.length,1);
});

test('Native publish: fresh current observation reuses a newly completed Draft asset without a second upload',async t=>{
  const f=await fixture(t);f.control.alreadyUploaded=true;
  await publishNativeRelease(f.options);assert.deepEqual(f.commands.map(value=>value.kind),['create','publish']);
});

test('Native publish: changed private upload bytes or malformed terminal output cannot proceed to publication',async t=>{
  for(const kind of ['changePayload','badTerminal']) {
    const f=await fixture(t);f.control[kind]=true;
    await assert.rejects(publishNativeRelease(f.options));assert(!f.commands.some(value=>value.kind==='publish'));
  }
});
