import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mkdir,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {loadInstalledProjectConfiguration,retireInstalledProjectConfiguration}
  from './installed-project-configuration.mjs';
import {selectInstalledProjectProfile} from './installed-project-profile.mjs';
import {loadInstalledProjectMockAnswers} from './installed-project-mock-answers.mjs';

assert.ok(process.env.ACTQL_TEST_ORIGINAL_MOCK_MODEL_RUNTIME,
  'Select the input-matching ordinary Common runtime');
const moon=await import(pathToFileURL(process.env.ACTQL_TEST_ORIGINAL_MOCK_MODEL_RUNTIME));
const source=readFileSync(new URL('./embedded-local.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function collect(node){
  if(node===null||typeof node!=='object')return;
  nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const methods=nodes.filter(node=>node.type==='Property'&&node.method&&
  node.key.name==='installMockModels');
const retires=nodes.filter(node=>node.type==='FunctionDeclaration'&&
  node.id.name==='retirePreparationReferences');
assert.equal(methods.length,1);assert.equal(retires.length,1);
const make=compileFunction(`
  let moon=input.moon,project=input.project,projectProfile=input.profile;
  let mockAnswers,mockModelProfile,mockModelProfileRetire,mockModelFlight;
  let mockPreparation={originalsForRuntime(runtime){
    if(runtime!==moon)throw Error('ForeignFixtureRuntime');return input.mockOriginal;},retire(){}};
  let referenceRetirement,referencesRetired=false;
  const originals={},sourceManaged={},control={},record={},host={};
  const originalInstallation={},duty={releaseReferences(){}};
  const profiles={retainedMockPreparation(){return undefined;}};
  ${source.slice(retires[0].start,retires[0].end)}
  const preparation={${source.slice(methods[0].start,methods[0].end)}};
  return {preparation,record,retire:retirePreparationReferences};`,
  ['input','checked','loadInstalledProjectMockAnswers','retireInstalledProjectConfiguration',
    'assertInitialControlInstallationCurrent','assertSourceManagedInstallationCurrent',
    'clientOperationError','now']);

// Real Common, actual public Project files, and exact Host assembly/lifetime
// statements. Startup/Source current ports are explicit stopping fixtures:
// no operational resource admission, physical Model or public Host is issued.
async function fixture(t,{loseAfterRead=false}={}){
  const scratch=await createOwnedScratch({parent:tmpdir(),prefix:'actql-host-mock-task-',
    label:'Host original Mock Task assembly'});
  for(const [name,wire]of Object.entries(projectTemplateFiles('churn-risk-mock'))){
    const filename=join(scratch.path,name);await mkdir(dirname(filename),{recursive:true});
    await writeFile(filename,wire);
  }
  const project=await loadInstalledProjectConfiguration(moon,{directory:scratch.path});
  const profile=selectInstalledProjectProfile(moon,project,'mock',65536);
  let current=true,reads=0;
  const assertCurrent=()=>{if(!current)throw Object.assign(new Error('OriginalHostChanged'),
    {code:'OriginalHostChanged'});};
  const original=Object.freeze({});
  const f=make({moon,project,profile,mockOriginal:original},checked,
    async(...args)=>{reads++;const answers=await loadInstalledProjectMockAnswers(...args);
      if(loseAfterRead)current=false;return answers;},retireInstalledProjectConfiguration,
    assertCurrent,assertCurrent,code=>Object.assign(new Error(code),{code}),
    ()=>'2026-10-19T00:00:00.000Z');
  t.after(()=>{f.retire();scratch.passed();});
  return {...f,reads:()=>reads};
}

test('actual Host Model assembly retains one original fixture and projects complete Common Task materials',async t=>{
  const f=await fixture(t),first=f.preparation.installMockModels(moon);
  assert.strictEqual(f.preparation.installMockModels(moon),first);
  const models=await first,entries=models.originalsForRuntime(moon);
  assert.equal(entries.length,1);assert.equal(f.reads(),1);
  assert.strictEqual(f.record.mockModels,models);
  assert.strictEqual(checked(moon.clientProgramOriginalMockProvider(entries[0].installation)),entries[0].provider);
  const wire=readFileSync(new URL('../../spec/local-check-environment.json',import.meta.url),'utf8').trimEnd();
  const material=models.modelInstallationForRuntime(moon,wire,JSON.parse(wire).evidence_bundle_cid);
  assert.equal(material.executionContracts.length,1);
  assert.equal(material.executionContracts[0].modelTaskCid,entries[0].taskCid);
  assert.equal(material.executionContracts[0].bodyWire,entries[0].executionWire);
  assert.deepEqual(material.dependencyBodies.map(body=>body.cid),
    [entries[0].promptCid,entries[0].retryCid,entries[0].backoffCid]);
  const body=JSON.parse(material.environmentWire);
  assert.ok(moon.clientProgramCheckEnvironment(material.environmentWire,
    body.evidence_bundle_cid,false,true,true,true,true,false,false));
  assert.equal(JSON.parse(entries[0].taskWire).connector_id,'mock');
  assert.equal(JSON.parse(entries[0].taskWire).task_id,'model-task:churn-risk.v1');
  f.retire();assert.equal(f.record.mockModelProfile,undefined);
  assert.throws(()=>models.originalsForRuntime(moon),{code:'InstalledMockModelsRetired'});
});

test('actual Host retains read originals across current loss and refuses replacement preparation',async t=>{
  const f=await fixture(t,{loseAfterRead:true});
  const first=f.preparation.installMockModels(moon);
  await assert.rejects(first,{code:'OriginalHostChanged'});
  assert.ok(f.record.mockAnswers);assert.ok(f.record.mockModelProfile);
  assert.throws(()=>f.preparation.installMockModels(moon),{code:'OriginalHostChanged'});
  assert.equal(f.reads(),1);
  // Retirement is the same existing DATA owner, not a new-work/current gate.
  f.retire();assert.equal(f.record.mockAnswers,undefined);
  assert.equal(f.record.mockModelProfile,undefined);
});
