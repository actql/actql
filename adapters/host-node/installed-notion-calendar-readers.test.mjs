import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {captureConfigurationReaders} from './source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {captureInstalledSourceServices} from './installed-host-services.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
import {prepareNotionUserListPages,NOTION_USER_LIST_OPERATION,NOTION_USER_LIST_API_VERSION}
  from '../connectors/notion/site/user-list-read.mjs';
import {prepareCalendarListPages,CALENDAR_LIST_OPERATION}
  from '../connectors/calendar/site/calendar-list-read.mjs';

const ok = value => ({$tag:1,_0:value});
const allLimits = {maxResponseBytes:8192,maxTotalResponseBytes:24576,maxNodes:512,maxDepth:16,
  maxRows:10,maxTotalRows:20,maxPages:4,maxRequests:4,pageSize:2,perPage:2,
  maxCursorBytes:128,maxCursorUnits:128,maxIdentityBytes:128,maxTargetBytes:1024,
  maxValueNodes:100,maxValueTextBytes:4096,maxRowsWireBytes:8192,maxRowsWireNodes:200,maxRowsWireDepth:8};
const columns = {notion:['email','id','name','type'],calendar:['access_role','id','summary','time_zone']};
const row = (family,id) => family === 'notion' ? {email:null,id,name:id,type:'bot'}
  : {access_role:'reader',id,summary:id,time_zone:'UTC'};
const page = (family,id,next=null) => ({rows:id === null ? [] : [row(family,id)],
  ids:id === null ? [] : [id],next});

// Actual provider adapters and Host owner, with explicit compiled-projection,
// Account/grant and physical response ports. No Common/SQLite/TLS or normal
// installer/Plan qualification is inferred from these callback-boundary cases.
function fixture(family,pages,{limits={},names=columns[family],status=200,consume,current,charge,projection}={}) {
  const events=[],requests=[],delivered=[],responses=[];
  const operation = family === 'notion' ? NOTION_USER_LIST_OPERATION : CALENDAR_LIST_OPERATION;
  const scope = Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(k=>[k,k])),
    operation,resourceOrigin:'https://provider.invalid'});
  const credential = {control:{identity:()=> 'same-grant'},journal:{
    claim(_cid,useId){return {use:{},record:{grantCid:'same-grant',useId},replayed:false};},
    authorize(){},finish(){}},resolveSecret:()=> 'fixture-secret'};
  const bodies=pages.map((_,i)=>Buffer.from(`original-page-${i}`));
  const selected = body => {assert.equal(events.at(-2),'charge');assert.equal(events.at(-1),'current');
    const index=bodies.indexOf(body);assert(index>=0);events.push('decode');return pages[index];};
  let live=true;
  const site={credential,referenceCurrent(){assert.equal(this,site);return live;},
    async callResource(input){assert.equal(this,site);requests.push(input.operations.get(operation));
      const response={accepted:true,statusCode:status,body:bodies[requests.length-1]};
      assert(response.body);responses.push(response);events.push('send');return response;}};
  const moon = family === 'notion' ? {
    notionProjectUserList(body){assert.equal(this,moon);const p=selected(body);return projection?projection(body,p):ok(p);},
    notionUserListIds(p){return p.ids;},
    notionUserListMetadataJson(p){return ok(JSON.stringify({rowCount:p.rows.length,nextCursor:p.next}));},
    notionUserListRowsWire(p,selected){assert.deepEqual(selected,names);return ok(JSON.stringify(p.rows));},
    notionUserListColumnNames(){return columns.notion;},
  } : {
    calendarProjectCalendarList(body){assert.equal(this,moon);const p=selected(body);return projection?projection(body,p):ok(p);},
    calendarListMetadataJson(p){return JSON.stringify({rowCount:p.rows.length,ids:p.ids,nextPageToken:p.next});},
    calendarListRowsWire(p,selected){assert.deepEqual(selected,columns.calendar);return ok(JSON.stringify(p.rows));},
    calendarListColumnNames(){return columns.calendar;},
  };
  const bounded={...allLimits,...limits};
  const callbacks={resource:family === 'notion' ? 'users':'calendars',columns:[...names],
    async verifyRead(){events.push('current');await current?.();},
    authorizationFor(index){events.push(`grant:${index}`);return {grant:{},scope,useId:`page-${index}`};},
    chargePage(body){assert.equal(body,responses.at(-1).body);events.push('charge');charge?.(body);
      return Object.freeze({body});},
    consumePage(rows,{charge:ticket}){assert.equal(ticket.body,responses.at(-1).body);
      delivered.push(...rows);consume?.(rows);}};
  const factory=createInstalledCredentialSourceReader({capacity:{},site,operation,
    maxResponses:bounded.maxPages,maxResponseBytes:bounded.maxResponseBytes,maxSecretBytes:64,
    preparePageReader({columns:selected},applySynchronousProjection){return (family === 'notion' ? prepareNotionUserListPages
      :prepareCalendarListPages)({moon,names:selected,limits:bounded},applySynchronousProjection);}});
  const reader=factory.prepare(callbacks);
  return {reader,factory,requests,events,delivered,moon,bounded,callbacks,
    notCurrent(){live=false;},bytes:bodies.reduce((n,b)=>n+BigInt(b.length),0n)};
}

