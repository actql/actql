import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
import {prepareNotionUserListPages, NOTION_USER_LIST_OPERATION, NOTION_USER_LIST_API_VERSION}
  from '../connectors/notion/site/user-list-read.mjs';
import {prepareCalendarListPages, CALENDAR_LIST_OPERATION}
  from '../connectors/calendar/site/calendar-list-read.mjs';

// Real provider namespaces and the shared Host reader, with explicit Credential,
// current, accounting and transport ports. This is not a normal installation,
// Common admission, funded RowRun, physical send or cleanup acknowledgement.
const notion = await import(process.env.ACTQL_TEST_NOTION_URL ??
  new URL('../../_build/js/release/build/connectors/notion/host_node/host_node.js', import.meta.url).href);
const calendar = await import(process.env.ACTQL_TEST_CALENDAR_URL ??
  new URL('../../_build/js/release/build/connectors/calendar/host_node/host_node.js', import.meta.url).href);
const limits = Object.freeze({maxResponseBytes:8192, maxTotalResponseBytes:24576,
  maxNodes:512, maxDepth:16, maxRows:2, maxTotalRows:4, maxPages:3, maxRequests:3,
  pageSize:2, perPage:2, maxCursorBytes:128, maxCursorUnits:128,
  maxIdentityBytes:128, maxTargetBytes:1024, maxValueNodes:100, maxValueTextBytes:4096,
  maxRowsWireBytes:8192, maxRowsWireNodes:200, maxRowsWireDepth:8});

function open(family, pages) {
  const operation = family === 'notion' ? NOTION_USER_LIST_OPERATION : CALENDAR_LIST_OPERATION;
  const moon = family === 'notion' ? notion : calendar;
  const scope = Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name => [name,name])),
    operation, resourceOrigin:'https://provider.invalid'});
  const credential = {control:{identity:() => 'explicit-grant'}, journal:{
    claim(_cid,useId) {return {use:{},record:{grantCid:'explicit-grant',useId},replayed:false};},
    authorize() {}, finish() {},
  }, resolveSecret:() => 'explicit-secret'};
  const bodies = pages.map(value => Buffer.from(JSON.stringify(value)));
  const requests = [], charged = [], delivered = [];
  const site = {credential, referenceCurrent() {assert.equal(this,site); return true;},
    async callResource(input) {
      assert.equal(this,site);
      requests.push(input.operations.get(operation));
      assert(requests.length <= bodies.length);
      return {accepted:true,statusCode:200,body:bodies[requests.length-1]};
    }};
  const factory = createInstalledCredentialSourceReader({capacity:{},site,operation,
    maxResponses:limits.maxPages,maxResponseBytes:limits.maxResponseBytes,maxSecretBytes:64,
    preparePageReader({columns},applySynchronousProjection) {
      return (family === 'notion' ? prepareNotionUserListPages : prepareCalendarListPages)(
        {moon,names:columns,limits},applySynchronousProjection);
    }});
  const reader = factory.prepare({resource:family === 'notion' ? 'users' : 'calendars',
    columns:family === 'notion' ? ['id','name'] : ['summary'],
    async verifyRead() {},
    authorizationFor(index) {return {grant:{},scope,useId:`page-${index}`};},
    chargePage(body) {
      assert.equal(body,bodies[requests.length-1]); charged.push(body);
      return Object.freeze({body});
    },
    consumePage(rows,{charge}) {
      assert.equal(charge.body,charged.at(-1));
      delivered.push(...rows);
    }});
  return {reader,requests,charged,delivered,bodies,close() {
    reader.requestStop();
    assert.equal(reader.observe().cleanupConfirmed,true);
    assert.equal(factory.retire(),true);
  }};
}

const cursor = 'opaque /+e\u0301📅';
const user = (id,name) => ({object:'user',id,type:'bot',name,bot:{}});
const users = (value,next) => ({object:'list',type:'user',user:{},results:[value],
  has_more:next !== null,next_cursor:next});
const entry = (id,summary) => ({id,summary,timeZone:'Asia/Tokyo',accessRole:'reader',deleted:false});
const calendars = (value,next) => ({kind:'calendar#calendarList',items:[value],
  ...(next === null ? {} : {nextPageToken:next})});

