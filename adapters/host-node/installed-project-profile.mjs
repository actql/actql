import {checked} from '../host-common/runtime-result.mjs';
import {installedProjectOriginalsForRuntime} from './installed-project-configuration.mjs';

const fail=code=>{throw Object.assign(new Error(code),{code});};

// Private installation DATA, never a permission or mock/Provider factory.
// Capture the actual runtime's original ports once. The existing Host still
// has to supply the selected physical records/answers/currentness and funding.
export function selectInstalledProjectProfile(moon,project,requested,maxWork){
  if(requested!==undefined&&(typeof requested!=='string'||!requested||
      !requested.isWellFormed())||!Number.isSafeInteger(maxWork)||maxWork<0||
      maxWork>2147483647)fail('InvalidInstalledProjectProfile');
  let original=project===undefined?undefined:installedProjectOriginalsForRuntime(project,moon);
  let configuration=original?.configuration;
  let ports=Object.freeze({select:moon?.clientProjectProfileSelect,
    matches:moon?.clientProjectProfileMatches,name:moon?.clientProjectProfileSelectedName,
    catalog:moon?.clientProjectProfileMockCatalogFile,
    data:moon?.clientProjectProfileMockDataFile,count:moon?.clientProjectProfileMockAnswerCount,
    task:moon?.clientProjectProfileMockAnswerTask,file:moon?.clientProjectProfileMockAnswerFile,
    retire:moon?.clientProjectProfileRetire});
  if(!Object.values(ports).every(port=>typeof port==='function')){
    fail('InstalledProjectProfileRuntimeUnavailable');
  }
  const call=(name,...args)=>Reflect.apply(ports[name],moon,args);
  let selection=checked(call('select',configuration,requested,maxWork));
  let retired=false;
  let view;
  function same(runtime,receiver){
    if(receiver!==view||runtime!==moon)fail('ForeignInstalledProjectProfile');
  }
  function current(runtime,receiver){
    same(runtime,receiver);
    if(retired)fail('InstalledProjectProfileRetired');
    if(project!==undefined&&installedProjectOriginalsForRuntime(project,moon)!==original){
      fail('ForeignInstalledProjectOriginal');
    }
    if(call('matches',selection,configuration,requested)!==true){
      fail('ForeignInstalledProjectProfile');
    }
  }
  const text=value=>{
    if(value!==undefined&&(typeof value!=='string'||!value||!value.isWellFormed())){
      fail('InvalidHostRuntimeResult');
    }
    return value;
  };
  view=Object.freeze({
    originalsForRuntime(runtime){
      current(runtime,this);
      const selected=text(checked(call('name',selection)));
      return Object.freeze({selection,configuration,requested,selected});
    },
    mockLocatorsForRuntime(runtime){
      current(runtime,this);
      const catalogFile=text(checked(call('catalog',selection)));
      const dataFile=text(checked(call('data',selection)));
      const answerCount=checked(call('count',selection));
      if(!Number.isSafeInteger(answerCount)||answerCount<0)fail('InvalidHostRuntimeResult');
      return Object.freeze({catalogFile,dataFile,answerCount});
    },
    mockAnswerForRuntime(runtime,index){
      current(runtime,this);
      if(!Number.isSafeInteger(index)||index<0)fail('InvalidInstalledProjectAnswerIndex');
      const task=text(checked(call('task',selection,index)));
      const file=text(checked(call('file',selection,index)));
      if((task===undefined)!==(file===undefined))fail('InvalidHostRuntimeResult');
      return task===undefined?undefined:Object.freeze({task,file});
    },
    retire(runtime){
      // Cleanup checks original identity, not new-operation/current permission.
      // The same issued view remembers its completed managed retirement; a
      // foreign/copied receiver cannot acknowledge someone else's duty.
      same(runtime,this);
      if(retired)return;
      checked(call('retire',selection));
      retired=true;
      original=configuration=selection=project=requested=ports=undefined;
    },
  });
  return view;
}
