// Local STORE uses the existing Row Effect/Preview/claim/publication owner.
// This installer retains the original Project/Account/collection and delegates
// only the approved byte transfer to the existing physical Root child.
import {createHash,randomUUID} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {authorizationDispatchFacts,assertAuthorizationAccountCurrent}
  from '../../../host-common/authorization-gate.mjs';
import {createInstalledRowEffect,retainInstalledRowEffectAdapter,
  installedRowEffectOwnerBinding} from '../../../host-node/installed-row-effect.mjs';
import {composeInstalledEffects} from '../../../host-node/installed-effect-inventory.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {prepareLocalFileStoreTarget} from './local-file-store-target.mjs';
import {prepareLocalStoredContentWrite} from '../site/root-stored-content-writer.mjs';

const wire=value=>canonicalJson(value,{dataKeys:true});
const cid=value=>'sha256:'+createHash('sha256').update(wire(value)).digest('hex');
const isCid=value=>typeof value==='string'&&/^sha256:[0-9a-f]{64}$/u.test(value);
const fail=(code,cause)=>{throw Object.assign(new Error(code,{cause}),{code});};
const closed=(value,keys)=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
  Object.keys(value).sort().join('\0')===[...keys].sort().join('\0');
const synchronous=value=>{
  if(value!==undefined){
    if(value instanceof Promise)void value.catch(()=>{});
    fail('InvalidLocalStoreCurrentFence');
  }
};
const declarationLimits=Object.freeze({maxBytes:131072,maxNodes:16384,maxDepth:64});
export const LOCAL_STORE_LIMITS=Object.freeze({maxRows:100,maxRequestBytes:100000,
  maxResponseBytes:65536,maxEffects:16});