test('real Notion projections preserve original strings and cursor through the shared reader',async() => {
  const f = open('notion',[users(user('N-e\u0301','一\r\n📚'),cursor),users(user('N-é',''),null)]);
  try {
    assert.deepEqual(await f.reader.read(),{pages:2,rowCount:2});
    assert.deepEqual(f.delivered,[{id:'N-e\u0301',name:'一\r\n📚'},{id:'N-é',name:''}]);
    assert.equal(f.charged.length,2);
    for(const [i,request] of f.requests.entries()) {
      assert.equal(request.method,'GET');
      const target = new URL(request.path,'https://provider.invalid');
      assert.equal(target.pathname,'/v1/users');
      assert(request.headers.some(([name,value]) => name === 'notion-version' && value === NOTION_USER_LIST_API_VERSION));
      const query = target.searchParams;
      assert.equal(query.get('page_size'),'2');
      assert.equal(query.get('start_cursor'),i === 0 ? null : cursor);
    }
    assert.equal(f.reader.observe().receivedBodyBytes,BigInt(f.bodies.reduce((n,body) => n+body.length,0)));
    assert.equal(f.reader.observe().cleanupConfirmed,false);
  } finally {f.close();}
  const duplicate = open('notion',[users(user('same','first'),cursor),users(user('same','second'),null)]);
  try {
    await assert.rejects(duplicate.reader.read(),error => error.cause?.code === 'NotionUserListDuplicateUser');
    assert.equal(duplicate.charged.length,2);
    assert.deepEqual(duplicate.delivered,[{id:'same',name:'first'}]);
  } finally {duplicate.close();}
});

test('real Calendar projections keep remaining rows and validate unselected captured columns',async() => {
  const f = open('calendar',[calendars(entry('C-e\u0301','予定 📅'),cursor),calendars(entry('C-é',''),null)]);
  try {
    assert.deepEqual(await f.reader.read(),{pages:2,rowCount:2});
    assert.deepEqual(f.delivered,[{id:'C-e\u0301',summary:'予定 📅',time_zone:'Asia/Tokyo',access_role:'reader'},
      {id:'C-é',summary:'',time_zone:'Asia/Tokyo',access_role:'reader'}]);
    assert.equal(f.charged.length,2);
    for(const [i,request] of f.requests.entries()) {
      const target = new URL(request.path,'https://provider.invalid');
      assert.equal(target.pathname,'/calendar/v3/users/me/calendarList');
      const query = target.searchParams;
      assert.equal(query.get('maxResults'),i === 0 ? '2' : '1');
      assert.equal(query.get('pageToken'),i === 0 ? null : cursor);
      assert.equal(query.get('showHidden'),'true');
      assert.equal(query.get('showDeleted'),'false');
      assert.equal(query.get('fields'),'kind,items(id,summary,timeZone,accessRole,deleted),nextPageToken');
    }
    assert.equal(f.reader.observe().cleanupConfirmed,false);
  } finally {f.close();}
  const malformed = open('calendar',[calendars({...entry('bad','visible'),timeZone:7},null)]);
  try {
    await assert.rejects(malformed.reader.read());
    assert.equal(malformed.charged.length,1);
    assert.deepEqual(malformed.delivered,[]);
  } finally {malformed.close();}
});

test('real Notion projection keeps remaining-page bounds without reading beyond an incomplete cap',async() => {
  const batch=(values,next)=>({object:'list',type:'user',user:{},results:values,
    has_more:next!==null,next_cursor:next});
  const f=open('notion',[batch([user('one','first')],cursor),
    batch([user('two','second'),user('three','third')],cursor+' next'),
    batch([user('four','fourth')],null)]);
  try{
    assert.deepEqual(await f.reader.read(),{pages:3,rowCount:4});
    assert.deepEqual(f.requests.map(request=>new URL(request.path,'https://provider.invalid').searchParams.get('page_size')),['2','2','1']);
    assert.deepEqual(f.requests.map(request=>new URL(request.path,'https://provider.invalid').searchParams.get('start_cursor')),[null,cursor,cursor+' next']);
    assert.deepEqual(f.delivered,[{id:'one',name:'first'},{id:'two',name:'second'},
      {id:'three',name:'third'},{id:'four',name:'fourth'}]);
    assert.equal(f.charged.length,3);assert.equal(f.reader.observe().cleanupConfirmed,false);
  }finally{f.close();}
  const capped=open('notion',[batch([user('one','first'),user('two','second')],cursor),
    batch([user('three','third'),user('four','fourth')],cursor+' next'),
    batch([user('five','not requested')],null)]);
  try{
    await assert.rejects(capped.reader.read(),error=>error.cause?.code==='NotionUserListRowLimit');
    assert.equal(capped.requests.length,2);assert.equal(capped.charged.length,2);
    assert.equal(capped.reader.observe().phase,'failed');
    assert.equal(capped.reader.observe().cleanupConfirmed,false);
  }finally{capped.close();}
});