for(const family of ['notion','calendar']) test(`${family} page meaning uses the same Host owner for empty one and multiple pages`,async()=>{
  for(const pages of [[page(family,null)],[page(family,'one')],
    [page(family,'one','opaque /+é'),page(family,'two')]]){
    const f=fixture(family,pages,{names:family === 'calendar' ? ['summary']:columns.notion});
    const result=await f.reader.read();
    assert.deepEqual(result,{pages:pages.length,rowCount:pages.flatMap(p=>p.rows).length});
    assert.deepEqual(f.delivered,pages.flatMap(p=>p.rows));
    assert.equal(f.requests.length,pages.length);
    for(const [i,request] of f.requests.entries()){
      const url=new URL(request.path,'https://provider.invalid');assert.equal(request.method,'GET');
      if(family === 'notion'){
        assert.equal(url.pathname,'/v1/users');assert.equal(url.searchParams.get('page_size'),'2');
        assert.equal(url.searchParams.get('start_cursor'),i === 0 ? null:'opaque /+é');
        assert(request.headers.some(([k,v])=>k==='notion-version'&&v===NOTION_USER_LIST_API_VERSION));
      }else{
        assert.equal(url.pathname,'/calendar/v3/users/me/calendarList');
        assert.equal(url.searchParams.get('maxResults'),'2');assert.equal(url.searchParams.get('showHidden'),'true');
        assert.equal(url.searchParams.get('showDeleted'),'false');
        assert.equal(url.searchParams.get('pageToken'),i === 0 ? null:'opaque /+é');
      }
    }
    assert.equal(f.reader.observe().receivedBodyBytes,f.bytes);
    assert.equal(f.reader.observe().cleanupConfirmed,false);
    f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
    f.reader.retry();assert.equal(f.requests.length,pages.length);
  }
});

test('Notion still refuses duplicate identity cursor target page row and aggregate raw bounds',async()=>{
  for(const mode of ['id','cursor','target','pages','rows','bytes']){
    const limits=mode==='target'?{maxTargetBytes:1}:mode==='pages'?{maxPages:1}:
      mode==='rows'?{maxTotalRows:1}:mode==='bytes'?{maxTotalResponseBytes:15}:{};
    const pages=[page('notion','one','cursor'),page('notion',mode==='id'?'one':'two',mode==='cursor'?'cursor':null)];
    const f=fixture('notion',pages,{limits});
    const code={id:'NotionUserListDuplicateUser',cursor:'NotionUserListRepeatedCursor',target:'NotionUserListTargetLimit',
      pages:'NotionUserListPageLimit',rows:'NotionUserListRowLimit',bytes:'NotionUserListResponseLimit'}[mode];
    await assert.rejects(f.reader.read(),e=>e.cause?.code===code);
    assert.equal(f.requests.length,mode==='target'?0:['pages','rows'].includes(mode)?1:2);
    f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);
  }
});

test('Notion requests only the remaining rows on its next original cursor',async()=>{
  const first=page('notion','one','same-original-cursor');
  first.rows.push(row('notion','two'));first.ids.push('two');
  const f=fixture('notion',[first,page('notion','three')],{limits:{maxTotalRows:3,pageSize:2}});
  try{
    assert.deepEqual(await f.reader.read(),{pages:2,rowCount:3});
    assert.deepEqual(f.requests.map(request=>new URL(request.path,'https://provider.invalid').searchParams.get('page_size')),['2','1']);
    assert.equal(new URL(f.requests[1].path,'https://provider.invalid').searchParams.get('start_cursor'),'same-original-cursor');
    assert.deepEqual(f.delivered,[row('notion','one'),row('notion','two'),row('notion','three')]);
  }finally{f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);}
});

