// Real temporary Git histories and inert fixed files only. No product build,
// remote history, published release, protected approval or mutation is proven.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspectFixedReleaseSource, maintenanceReviewPlan} from './release-source.mjs';
import {releaseVersion} from './release-version.mjs';
import {runRelease} from './release.mjs';

const hash = body => createHash('sha256').update(body).digest('hex');
const wire = value => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
const policy = {schemaVersion:'actql-release-policy/0.1',allowedLines:['0.0'],
  publicationAuthority:'external-owner-approval-required'};
const branches = {schemaVersion:'actql-release-branches/0.1',
  lines:[{line:'0.0',sourceBranch:'main',maintenanceCut:null}]};

async function fixture(t) {
  const root=await mkdtemp(join(tmpdir(),'actql-fixed-source-'));
  t.after(()=>rm(root,{recursive:true,force:true}));
  const repository=join(root,'repository');await mkdir(repository);
  const git=(...args)=>execFileSync('git',['-c','commit.gpgsign=false',...args],
    {cwd:repository,encoding:'utf8',stdio:'pipe'}).trim();
  git('init','-q','--initial-branch=main');git('config','user.name','Inert Fixture');
  git('config','user.email','fixture@example.invalid');
  const commit=async body=>{await writeFile(join(repository,'program.txt'),body);git('add','.');
    git('commit','-qm','test: independent fixture');return git('rev-parse','HEAD');};
  const previousCommit=await commit('Independent previous source\n');
  const candidateCommit=await commit('Independent candidate source\n');
  const fixed=async (name,version,source,branch='main')=>{
    const directory=join(root,name);await mkdir(join(directory,'node'),{recursive:true});
    const payload=Buffer.from(`INERT fixed ${name} bytes, never an executed package\n`);
    const artifact={targetId:'node',ecosystem:'npm',name:'@actql/node',version,
      file:`actql-node-${version}.tgz`,bytes:payload.length,sha256:hash(payload),
      integrity:`sha512-${createHash('sha512').update(payload).digest('base64')}`,
      path:`node/actql-node-${version}.tgz`};
    await writeFile(join(directory,artifact.path),payload);
    const child=wire({version:'actql-package-release/0.1',sourceSha:source,
      cohort:{packageVersion:version,registry:'https://registry.npmjs.org/',tag:'candidate-synthetic'},
      packages:[artifact]});
    await writeFile(join(directory,'node/release.json'),child);
    const body={schemaVersion:'actql-release-set/0.1',release:releaseVersion(version),
      request:{schemaVersion:'actql-release-request/0.1',releaseId:'inert-fixed-source',version,
        source:{repository:'https://github.com/actql/actql',commit:source,branch},
        targets:[{id:'node',ecosystem:'npm',packages:['@actql/node'],platforms:['darwin-arm64'],profiles:['local'],
          destination:'https://registry.npmjs.org/',channels:['candidate-synthetic']}],
        notes:{summary:'Not an actual product release',breakingChanges:[],migration:[],knownLimitations:['Inert bytes only']}},
      policy:{...policy,allowedLines:[releaseVersion(version).line]},
      cohorts:[{targetId:'node',kind:'node-npm',path:'node/release.json',bytes:child.length,sha256:hash(child),
        verification:'Independent inert cold-byte fixture; not producer or publication evidence'}],
      artifacts:[artifact],acceptance:'unaccepted',qualification:'Inert source-history binding only'};
    const raw=wire(body),digest=hash(raw);
    await writeFile(join(directory,'release-set.json'),raw);
    await writeFile(join(directory,'release-set.sha256'),`${digest}  release-set.json\n`);
    return {directory,digest,raw,body,payload,artifact};
  };
  const prior=await fixed('previous','0.0.6',previousCommit);
  const candidate=await fixed('candidate','0.0.7-rc.1',candidateCommit);
  const history={kind:'previous',directory:prior.directory,manifestSha256:prior.digest};
  const options={directory:candidate.directory,expectedSha256:candidate.digest,repository,policy,branches,history};
  return {root,repository,git,commit,fixed,previousCommit,candidateCommit,prior,candidate,history,options,
    inspect:extra=>inspectFixedReleaseSource({...options,...extra})};
}

