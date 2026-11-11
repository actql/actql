import assert from 'node:assert/strict';
import test from 'node:test';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable,installedConnectorForTable} from '../../../host-node/installed-connectors.mjs';

test('ordinary installed Source selection reaches the Calendar-owned factory',()=>{
  const table=createInstalledConnectorTable(installedConnectors);
  const selected=installedConnectorForTable(table,'source',{version:'actql-installed-calendar-source/0.1'});
  assert.equal(selected.registration,'calendar');
  assert.equal(selected.providerBundle,'connectors/calendar/host_node');
});


import {checkInstalledCalendarSourceProfile,loadInstalledCalendarSource,installedCalendarSourceIdentityParts} from '../host/installed-calendar-source.mjs';
const limits={maxResponseBytes:4096,maxNodes:512,maxDepth:16,maxPages:4,maxRows:10,maxRequests:4,perPage:2,
  maxCursorUnits:128,maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:4096,maxRowsWireNodes:100,
  maxRowsWireDepth:8,maxDeclarationBytes:4096,maxDeclarationNodes:1000,maxSecretBytes:128,maxCaBytes:16384};
const profile={version:'actql-installed-calendar-source/0.1',connectorId:'fixture',siteProfilePath:'/unused/site.json',
  accountConfigurationWire:'{}',limits};

test('installed Calendar snapshots the closed profile without inventing grants or bounds',()=>{
  const selected=checkInstalledCalendarSourceProfile(profile);
  assert.deepEqual(selected,profile);assert(Object.isFrozen(selected)&&Object.isFrozen(selected.limits));
  for(const patch of [{perPage:251},{maxPages:5,maxRequests:4},{maxRows:0},{maxSecretBytes:2147483647}])
    assert.throws(()=>checkInstalledCalendarSourceProfile({...profile,limits:{...limits,...patch}}),{code:'InvalidInstalledCalendarSourceProfile'});
  for(const value of [{...profile,resource:'free_busy'},{...profile,siteProfilePath:'relative'},
    {...profile,limits:{...limits,unexpected:1}}])
    assert.throws(()=>checkInstalledCalendarSourceProfile(value),{code:'InvalidInstalledCalendarSourceProfile'});
  const changing={...profile};Object.defineProperty(changing,'connectorId',{enumerable:true,get(){throw Error('must not invoke a profile accessor');}});
  assert.throws(()=>checkInstalledCalendarSourceProfile(changing),{code:'InvalidInstalledCalendarSourceProfile'});
});

test('installed Calendar refuses missing original initialization before profile I/O',async()=>{
  await assert.rejects(loadInstalledCalendarSource(profile,{}),{code:'CalendarSourceInitializationUnavailable'});
  await assert.rejects(loadInstalledCalendarSource(profile,{readerCapacity:{}}),{code:'CalendarSourceInitializationUnavailable'});
});