test('Notion refuses an incomplete capped Source before another send or indexed grant',async()=>{
  const f=fixture('notion',[page('notion','one','more'),page('notion','two')],{limits:{maxTotalRows:1}});
  try{
    await assert.rejects(f.reader.read(),error=>error.cause?.code==='NotionUserListRowLimit');
    assert.equal(f.requests.length,1);assert.equal(f.events.filter(event=>event==='charge').length,1);
    assert.deepEqual(f.events.filter(event=>event.startsWith('grant:')),['grant:0']);
    assert.equal(f.reader.observe().phase,'failed');
  }finally{f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed,true);assert.equal(f.factory.retire(),true);}
});

test('Calendar retains remaining-row requests full columns and duplicate or incomplete-page refusals',async()=>{
  const f=fixture('calendar',[page('calendar','one','next'),page('calendar','two')],{limits:{maxRows:2},names:['summary']});
  await f.reader.read();
  assert.equal(new URL(f.requests[0].path,'https://provider.invalid').searchParams.get('maxResults'),'2');
  assert.equal(new URL(f.requests[1].path,'https://provider.invalid').searchParams.get('maxResults'),'1');
  assert.deepEqual(f.delivered,[row('calendar','one'),row('calendar','two')]);f.reader.requestStop();
  for(const mode of ['id','cursor','pages','rows']){
    const limits=mode==='pages'?{maxPages:1}:mode==='rows'?{maxRows:1}:{};
    const pages=[page('calendar','one','next'),page('calendar',mode==='id'?'one':'two',mode==='cursor'?'next':null)];
    const g=fixture('calendar',pages,{limits});
    const code={id:'CalendarListDuplicateRecord',cursor:'CalendarListCursorCycle',pages:'CalendarListPageLimit',rows:'CalendarListRowLimit'}[mode];
    await assert.rejects(g.reader.read(),e=>e.cause?.code===code);
    assert.equal(g.requests.length,['pages','rows'].includes(mode)?1:2);
    g.reader.requestStop();assert.equal(g.reader.observe().cleanupConfirmed,true);
  }
});

test('both providers charge a rejected body without decoding or manufacturing empty completion',async()=>{
  for(const family of ['notion','calendar']){
    const f=fixture(family,[page(family,'one')],{status:403});
    await assert.rejects(f.reader.read(),e=>e.cause?.code===(family === 'notion'?'NotionUserListReadRejected':'CalendarListReadRejected')&&
      !Object.hasOwn(e,'observations'));
    assert.equal(f.events.filter(e=>e==='charge').length,1);assert(!f.events.includes('decode'));
    assert.deepEqual(f.delivered,[]);f.reader.requestStop();assert(f.reader.observe().cleanupConfirmed);
  }
});

test('both provider callbacks preserve original cancellation or current loss without another send',async()=>{
  for(const family of ['notion','calendar']) for(const mode of ['cancel','current']){
    let f;const cause=new Error('same original cancellation');
    f=fixture(family,[page(family,'one','next'),page(family,'two')],{consume(){
      if(mode==='cancel')f.reader.requestStop(cause);else f.notCurrent();}});
    await assert.rejects(f.reader.read(),e=>mode==='cancel'?e.cause===cause:e.cause?.code==='InstalledSourceReaderNotCurrent');
    assert.equal(f.requests.length,1);f.reader.requestStop();assert(f.reader.observe().cleanupConfirmed);
  }
});

test('both providers capture original projection methods columns and limits before the first Host await',async()=>{
  for(const family of ['notion','calendar']){
    const f=fixture(family,[page(family,'one','next'),page(family,'two')]);
    const name=family === 'notion'?'notionProjectUserList':'calendarProjectCalendarList';
    f.moon[name]=()=>assert.fail('replaced projection');f.callbacks.columns[0]='foreign';f.bounded.maxPages=1;
    assert.equal((await f.reader.read()).rowCount,2);f.reader.requestStop();
    assert(f.reader.observe().cleanupConfirmed);
  }
});


