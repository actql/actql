import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mkdir, writeFile, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {parse} from 'acorn';
import {pathToFileURL} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {loadInstalledProjectConfiguration, retireInstalledProjectConfiguration}
  from './installed-project-configuration.mjs';
import {selectInstalledProjectProfile} from './installed-project-profile.mjs';
import {loadInstalledProjectMockAnswers} from '../local-node/installed-project-mock-answers.mjs';

assert.ok(process.env.ACTQL_TEST_ORIGINAL_MOCK_MODEL_RUNTIME,
  'Select the input-matching ordinary Common runtime with the original Mock Model owner');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_ORIGINAL_MOCK_MODEL_RUNTIME));
const limits = Object.freeze({maxTasks:128,maxBytes:65536,maxNodes:4096,maxDepth:64,
  maxMembers:256,contractNodes:4096,contractDepth:64,contractTextBytes:65536,
  maxWork:2097152,valueNodes:4096,valueDepth:64,valueTextBytes:65536,maxEntries:128});
const core = [limits.maxBytes,limits.maxNodes,limits.maxDepth,limits.maxMembers,
  limits.contractNodes,limits.contractDepth,limits.contractTextBytes,limits.maxWork];
const controllerSource=readFileSync(new URL('./installed-model-continuation.mjs',import.meta.url),'utf8');
const controllerTree=parse(controllerSource,{ecmaVersion:'latest',sourceType:'module'});
const dispatchPreparation=controllerTree.body.find(node=>node.type==='FunctionDeclaration'&&
  node.id.name==='requireModelDispatchPreparation');
assert(dispatchPreparation);
const requireDispatchPreparation=new Function('checked','fail',
  'return ('+controllerSource.slice(dispatchPreparation.start,dispatchPreparation.end)+');')(
    checked,code=>{throw Object.assign(new Error(code),{code});});

// Real Common and the unchanged public Project/Task/answer files. This is
// installation/original correspondence, not a Host startup, Model invocation,
// Account grant, physical resource supplier or installed README success.
async function fixture(t,{deferAnswers=false}={}) {
  const scratch = await createOwnedScratch({parent:tmpdir(),prefix:'actql-mock-model-original-',
    label:'public Mock Task original binding'});
  const files = projectTemplateFiles('churn-risk-mock');
  for (const [name,wire] of Object.entries(files)) {
    const path = join(scratch.path,name);
    await mkdir(dirname(path),{recursive:true});
    await writeFile(path,wire);
  }
  const project = await loadInstalledProjectConfiguration(moon,{directory:scratch.path});
  const selected = selectInstalledProjectProfile(moon,project,'mock',65536);
  let current = true,retired = false;
  const assertCurrent = () => {
    if (!current) throw Object.assign(new Error('OriginalMockHostCurrentRefused'),
      {code:'OriginalMockHostCurrentRefused'});
  };
  const answers = await loadInstalledProjectMockAnswers(moon,project,selected,{limits,assertCurrent,deferAnswers});
  const profile = checked(moon.clientProgramInstallMockProfile(...core));
  const now = () => '2026-10-19T00:00:00.000Z';
  t.after(() => {
    answers.retire(moon);
    if (!retired) moon.clientProgramRetireMockProfile(profile);
    selected.retire(moon);
    retireInstalledProjectConfiguration(project,moon);
    scratch.passed();
  });
  return {files,answers,profile,now,assertCurrent,
    bind:() => answers.bindModelsForRuntime(moon,profile,now),
    loseCurrent:() => {current=false;},
    retireProfile:() => {assert.equal(moon.clientProgramRetireMockProfile(profile),true);retired=true;}};
}

test('actual public Mock Task binds the same checked answers and ignores configured live Provider selection',async t => {
  const f=await fixture(t),originals=f.answers.originalsForRuntime(moon),bound=f.bind();
  const entries=bound.originalsForRuntime(moon);
  assert.equal(entries.length,1);
  assert.strictEqual(entries[0].task,originals[0].task);
  assert.strictEqual(entries[0].answers,originals[0].answers);
  assert.equal(JSON.parse(entries[0].taskWire).task_id,'model-task:churn-risk.v1');
  assert.equal(JSON.parse(entries[0].taskWire).connector_id,'mock');
  assert.equal(JSON.parse(f.files['model-tasks.json']).default_provider,'openai');
  assert.strictEqual(checked(moon.clientProgramOriginalMockProvider(entries[0].installation)),
    entries[0].provider);
  assert.strictEqual(bound.forTaskCid(moon,entries[0].taskCid),entries[0]);
  assert.strictEqual(f.bind(),bound);
});

test('actual Mock provider binding uses its same profile originals and refuses lost currentness',async t => {
  const f=await fixture(t),bound=f.bind();
  const originals=bound.providerBindingOriginalsForRuntime(moon);
  const value=checked(moon.clientProgramModelProviderBinding('mock',
    originals.installationRevision.wire,originals.configurationContract.wire,
    originals.configuration.wire));
  const body=JSON.parse(moon.strategyRunEvidenceJson(value));
  assert.equal(body.provider_id,'mock');
  assert.equal(body.installation_revision_cid,originals.installationRevision.cid);
  assert.equal(body.configuration_contract_cid,originals.configurationContract.cid);
  assert.equal(body.configuration_cid,originals.configuration.cid);
  assert.equal(JSON.parse(originals.configurationContract.wire).network,false);
  assert.throws(() => bound.providerBindingOriginalsForRuntime.call({},moon),
    {code:'ForeignInstalledMockModelOriginal'});
  f.loseCurrent();
  assert.throws(() => bound.providerBindingOriginalsForRuntime(moon),
    {code:'OriginalMockHostCurrentRefused'});
});

