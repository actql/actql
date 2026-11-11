// Actual loader declarations and shared method capture with explicit ports.
// This fixture issues no Common parent, Account decision or physical read.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';

const source=await readFile(new URL('../host/installed-calendar-source.mjs',import.meta.url),'utf8');
const servicesSource=await readFile(new URL('../../../host-node/installed-host-services.mjs',import.meta.url),'utf8');
const declarations=code=>parse(code,{ecmaVersion:'latest',sourceType:'module'}).body.map(node=>node.declaration??node);
const capture=declarations(servicesSource).find(node=>node.id?.name==='captureInstalledSourceServices');
assert(capture);
const captureInstalledSourceServices=Function('nodeTypes',servicesSource.slice(capture.start,capture.end)+
  '\nreturn captureInstalledSourceServices;')(nodeTypes);
const body=declarations(source).filter(node=>['VariableDeclaration','FunctionDeclaration'].includes(node.type))
  .map(node=>source.slice(node.start,node.end)).join('\n');
const ok=value=>({$tag:1,_0:value});
const columns=['id','summary','time_zone','access_role'];
const limits={maxResponseBytes:8192,maxNodes:512,maxDepth:16,maxPages:4,maxRows:3,maxRequests:5,perPage:2,
  maxCursorUnits:128,maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,
  maxRowsWireNodes:200,maxRowsWireDepth:8,maxDeclarationBytes:4096,maxDeclarationNodes:1000,
  maxSecretBytes:128,maxCaBytes:16384};

function fixture({implementationFailure,sourceFailure,foreignCapacity=false}={}){
  const events=[],cleanup=[],installation={},capacity={},acquisition={},declaration={},result={};
  const environment=Object.freeze({wire:'original-environment'});
  const declared=Object.freeze({views:[{resource:'calendars',fields:columns}]});
  const profile={version:'actql-installed-calendar-source/0.1',connectorId:'calendar',
    siteProfilePath:'/UNOPENED/calendar-site.json',accountConfigurationWire:'{}',limits:{...limits}};
  const siteProfile={version:'actql-installed-calendar-site/0.1',apiOrigin:'https://calendar.invalid',
    credentialAuthorityId:'original-authority',credentialKeyId:'original-key',
    credentialPrivateKeyPath:'/UNOPENED/key',environment:'fixture',journalRoot:'/UNOPENED/journal',
    namespaceId:'fixture',siteGeneration:1,siteKey:'calendar'};
  const sourceInitialization={prepareDeclaration(views){
    assert.equal(this,sourceInitialization);
    assert.deepEqual(views,[{resource:'calendars',resource_kind:'calendar_list',schema_wire:'original-schema',
      schema_cid:`sha256:${createHash('sha256').update('original-schema').digest('hex')}`,facts_wire:'original-facts'}]);
    events.push('declaration');return{declaration,declared,environment};
  }};
  const provider={
    calendarListColumnNames(){assert.equal(this,provider);return columns.slice();},
    calendarListSchemaWire(){assert.equal(this,provider);events.push('schema');return ok('original-schema');},
    calendarListRelationFactsWire(){assert.equal(this,provider);return'original-facts';},
    calendarProjectCalendarList(){assert.fail('No response in construction scope');},
    calendarListRowsWire(){assert.fail('No response');},
    calendarListMetadataJson(){assert.fail('No response');},
  };
  const implementation=Object.freeze({capacity,runAcquisitionLimits:acquisition});
  const authorization={context:{contextCid:'original-context'}},site={},reader=Object.freeze({capacity:foreignCapacity?{}:capacity});
  let implementationInput,readerInput,sourceInput;
  const services={
    sourceReaderImplementationProfile(input){
      assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);events.push('profile');
      return{maxDeclarationBytes:4096,maxDeclarationNodes:1000,pageSize:250,maxTotalRows:1000,
        maxTotalResponseBytes:65536,maxCursorBytes:1024,maxTargetBytes:4096};
    },
    sourceReaderImplementation(input){
      assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);implementationInput=input;events.push('implementation');
      if(implementationFailure)throw implementationFailure;return implementation;
    },
    async openRowSite(input){
      assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.runAcquisitionLimits,acquisition);
      events.push('site');return{site,authorization};
    },
    createSourceReader(input){
      assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.implementation,implementation);
      assert.equal(input.site,site);readerInput=input;events.push('reader');return reader;
    },
  };
  const configurationReader={readJson(path){
    assert.equal(this,configurationReader);assert.equal(path,profile.siteProfilePath);
    // The actual loader must have captured all original methods before await.
    for(const name of Object.keys(services))services[name]=()=>assert.fail('Replaced service consumed');
    for(const name of Object.keys(provider))provider[name]=()=>assert.fail('Replaced provider consumed');
    sourceInitialization.prepareDeclaration=()=>assert.fail('Replaced constructor consumed');
    events.push('configuration');return siteProfile;
  },readText(){assert.fail('No CA selected');}};
  const ports={createHash,isAbsolute,nodeTypes,types:nodeTypes,canonicalJson,checked,captureConfigurationReaders,
    captureInstalledSourceServices,CALENDAR_LIST_OPERATION:'calendar:calendars:list',
    prepareCalendarListPages(){assert.fail('No page read in constructor scope');},
    createInstalledRowSource(input){
      assert.equal(input.declaration,declaration);assert.equal(input.declared,declared);
      assert.equal(input.environment,environment);assert.equal(input.environmentWire,environment.wire);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.providerReader,reader);
      assert.equal(input.authorization,authorization);assert.equal(input.site,site);sourceInput=input;events.push('source');
      if(sourceFailure)throw sourceFailure;return result;
    },
    retainInstalledHostInitializationFailure(cause,original){
      assert.equal(original.sourceReader,reader);assert.equal(original.sourceProfile,site);cleanup.push({cause,original});return cause;
    },
  };
  const load=Function(...Object.keys(ports),body+'\nreturn loadInstalledCalendarSource;')(...Object.values(ports));
  return{events,cleanup,result,profile,sourceInitialization,services,
    selected:()=>({implementationInput,readerInput,sourceInput}),
    load:(overrides={})=>load(profile,{moon:{},providerMoon:provider,runtimeBundleCid:'original-runtime',
      installation,sourceInitialization,installationServices:services,configurationReader,
      resolveSecret(){assert.fail('No credential resolution');},...overrides})};
}