// Invoke the actual exported identity and loader with original configuration
// ports. The provider sentinel precedes declaration, Account and Source work.
function originalConfiguration({ca=true, mutate=false, failure}={}) {
  const events=[], selected={...profile,limits:{...limits,maxCaBytes:16000000}};
  const site={version:'actql-installed-calendar-site/0.1',apiOrigin:'https://www.googleapis.com',
    credentialAuthorityId:'authority',credentialKeyId:'key',credentialPrivateKeyPath:'/UNOPENED/key',
    environment:'test',journalRoot:'/UNOPENED/journal',namespaceId:'test',siteGeneration:1,siteKey:'calendar',
    ...(ca?{caPath:'/UNOPENED/ca.pem'}:{})};
  const pem='-----BEGIN CERTIFICATE-----\nORIGINAL\n-----END CERTIFICATE-----\n';
  const reader={readJson(path){assert.equal(this,reader);assert.equal(path,selected.siteProfilePath);events.push('json');
    if(mutate)reader.readJson=reader.readText=()=>assert.fail('late method read');return site;},
    readText(path,bounds){assert.equal(this,reader);assert.equal(path,site.caPath);assert.deepEqual(bounds,{maxBytes:16000000});events.push('text');if(failure)throw failure;return pem;}};
  const originalJson=reader.readJson, read=(...args)=>Reflect.apply(originalJson,reader,args);
  const stop=new Error('Original provider boundary');
  const provider=Object.fromEntries(['calendarProjectCalendarList','calendarListRowsWire','calendarListMetadataJson',
    'calendarListColumnNames','calendarListSchemaWire','calendarListRelationFactsWire'].map(name=>[name,function(){
      assert.equal(this,provider);if(name==='calendarListColumnNames')return ['id'];
      assert.equal(name,'calendarListSchemaWire');events.push('schema');throw stop;} ]));
  const installation=Object.freeze({original:'calendar'});
  const sourceInitialization=Object.freeze({prepareDeclaration(){assert.fail('no declaration before schema');}});
  const installationServices={
    sourceReaderImplementationProfile(input){assert.equal(this,installationServices);
      assert.equal(input.installation,installation);assert.equal(input.sourceInitialization,sourceInitialization);
      assert.equal(input.metadataResponses,0);assert.equal(input.originUnits,site.apiOrigin.length);
      return Object.freeze({maxDeclarationBytes:limits.maxDeclarationBytes,maxDeclarationNodes:limits.maxDeclarationNodes,
        pageSize:2,maxTotalRows:10,maxTotalResponseBytes:16384,maxCursorBytes:512,maxTargetBytes:4096});},
    sourceReaderImplementation(input){assert.equal(this,installationServices);
      assert.equal(input.installation,installation);assert.equal(input.sourceInitialization,sourceInitialization);
      assert.equal(input.columnCount,1);return Object.freeze({original:'unexecuted implementation'});},
    openRowSite(){assert.fail('no Site before provider schema');},
    createSourceReader(){assert.fail('no reader before provider schema');},
  };
  return {reader,events,stop,site,selected,pem,
    identity(context=true){return installedCalendarSourceIdentityParts(selected,selected,read,undefined,
      context?{configurationReader:reader}:undefined);},
    load(){return loadInstalledCalendarSource(selected,{sourceInitialization,installation,installationServices,
      resolveSecret(){assert.fail('no secret read');},providerMoon:provider,configurationReader:reader});}};
}

test('Calendar original reader public identity honors the supplied JSON port without context',async()=>{
  const f=originalConfiguration({ca:false});const actual=await f.identity(false);
  assert.deepEqual(f.events,['json']);assert.deepEqual(actual,[{...f.selected,accountConfigurationWire:{}},f.site,{}]);
});

test('Calendar original reader public callers capture both methods and preserve original CA bound',async()=>{
  for(const entry of ['identity','load']){
    const f=originalConfiguration({mutate:true});
    if(entry==='identity'){
      const result=await f.identity();const {createHash}=await import('node:crypto');
      assert.equal(result[2].caSha256,'sha256:'+createHash('sha256').update(Buffer.from(f.pem,'ascii')).digest('hex'));
    }else await assert.rejects(f.load(),error=>error===f.stop);
    assert.deepEqual(f.events,entry==='identity'?['json','text']:['json','text','schema']);
  }
});

test('Calendar original reader public callers preserve pending error and refuse method accessors',async()=>{
  for(const entry of ['identity','load']){
    let retries=0;const error=Object.assign(new Error('Original pending read'),{cleanupPending:true,
      cleanupHandle:{retry(){retries++;}}});
    const f=originalConfiguration({failure:error});await assert.rejects(f[entry](),actual=>actual===error);
    assert.equal(retries,0);assert.deepEqual(f.events,['json','text']);
    for(const name of ['readJson','readText']){
      const bad=originalConfiguration();Object.defineProperty(bad.reader,name,{get(){assert.fail('accessor invoked');}});
      await assert.rejects(bad[entry](),{code:'InstalledCalendarConfigurationReaderUnavailable'});assert.deepEqual(bad.events,[]);
    }
  }
});