test('both provider adapters retain unexpected asynchronous compiled projections until their same borrow settles',async()=>{
  for(const family of ['notion','calendar']){
    let release,finished;
    const pending=new Promise(resolve=>{release=resolve;});
    const settled=new Promise(resolve=>{finished=resolve;});
    const f=fixture(family,[page(family,'one')],{projection:async(body,value)=>{
      await pending;assert.equal(body.toString(),'original-page-0');finished();return ok(value);
    }});
    await assert.rejects(f.reader.read());f.reader.requestStop();
    try{
      assert.equal(f.reader.observe().readPending,false);
      assert.equal(f.reader.observe().transportClosed,true);
      assert.equal(f.reader.observe().cleanupConfirmed,false);
    }finally{
      release();await settled;await new Promise(resolve=>setImmediate(resolve));
    }
    assert.equal(f.reader.observe().cleanupConfirmed,true);
    assert.equal(f.requests.length,1);assert.equal(f.delivered.length,0);
  }
});

// Execute the actual loader bodies with explicit declaration, Account and Site
// ports. The real shared factory and initialization cleanup own retirement;
// no Common admission, credential material, filesystem or provider I/O occurs.
async function initializationFixture(family,{failConstruction=true}={}) {
  const path=new URL(`../connectors/${family}/host/installed-${family}-source.mjs`,import.meta.url);
  const code=await readFile(path,'utf8');
  const declarations=parse(code,{ecmaVersion:'latest',sourceType:'module'}).body.flatMap(node=>{
    const value=node.declaration??node;
    return ['VariableDeclaration','FunctionDeclaration'].includes(value.type)
      ?[code.slice(value.start,value.end)]:[];
  }).join('\n');
  const limitNames=family==='notion'
    ?['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth','maxRows','maxTotalRows',
      'maxPages','pageSize','maxCursorBytes','maxIdentityBytes','maxTargetBytes','maxValueNodes',
      'maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth']
    :['maxResponseBytes','maxNodes','maxDepth','maxPages','maxRows','maxRequests','perPage',
      'maxCursorUnits','maxValueNodes','maxValueTextBytes','maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];
  const limits=Object.fromEntries([...limitNames,'maxDeclarationBytes','maxDeclarationNodes',
    'maxSecretBytes','maxCaBytes'].map(name=>[name,10]));
  const profile={version:`actql-installed-${family}-source/0.1`,connectorId:'fixture',
    siteProfilePath:'/UNOPENED/site.json',accountConfigurationWire:'{}',limits};
  const siteProfile={version:`actql-installed-${family}-site/0.1`,apiOrigin:'https://provider.invalid',
    credentialAuthorityId:'fixture',credentialKeyId:'key',credentialPrivateKeyPath:'/UNOPENED/key',
    environment:'fixture',journalRoot:'/UNOPENED/journal',namespaceId:'fixture',siteGeneration:1,siteKey:'fixture'};
  let factory,closed=0,configurationReads=0;
  const serviceCalls=[],installation=Object.freeze({registration:family,revision:family+'/0.1'});
  const declaration=Object.freeze({original:'declaration'}),declared=Object.freeze({views:[{fields:['id']}]}),
    environment=Object.freeze({wire:'explicit original environment'}),sourcePort=Object.freeze({original:'Source constructor port'});
  const sourceInitialization={prepareDeclaration(views,expected){
    assert.equal(this,sourceInitialization);assert.equal(views.length,1);assert.equal(expected,undefined);
    serviceCalls.push('prepareDeclaration');return Object.freeze({declaration,declared,environment});
  }};
  const implementation=Object.freeze({runAcquisitionLimits:Object.freeze({maxBindings:1,maxSecretBytes:10})});
  const failure=new Error('same original Source constructor failure');
  const site={credential:{},referenceCurrent:()=>true,callResource(){assert.fail('no send');},
    close(){
      assert.throws(()=>factory.prepare({}),{code:'InstalledSourceReaderFactoryClosed'});
      closed++;
    }};
  const services={
    sourceReaderImplementationProfile(input){assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.metadataResponses,0);
      assert.equal(input.originUnits,siteProfile.apiOrigin.length);serviceCalls.push('profile');
      return Object.freeze({maxDeclarationBytes:10,maxDeclarationNodes:10});},
    sourceReaderImplementation(input){assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.columnCount,1);
      serviceCalls.push('implementation');return implementation;},
    async openRowSite(input){assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.runAcquisitionLimits,implementation.runAcquisitionLimits);
      assert(Object.isFrozen(input.profile));serviceCalls.push('site');return{site,authorization:{context:{contextCid:'explicit Account port'}}};},
    createSourceReader(input){assert.equal(this,services);assert.equal(input.installation,installation);
      assert.equal(input.sourceInitialization,sourceInitialization);assert.equal(input.implementation,implementation);assert.equal(input.site,site);
      serviceCalls.push('reader');return createInstalledCredentialSourceReader({capacity:{},site,operation:input.operation,
        maxResponses:limits.maxPages,maxResponseBytes:limits.maxResponseBytes,maxSecretBytes:limits.maxSecretBytes,
        preparePageReader:input.preparePageReader});},
  };
  const ports={createHash,isAbsolute,nodeTypes,canonicalJson:JSON.stringify,checked,captureConfigurationReaders,
    retainInstalledHostInitializationFailure,captureInstalledSourceServices,
    prepareNotionUserListPages,prepareCalendarListPages,NOTION_USER_LIST_OPERATION,CALENDAR_LIST_OPERATION,
    createInstalledRowSource:async input=>{factory=input.providerReader;assert.equal(input.sourceInitialization,sourceInitialization);
      assert.equal(input.environment,environment);assert.equal(input.declaration,declaration);assert.equal(input.declared,declared);
      assert.equal(input.environmentWire,environment.wire);serviceCalls.push('source');if(failConstruction)throw failure;return sourcePort;}};
  const cap=family[0].toUpperCase()+family.slice(1);
  const load=Function(...Object.keys(ports),declarations+`\nreturn loadInstalled${cap}Source;`)(...Object.values(ports));
  const provider=Object.fromEntries((family==='notion'
    ?['notionUserListSchemaWire','notionUserListRelationFactsWire','notionUserListColumnNames',
      'notionUserListRowsWire','notionUserListMetadataJson','notionUserListIds','notionProjectUserList']
    :['calendarListSchemaWire','calendarListRelationFactsWire','calendarListColumnNames',
      'calendarListRowsWire','calendarListMetadataJson','calendarProjectCalendarList'])
    .map(name=>[name,()=>name.endsWith('SchemaWire')?ok('explicit schema port'):name.endsWith('ColumnNames')?['id']:'explicit provider port']));
  return {failure,siteProfile,sourcePort,sourceInitialization,services,serviceCalls,
    closed:()=>closed,factory:()=>factory,configurationReads:()=>configurationReads,
    cleanup(){if(factory?.retire()===true&&closed===0)site.close();},
    load:(overrides={})=>load(profile,{moon:{},providerMoon:provider,installationServices:services,installation,sourceInitialization,
      runtimeBundleCid:'explicit runtime port',
      resolveSecret(){assert.fail('no secret resolution');},configurationReader:{
        readJson(){configurationReads++;return siteProfile;},readText(){assert.fail('no CA read');}},...overrides})};
}