test('Calendar calendars constructs through original Host Source services without external capacity',async()=>{
  const f=fixture();assert.equal(await f.load(),f.result);
  assert.deepEqual(f.events,['configuration','profile','implementation','schema','declaration','site','reader','source']);
  const {implementationInput,readerInput,sourceInput}=f.selected();
  assert.deepEqual(implementationInput.limits,{
    maxResponseBytes:8192,maxTotalResponseBytes:32768,maxNodes:512,maxDepth:16,
    maxRows:2,maxTotalRows:3,maxPages:4,pageSize:2,maxCursorBytes:512,
    maxIdentityBytes:4096,maxTargetBytes:4096,maxValueNodes:100,maxValueTextBytes:4096,
    maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8,maxSecretBytes:128,
  });
  assert.equal(implementationInput.columnCount,4);
  assert.deepEqual(sourceInput.limits,{maxPages:4,maxPageBytes:8192,maxPageRows:2,maxCaptureRows:3});
  assert.equal(readerInput.operation,'calendar:calendars:list');
  assert.equal(typeof readerInput.preparePageReader,'function');
});

test('Calendar original constructor and service accessors refuse before configuration',async()=>{
  const f=fixture();await assert.rejects(f.load({sourceInitialization:undefined}),{code:'CalendarSourceInitializationUnavailable'});
  assert.deepEqual(f.events,[]);
  const g=fixture(),replacement={...g.services};
  Object.defineProperty(replacement,'openRowSite',{get(){assert.fail('Accessor invoked');}});
  await assert.rejects(g.load({installationServices:replacement}),{code:'InstalledCalendarSourceServicesUnavailable'});
  assert.deepEqual(g.events,[]);
});

test('Calendar retains original implementation failure and original failed reader children',async()=>{
  const original=Object.assign(new Error('OriginalImplementationPending'),{cleanupPending:true});
  const f=fixture({implementationFailure:original});await assert.rejects(f.load(),cause=>cause===original);
  assert.deepEqual(f.events,['configuration','profile','implementation']);assert.equal(f.cleanup.length,0);
  const failure=Object.assign(new Error('OriginalSourcePending'),{cleanupPending:true});
  const g=fixture({sourceFailure:failure});await assert.rejects(g.load(),cause=>cause===failure);
  assert.equal(g.cleanup.length,1);assert.equal(g.cleanup[0].cause,failure);
  const h=fixture({foreignCapacity:true});
  await assert.rejects(h.load(),{code:'InstalledCalendarReaderImplementationMismatch'});
  assert.equal(h.cleanup.length,1);assert(!h.events.includes('source'));
});


test('Calendar Source selects its complete original page recipe before the shared reader constructor',async()=>{
  const f=fixture();assert.equal(await f.load(),f.result);
  assert.deepEqual(f.selected().implementationInput.limits,{
    maxResponseBytes:8192,maxTotalResponseBytes:32768,maxNodes:512,maxDepth:16,
    maxRows:2,maxTotalRows:3,maxPages:4,pageSize:2,maxCursorBytes:512,
    maxIdentityBytes:4096,maxTargetBytes:4096,maxValueNodes:100,maxValueTextBytes:4096,
    maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8,maxSecretBytes:128,
  });
  assert.deepEqual(f.selected().sourceInput.limits,
    {maxPages:4,maxPageBytes:8192,maxPageRows:2,maxCaptureRows:3});
});


test('Calendar original total response and cursor limits refuse before shared construction',async()=>{
  for(const change of [{maxResponseBytes:20000},{maxCursorUnits:300},{maxRows:1001}]){
    const f=fixture();Object.assign(f.profile.limits,change);
    await assert.rejects(f.load(),{code:'InstalledSourceReaderImplementationBoundsExceeded'});
    assert.deepEqual(f.events,['configuration','profile']);
  }
});