test('fixed source: original upper and prior bytes bind real ancestry while an advanced branch cannot replace fixed SHA',async t=>{
  const f=await fixture(t),advanced=await f.commit('A later development commit is not this candidate\n');
  const result=await f.inspect();
  assert.equal(result.manifestSha256,f.candidate.digest);
  assert.deepEqual(result.history,{kind:'previous',manifestSha256:f.prior.digest});
  assert.equal(result.source.source.commit,f.candidateCommit);assert.equal(result.source.branchTip,advanced);
  assert.deepEqual(result.source.previousRelease,{version:'0.0.6',source:f.prior.body.request.source});
  assert.equal(result.execution,'unavailable');assert.match(result.qualification,/no publication history discovery/u);
  assert(result.pending.some(value=>value.includes('actual previous published release')));
  assert.equal(f.git('rev-parse','HEAD'),advanced);
  for(const fixed of [f.candidate,f.prior]){
    assert.deepEqual(await readFile(join(fixed.directory,'release-set.json')),fixed.raw);
    assert.deepEqual(await readFile(join(fixed.directory,fixed.artifact.path)),fixed.payload);
  }
});

test('fixed source: initial is an explicit unauthenticated scope claim, never missing history or approved JSON',async t=>{
  const f=await fixture(t);
  for(const history of [undefined,null,{}, {kind:'unknown'}, {kind:'initial',approved:true},
    {kind:'previous'}, {...f.history,directory:'relative'}, {...f.history,manifestSha256:'not-a-digest'}])
    await assert.rejects(f.inspect({history}));
  const result=await f.inspect({history:{kind:'initial'}});
  assert.deepEqual(result.history,{kind:'initial'});assert.equal(result.source.previousRelease,null);
  assert(result.pending.some(value=>value.includes('authenticate the selected initial scope')));
  assert.equal(result.execution,'unavailable');
});

test('fixed source: same-line complete version order refuses rollback/equal and an unrelated line',async t=>{
  const f=await fixture(t);
  for(const [index,version]of ['0.0.7-rc.1','0.0.7','0.0.8','0.1.0'].entries()){
    const prior=await f.fixed(`prior-version-${index}`,version,f.previousCommit);
    await assert.rejects(f.inspect({history:{kind:'previous',directory:prior.directory,manifestSha256:prior.digest}}),
      version==='0.1.0'?/same selected line/u:/must follow the complete previous version/u);
  }
});

test('fixed source: exact known prior commit must exist and be an ancestor, not a branch label or claimed hash',async t=>{
  const f=await fixture(t);
  f.git('checkout','-q','--orphan','unrelated');f.git('rm','-rf','.');
  const unrelated=await f.commit('Separate original root, not the release history\n');f.git('checkout','-q','main');
  const prior=await f.fixed('unrelated','0.0.6',unrelated);
  await assert.rejects(f.inspect({history:{kind:'previous',directory:prior.directory,manifestSha256:prior.digest}}),/does not descend/u);
  const missing=await f.fixed('missing','0.0.6','a'.repeat(40));
  await assert.rejects(f.inspect({history:{kind:'previous',directory:missing.directory,manifestSha256:missing.digest}}));
  assert.equal(f.git('rev-parse','HEAD'),f.candidateCommit);
});

test('fixed source: candidate policy and artifact text cannot replace trusted policy or actual branch membership',async t=>{
  const f=await fixture(t);
  await assert.rejects(f.inspect({policy:{...policy,allowedLines:['0.1']},branches:{...branches,
    lines:[{line:'0.1',sourceBranch:'main',maintenanceCut:null}]}}),/not allowed/u);
  f.git('checkout','-qb','feature/unmerged');const detached=await f.commit('Unmerged candidate\n');f.git('checkout','-q','main');
  const foreign=await f.fixed('unmerged','0.0.7',detached);
  await assert.rejects(f.inspect({directory:foreign.directory,expectedSha256:foreign.digest}),/not on its named source branch/u);
  const mislabeled=await f.fixed('wrong-branch','0.0.7',f.candidateCommit,'feature/unmerged');
  await assert.rejects(f.inspect({directory:mislabeled.directory,expectedSha256:mislabeled.digest}),/selected development or maintenance source branch/u);
});

