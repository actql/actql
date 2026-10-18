// Physical adaptation of the existing Slack reader to one original RowRun.
// Common, Account, Credential and Resource keep their existing responsibilities.
import {types} from 'node:util';
import {ownInvocationAuthorization,invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {openHttpsCredentialBinding,closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';
import {createSlackChannelListReader,SLACK_CHANNEL_LIST_OPERATION,SLACK_WORKSPACE_IDENTITY_OPERATION} from '../site/channel-list-read.mjs';

const fail=code=>{throw Object.assign(new Error(code),{code});};
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed();
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const providerNames=['slackProjectChannelList','slackChannelListIds','slackChannelListRowsWire',
  'slackChannelListMetadataJson','slackChannelListColumnNames','slackProjectWorkspaceIdentity','slackWorkspaceIdentityMatches'];
function data(value,name){
  if(value===null||typeof value!=='object'||types.isProxy(value))fail('InvalidInstalledSlackReader');
  const descriptor=Object.getOwnPropertyDescriptor(value,name);
  if(!descriptor?.enumerable||!Object.hasOwn(descriptor,'value'))fail('InvalidInstalledSlackReader');
  return descriptor.value;
}
function methods(value,names){
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const method=data(value,name);if(typeof method!=='function')fail('InvalidInstalledSlackReader');
    return[name,method];
  })));
}