test('actual Mock Model refuses equal-wire foreign Task instead of replacing the original answers',async t => {
  const f=await fixture(t),bound=f.bind(),entry=bound.originalsForRuntime(moon)[0];
  const foreign=checked(moon.clientProgramReadPublicModelTask(
    f.files['model-tasks/churn-risk.v1.yaml'],'yaml',...core));
  assert.notStrictEqual(foreign,entry.task);
  assert.throws(() => checked(moon.clientProgramInstallOriginalMock(f.profile,
    foreign,entry.normalized,entry.answers,f.now)),{code:'MoonBitHostFailure'});
  const foreignNormalized=checked(moon.clientProgramNormalizeMockTask(foreign,f.profile,...core));
  assert.throws(() => checked(moon.clientProgramInstallOriginalMock(f.profile,
    foreign,foreignNormalized,entry.answers,f.now)),{code:'MoonBitHostFailure'});
  assert.strictEqual(bound.originalsForRuntime(moon)[0],entry);
});

test('actual Mock Model binding refuses another nominal fixture profile with identical static content',async t => {
  const f=await fixture(t),bound=f.bind();
  const foreign=checked(moon.clientProgramInstallMockProfile(...core));
  try {
    assert.notStrictEqual(foreign,f.profile);
    assert.throws(() => f.answers.bindModelsForRuntime(moon,foreign,f.now),
      {code:'ForeignInstalledMockModelOriginal'});
    assert.strictEqual(f.bind(),bound);
  } finally {moon.clientProgramRetireMockProfile(foreign);}
});

test('actual Mock Model current refusal and retired profile do not acknowledge or replace originals',async t => {
  const f=await fixture(t),bound=f.bind();
  f.loseCurrent();
  assert.throws(() => bound.originalsForRuntime(moon),{code:'OriginalMockHostCurrentRefused'});
  // Cleanup remains the same answer/Model owner even after new-work currentness
  // is lost. Retirement is not a public Run or physical capacity receipt.
  f.answers.retire(moon);
  assert.throws(() => bound.originalsForRuntime(moon),{code:'InstalledMockModelsRetired'});
  f.retireProfile();
});

test('same live Core Mock installation admits no-I/O preparation without fabricating egress',async t => {
  const f=await fixture(t),entry=f.bind().originalsForRuntime(moon)[0];
  requireDispatchPreparation(moon,{localMock:true,originalMockInstallation:entry.installation,
    provider:entry.provider});
  assert.throws(()=>requireDispatchPreparation(moon,{localMock:true,provider:entry.provider}),
    {code:'InstalledMockModelOriginalUnavailable'});
  assert.throws(()=>requireDispatchPreparation(moon,{localMock:true,
    originalMockInstallation:entry.installation,provider:{}}),
    {code:'InstalledMockModelOriginalUnavailable'});
});

test('copied or retired Mock originals cannot replace dispatch preparation',async t => {
  const f=await fixture(t),entry=f.bind().originalsForRuntime(moon)[0];
  assert.throws(()=>requireDispatchPreparation(moon,{localMock:true,
    originalMockInstallation:{...entry.installation},provider:entry.provider}),
    {code:'MoonBitHostFailure'});
  f.answers.retire(moon);
  assert.throws(()=>requireDispatchPreparation(moon,{localMock:true,
    originalMockInstallation:entry.installation,provider:entry.provider}),
    {code:'MoonBitHostFailure'});
});

test('external Provider preparation keeps the original egress refusal',()=>{
  const original=new Error('OriginalEgressRefusal');
  assert.throws(()=>requireDispatchPreparation(moon,{egressFailure:original}),error=>error===original);
  assert.throws(()=>requireDispatchPreparation(moon,{}),{message:'InstalledModelEgressUnavailable'});
  requireDispatchPreparation(moon,{egressAdmission:{}});
});

// New changed-boundary cases require the actual input-matching Common module;
// no identity double below can supply its declaration or typed answer owner.
test('actual Mock declaration projects original metadata before live answer materialization',async t=>{
  const f=await fixture(t,{deferAnswers:true}),input=f.answers.originalsForRuntime(moon)[0];
  assert.equal(input.answers,undefined);assert.equal(input.answerWire,undefined);
  const bound=f.bind(),entry=bound.originalsForRuntime(moon)[0];
  assert.strictEqual(checked(moon.clientProgramOriginalMockDeclaration(entry.installation)),entry.normalized);
  assert.ok(bound.providerBindingOriginalsForRuntime(moon).configuration);
  await bound.prepareAnswersForRuntime(moon,entry.installation);
  const retained=f.answers.originalsForRuntime(moon)[0];
  assert.ok(retained.answers);assert.equal(typeof retained.answerWire,'string');
  assert.strictEqual(checked(moon.clientProgramOriginalMockProvider(entry.installation)),entry.provider);
  assert.ok(checked(moon.clientProgramMockAnswerCount(retained.answers,retained.task))>=1);
});

test('actual Mock metadata survives absent answer file but new live preparation still refuses it',async t=>{
  const f=await fixture(t,{deferAnswers:true}),input=f.answers.originalsForRuntime(moon)[0];
  await unlink(input.answerPath);
  const bound=f.bind(),entry=bound.originalsForRuntime(moon)[0];
  assert.strictEqual(checked(moon.clientProgramOriginalMockDeclaration(entry.installation)),entry.normalized);
  assert.ok(bound.providerBindingOriginalsForRuntime(moon).installationRevision);
  await assert.rejects(bound.prepareAnswersForRuntime(moon,entry.installation),{code:'ENOENT'});
  assert.equal(input.answers,undefined);
});