test('both installed loaders retire their same created reader before Site cleanup on construction failure',async()=>{
  for(const family of ['notion','calendar']){
    const f=await initializationFixture(family);let failure;
    try{
      await assert.rejects(f.load(),error=>{failure=error;return error.primaryFailure===f.failure;});
      assert.equal(failure.cleanupPending,false);
      assert.equal(f.closed(),1);
      assert.throws(()=>f.factory().prepare({}),{code:'InstalledSourceReaderFactoryClosed'});
    }finally{
      // Test-owned unwinding uses the same original aliases even on the red.
      f.factory()?.retire();
      await failure?.cleanupHandle.retry();
    }
  }
});


test('both installed loaders refuse missing Reader inputs before any configuration read',async()=>{
  for(const family of ['notion','calendar'])for(const missing of ['sourceInitialization','installation','installationServices','configurationReader','resolveSecret']){
    const f=await initializationFixture(family),title=family[0].toUpperCase()+family.slice(1);
    const code=missing==='installationServices'?`Installed${title}SourceServicesUnavailable`:
      missing==='configurationReader'?`Installed${title}ConfigurationReaderUnavailable`:
      title+(missing==='resolveSecret'?'CredentialMaterialUnavailable':'SourceInitializationUnavailable');
    await assert.rejects(f.load({[missing]:undefined}),{code});
    assert.equal(f.configurationReads(),0,'no configuration read before required Reader inputs');
    assert.equal(f.factory(),undefined);assert.equal(f.closed(),0);
  }
});