export function createSlackChannelSourceReaderFactory({provider,site,capacity,workspaceId,limits,maxSecretBytes}){
  if(capacity===undefined||capacity===null)fail('SlackReaderCapacityUnavailable');
  if(!text(workspaceId)||!positive(maxSecretBytes)||!positive(limits?.maxPages))fail('InvalidInstalledSlackReader');
  const ports=methods(provider,providerNames),sitePorts=methods(site,['issueReadGrant']);
  const credential=data(site,'credential'),bounded=Object.freeze({...limits});
  const selectedProvider=Object.freeze(Object.fromEntries(providerNames.map(name=>[
    name,(...args)=>Reflect.apply(ports[name],provider,args)])));
  const preparations=new WeakSet();
  const factory=Object.freeze({capacity,prepare(options){
    if(this!==factory)fail('ForeignInstalledSlackReaderFactory');
    const rowRun=data(options,'rowRun'),acquisition=data(rowRun,'acquisition');
    if(acquisition===null||typeof acquisition!=='object'||preparations.has(acquisition))fail('InstalledSlackReaderAlreadyPrepared');
    if(data(options,'resource')!=='channels'||data(options,'operation')!==SLACK_CHANNEL_LIST_OPERATION)fail('ForeignInstalledSlackRead');
    const run=data(rowRun,'run'),requestId=data(rowRun,'requestId'),
      runInvocationCid=data(rowRun,'runInvocationCid'),dispatchRequestCid=data(rowRun,'dispatchRequestCid');
    if(!run||!text(requestId)||!text(runInvocationCid)||!text(dispatchRequestCid))fail('InvalidInstalledSlackReader');
    const callbacks=methods(options,['verifyRead','authorizationFor','chargePage','consumeObservation','consumePage']);
    const invoke=(name,...args)=>Reflect.apply(callbacks[name],options,args);
    const selectedNames=data(options,'columns');
    if(!Array.isArray(selectedNames))fail('InvalidInstalledSlackReader');
    const names=Object.freeze(selectedNames.slice()),stop=new AbortController(),originalSignal=data(options,'signal');
    const signal=originalSignal===undefined?stop.signal:AbortSignal.any([originalSignal,stop.signal]);
    preparations.add(acquisition);
    let phase='ready',child,childPorts,binding,transportClosed=false,
      originalFailure,transportFailure,observationFailure,initial,identityAuthorization,readResult,stopResult;
    const verify=async operation=>{
      if(operation!==SLACK_CHANNEL_LIST_OPERATION&&operation!==SLACK_WORKSPACE_IDENTITY_OPERATION)fail('ForeignInstalledSlackOperation');
      signal.throwIfAborted();const decision=await invoke('verifyRead');signal.throwIfAborted();return decision;
    };
    const closeTransport=()=>{
      if(binding!==undefined&&!transportClosed){
        try{transportClosed=closeHttpsCredentialBinding(binding)==='closed';}
        catch(cause){transportFailure??=cause;throw cause;}
      }
    };
    const authorizationFor=async({operation,index})=>{
      if(operation===SLACK_CHANNEL_LIST_OPERATION){
        if(!Number.isSafeInteger(index)||index<0||index>=bounded.maxPages)fail('InvalidInstalledSlackReadOrdinal');
        const authorization=ownInvocationAuthorization(await invoke('authorizationFor',index));
        if(authorization.scope.operation!==operation||!invocationBindingsMatch(authorization.scope,initial.scope))fail('ForeignInstalledSlackRead');
        await verify(operation);return authorization;
      }
      if(operation!==SLACK_WORKSPACE_IDENTITY_OPERATION||index!==0||identityAuthorization!==undefined)fail('ForeignInstalledSlackIdentity');
      const decision=await verify(operation);
      // The same Site issues a separate original operation grant. Observing a
      // workspace never retargets the conversations.list grant or grants API rights.
      const grant=Reflect.apply(sitePorts.issueReadGrant,site,[{operation,decision,resource:'channels',
        runInvocationCid,dispatchRequestCid,maxUses:1}]);
      const authorization=ownInvocationAuthorization({...grant,useId:requestId+'-workspace-identity-0'});
      if(authorization.scope.operation!==operation||!invocationBindingsMatch(authorization.scope,initial.scope))fail('ForeignInstalledSlackIdentity');
      identityAuthorization=authorization;
      await verify(operation);return authorization;
    };
    const handle=Object.freeze({
      async read(){
        if(this!==handle)fail('ForeignInstalledSlackReader');
        if(phase!=='ready')fail('InstalledSlackReaderAlreadyStarted');phase='reading';
        try{
          await verify(SLACK_CHANNEL_LIST_OPERATION);
          initial=ownInvocationAuthorization(await invoke('authorizationFor',0));
          if(initial.scope.operation!==SLACK_CHANNEL_LIST_OPERATION||initial.scope.runInvocationCid!==runInvocationCid||
              initial.scope.dispatchRequestCid!==dispatchRequestCid)fail('ForeignInstalledSlackRun');
          await verify(SLACK_CHANNEL_LIST_OPERATION);
          binding=openHttpsCredentialBinding({...credential,scope:initial.scope,maxSecretBytes});
          child=createSlackChannelListReader({moon:selectedProvider,workspaceId,names,initialAuthorization:initial,
            credential:{...credential,binding},authorizationFor,current:verify,limits:bounded,signal,
            chargeResponse:(...args)=>invoke('chargePage',...args),
            consumeObservation:(...args)=>invoke('consumeObservation',...args),
            consumePage:(...args)=>invoke('consumePage',...args)});
          // Keep the actual child before reading any getter or awaiting it.
          childPorts=methods(child,['read','requestStop','observe']);
          readResult=Reflect.apply(childPorts.read,child,[]);
          const result=await readResult;
          await verify(SLACK_CHANNEL_LIST_OPERATION);phase='succeeded';return result;
        }catch(cause){phase='failed';originalFailure=cause;throw cause;}
        finally{try{closeTransport();}catch(cause){if(originalFailure===undefined)throw cause;}}
      },
      requestStop(reason){
        if(this!==handle)fail('ForeignInstalledSlackReader');
        stop.abort(reason);
        try{if(childPorts!==undefined)stopResult=Reflect.apply(childPorts.requestStop,child,[reason]);}
        finally{closeTransport();}
        return stopResult;
      },
      observe(){
        if(this!==handle)fail('ForeignInstalledSlackReader');
        let observed;
        try{if(childPorts!==undefined)observed=Reflect.apply(childPorts.observe,child,[]);}
        catch(cause){observationFailure??=cause;throw cause;}
        // Physical transport closure cannot retire escaped raw/error/Promise
        // aliases or return their original RowRun reservation.
        return Object.freeze({phase,transportClosed,child:observed,
          transportFailure:transportFailure!==undefined,observationFailure:observationFailure!==undefined,
          cleanupConfirmed:false});
      },
    });
    return handle;
  }});
  return factory;
}
