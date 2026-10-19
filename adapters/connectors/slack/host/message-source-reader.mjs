// Physical realization of one original messages RowRun. Common owns checked
// conversation/history/reply prefixes, coalescence, row admission and capture.
import {types} from 'node:util';
import {ownInvocationAuthorization,invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {createSlackConversationListReaderForHistory,selectSlackOriginalChannel,
  SLACK_CHANNEL_LIST_OPERATION} from '../site/channel-list-read.mjs';
import {createSlackMessageHistoryReaderFromChannel,createSlackMessageRepliesReader,
  coalesceSlackMessageReaders,SLACK_MESSAGE_HISTORY_OPERATION,SLACK_MESSAGE_REPLIES_OPERATION,
  SLACK_WORKSPACE_IDENTITY_OPERATION} from '../site/message-history-read.mjs';

const fail=code=>{throw Object.assign(new Error(code),{code});};
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed();
const operations=new Set([SLACK_CHANNEL_LIST_OPERATION,SLACK_MESSAGE_HISTORY_OPERATION,
  SLACK_MESSAGE_REPLIES_OPERATION,SLACK_WORKSPACE_IDENTITY_OPERATION]);
const providerNames=['slackProjectChannelList','slackProjectHistoryConversationList','slackChannelListIds',
  'slackChannelListRowsWire','slackChannelListMetadataJson','slackChannelListColumnNames',
  'slackProjectWorkspaceIdentity','slackWorkspaceIdentityMatches','slackPrepareMessageHistoryFromChannel',
  'slackMessageHistoryMatchesChannel','slackAdmitMessageHistoryPage','slackMessageHistoryRequestMatches',
  'slackMessagePageRowsWire','slackMessagePageRowCount','slackMessageColumnNames',
  'slackPrepareMessageHistory','slackBeginMessageHistory','slackMessageHistoryRequestJson',
  'slackMessageHistoryPageHasNext','slackNextMessageHistoryRequest','slackFinishMessageHistory',
  'slackCloseMessageHistory','slackPrepareMessageReplies','slackMessageRepliesMatchesOriginal',
  'slackBeginMessageReplies','slackMessageRepliesRequestMatches','slackMessageRepliesRequestJson',
  'slackAdmitMessageRepliesPage','slackMessageRepliesPageHasNext','slackNextMessageRepliesRequest',
  'slackFinishMessageReplies','slackMessageRepliesPageRowCount','slackMessageRepliesPageRowsWire',
  'slackCloseMessageReplies','slackCoalesceMessageOriginals','slackMessageProjectionRowCount',
  'slackMessageProjectionRowsWire'];
function data(value,name){
  if(value===null||typeof value!=='object'||types.isProxy(value))fail('InvalidInstalledSlackMessagesReader');
  const d=Object.getOwnPropertyDescriptor(value,name);
  if(!d?.enumerable||!Object.hasOwn(d,'value'))fail('InvalidInstalledSlackMessagesReader');
  return d.value;
}
function methods(value,names){
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const method=data(value,name);if(typeof method!=='function')fail('InvalidInstalledSlackMessagesReader');
    return[name,method];
  })));
}

