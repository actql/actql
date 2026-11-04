import {open} from 'node:fs/promises';
import {extname, resolve} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime, resolveInstalledProjectTaskPath} from '../host-node/installed-project-configuration.mjs';
import {readBoundedConfigurationUtf8} from '../host-node/source-profile-json.mjs';

const fail=code=>{throw Object.assign(new Error(code),{code});};
const fields=Object.freeze(['contractDepth','contractNodes','contractTextBytes','maxBytes',
  'maxDepth','maxEntries','maxMembers','maxNodes','maxTasks','maxWork',
  'valueDepth','valueNodes','valueTextBytes']);

function snapshotLimits(value){
  if(value===null||typeof value!=='object'||Array.isArray(value))fail('InvalidInstalledMockAnswerLimits');
  const keys=Object.keys(value).sort();
  if(keys.length!==fields.length||keys.some((key,index)=>key!==fields[index]))fail('InvalidInstalledMockAnswerLimits');
  const result={};
  for(const key of fields){const n=value[key];
    if(!Number.isSafeInteger(n)||n<0||n>2147483647)fail('InvalidInstalledMockAnswerLimits');
    result[key]=n;
  }
  return Object.freeze(result);
}

function format(path){
  const extension=extname(path);
  if(extension==='.json')return 'json';
  if(extension==='.yaml'||extension==='.yml')return 'yaml';
  fail('InstalledMockAnswerFormatUnavailable');
}