test('fixed source: changed/missing original candidate or prior files refuse without a rebuild or branch write',async t=>{
  const f=await fixture(t),head=f.git('rev-parse','HEAD');
  await assert.rejects(f.inspect({expectedSha256:'b'.repeat(64)}),/externally retained digest/u);
  await assert.rejects(f.inspect({history:{...f.history,manifestSha256:'c'.repeat(64)}}),/externally retained digest/u);
  await writeFile(join(f.prior.directory,f.prior.artifact.path),Buffer.from('Changed prior bytes'));
  await assert.rejects(f.inspect());
  await writeFile(join(f.prior.directory,f.prior.artifact.path),f.prior.payload);
  await rm(join(f.candidate.directory,f.candidate.artifact.path));
  await assert.rejects(f.inspect(),{code:'ENOENT'});
  assert.equal(f.git('rev-parse','HEAD'),head);
  await assert.rejects(readFile(join(f.candidate.directory,f.candidate.artifact.path)),{code:'ENOENT'});
});

test('fixed source: maintenance keeps the original fixed cut and reports broad development history separately',async t=>{
  const f=await fixture(t),cut=f.candidateCommit;
  f.git('branch','release/0.0');const main=await f.commit('Unrelated development feature\n');
  f.git('checkout','-q','release/0.0');await writeFile(join(f.repository,'maintenance.txt'),'Separate line fix\n');
  f.git('add','.');f.git('commit','-qm','fix: inert line patch');
  const fixed=await f.fixed('maintenance','0.0.7',f.git('rev-parse','HEAD'),'release/0.0');
  const selected={...branches,lines:[{line:'0.0',sourceBranch:'release/0.0',maintenanceCut:cut}]};
  const result=await f.inspect({directory:fixed.directory,expectedSha256:fixed.digest,branches:selected});
  assert.equal(result.source.findings.length,0);assert.equal(result.source.maintenanceCut,cut);
  f.git('merge','--no-ff','main','-m','merge: broad history');
  const broad=await f.fixed('broad','0.0.7',f.git('rev-parse','HEAD'),'release/0.0');
  const rejected=await f.inspect({directory:broad.directory,expectedSha256:broad.digest,branches:selected});
  assert.equal(rejected.source.findings[0].kind,'development-history-crossed-cut');
  assert(rejected.source.findings[0].commits.includes(main));assert.equal(rejected.execution,'unavailable');
  assert.throws(()=>maintenanceReviewPlan(rejected.source,{}),/must not be merged/u);
});

test('fixed source: actual CLI selects bound initial/prior input without checkout, tags, publication or output files',async t=>{
  const f=await fixture(t),file=join(f.root,'history.json');await writeFile(file,wire(f.history));
  const args=['fixed-source-plan',f.candidate.directory,f.candidate.digest,f.repository,file];
  const result=await runRelease(args);
  assert.equal(result.source.source.commit,f.candidateCommit);assert.equal(result.history.manifestSha256,f.prior.digest);
  await writeFile(file,wire({kind:'initial'}));assert.equal((await runRelease(args)).history.kind,'initial');
  await assert.rejects(runRelease([...args,'unused','extra']),/usage/u);
  await assert.rejects(runRelease(['publish',f.candidate.directory]),/publication authority/u);
  assert.equal(f.git('rev-parse','HEAD'),f.candidateCommit);assert.equal(f.git('tag','-l'),'');
  assert.deepEqual(await readFile(join(f.candidate.directory,'release-set.json')),f.candidate.raw);
});

test('fixed source: original history selection survives caller mutation across byte-reader awaits',async t=>{
  const f=await fixture(t),history=structuredClone(f.history);
  const pending=f.inspect({history});
  history.kind='initial';delete history.directory;delete history.manifestSha256;
  const result=await pending;
  assert.deepEqual(result.history,{kind:'previous',manifestSha256:f.prior.digest});
  assert.equal(result.source.previousRelease.source.commit,f.previousCommit);
});

test('fixed source: original policy and branch configuration survive caller mutation across byte-reader awaits',async t=>{
  const f=await fixture(t),selectedPolicy=structuredClone(policy),selectedBranches=structuredClone(branches);
  const pending=f.inspect({policy:selectedPolicy,branches:selectedBranches});
  selectedPolicy.allowedLines=['0.1'];selectedBranches.lines=[];
  const result=await pending;
  assert.equal(result.source.line,'0.0');assert.equal(result.source.sourceBranch,'main');
  assert.equal(result.source.source.commit,f.candidateCommit);
});