test('both installed loaders retain the original provider methods and receiver before configuration awaits',async()=>{
  for(const family of ['notion','calendar']){
    const f=await initializationFixture(family);
    const names=family==='notion'
      ?['notionUserListSchemaWire','notionUserListRelationFactsWire','notionUserListColumnNames',
        'notionUserListRowsWire','notionUserListMetadataJson','notionUserListIds','notionProjectUserList']
      :['calendarListSchemaWire','calendarListRelationFactsWire','calendarListColumnNames',
        'calendarListRowsWire','calendarListMetadataJson','calendarProjectCalendarList'];
    const provider={},reads=new Map(),calls=[];
    let replaced=false,readsBeforeAwait,failure;
    for(const name of names)Object.defineProperty(provider,name,{get(){
      reads.set(name,(reads.get(name)??0)+1);
      if(replaced)return()=>assert.fail('replacement provider after configuration await');
      return function(){
        assert.equal(this,provider);calls.push(name);
        return name.endsWith('SchemaWire')?ok('explicit schema port'):name.endsWith('ColumnNames')?['id']:'explicit provider port';
      };
    }});
    try{
      await assert.rejects(f.load({providerMoon:provider,configurationReader:{async readJson(){
        readsBeforeAwait=new Map(reads);await Promise.resolve();replaced=true;return f.siteProfile;
      },readText(){assert.fail('no CA read');}}}),error=>{
        failure=error;return error.primaryFailure===f.failure;
      });
      assert.deepEqual(readsBeforeAwait,new Map(names.map(name=>[name,1])));
      assert.deepEqual(reads,readsBeforeAwait,'no provider reread after configuration await');
      assert.deepEqual(calls,[names.find(name=>name.endsWith('ColumnNames')),...names.slice(0,2)]);
      assert.equal(f.closed(),1);
      assert.equal(failure.cleanupPending,false);
    }finally{
      f.factory()?.retire();await failure?.cleanupHandle?.retry();
    }
  }
});

test('Notion refuses an incomplete provider before configuration or Site construction',async()=>{
  const names=['notionUserListSchemaWire','notionUserListRelationFactsWire','notionUserListColumnNames',
    'notionUserListRowsWire','notionUserListMetadataJson','notionUserListIds','notionProjectUserList'];
  for(const missing of names){
    const f=await initializationFixture('notion');
    const provider=Object.fromEntries(names.filter(name=>name!==missing).map(name=>[name,()=>assert.fail('no provider call')]));
    await assert.rejects(f.load({providerMoon:provider}),{code:'InstalledNotionProviderUnavailable'});
    assert.equal(f.configurationReads(),0);assert.equal(f.factory(),undefined);assert.equal(f.closed(),0);
  }
});

test('both installed loaders forward their same original initialization through the complete service quartet',async()=>{
  for(const family of ['notion','calendar']){
    const f=await initializationFixture(family,{failConstruction:false});
    try{
      assert.equal(await f.load(),f.sourcePort);
      assert.deepEqual(f.serviceCalls,['profile','implementation','prepareDeclaration','site','reader','source']);
      assert.equal(f.configurationReads(),1);assert.equal(f.closed(),0);
    }finally{f.cleanup();}
    assert.equal(f.closed(),1);
  }
});

test('both installed loaders capture original initialization and service methods before configuration awaits',async()=>{
  for(const family of ['notion','calendar']){
    const f=await initializationFixture(family,{failConstruction:false});
    try{
      assert.equal(await f.load({configurationReader:{async readJson(){
        await Promise.resolve();
        f.sourceInitialization.prepareDeclaration=()=>assert.fail('late declaration method');
        for(const name of ['sourceReaderImplementationProfile','sourceReaderImplementation','openRowSite','createSourceReader']){
          f.services[name]=()=>assert.fail('late service method');
        }
        return f.siteProfile;
      },readText(){assert.fail('no CA read');}}}),f.sourcePort);
      assert.deepEqual(f.serviceCalls,['profile','implementation','prepareDeclaration','site','reader','source']);
    }finally{f.cleanup();}
  }
});