export function createSlackMessageSourceReaderFactory({provider,site,capacity,workspaceId,limits,maxSecretBytes}){
  if(capacity===undefined||capacity===null)fail('SlackReaderCapacityUnavailable');
  if(!text(workspaceId)||!positive(maxSecretBytes)||
      !['maxPages','maxTotalRows','maxNodes','maxDepth','maxValueTextBytes'].every(k=>positive(limits?.[k]))) {
    fail('InvalidInstalledSlackMessagesReader');
  }
  const ports=methods(provider,providerNames),sitePorts=methods(site,['issueReadGrant']);
  const credential=data(site,'credential'),bounded=Object.freeze({...limits});
  const selectedProvider=Object.freeze(Object.fromEntries(providerNames.map(name=>[
    name,(...args)=>Reflect.apply(ports[name],provider,args)])));
  const preparations=new WeakSet();
  const factory=Object.freeze({capacity,prepare(options){
    if(this!==factory)fail('ForeignInstalledSlackReaderFactory');
    if(data(options,'resource')!=='messages'||data(options,'operation')!==SLACK_MESSAGE_HISTORY_OPERATION)fail('ForeignInstalledSlackRead');
    const rowRun=data(options,'rowRun'),acquisition=data(rowRun,'acquisition');
    if(acquisition===null||typeof acquisition!=='object'||preparations.has(acquisition))fail('InstalledSlackReaderAlreadyPrepared');
    const run=data(rowRun,'run'),requestId=data(rowRun,'requestId'),runInvocationCid=data(rowRun,'runInvocationCid'),
      dispatchRequestCid=data(rowRun,'dispatchRequestCid');
    if(!run||!text(requestId)||!text(runInvocationCid)||!text(dispatchRequestCid))fail('InvalidInstalledSlackMessagesReader');
    const callbacks=methods(options,['verifyRead','authorizationFor','chargePage','consumeObservation','consumePage']);
    const invoke=(name,...args)=>Reflect.apply(callbacks[name],options,args);
    const columns=data(options,'columns');if(!Array.isArray(columns))fail('InvalidInstalledSlackMessagesReader');
    const names=Object.freeze(columns.slice()),stop=new AbortController(),originalSignal=data(options,'signal');
    const signal=originalSignal===undefined?stop.signal:AbortSignal.any([originalSignal,stop.signal]);
    preparations.add(acquisition);
    let phase='ready',initial,binding,transportClosed=false,pending,requestCount=0,bodyBytes=0,
      observedRows=0,outputRows=0,originalFailure,transportFailure,observationFailure;
    const children=[],channelPages=[],histories=[],projections=[],grants=new Map();
    const verify=async operation=>{
      if(!operations.has(operation))fail('ForeignInstalledSlackOperation');
      signal.throwIfAborted();const decision=await invoke('verifyRead');signal.throwIfAborted();return decision;
    };
    const closeTransport=()=>{
      if(binding!==undefined&&!transportClosed){
        try{transportClosed=closeHttpsCredentialBinding(binding)==='closed';}
        catch(cause){transportFailure??=cause;throw cause;}
      }
    };
    const consumePrevious=async()=>{
      if(pending!==undefined){
        const original=pending;await invoke('consumeObservation',original);pending=undefined;
      }
    };
    const operationGrant=(operation,decision)=>{
      let grant=grants.get(operation);
      if(grant===undefined){
        grant=Reflect.apply(sitePorts.issueReadGrant,site,[{operation,decision,resource:'messages',
          runInvocationCid,dispatchRequestCid,maxUses:bounded.maxPages}]);
        grants.set(operation,grant);
      }
      return grant;
    };
    const initialFor=async operation=>{
      const decision=await verify(operation);
      const authorization=ownInvocationAuthorization({...operationGrant(operation,decision),
        useId:requestId+'-initial-'+operation});
      if(authorization.scope.operation!==operation||!invocationBindingsMatch(authorization.scope,initial.scope))fail('ForeignInstalledSlackRead');
      await verify(operation);return authorization;
    };
    const authorizationFor=async({operation,index})=>{
      await verify(operation);
      if(!Number.isSafeInteger(index)||index<0||index>=bounded.maxPages||requestCount>=bounded.maxPages) {
        fail('InstalledSlackMessagesRequestLimit');
      }
      // One pending ticket at all times. Earlier tickets account for their
      // actual responses; retained nominal readers, not this last ticket,
      // supply the original multi-response projection prefix.
      await consumePrevious();const decision=await verify(operation);
      let authorization;
      if(operation===SLACK_MESSAGE_HISTORY_OPERATION){
        authorization=ownInvocationAuthorization(await invoke('authorizationFor',requestCount));
      }else{
        authorization=ownInvocationAuthorization({...operationGrant(operation,decision),useId:requestId+'-'+operation+'-'+requestCount});
      }
      if(authorization.scope.operation!==operation||!invocationBindingsMatch(authorization.scope,initial.scope))fail('ForeignInstalledSlackRead');
      await verify(operation);requestCount++;return authorization;
    };
    const chargeResponse=async body=>{
      if(pending!==undefined)fail('InstalledSlackMessagesPendingCharge');
      pending=await invoke('chargePage',body);
      if(body.byteLength>bounded.maxTotalResponseBytes-bodyBytes)fail('InstalledSlackMessagesResponseLimit');
      bodyBytes+=body.byteLength;return pending;
    };
    const checkPage=(rows,metadata)=>{
      if(metadata.charge!==pending||pending===undefined)fail('ForeignInstalledSlackMessagesCharge');
      if(rows.length>bounded.maxTotalRows-observedRows)fail('InstalledSlackMessagesOccurrenceLimit');
      observedRows+=rows.length;
    };
    const deferObservation=charge=>{if(charge!==pending||pending===undefined)fail('ForeignInstalledSlackMessagesCharge');};
    const child=reader=>{const captured=methods(reader,['read','requestStop','observe']);
      const entry={reader,captured};children.push(entry);return entry;};
    const readChild=entry=>Reflect.apply(entry.captured.read,entry.reader,[]);
    const shared=()=>({moon:selectedProvider,workspaceId,credential:{...credential,binding},
      authorizationFor,limits:{...bounded,maxComparisonNodes:bounded.maxNodes,maxComparisonDepth:bounded.maxDepth,
        maxComparisonTextBytes:bounded.maxValueTextBytes,maxWork:bounded.maxNodes},current:verify,
      chargeResponse,consumeObservation:deferObservation,signal});
    const append=async rows=>{
      await verify(SLACK_MESSAGE_HISTORY_OPERATION);
      if(pending===undefined)fail('InstalledSlackMessagesOriginalChargeUnavailable');
      if(rows.length>bounded.maxTotalRows-outputRows)fail('InstalledSlackMessagesRowLimit');
      const original=pending;await invoke('consumePage',rows,{charge:original});pending=undefined;
      await verify(SLACK_MESSAGE_HISTORY_OPERATION);outputRows+=rows.length;
    };
    const handle=Object.freeze({
      async read(){
        if(this!==handle)fail('ForeignInstalledSlackReader');
        if(phase!=='ready')fail('InstalledSlackReaderAlreadyStarted');phase='reading';
        try{
          await verify(SLACK_MESSAGE_HISTORY_OPERATION);
          initial=ownInvocationAuthorization(await invoke('authorizationFor',0));
          if(initial.scope.operation!==SLACK_MESSAGE_HISTORY_OPERATION||initial.scope.runInvocationCid!==runInvocationCid||
              initial.scope.dispatchRequestCid!==dispatchRequestCid)fail('ForeignInstalledSlackRun');
          await verify(SLACK_MESSAGE_HISTORY_OPERATION);
          binding=openHttpsCredentialBinding({...credential,scope:initial.scope,maxSecretBytes});
          // Binding preparation is not an exchange and does not claim a use.
          const channelAuthorization=await initialFor(SLACK_CHANNEL_LIST_OPERATION);
          const channels=child(createSlackConversationListReaderForHistory({...shared(),names:['id'],
            initialAuthorization:channelAuthorization,consumePage:(rows,metadata)=>{
              checkPage(rows,metadata);channelPages.push({token:metadata.originalPage,count:rows.length});
            }}));
          await readChild(channels);await verify(SLACK_CHANNEL_LIST_OPERATION);
          for(const page of channelPages)for(let index=0;index<page.count;index++){
            const selection=selectSlackOriginalChannel(channels.reader,page.token,index),pages=[],replies=[];
            const history=child(createSlackMessageHistoryReaderFromChannel({...shared(),channelSelection:selection,
              names:Reflect.apply(ports.slackMessageColumnNames,provider,[]),initialAuthorization:initial,
              consumePage:(rows,metadata)=>{checkPage(rows,metadata);pages.push({token:metadata.originalPage,count:rows.length});}}));
            histories.push({history,pages,replies});await readChild(history);
            for(const observed of pages)for(let row=0;row<observed.count;row++){
              const replyAuthorization=await initialFor(SLACK_MESSAGE_REPLIES_OPERATION);
              const reply=child(createSlackMessageRepliesReader({...shared(),historyReader:history.reader,
                originalPage:observed.token,index:row,names:[],initialAuthorization:replyAuthorization,
                consumePage:(rows,metadata)=>checkPage(rows,metadata)}));
              replies.push(reply);await readChild(reply);
            }
            const projection=await coalesceSlackMessageReaders({historyReader:history.reader,
              replyReaders:replies.map(entry=>entry.reader),names,signal,limits:{maxRows:bounded.maxTotalRows,
                maxOccurrences:bounded.maxTotalRows,maxWork:bounded.maxNodes,maxComparisonNodes:bounded.maxNodes,
                maxComparisonDepth:bounded.maxDepth,maxComparisonTextBytes:bounded.maxValueTextBytes,
                maxRowsWireBytes:bounded.maxRowsWireBytes,maxRowsWireNodes:bounded.maxRowsWireNodes,
                maxRowsWireDepth:bounded.maxRowsWireDepth}});
            projections.push(projection);await append(projection.rows);
          }
          if(histories.length===0)await append([]);
          await verify(SLACK_MESSAGE_HISTORY_OPERATION);phase='succeeded';
          return Object.freeze({rowCount:outputRows,cleanupConfirmed:false});
        }catch(cause){phase='failed';originalFailure=cause;throw cause;}
        finally{try{closeTransport();}catch(cause){if(originalFailure===undefined)throw cause;}}
      },
      requestStop(reason){
        if(this!==handle)fail('ForeignInstalledSlackReader');stop.abort(reason);
        try{for(const entry of children)Reflect.apply(entry.captured.requestStop,entry.reader,[reason]);}
        finally{closeTransport();}
      },
      observe(){
        if(this!==handle)fail('ForeignInstalledSlackReader');
        const observations=[];
        try{for(const entry of children)observations.push(Reflect.apply(entry.captured.observe,entry.reader,[]));}
        catch(cause){observationFailure??=cause;throw cause;}
        return Object.freeze({phase,transportClosed,children:Object.freeze(observations),
          pendingCharge:pending!==undefined,transportFailure:transportFailure!==undefined,
          observationFailure:observationFailure!==undefined,cleanupConfirmed:false});
      },
    });
    return handle;
  }});
  return factory;
}