export async function installPreparedProjectLocalFileEffects({moon,preparation,sourceManaged,
  baseEnvironmentWire,authorizationFor,principalId,runtimeBundleCid,ledgerRoot,
  nativeFilesystem,effectResources,sourceBindings}) {
  if(typeof preparation?.originalsForRuntime!=='function'||
      typeof sourceManaged?.assertCurrent!=='function'||typeof authorizationFor!=='function'||
      typeof principalId!=='string'||!isCid(runtimeBundleCid)||typeof ledgerRoot!=='string'||
      !Array.isArray(sourceBindings))fail('InvalidLocalFileEffectInstallation');
  const bundle=preparation.originalsForRuntime(moon);
  const resources=Object.freeze(Object.fromEntries(['bindRunOriginal','assertCurrent','limits'].map(name=>{
    const method=Object.getOwnPropertyDescriptor(effectResources??{},name)?.value;
    if(typeof method!=='function')fail('LocalStoreEffectResourcesUnavailable');
    return[name,(...args)=>Reflect.apply(method,effectResources,args)];
  })));
  const current=()=>{
    synchronous(sourceManaged.assertCurrent());
    if(preparation.originalsForRuntime(moon)!==bundle)fail('ForeignLocalFilesPreparation');
  };
  current();
  // These selectors name already admitted Project entries, not new profile
  // reads. Reuse the existing installation inventory and partial-close owner.
  const effects=await composeInstalledEffects(bundle.sources.map(entry=>entry.connection),
    {moon,baseEnvironmentWire},async(connection,_options,retain)=>{
      current();
      const entries=bundle.sources.filter(entry=>entry.connection===connection);
      if(entries.length!==1)fail('InvalidLocalFileEffectInstallation');
      const entry=entries[0],authorization=await authorizationFor(connection);
      current();
      const bindingCid=cid({scope:entry.scopeCid,declaration:entry.wire,
        account_context:authorization.context.contextCid});
      const binding=sourceBindings.filter(value=>value.connectorId===entry.connectorId);
      if(binding.length!==1||binding[0].bindingCid!==bindingCid)
        fail('ForeignLocalFileEffectInstallation');
      const target=prepareLocalFileStoreTarget(moon,{declaredWire:entry.wire,
        connectorId:entry.connectorId,rootPath:entry.rootPath,scopeCid:entry.scopeCid,
        authorityScopeCid:authorization.context.contextCid,assertCurrent:current,...declarationLimits});
      const declared=JSON.parse(target.declarationWire),command=JSON.parse(target.commandWire),
        mapping=JSON.parse(target.mappingWire);
      const environment=rowSourceCheckEnvironment(baseEnvironmentWire,declared,[target.mappingWire]);
      const limits=Object.freeze({...LOCAL_STORE_LIMITS,maxFileBytes:entry.limits.maxFileBytes});
      const {driver,site}=createLocalFileStoreDriver({entry,target,command,bindingCid,principalId,
        authorization,assertCurrent:current,resources,limits,nativeFilesystem});
      let effect;
      try{
        effect=await createInstalledRowEffect({moon,
          mappings:[{resource:'files',mappingRef:mapping.mapping_ref,
            mappingCid:mapping.mapping_contract_cid,body:target.mappingWire}],
          commands:[{resource:'files',commandRef:command.command_id,
            commandCid:command.contract_cid,body:target.commandWire}],
          environmentWire:environment.wire,connectorId:entry.connectorId,
          connectorRegistration:'local',connectorRevision:'local/0.1',connection,
          site,authorization,runtimeBundleCid,bindingCid,ledgerRoot,driver,effectResources:resources,
          issueOriginalCollectionReference:target.issueOriginalCollectionReference,
          limits:{maxRows:limits.maxRows,maxMembers:limits.maxEffects}});
        retain(effect); // Before a current/metadata callback can reject it.
        current();
        const original=installedRowEffectOwnerBinding(effect);
        if(!isCid(original?.cid))fail('ForeignLocalFileEffectInstallation');
        const queryStoreTargets=Object.freeze([Object.freeze({name:connection+'.files',
          targetRef:target.targetRef,installationBindingCid:bindingCid,installationOwnerCid:original.cid})]);
        return retainInstalledRowEffectAdapter(effect,Object.freeze({...effect,queryStoreTargets}));
      }catch(cause){
        if(effect!==undefined)throw cause;
        throw await retainInstalledHostInitializationFailure(cause,{installedEffect:{close:site.close}});
      }
    });
  try{
    current();
    return Object.freeze({...effects,
      queryStoreTargets:Object.freeze(effects.effects.flatMap(effect=>effect.queryStoreTargets))});
  }catch(cause){
    throw await retainInstalledHostInitializationFailure(cause,{installedEffect:effects});
  }
}