test('both installed loaders refuse initializer and service method accessors before configuration I/O',async()=>{
  for(const family of ['notion','calendar']){
    const title=family[0].toUpperCase()+family.slice(1),f=await initializationFixture(family);
    Object.defineProperty(f.sourceInitialization,'prepareDeclaration',{get(){assert.fail('initializer accessor invoked');}});
    await assert.rejects(f.load(),{code:title+'SourceInitializationUnavailable'});assert.equal(f.configurationReads(),0);
    for(const name of ['sourceReaderImplementationProfile','sourceReaderImplementation','openRowSite','createSourceReader']){
      const s=await initializationFixture(family);
      Object.defineProperty(s.services,name,{get(){assert.fail('service accessor invoked');}});
      await assert.rejects(s.load(),{code:'Installed'+title+'SourceServicesUnavailable'});assert.equal(s.configurationReads(),0);
    }
  }
});

// Execute each original fixture's after callback with the actual shared
// factory. RowRun, Journal and server are explicit ordering ports here; no
// Common admission, native I/O or physical cleanup receipt is synthesized.
test('provider fixtures retire their original factories before closing dependent fixture owners',async()=>{
  for(const family of ['notion','calendar'])for(const returned of [true,false]){
    const file=family==='notion'?'user-list-read.fixture.mjs':'calendar-list.fixture.mjs';
    const code=await readFile(new URL(`../connectors/${family}/test/${file}`,import.meta.url),'utf8');
    const ast=parse(code,{ecmaVersion:'latest',sourceType:'module'});
    const fixture=ast.body.find(node=>node.type==='ExportNamedDeclaration'&&
      node.declaration?.id?.name===(family==='notion'?'userListFixture':'calendarFixture')).declaration;
    const after=fixture.body.body.find(node=>node.type==='ExpressionStatement'&&
      node.expression.callee?.object?.name==='t'&&node.expression.callee.property?.name==='after').expression.arguments[0];
    const failure=new Error('same original provider preparation failure'),events=[];
    const factory=createInstalledCredentialSourceReader({capacity:{},operation:'fixture:list',
      maxResponses:1,maxResponseBytes:128,maxSecretBytes:64,
      site:{credential:{},referenceCurrent:()=>true,callResource(){assert.fail('no transport');}},
      preparePageReader(){
        return{fetchPage(){assert.fail('no page request');},decodePage(){assert.fail('no projection');}};
      }});
    const options={resource:'fixture',columns:['id'],verifyRead:async()=>{},
      authorizationFor(){assert.fail('no grant');},chargePage(){assert.fail('no charge');},
      consumePage(){assert.fail('no row');}};
    if(!returned)Object.defineProperty(options,'signal',{get(){throw failure;}});
    const readers=[];
    const assertRetired=()=>assert.throws(()=>factory.prepare({}),{code:'InstalledSourceReaderFactoryClosed'});
    try{
      if(returned)readers.push(factory.prepare(options));
      else assert.throws(()=>factory.prepare(options),error=>error===failure);
      const row={close(){assertRetired();events.push('row');},usage:()=>({})};
      const journal={close(){assertRetired();events.push('journal');}};
      const server={close(done){assertRetired();events.push('server');done();}};
      const cleanup=Function('assert','readers','factories','row','journal','server','t','root',
        'ledgerUsageFieldsFor',`return (${code.slice(after.start,after.end)});`)(assert,readers,[factory],
        row,journal,server,{diagnostic(){}},'/UNOPENED/fixture',()=>[0n,0n,0n,0n]);
      await cleanup();
      assertRetired();assert.deepEqual(events,['row','journal','server']);
      if(returned)assert.equal(readers[0].observe().cleanupConfirmed,true);
    }finally{
      // Test-owned unwinding retains the same original even on the red.
      for(const reader of readers)reader.requestStop();
      assert.equal(factory.retire(),true);
    }
  }
});