// Existing installation DATA acquisition only. This does not install mock
// Source/Effect/Model execution, a Provider, handling policy or physical funds.
// The caller funds all original wires/trees/checked values and read workspace.
export async function loadInstalledProjectMockAnswers(moon,project,profile,
  {limits,assertCurrent,openFile=open}={}){
  let original=installedProjectOriginalsForRuntime(project,moon);
  const bounds=snapshotLimits(limits);
  if(typeof assertCurrent!=='function'||typeof openFile!=='function'||
      typeof project.directory!=='string'||
      typeof profile?.originalsForRuntime!=='function'||
      typeof profile?.mockLocatorsForRuntime!=='function'||
      typeof profile?.mockAnswerForRuntime!=='function')fail('InvalidInstalledMockAnswerInstallation');
  let profilePorts=Object.freeze({originals:profile.originalsForRuntime,
    locators:profile.mockLocatorsForRuntime,answer:profile.mockAnswerForRuntime});
  let ports=Object.freeze({count:moon?.clientProjectModelRegistryTaskCount,
    task:moon?.clientProjectModelRegistryTaskName,file:moon?.clientProjectModelRegistryTaskFile,
    readTask:moon?.clientProgramReadPublicModelTask,name:moon?.clientProgramPublicModelTaskName,
    readAnswers:moon?.clientProgramReadMockAnswers,retire:moon?.clientProgramRetireMockAnswers});
  if(!Object.values(ports).every(port=>typeof port==='function'))fail('InstalledProjectRuntimeUnavailable');
  const call=(name,...args)=>Reflect.apply(ports[name],moon,args);
  const select=(name,...args)=>Reflect.apply(profilePorts[name],profile,[moon,...args]);
  let selection=select('originals');
  const check=()=>{
    assertCurrent();
    if(installedProjectOriginalsForRuntime(project,moon)!==original||
        select('originals').selection!==selection.selection||
        selection.configuration!==original.configuration||selection.selected!=='mock'){
      fail('ForeignInstalledMockAnswerOriginal');
    }
  };
  check();
  const answerCount=select('locators').answerCount;
  const taskCount=original.modelRegistry===undefined?0:call('count',original.modelRegistry);
  if(!Number.isSafeInteger(taskCount)||taskCount<0||taskCount>bounds.maxTasks||
      !Number.isSafeInteger(answerCount)||answerCount<0||answerCount>bounds.maxTasks){
    fail('InstalledMockAnswerCountLimit');
  }
  if(answerCount>0&&typeof project.registryPath!=='string')fail('InstalledMockAnswerTaskUnavailable');
  const taskBounds=[bounds.maxBytes,bounds.maxNodes,bounds.maxDepth,bounds.maxMembers,
    bounds.contractNodes,bounds.contractDepth,bounds.contractTextBytes,bounds.maxWork];
  const answerBounds=[bounds.maxBytes,bounds.maxNodes,bounds.maxDepth,bounds.maxMembers,
    bounds.valueNodes,bounds.valueDepth,bounds.valueTextBytes,bounds.maxEntries,bounds.maxWork];
  let retained=[],selectionWork=bounds.maxWork;
  try{
    for(let index=0;index<answerCount;index++){
      check();
      const locator=select('answer',index);
      if(locator===undefined)fail('InvalidInstalledMockAnswerSelection');
      let taskFile;
      for(let position=0;position<taskCount;position++){
        if(selectionWork===0)fail('InstalledMockAnswerSelectionWorkLimit');
        selectionWork--;
        if(call('task',original.modelRegistry,position)===locator.task){
          taskFile=call('file',original.modelRegistry,position);break;
        }
      }
      if(typeof taskFile!=='string'||!taskFile)fail('InstalledMockAnswerTaskUnavailable');
      const taskPath=resolveInstalledProjectTaskPath(project,moon,taskFile);
      const answerPath=resolve(project.directory,locator.file);
      const taskFormat=format(taskPath),answerFormat=format(answerPath);
      const taskWire=await readBoundedConfigurationUtf8(taskPath,{maxBytes:bounds.maxBytes,openFile});
      check();
      const task=checked(call('readTask',taskWire,taskFormat,...taskBounds));
      if(call('name',task)!==locator.task)fail('InstalledMockAnswerTaskMismatch');
      const answerWire=await readBoundedConfigurationUtf8(answerPath,{maxBytes:bounds.maxBytes,openFile});
      check();
      const answers=checked(call('readAnswers',task,answerWire,answerFormat,...answerBounds));
      retained.push(Object.freeze({task,answers,name:locator.task,taskPath,answerPath,taskWire,answerWire}));
      check();
    }
  }catch(error){
    const retirement=[];
    for(const entry of retained){try{checked(call('retire',entry.answers,entry.task));}catch(cause){retirement.push(cause);}}
    if(retirement.length){
      // Preserve the original read/close carrier and exact unretired DATA.
      // No physical acknowledgement or new cleanup authority is manufactured.
      const failure=new AggregateError([error,...retirement],'InstalledMockAnswerRetirementPending',{cause:error});
      failure.originalAnswerCustody=Object.freeze(retained);
      throw failure;
    }
    throw error;
  }
  retained=Object.freeze(retained);
  let retired=false,retireIndex=0,view,modelBinding;
  const same=(runtime,receiver)=>{
    if(runtime!==moon||receiver!==view)fail('ForeignInstalledMockAnswerOriginal');
  };
  view=Object.freeze({
    originalsForRuntime(runtime){
      same(runtime,this);
      if(retired)fail('InstalledMockAnswersRetired');
      check();return retained;
    },
    bindModelsForRuntime(runtime,originalProfile,now){
      same(runtime,this);
      if(retired)fail('InstalledMockAnswersRetired');
      check();
      if(typeof now!=='function')fail('InvalidInstalledMockModelClock');
      if(modelBinding!==undefined){
        if(modelBinding.profile!==originalProfile||modelBinding.now!==now){
          fail('ForeignInstalledMockModelOriginal');
        }
        if(modelBinding.failed)throw modelBinding.failure;
        modelBinding.value.originalsForRuntime(runtime);
        return modelBinding.value;
      }
      // This SAME answer owner retains each actual Model installation before
      // its next fallible operation. Neither CID lookup nor these callbacks
      // supplies startup, an Account decision, dispatch or physical capacity.
      const callbacks=Object.freeze({normalize:moon.clientProgramNormalizeMockTask,
        materials:moon.clientProgramNormalizedPublicModelTaskMaterials,
        execution:moon.clientProgramMockExecutionMaterials,
        install:moon.clientProgramInstallOriginalMock,
        provider:moon.clientProgramOriginalMockProvider,
        retire:moon.clientProgramRetireOriginalMock,
        environment:moon.clientProgramProjectPublicModelTaskEnvironment});
      if(!Object.values(callbacks).every(callback=>typeof callback==='function')){
        fail('InstalledMockModelRuntimeUnavailable');
      }
      const state={profile:originalProfile,now,callbacks,entries:[],retireIndex:0,
        failed:false,failure:undefined,value:undefined,retired:false};
      modelBinding=state;
      const modelCall=(name,...args)=>Reflect.apply(state.callbacks[name],moon,args);
      const profileOriginalsPort=moon.clientProgramMockProfileOriginals;
      const currentModels=(runtime,receiver)=>{
        if(runtime!==moon||receiver!==state.value)fail('ForeignInstalledMockModelOriginal');
        if(retired||state.retired)fail('InstalledMockModelsRetired');
        check();
        if(modelBinding!==state)fail('ForeignInstalledMockModelOriginal');
        if(state.failed)throw state.failure;
        // The portable Model owner checks the SAME retained profile, Task and
        // answers; a replacement/copy cannot become a valid Provider here.
        for(const entry of state.entries){
          if(checked(modelCall('provider',entry.installation))!==entry.provider){
            fail('ForeignInstalledMockModelOriginal');
          }
        }
        return state.entries;
      };
      try{
        for(const entry of retained){
          check();
          const normalized=checked(modelCall('normalize',entry.task,originalProfile,...taskBounds));
          const material=modelCall('materials',normalized);
          const taskWire=runtimeField(material,0),taskCid=runtimeField(material,1);
          const promptWire=runtimeField(material,2),promptCid=runtimeField(material,3);
          if([taskWire,taskCid,promptWire,promptCid].some(value=>typeof value!=='string')){
            fail('InvalidHostRuntimeResult');
          }
          const execution=modelCall('execution',originalProfile,normalized,...taskBounds);
          const executionMaterial=checked(execution);
          const [executionWire,executionCid,retryWire,retryCid,backoffWire,backoffCid]=
            Array.from({length:6},(_,index)=>runtimeField(executionMaterial,index));
          if([executionWire,executionCid,retryWire,retryCid,backoffWire,backoffCid]
            .some(value=>typeof value!=='string'))fail('InvalidHostRuntimeResult');
          const installation=checked(modelCall('install',originalProfile,
            entry.task,normalized,entry.answers,now));
          const bound={...entry,normalized,taskWire,taskCid,promptWire,promptCid,
            executionWire,executionCid,retryWire,retryCid,backoffWire,backoffCid,
            installation,provider:undefined};
          state.entries.push(bound);
          bound.provider=checked(modelCall('provider',installation));
          Object.freeze(bound);
          check();
        }
        state.entries=Object.freeze(state.entries);
        state.value=Object.freeze({
          originalsForRuntime(runtime){return currentModels(runtime,this);},
          providerBindingOriginalsForRuntime(runtime){
            currentModels(runtime,this);
            if(typeof profileOriginalsPort!=='function')fail('InstalledMockModelRuntimeUnavailable');
            const material=Reflect.apply(profileOriginalsPort,moon,[state.profile]);
            if(material===undefined)fail('ForeignInstalledMockModelOriginal');
            const fields=Array.from({length:6},(_,index)=>runtimeField(material,index));
            if(fields.some(value=>typeof value!=='string'))fail('InvalidHostRuntimeResult');
            currentModels(runtime,this);
            return Object.freeze({
              installationRevision:Object.freeze({wire:fields[0],cid:fields[1]}),
              configurationContract:Object.freeze({wire:fields[2],cid:fields[3]}),
              configuration:Object.freeze({wire:fields[4],cid:fields[5]}),
            });
          },
          forTaskCid(runtime,taskCid){
            const entries=currentModels(runtime,this);
            if(typeof taskCid!=='string')fail('InvalidInstalledMockModelTask');
            return entries.find(entry=>entry.taskCid===taskCid);
          },
          projectEnvironmentForRuntime(runtime,wire,evidenceCid){
            const entries=currentModels(runtime,this);
            if(typeof wire!=='string'||typeof evidenceCid!=='string'){
              fail('InvalidInstalledProjectEnvironment');
            }
            const projection=checked(modelCall('environment',wire,evidenceCid,
              entries.map(entry=>entry.normalized),...taskBounds));
            const environmentWire=runtimeField(projection,0),identity=runtimeField(projection,1);
            const work=runtimeField(projection,2);
            if(typeof environmentWire!=='string'||typeof identity!=='string'||
                !Number.isSafeInteger(work)||work<0)fail('InvalidHostRuntimeResult');
            currentModels(runtime,this);
            return Object.freeze({environmentWire,evidenceCid:identity,work});
          },
          modelInstallationForRuntime(runtime,wire,evidenceCid){
            const entries=currentModels(runtime,this);
            const projected=this.projectEnvironmentForRuntime(runtime,wire,evidenceCid);
            const dependencyBodies=[];
            for(const entry of entries){
              // Assemble only the existing Host reader's DATA envelope. Every
              // body/CID came from the same Common normalization/execution
              // owner; the Host defines no retry, backoff or codec semantics.
              for(const [bodyWire,cid] of [[entry.promptWire,entry.promptCid],
                [entry.retryWire,entry.retryCid],[entry.backoffWire,entry.backoffCid]]){
                const previous=dependencyBodies.find(body=>body.cid===cid);
                if(previous!==undefined){
                  if(previous.bodyWire!==bodyWire)fail('InstalledMockModelBodyMismatch');
                }else dependencyBodies.push(Object.freeze({bodyWire,cid}));
              }
            }
            const executionContracts=entries.map(entry=>Object.freeze({
              modelTaskCid:entry.taskCid,bodyWire:entry.executionWire,cid:entry.executionCid}));
            currentModels(runtime,this);
            return Object.freeze({environmentWire:projected.environmentWire,
              executionContracts:Object.freeze(executionContracts),
              dependencyBodies:Object.freeze(dependencyBodies)});
          },
        });
        currentModels(runtime,state.value);
        return state.value;
      }catch(error){state.failed=true;state.failure=error;throw error;}
    },
    retire(runtime){
      same(runtime,this);
      if(retired)return;
      if(modelBinding!==undefined&&!modelBinding.retired){
        while(modelBinding.retireIndex<modelBinding.entries.length){
          const entry=modelBinding.entries[modelBinding.retireIndex];
          if(checked(Reflect.apply(modelBinding.callbacks.retire,moon,
            [entry.installation]))!==true)fail('InstalledMockModelsCleanupPending');
          modelBinding.retireIndex++;
        }
        modelBinding.retired=true;
        modelBinding.entries=modelBinding.profile=modelBinding.now=modelBinding.callbacks=undefined;
      }
      // The same view finalizes once. A foreign/copied view cannot consume it.
      while(retireIndex<retained.length){
        const entry=retained[retireIndex];
        checked(call('retire',entry.answers,entry.task));retireIndex++;
      }
      retained=undefined;retired=true;
      modelBinding=undefined;
      original=selection=project=profile=profilePorts=ports=assertCurrent=openFile=undefined;
    },
  });
  return view;
}
