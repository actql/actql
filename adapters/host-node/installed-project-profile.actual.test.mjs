import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {checked} from '../host-common/runtime-result.mjs';
import {admitInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {selectInstalledProjectProfile} from './installed-project-profile.mjs';

assert.ok(process.env.ACTQL_TEST_PROJECT_PROFILE_RUNTIME,'Matching original profile Common runtime required');
const moon=await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_PROFILE_RUNTIME));
const wire='{"version":"actql-config/0.1","profile":"mock","mock":{"catalog":"./catalog-é.json","data":"./data-é.json","answers":{"task:é":"./answer.yaml"}}}';
const project=()=>admitInstalledProjectConfiguration(moon,wire);

test('actual profile retains original project and exact mock locators',()=>{
  const p=project(),view=selectInstalledProjectProfile(moon,p,undefined,65536);
  const original=view.originalsForRuntime(moon);
  assert.strictEqual(original.configuration,p.originalsForRuntime(moon).configuration);
  assert.equal(original.requested,undefined);assert.equal(original.selected,'mock');
  assert.deepEqual(view.mockLocatorsForRuntime(moon),{catalogFile:'./catalog-é.json',dataFile:'./data-é.json',answerCount:1});
  assert.equal(moon.clientProjectConfigurationMockCatalogFile(original.configuration),'./catalog-é.json');
  assert.deepEqual(view.mockAnswerForRuntime(moon,0),{task:'task:é',file:'./answer.yaml'});
  assert.equal(view.mockAnswerForRuntime(moon,1),undefined);
  assert.ok(Object.isFrozen(original));view.retire(moon);
});

test('actual profile override never adopts another profile mock data or repairs exact text',()=>{
  const view=selectInstalledProjectProfile(moon,project(),'profile:é',65536);
  assert.equal(view.originalsForRuntime(moon).selected,'profile:é');
  assert.deepEqual(view.mockLocatorsForRuntime(moon),{catalogFile:undefined,dataFile:undefined,answerCount:0});
  assert.equal(view.mockAnswerForRuntime(moon,0),undefined);view.retire(moon);
});

test('actual profile rejects copied project view receiver and another runtime',()=>{
  const p=project();
  assert.throws(()=>selectInstalledProjectProfile(moon,{...p},undefined,65536),{code:'ForeignInstalledProjectOriginal'});
  assert.throws(()=>selectInstalledProjectProfile({...moon},p,undefined,65536),{code:'ForeignInstalledProjectRuntime'});
  const view=selectInstalledProjectProfile(moon,p,undefined,65536);
  assert.throws(()=>view.originalsForRuntime({...moon}),{code:'ForeignInstalledProjectProfile'});
  assert.throws(()=>({...view}).originalsForRuntime(moon),{code:'ForeignInstalledProjectProfile'});
  assert.throws(()=>({...view}).mockLocatorsForRuntime(moon),{code:'ForeignInstalledProjectProfile'});
  assert.throws(()=>view.mockLocatorsForRuntime({...moon}),{code:'ForeignInstalledProjectProfile'});
  assert.throws(()=>({...view}).retire(moon),{code:'ForeignInstalledProjectProfile'});
  assert.equal(view.originalsForRuntime(moon).selected,'mock');view.retire(moon);
});

test('actual absent project profile issues no mock record or answer original',()=>{
  const original=selectInstalledProjectProfile(moon,undefined,undefined,0);
  assert.equal(original.originalsForRuntime(moon).selected,undefined);
  assert.deepEqual(original.mockLocatorsForRuntime(moon),{catalogFile:undefined,dataFile:undefined,answerCount:0});
  original.retire(moon);
  const explicit=selectInstalledProjectProfile(moon,undefined,'mock',4);
  assert.equal(explicit.originalsForRuntime(moon).selected,'mock');
  assert.deepEqual(explicit.mockLocatorsForRuntime(moon),{catalogFile:undefined,dataFile:undefined,answerCount:0});
  explicit.retire(moon);
});

test('actual profile rejects invalid choices and retains nominal retirement without physical ACK',()=>{
  for(const choice of [null,false,'','\ud800']){
    assert.throws(()=>selectInstalledProjectProfile(moon,project(),choice,100),{code:'InvalidInstalledProjectProfile'});
  }
  assert.throws(()=>selectInstalledProjectProfile(moon,project(),'m\0k',100),{code:'MoonBitHostFailure'});
  assert.throws(()=>selectInstalledProjectProfile(moon,project(),'mock',3),{code:'MoonBitHostFailure'});
  const view=selectInstalledProjectProfile(moon,project(),undefined,0);
  const {selection}=view.originalsForRuntime(moon);
  view.retire(moon);view.retire(moon);
  assert.throws(()=>view.originalsForRuntime(moon),{code:'InstalledProjectProfileRetired'});
  assert.throws(()=>view.mockLocatorsForRuntime(moon),{code:'InstalledProjectProfileRetired'});
  assert.throws(()=>({...view}).retire(moon),{code:'ForeignInstalledProjectProfile'});
  assert.throws(()=>view.retire({...moon}),{code:'ForeignInstalledProjectProfile'});
  // The actual Common Owner also refuses the same retired opaque reference.
  const result=moon.clientProjectProfileSelectedName(selection);
  assert.throws(()=>checked(result),{code:'MoonBitHostFailure'});
});


test('actual profile keeps legacy data-only configuration without a catalog default',()=>{
  const legacy=admitInstalledProjectConfiguration(moon,
    '{"version":"actql-config/0.1","profile":"mock","mock":{"data":"./legacy.json"}}');
  const view=selectInstalledProjectProfile(moon,legacy,undefined,0);
  assert.deepEqual(view.mockLocatorsForRuntime(moon),
    {catalogFile:undefined,dataFile:'./legacy.json',answerCount:0});
  view.retire(moon);
});
