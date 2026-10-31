import assert from 'node:assert/strict';
import test from 'node:test';
// CI consumes its already-required Node Common. A focused source component can
// select an explicitly qualified build of the unchanged Gmail provider only.
const originalProvider = await import(process.env.ACTQL_TEST_GMAIL_PROVIDER_MODULE ??
  new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
import {prepareGmailThreadReadSequence} from '../site/gmail-thread-read.mjs';
import {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding,callHttpsCredentialResource}
  from '../../../site-node/https-credential-resource.mjs';

// Actual unchanged compiled Gmail parser/nominal control and changed protocol;
// current, IO and accounting are explicit ports, not an ordinary Host/Run.
const limits=Object.freeze({maxResponseBytes:16384,maxTotalResponseBytes:131072,maxNodes:2048,maxDepth:16,
  pageSize:100,maxPages:3,maxThreads:10,maxMailboxBytes:256,maxTargetBytes:2048,maxIdBytes:128,maxTokenBytes:128,
  maxMessages:20,maxLabels:100,maxHeaders:100,maxHeaderUnits:1024,maxCommentDepth:8,
  maxValueNodes:100,maxValueTextBytes:8192,maxRowsWireBytes:16384,maxRowsWireNodes:100,maxRowsWireDepth:8});
const row={id:'t/+',labels:[],last_message_date:'1969-12-31T23:59:59.999Z',message_count:'1',subject:null};
const responses=()=>[{nextPageToken:'opaque/+ ='},{threads:[{id:'t/+'}],nextPageToken:'last'},
  {id:'t/+',messages:[{id:'m',threadId:'t/+',internalDate:'-1',payload:{}}]},{}];
function fixture({afterObservation,malformed=false}={}) {
  const events=[],requests=[],rows=[];let pendingCharge=false,current=true,nextCalls=0,closeCalls=0;
  const provider={...originalProvider,
    gmailNextThreadRequest(...args){nextCalls++;return Reflect.apply(originalProvider.gmailNextThreadRequest,originalProvider,args);},
    gmailCloseThreadRead(...args){closeCalls++;return Reflect.apply(originalProvider.gmailCloseThreadRead,originalProvider,args);}};
  const values=responses();if(malformed)values[2]={id:'foreign',messages:[]};
  const sequence=prepareGmailThreadReadSequence({moon:provider,mailbox:'support+box@example.test',names:['id'],limits},
    (method,receiver,args)=>Reflect.apply(method,receiver,args));
  const verify=()=>{if(!current)throw new Error('original-current-refusal');};
  const context={project(method,receiver,args){verify();assert.equal(pendingCharge,false);
      const value=Reflect.apply(method,receiver,args);verify();return value;},
    async readChild(input){verify();assert.equal(pendingCharge,false);const prepared=input.prepare();
      assert.equal(typeof prepared.original,'object');
      const selected=JSON.parse(originalProvider.gmailThreadRequestJson(prepared.original));
      assert.equal(selected.ordinal,requests.length);assert.equal(selected.mailbox,'support+box@example.test');
      assert.equal(input.operation,selected.isList?'gmail:threads:list':'gmail:threads:get');
      requests.push(prepared.request);events.push(input.operation);pendingCharge=true;
      return prepared.project({accepted:true,statusCode:200,body:Buffer.from(JSON.stringify(values[requests.length-1]))});
    },async consumeObservation(){verify();assert.equal(pendingCharge,true);events.push('consume-observation');
      pendingCharge=false;await afterObservation?.(()=>{current=false;});verify();},
    async consumePage(value){verify();assert.equal(pendingCharge,true);events.push('consume-row');
      rows.push(...value);pendingCharge=false;},
  };
  return{sequence,events,requests,rows,context,counts:()=>({nextCalls,closeCalls,pendingCharge}),
    read:()=>sequence.read(context)};
}

test('same compiled Gmail control consumes every empty list and dependent get before its next original',async()=>{
  const f=fixture();await f.read();assert.deepEqual(f.rows,[row]);
  assert.deepEqual(f.events,['gmail:threads:list','consume-observation','gmail:threads:list','consume-observation',
    'gmail:threads:get','consume-row','gmail:threads:list','consume-observation']);
  assert.equal(f.requests[2].path,'/gmail/v1/users/support%2Bbox%40example.test/threads/t%2F%2B');
  assert.deepEqual(f.requests[2].query,[['format','metadata'],['metadataHeaders','Subject'],['metadataHeaders','Date'],
    ['fields','id,messages(id,threadId,labelIds,internalDate,payload(headers(name,value)))']]);
  assert.equal(f.requests[1].query.at(-1)[1],'opaque/+ =');
  assert.equal(f.sequence.retire(),true);assert.equal(f.sequence.retire(),true);assert.equal(f.counts().closeCalls,1);
  await assert.rejects(f.read(),{code:'GmailThreadReaderAlreadyStarted'});
});

test('same Gmail sequence cannot issue another nominal request after awaited current refusal',async()=>{
  const f=fixture({afterObservation:async revoke=>{await Promise.resolve();revoke();}});
  await assert.rejects(f.read(),/original-current-refusal/);assert.equal(f.requests.length,1);
  assert.equal(f.counts().nextCalls,1);assert.deepEqual(f.rows,[]);assert.equal(f.sequence.retire(),true);
  assert.equal(f.counts().closeCalls,1);
});

test('malformed original get keeps its outstanding charge and cannot retry or return partial rows',async()=>{
  const f=fixture({malformed:true});await assert.rejects(f.read());assert.equal(f.requests.length,3);
  assert.equal(f.counts().pendingCharge,true);assert.deepEqual(f.rows,[]);
  assert.equal(f.sequence.retire(),true);assert.equal(f.counts().closeCalls,1);
  await assert.rejects(f.read(),{code:'GmailThreadReaderAlreadyStarted'});
});

test('same Gmail sequence cannot retire its control while an original observation consumer is pending',async()=>{
  let enter,release;const entered=new Promise(resolve=>{enter=resolve;}),wait=new Promise(resolve=>{release=resolve;});
  const f=fixture({afterObservation:async()=>{enter();await wait;}});const original=f.read();await entered;
  assert.equal(f.sequence.retire(),false);assert.equal(f.counts().closeCalls,0);assert.equal(f.requests.length,1);
  release();await original;assert.equal(f.sequence.retire(),true);assert.equal(f.counts().closeCalls,1);
});

test('shared Gmail reader retains separate original operation grants responses and binding until same retirement',async t=>{
  const path='/gmail/v1/users/support%2Bbox%40example.test/threads';
  const server=await openHttpsExchangeFixture(t,{routes:[{method:'GET',pathname:path,
    handle:()=>({body:{threads:[{id:'t/+'}]}})},{method:'GET',pathname:path+'/t%2F%2B',
    handle:()=>({body:responses()[2]})}]});
  const scope=Object.freeze({issuerAuthority:'authority',principal:'principal',namespaceId:'fixture',environment:'test',
    siteKey:'gmail',siteGeneration:1,runtimeBundleCid:'runtime',connectorRegistration:'gmail',connectorRevision:'gmail/0.1',
    resourceOrigin:server.origin,runInvocationCid:'run',taskAttempt:1,dispatchRequestCid:'dispatch',operation:'gmail:threads:list'});
  const list=Object.freeze({grant:{},scope}),get=Object.freeze({grant:{},scope:Object.freeze({...scope,operation:'gmail:threads:get'})});
  const control={identity:grant=>grant===list.grant?'list-grant':'get-grant'};
  const journal={claim(identity){const grant=identity==='list-grant'?list.grant:get.grant;
      return {replayed:false,grant,use:{},record:{useCid:'use',grantCid:identity}};},
    authorize(){},finish(){}};
  let credential,closeCalls=0,retireReady=false,protocolCloses=0,charges=0,observations=0;const rows=[];
  const originalSite={site:{},referenceCurrent:()=>true,
    authorizationPurpose(original){assert.equal(original,list);return {kind:'read'};},
    bindRunAcquisition(original,callbacks){assert.equal(original,list);callbacks.assertCurrent();
      const resolveSecret=async()=> 'fixture-secret';
      const binding=openHttpsCredentialBinding({scope,control,journal,resolveSecret,maxSecretBytes:128,
        assertCurrent:callbacks.assertCurrent});
      credential=Object.freeze({binding,control,journal,resolveSecret,ca:server.ca,currentBeforeSend:callbacks.observeCurrent});
      return Object.freeze({credential,close(){closeCalls++;return closeHttpsCredentialBinding(binding);},
        retire(){return retireReady;}});
    },readChildCredential(acquisition,original){assert.equal(acquisition.credential,credential);
      assert(original===list||original===get);return credential;},callResource:callHttpsCredentialResource};
  const provider={...originalProvider,gmailCloseThreadRead(...args){protocolCloses++;
    return Reflect.apply(originalProvider.gmailCloseThreadRead,originalProvider,args);}};
  const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent(){},maxResponses:13,
    maxResponseBytes:limits.maxResponseBytes,maxTotalResponseBytes:limits.maxTotalResponseBytes,
    prepareReadSequence({columns},apply){return prepareGmailThreadReadSequence({moon:provider,
      mailbox:'support+box@example.test',names:columns,limits},apply);}});
  const originals=new WeakSet();
  const reader=factory.prepare({resource:'threads',columns:['id'],originalAuthorization:list,verifyRead(){},
    authorizationFor(index){assert.equal(index,0);return {...list,useId:'list-0'};},
    authorizeReadChild(operation,index,original){assert.equal(originals.has(original),false);originals.add(original);
      const selected=operation==='gmail:threads:list'?list:get;
      return {originalAuthorization:selected,authorization:{...selected,useId:'request-'+index}};},
    chargePage(){charges++;return {ordinal:charges};},consumeObservation(){observations++;},
    consumePage(value){rows.push(...value);}});
  try{
    assert.deepEqual(await reader.read(),{pages:2,rowCount:1});assert.deepEqual(rows,[row]);
    assert.equal(charges,2);assert.equal(observations,1);assert.equal(server.seen().length,2);
    reader.requestStop();assert.equal(reader.observe().transportClosed,true);
    assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(protocolCloses,1);
    retireReady=true;reader.retry();assert.equal(reader.observe().cleanupConfirmed,true);
    assert.equal(factory.retire(),true);assert.equal(closeCalls,1);assert.equal(protocolCloses,1);
  }finally{retireReady=true;reader.requestStop();factory.retire();}
});