// This physical adapter receives the original Account decision and Run port;
// request DATA cannot construct either. The native child performs no I/O until
// send, after the existing durable claim and explicit whole-Preview approval.
export function createLocalFileStoreDriver({entry,target,command,bindingCid,principalId,
  authorization,assertCurrent,resources,limits,nativeFilesystem}) {
  const requests=new WeakMap(),descriptions=new WeakMap(),grants=new WeakMap(),children=new Set();
  let closing=false;
  const current=()=>{if(closing)fail('LocalStoreInstallationClosing');synchronous(assertCurrent());};
  const runCurrent=runOriginal=>{
    current();
    if(runOriginal===null||typeof runOriginal!=='object')fail('ForeignLocalStoreRun');
    synchronous(resources.assertCurrent(runOriginal));
    const actual=resources.limits(runOriginal);
    if(Object.entries(limits).some(([name,value])=>!Number.isSafeInteger(actual?.[name])||actual[name]<value))
      fail('LocalStoreEffectLimitsUnavailable');
    current();
  };
  const memberCurrent=member=>{
    current();
    if(member.kind!=='command'||member.resource!=='files'||
        member.command.commandRef!==command.command_id||member.command.commandCid!==command.contract_cid)
      fail('ForeignLocalStoreMember');
  };
  const description=(value,runOriginal)=>{
    const original=descriptions.get(value);
    if(original===undefined||runOriginal!==undefined&&original.runOriginal!==runOriginal)
      fail('ForeignLocalStoreDescription');
    runCurrent(original.runOriginal);return original;
  };
  const own=(request,runOriginal)=>{
    const original=requests.get(request);
    if(original===undefined||original.released||
        runOriginal!==undefined&&original.runOriginal!==runOriginal)fail('ForeignLocalStoreRequest');
    runCurrent(original.runOriginal);return original;
  };
  const validPath=path=>typeof path==='string'&&path.length>0&&path.isWellFormed()&&
    !path.includes('\0')&&!isAbsolute(path)&&Buffer.byteLength(path)<=entry.limits.maxPathBytes&&
    path.split('/').length<=128&&path.split('/').every(part=>part!=='.'&&part!=='..'&&
      part.length>0&&Buffer.byteLength(part)<=1024);
  const requestFrom=(record,runOriginal,borrow,contentOwner)=>{
    runCurrent(runOriginal);
    if(!closed(record,['binding','command','target','value'])||record.binding!==bindingCid||
        record.command!==command.contract_cid||wire(record.target)!==target.resourceWire||
        !closed(record.value,['content','path',...(Object.hasOwn(record.value??{},'overwrite')?['overwrite']:[])])||
        !validPath(record.value.path)||record.value.content===null||typeof record.value.content!=='object'||
        Object.hasOwn(record.value,'overwrite')&&typeof record.value.overwrite!=='boolean'||
        Buffer.byteLength(wire(record))>limits.maxRequestBytes)fail('InvalidLocalStoreRequest');
    const immutable=JSON.parse(wire(record));
    Object.freeze(immutable.target);Object.freeze(immutable.value.content);Object.freeze(immutable.value);
    Object.freeze(immutable);
    const request=Object.freeze({});
    requests.set(request,{record:immutable,cid:cid(immutable),runOriginal,borrow,contentOwner,
      writeChild:undefined,released:false});
    return request;
  };
  const decisionCurrent=decision=>{
    current();const facts=authorizationDispatchFacts(decision);
    if(facts?.principal!==principalId||facts.configurationCid!==authorization.configurationCid||
        decision.action!=='dispatch'||decision.boundary!=='effect_commit'||
        decision.tuple?.connection!==entry.connection||decision.tuple?.resource!=='files'||
        decision.tuple?.operation!=='effect'||decision.basis!=='resumed'||
        !isCid(decision.checkpointCid)||!isCid(decision.resolutionCid))fail('LocalStoreNotAuthorized');
    assertAuthorizationAccountCurrent(decision);current();
  };
  const close=async()=>{
    closing=true;
    for(const child of children)await child.release();
    if([...children].some(child=>child.status().pending))fail('LocalStoreCleanupPending');
  };
  const recover=({durable,body,memberIndexes,runOriginal,members,runInvocationCid,dispatches})=>{
    runCurrent(runOriginal);
    if(!Array.isArray(body?.effects)||body.effects.length>limits.maxEffects||
        !Array.isArray(durable?.connectorRecovery))fail('InvalidLocalStoreRecovery');
    const indexes=memberIndexes??body.effects.map((_,index)=>index),restored=[],currents=[];
    let previous=-1;
    for(const index of indexes){
      if(!Number.isSafeInteger(index)||index<=previous||index>=body.effects.length)fail('InvalidLocalStoreRecovery');
      previous=index;
      const matches=durable.connectorRecovery.filter(value=>value.memberIndex===index);
      if(matches.length!==1||matches[0].kind!=='local-file-store'||
          typeof matches[0].wire!=='string'||Buffer.byteLength(matches[0].wire)>limits.maxRequestBytes)
        fail('InvalidLocalStoreRecovery');
      const saved=JSON.parse(matches[0].wire);
      if(!closed(saved,['binding','requests'])||saved.binding!==bindingCid||
          cid(saved)!==matches[0].observationCid||!Array.isArray(saved.requests)||
          saved.requests.length>limits.maxRows||saved.requests.length!==body.effects[index].changes.length)
        fail('InvalidLocalStoreRecovery');
      // Rebuilding approved DATA does not reconstruct a Content read grant.
      // A still-unattempted send must separately bind its restored original.
      restored.push(saved.requests.map(record=>requestFrom(record,runOriginal)));
      memberCurrent(members?.[index]);
      if(!isCid(runInvocationCid)||!isCid(dispatches?.[index]))fail('ForeignLocalStoreDescription');
      const selected=Object.freeze({});
      descriptions.set(selected,{runInvocationCid,dispatchRequestCid:dispatches[index],runOriginal});
      currents.push(selected);
    }
    return{requests:restored,currents};
  };
  const driver=Object.freeze({kinds:Object.freeze(['command']),writeOperation:()=> 'files.write',
    describe({member,runInvocationCid,dispatchRequestCid,runOriginal}){
      memberCurrent(member);runCurrent(runOriginal);
      if(!isCid(runInvocationCid)||!isCid(dispatchRequestCid))fail('ForeignLocalStoreDescription');
      const value=Object.freeze({});descriptions.set(value,{runInvocationCid,dispatchRequestCid,runOriginal});
      return value;
    },
    prepareRequest(){fail('OriginalLocalStoreContentRequired');},
    prepareRequestChild({member,value,selector,current:selected,content,contentOwner,runOriginal}){
      memberCurrent(member);description(selected,runOriginal);
      let request,stopping=false,preparing=false;
      const child=Object.freeze({
        prepare(){
          if(stopping||preparing||request!==undefined)fail('ForeignLocalStoreRequest');
          preparing=true;
          try{
            const borrowed=content('content');
            if(borrowed.current()!==true||borrowed.wire()!==wire(value.content))
              fail('OriginalEffectContentUnavailable');
            request=requestFrom({binding:bindingCid,command:command.contract_cid,target:selector,value},
              runOriginal,borrowed,contentOwner);
            if(stopping)fail('LocalStoreRequestClosing');
            return Object.freeze({request,requestCid:requests.get(request).cid});
          }finally{preparing=false;}
        },
        async release(){
          stopping=true;
          const state=request===undefined?undefined:requests.get(request);
          if(state?.writeChild!==undefined)await state.writeChild.close();
          if(preparing||state?.writeChild?.status().pending)return false;
          if(state!==undefined){state.released=true;state.borrow=state.contentOwner=undefined;}
          children.delete(child);return true;
        },
        retry(){return child.release();},
        status(){const state=request===undefined?undefined:requests.get(request);
          return Object.freeze({pending:!stopping||preparing||state?.writeChild?.status().pending===true});},
      });
      children.add(child);return child;
    },
    requestFacts(request){const {record}=own(request);return{value:record.value,target:record.target};},
    requestCid:request=>own(request).cid,
    recheckRequests({member,entries,runOriginal}){
      memberCurrent(member);runCurrent(runOriginal);
      for(const {request} of entries){
        const original=own(request,runOriginal);
        if(original.borrow?.current()!==true||typeof original.contentOwner?.consumeContent!=='function')
          fail('OriginalEffectContentUnavailable');
      }
    },
    footprint:()=>({providerNamespace:'local',resourceKind:'file_collection',boundaryCid:bindingCid}),
    recoveryEntry({entries}){
      // Preserve admission of every original request before encoding any row.
      // These are the same immutable records, not reconstructed Content grants.
      const records=entries.map(entry=>own(entry.request).record);
      const prefix=`{"binding":${wire(bindingCid)},"requests":[`;
      let bytes=Buffer.byteLength(prefix)+2;
      const rows=[];
      for(const record of records){
        const row=wire(record),separator=rows.length===0?0:1;
        const size=Buffer.byteLength(row);
        if(size>limits.maxRequestBytes-bytes-separator)fail('LocalStoreRecoveryLimit');
        bytes+=size+separator;rows.push(row);
      }
      if(bytes>limits.maxRequestBytes)fail('LocalStoreRecoveryLimit');
      // The closed envelope has the same canonical key order. Join only after
      // the original total-byte guard, and hash that SAME completed wire once.
      const body=prefix+rows.join(',')+']}';
      return{kind:'local-file-store',wire:body,
        observationCid:'sha256:'+createHash('sha256').update(body).digest('hex')};
    },
    recoverRequests:recover,recoverMemberRequests:recover,
    prepareRecoveredContentChild({recovered,members,entries,memberIndexes,control,store,
      contentRun,principalId:actor,assertCurrent:checkCurrent,signal,limits:inputLimits,runOriginal}){
      runCurrent(runOriginal);
      if(typeof contentRun?.prepareRecoveredCommandContent!=='function'||
          recovered?.prepared===undefined||recovered.allowed===undefined||actor!==principalId)
        fail('OriginalEffectContentUnavailable');
      const compiled=control.adoptCheckedClientEffectSerializationRun(
        recovered.allowed,recovered.runDefinition);
      const selected=[];
      for(const index of memberIndexes){
        memberCurrent(members[index]);
        for(const entry of entries[index])selected.push({state:own(entry.request,runOriginal),index});
      }
      if(selected.length>limits.maxRows)fail('LocalStoreRecoveryLimit');
      const retained=[];
      let stopping=false,released=false,attempted=false,flight;
      const child=Object.freeze({
        prepare(){
          if(attempted||stopping)fail('LocalStoreRecoveryAlreadyAttempted');
          attempted=true;
          const work=(async()=>{
            for(const {state,index} of selected){
              runCurrent(runOriginal);checkCurrent?.();signal?.throwIfAborted();
              const sources=recovered.computation.effectSources?.filter(source=>
                source.memberIndex===members[index].memberIndex);
              if(sources?.length!==1)fail('OriginalEffectContentUnavailable');
              const contentChild=contentRun.prepareRecoveredCommandContent({
                prepared:recovered.prepared,compiled,definition:recovered.runDefinition,
                captured:recovered.computation.computation.capturedRun,
                preview:recovered.computation.preview,invocation:recovered.computation.invocation,
                source:sources[0].source,store,principalId:actor,
                memberIndex:members[index].memberIndex,
                row:entries[index].findIndex(entry=>requests.get(entry.request)===state),
                inputName:'content',referenceWire:wire(state.record.value.content),signal,
                limits:{maxFields:inputLimits.maxFields,maxWork:inputLimits.maxWork,
                  maxWireBytes:inputLimits.body.maxBytes,maxNodes:inputLimits.body.maxNodes,
                  maxDepth:inputLimits.body.maxDepth},
                assertCurrent(){
                  if(stopping)fail('LocalStoreRequestClosing');
                  runCurrent(runOriginal);checkCurrent?.();
                }});
              retained.push(contentChild); // Before current callbacks or Store I/O.
              if(stopping)fail('LocalStoreRequestClosing');
              const restored=await contentChild.prepare();
              if(stopping)fail('LocalStoreRequestClosing');
              runCurrent(runOriginal);checkCurrent?.();
              state.borrow=restored.borrow;state.contentOwner=restored.contentOwner;
            }
          })();
          flight=work;
          return work.finally(()=>{if(flight===work)flight=undefined;});
        },
        async release(){
          stopping=true;
          if(flight!==undefined)return false;
          for(const {state} of selected){
            if(state.writeChild!==undefined)await state.writeChild.close();
            if(state.writeChild?.status().pending)return false;
          }
          for(const contentChild of retained)await contentChild.release();
          if(retained.some(contentChild=>contentChild.status().pending))return false;
          for(const {state} of selected){state.released=true;state.borrow=state.contentOwner=undefined;}
          released=true;children.delete(child);return true;
        },
        status:()=>Object.freeze({pending:!released||flight!==undefined}),
      });
      children.add(child);return child;
    },
    async send({member,request,current:selected,authorization:supplied,signal,runOriginal}){
      memberCurrent(member);const observed=description(selected,runOriginal),original=own(request,runOriginal);
      const grant=grants.get(supplied?.proof);
      if(grant===undefined||grant.used||grant.runInvocationCid!==observed.runInvocationCid||
          grant.dispatchRequestCid!==observed.dispatchRequestCid||typeof supplied.useId!=='string'||
          Buffer.byteLength(supplied.useId)>4096)fail('ForeignLocalStoreUse');
      decisionCurrent(grant.decision);
      if(original.writeChild!==undefined)fail('LocalFileWriteAlreadyAttempted');
      grant.used=true;
      const write=prepareLocalStoredContentWrite({native:nativeFilesystem,rootPath:entry.rootPath,
        path:original.record.value.path,temporaryName:'.actql-store-'+randomUUID(),
        maxBytes:limits.maxFileBytes,overwrite:original.record.value.overwrite??false,
        contentOwner:original.contentOwner,content:original.borrow,signal,
        assertCurrent(){runCurrent(runOriginal);decisionCurrent(grant.decision);}});
      original.writeChild=write; // Before execute/acquisition or a later callback.
      let result,primary,failed=false;
      try{result=await write.execute();}catch(cause){failed=true;primary=cause;}
      let cleanup,cleanupFailed=false;
      try{if((await write.close()).pending){cleanupFailed=true;cleanup=new Error('LocalStoreCleanupPending');}}
      catch(cause){cleanupFailed=true;cleanup=cause;}
      if(cleanupFailed)throw Object.assign(new Error('LocalStoreCleanupPending',
        {cause:failed?primary:cleanup}),{code:'LocalStoreCleanupPending',cleanupPending:true,
        cleanupHandle:Object.freeze({status:write.status,retry:write.retry})});
      if(failed)throw primary;
      const response={request_cid:original.cid,path:result.path,bytes:result.bytes,action:'stored'};
      const bytes=Buffer.from(wire(response));
      if(bytes.length>limits.maxResponseBytes)fail('LocalStoreResponseLimit');
      return Object.freeze({observation:Object.freeze({useCid:cid({binding:bindingCid,
        run:grant.runInvocationCid,dispatch:grant.dispatchRequestCid,subject:grant.subjectCid,use:supplied.useId}),
        statusCode:200,body:bytes})});
    },
    project({request,observation}){
      const original=own(request);
      if(!isCid(observation?.useCid)||observation.statusCode!==200||
          !(observation.body instanceof Uint8Array)||observation.body.length>limits.maxResponseBytes)
        return{kind:'unknown'};
      let response;try{response=JSON.parse(Buffer.from(observation.body).toString('utf8'));}catch{return{kind:'unknown'};}
      if(!closed(response,['request_cid','path','bytes','action'])||response.request_cid!==original.cid||
          response.path!==original.record.value.path||response.action!=='stored'||
          !Number.isSafeInteger(response.bytes)||response.bytes<0||response.bytes>limits.maxFileBytes)
        return{kind:'unknown'};
      return{kind:'typed-success-response',outcome:{state:'applied',result:{}}};
    },
  });
  const site=Object.freeze({
    issueReadGrant(){fail('LocalStoreTargetReadUnavailable');},
    issueEffectGrant({operation,decision,resource,runInvocationCid,dispatchRequestCid,subjectCid}){
      if(operation!=='files.write'||resource!=='files'||!isCid(runInvocationCid)||
          !isCid(dispatchRequestCid)||!isCid(subjectCid)||decision?.subjectCid!==subjectCid)
        fail('LocalStoreNotAuthorized');
      decisionCurrent(decision);
      const proof=Object.freeze({});grants.set(proof,{decision,runInvocationCid,dispatchRequestCid,subjectCid,used:false});
      return Object.freeze({proof});
    },
    close,status:()=>Object.freeze({pending:children.size!==0}),
  });
  return Object.freeze({driver,site});
}