test('provider fixture cleanup preserves dependent owners while the original factory remains pending',async()=>{
  for(const family of ['notion','calendar']){
    const file=family==='notion'?'user-list-read.fixture.mjs':'calendar-list.fixture.mjs';
    const code=await readFile(new URL(`../connectors/${family}/test/${file}`,import.meta.url),'utf8');
    const fixture=parse(code,{ecmaVersion:'latest',sourceType:'module'}).body.find(node=>
      node.type==='ExportNamedDeclaration'&&node.declaration?.id?.name===
        (family==='notion'?'userListFixture':'calendarFixture')).declaration;
    const after=fixture.body.body.find(node=>node.type==='ExpressionStatement'&&
      node.expression.callee?.object?.name==='t'&&node.expression.callee.property?.name==='after').expression.arguments[0];
    let release;
    const pending=new Promise(resolve=>{release=resolve;}),closed=[];
    const factory=createInstalledCredentialSourceReader({capacity:{},operation:'fixture:list',
      maxResponses:1,maxResponseBytes:128,maxSecretBytes:64,
      site:{credential:{},referenceCurrent:()=>true,callResource(){assert.fail('no transport');}},
      preparePageReader:()=>pending});
    const reader=factory.prepare({resource:'fixture',columns:['id'],verifyRead:async()=>{},
      authorizationFor(){assert.fail('no grant');},chargePage(){assert.fail('no charge');},
      consumePage(){assert.fail('no row');}});
    try{
      await assert.rejects(reader.read(),{code:'InstalledSourcePageCallbackNotSynchronous'});
      reader.requestStop();assert.equal(factory.retire(),false);
      const cleanup=Function('assert','readers','factories','row','journal','server','t','root',
        'ledgerUsageFieldsFor',`return (${code.slice(after.start,after.end)});`)(assert,[reader],[factory],
        {close(){closed.push('row');},usage:()=>({})},{close(){closed.push('journal');}},
        {close(done){done();}},{diagnostic(){}},'/UNOPENED/fixture',()=>[0n,0n,0n,0n]);
      await assert.rejects(cleanup(),AggregateError);
      assert.deepEqual(closed,[],'pending original child cannot permit dependent close');
      assert.equal(reader.observe().cleanupConfirmed,false);
    }finally{
      release({fetchPage(){assert.fail('no request');},decodePage(){assert.fail('no projection');}});
      await pending;await new Promise(resolve=>setImmediate(resolve));
      reader.requestStop();assert.equal(factory.retire(),true);
    }
  }
});

test('provider fixture cleanup preserves the original RowRun close failure before Journal close',async()=>{
  for(const family of ['notion','calendar']){
    const file=family==='notion'?'user-list-read.fixture.mjs':'calendar-list.fixture.mjs';
    const code=await readFile(new URL(`../connectors/${family}/test/${file}`,import.meta.url),'utf8');
    const fixture=parse(code,{ecmaVersion:'latest',sourceType:'module'}).body.find(node=>
      node.type==='ExportNamedDeclaration'&&node.declaration?.id?.name===
        (family==='notion'?'userListFixture':'calendarFixture')).declaration;
    const after=fixture.body.body.find(node=>node.type==='ExpressionStatement'&&
      node.expression.callee?.object?.name==='t'&&node.expression.callee.property?.name==='after').expression.arguments[0];
    const factory=createInstalledCredentialSourceReader({capacity:{},operation:'fixture:list',
      maxResponses:1,maxResponseBytes:128,maxSecretBytes:64,
      site:{credential:{},referenceCurrent:()=>true,callResource(){assert.fail('no transport');}},
      preparePageReader:()=>({fetchPage(){assert.fail('no request');},decodePage(){assert.fail('no projection');}})});
    const reader=factory.prepare({resource:'fixture',columns:['id'],verifyRead:async()=>{},
      authorizationFor(){assert.fail('no grant');},chargePage(){assert.fail('no charge');},
      consumePage(){assert.fail('no row');}});
    const original=new Error('same original RowRun close failure');let journalCloses=0;
    try{
      const cleanup=Function('assert','readers','factories','row','journal','server','t','root',
        'ledgerUsageFieldsFor',`return (${code.slice(after.start,after.end)});`)(assert,[reader],[factory],
        {close(){throw original;},usage(){assert.fail('no settled usage');}},
        {close(){journalCloses++;}},{close(done){done();}},{diagnostic(){}},'/UNOPENED/fixture',
        ()=>assert.fail('no settled Ledger'));
      await assert.rejects(cleanup(),error=>error instanceof AggregateError&&error.errors.includes(original));
      assert.equal(journalCloses,0);assert.equal(reader.observe().cleanupConfirmed,true);
      assert.throws(()=>factory.prepare({}),{code:'InstalledSourceReaderFactoryClosed'});
    }finally{reader.requestStop();assert.equal(factory.retire(),true);}
  }
});
