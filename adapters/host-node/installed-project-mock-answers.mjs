import {open} from 'node:fs/promises';
import {dirname, extname, resolve} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {installedProjectOriginalsForRuntime} from './installed-project-configuration.mjs';
import {readBoundedConfigurationUtf8} from './source-profile-json.mjs';

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
      const taskPath=resolve(dirname(project.registryPath),taskFile);
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
  let retired=false,retireIndex=0,view;
  const same=(runtime,receiver)=>{
    if(runtime!==moon||receiver!==view)fail('ForeignInstalledMockAnswerOriginal');
  };
  view=Object.freeze({
    originalsForRuntime(runtime){
      same(runtime,this);
      if(retired)fail('InstalledMockAnswersRetired');
      check();return retained;
    },
    retire(runtime){
      same(runtime,this);
      if(retired)return;
      // The same view finalizes once. A foreign/copied view cannot consume it.
      while(retireIndex<retained.length){
        const entry=retained[retireIndex];
        checked(call('retire',entry.answers,entry.task));retireIndex++;
      }
      retained=undefined;retired=true;
      original=selection=project=profile=profilePorts=ports=assertCurrent=openFile=undefined;
    },
  });
  return view;
}
