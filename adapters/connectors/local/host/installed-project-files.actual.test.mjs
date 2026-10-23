import assert from 'node:assert/strict';
import {mkdir,writeFile,open} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {loadInstalledProjectConfiguration} from '../../../host-node/installed-project-configuration.mjs';
import {prepareInstalledProjectLocalFiles} from './installed-project-files.mjs';

assert(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME,'Select the actual qualified Common runtime');
const moon=await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const limits=Object.freeze({maxEntries:16,maxDepth:4,maxPathBytes:256,maxFiles:8,
  maxFileBytes:131072,maxReadBytes:524288,maxPages:8,maxPageBytes:65536,maxPageRows:8,
  maxAttempts:8,maxDurationMs:10000,maxListingBytes:524288});
let scratch,sequence=0;
test.before(async()=>{scratch=await createOwnedScratch({parent:join(root,'_build'),
  prefix:'local-project-files-',label:'Local Project original files preparation'});});
test.after(()=>scratch?.passed());
async function fixture(wire){
  const directory=join(scratch.path,String(++sequence));await mkdir(join(directory,'configuration'),{recursive:true});
  await writeFile(join(directory,'actql.config.json'),'{"version":"actql-config/0.1","connectors":"configuration/connectors.json"}');
  await writeFile(join(directory,'configuration/connectors.json'),wire);
  return{directory,project:await loadInstalledProjectConfiguration(moon,{directory})};
}
const document=entry=>' {"version":"actql-connectors/0.1","connections":{"local":'+entry+'}}\n';

test('actual Common Local preparation preserves original Project bytes and typed files/contents without filesystem discovery',async()=>{
  const entry='{ "connector" : "local", "root" : "../data-é", "version" : "content", "tables" : {} }';
  const f=await fixture(document(entry));let opens=0;
  const preparation=await prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){},
    openFile:async(path,...args)=>{assert.equal(path,join(f.directory,'configuration/connectors.json'));opens++;return open(path,...args);}});
  assert.equal(opens,1,'no business directory, child file, credential or Root was acquired');
  const original=preparation.originalsForRuntime(moon);assert.equal(original.sources.length,1);
  assert.strictEqual(original.project,f.project.originalsForRuntime(moon));
  assert.equal(original.connections.wire,document(entry));
  const source=original.sources[0];assert.equal(source.originalEntryWire,entry);
  assert.equal(source.rootPath,join(f.directory,'data-é'));assert.equal(source.versionMode,'content');
  assert(Object.isFrozen(original)&&Object.isFrozen(original.sources)&&Object.isFrozen(source.limits));
  const declared=JSON.parse(source.wire);assert.deepEqual(declared.views.map(x=>x.resource).sort(),['contents','files']);
  const contracts=declared.contracts.map(text=>JSON.parse(text));
  const files=contracts.find(x=>x.kind==='carrier_schema'&&x.body.fields.size);
  assert.deepEqual(files.body.fields.size,{type:'int64',nullable:false});
  assert.deepEqual(files.body.fields.modified_time,{type:'timestamp',nullable:false});
  const contents=contracts.find(x=>x.kind==='carrier_schema'&&x.body.fields.content);
  assert.deepEqual(contents.body.fields.content,{type:'content_ref',nullable:false});
  assert.deepEqual(source.queryAliases,[{name:'local',resource:'files'},
    {name:'local.files',resource:'files'},{name:'local.contents',resource:'contents'}]);
  preparation.retire(moon);
  assert.throws(()=>preparation.originalsForRuntime(moon),{code:'LocalFilesPreparationRetired'});
});

test('absent and unrelated connections create no Local declaration or default limits',async()=>{
  assert.equal(await prepareInstalledProjectLocalFiles({},undefined),undefined);
  for(const wire of ['{"version":"actql-connectors/0.1","connections":{}}',
    '{"version":"actql-connectors/0.1","connections":{"n":{"connector":"notion","credentials":{"env":"DO_NOT_READ"}}}}']){
    const f=await fixture(wire);
    assert.equal(await prepareInstalledProjectLocalFiles(moon,f.project,{assertCurrent(){}}),undefined);
  }
});

test('Local preparation refuses malformed roots and unsupported version selection without guessed semantics',async()=>{
  for(const value of [null,false,'','a\0b']){
    const f=await fixture(document(JSON.stringify({connector:'local',root:value,tables:{}})));
    await assert.rejects(prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){}}),
      {code:'InvalidLocalFilesConnection'});
  }
  const f=await fixture(document('{"connector":"local","root":"../data","version":"guess"}'));
  await assert.rejects(prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){}}),
    {code:'LocalFilesVersionUnavailable'});
});

test('Local preparation keeps nominal runtime/receiver and currentness fences with explicit limits',async()=>{
  const f=await fixture(document('{"connector":"local","root":"../data","tables":{}}'));
  let current=true;
  const preparation=await prepareInstalledProjectLocalFiles(moon,f.project,{limits,assertCurrent(){
    if(!current)throw Object.assign(new Error('current changed'),{code:'TestCurrentChanged'});
  }});
  assert.equal(preparation.originalsForRuntime(moon).sources[0].versionMode,'metadata');
  assert.throws(()=>({...preparation}).originalsForRuntime(moon),{code:'ForeignLocalFilesPreparation'});
  assert.throws(()=>preparation.originalsForRuntime({...moon}),{code:'ForeignLocalFilesPreparation'});
  await assert.rejects(prepareInstalledProjectLocalFiles(moon,{...f.project},{limits,assertCurrent(){}}),
    {code:'ForeignInstalledProjectOriginal'});
  await assert.rejects(prepareInstalledProjectLocalFiles({...moon},f.project,{limits,assertCurrent(){}}),
    {code:'ForeignInstalledProjectRuntime'});
  await assert.rejects(prepareInstalledProjectLocalFiles(moon,f.project,{assertCurrent(){}}),
    {code:'LocalFilesLimitsUnavailable'});
  current=false;assert.throws(()=>preparation.originalsForRuntime(moon),{code:'TestCurrentChanged'});
  preparation.retire(moon);
});
