// Project and Connector owners admit their own original bytes. This caller
// selects one declared connection; it does not install a Site or resolve keys.
import {open} from 'node:fs/promises';
import {types} from 'node:util';
import {loadInstalledProjectConnections} from '../../../host-node/installed-project-connections.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

const fail=code=>{throw Object.assign(new Error(code),{code});};
const limitsKeys=['maxConnections','maxSelectionWork','maxDatabases','maxCredentialReferenceBytes',
  'maxBytes','maxNodes','maxDepth','maxDataSources','maxProperties','maxIdentityBytes','maxNameBytes',
  'maxContractNodes','maxContractDepth','maxContractTextBytes','maxColumns','maxWork'];
const projectPorts=['clientProjectConnectionsCount','clientProjectConnectionsName',
  'clientProjectConnectionsConnector','clientProjectConnectionsEntryOriginalJson'];
const providerPorts=['notionReadPublicConnection'];
const originalViews=new WeakMap();
const positive=value=>Number.isSafeInteger(value)&&value>0&&value<=2147483647;
const text=value=>typeof value==='string'&&value.length>0&&value.isWellFormed()&&!value.includes('\0');
function ports(receiver,names){
  if(receiver===null||typeof receiver!=='object'||types.isProxy(receiver))fail('NotionProjectConnectionRuntimeUnavailable');
  return Object.freeze(Object.fromEntries(names.map(name=>{
    const d=Object.getOwnPropertyDescriptor(receiver,name);
    if(!d||!Object.hasOwn(d,'value')||typeof d.value!=='function')fail('NotionProjectConnectionRuntimeUnavailable');
    return[name,d.value];
  })));
}
function readLimits(value){
  if(value===null||typeof value!=='object'||types.isProxy(value)||
      Object.getPrototypeOf(value)!==Object.prototype)fail('InvalidNotionProjectConnectionLimits');
  const descriptors=Object.getOwnPropertyDescriptors(value),keys=Reflect.ownKeys(descriptors);
  if(keys.length!==limitsKeys.length||keys.some(key=>!limitsKeys.includes(key)))fail('InvalidNotionProjectConnectionLimits');
  return Object.freeze(Object.fromEntries(limitsKeys.map(key=>{
    const d=descriptors[key];
    if(!d?.enumerable||!Object.hasOwn(d,'value')||!positive(d.value))fail('InvalidNotionProjectConnectionLimits');
    return[key,d.value];
  })));
}
function current(state){
  if(state.retired)fail('NotionProjectConnectionRetired');
  if(state.failure!==undefined)throw state.failure;
  try{
    const value=state.references.acquisition.originalsForRuntime(state.references.moon);
    if(value!==state.references.originals)fail('ForeignNotionProjectConnection');
  }catch(cause){state.failure=cause;throw cause;}
}

// Only this acquisition issues a view. Returned fields are configuration DATA;
// even the original Project, entry and typed Connector value issue no authority.
export async function loadInstalledNotionProjectConnection(moon,providerMoon,project,name,options){
  if(options===null||typeof options!=='object'||types.isProxy(options)||
      Object.getPrototypeOf(options)!==Object.prototype)fail('InvalidNotionProjectConnection');
  const descriptors=Object.getOwnPropertyDescriptors(options),keys=Reflect.ownKeys(descriptors);
  if(keys.some(key=>!['limits','assertCurrent','openFile'].includes(key))||
      ['limits','assertCurrent'].some(key=>!descriptors[key]?.enumerable||!Object.hasOwn(descriptors[key],'value'))||
      keys.some(key=>!Object.hasOwn(descriptors[key],'value')))fail('InvalidNotionProjectConnection');
  const limits=descriptors.limits.value,assertCurrent=descriptors.assertCurrent.value,
    openFile=descriptors.openFile===undefined?open:descriptors.openFile.value;
  if(!text(name)||typeof assertCurrent!=='function'||typeof openFile!=='function')fail('InvalidNotionProjectConnection');
  const bounded=readLimits(limits),common=ports(moon,projectPorts),provider=ports(providerMoon,providerPorts);
  const call=(method,...args)=>Reflect.apply(common[method],moon,args);
  const fence=()=>{
    const result=Reflect.apply(assertCurrent,options,[]);
    if(result!==undefined){
      if(typeof result?.then==='function')void Promise.resolve(result).catch(()=>{});
      fail('InvalidNotionProjectConnectionCurrentFence');
    }
  };
  fence();
  const acquisition=await loadInstalledProjectConnections(moon,project,{assertCurrent:fence,
    openFile:(...args)=>Reflect.apply(openFile,options,args)});
  const originals=acquisition.originalsForRuntime(moon);
  if(originals.connections===undefined)fail('NotionProjectConnectionUnavailable');
  const count=call('clientProjectConnectionsCount',originals.connections);
  if(!Number.isSafeInteger(count)||count<0||count>bounded.maxConnections)fail('NotionProjectConnectionSelectionLimit');
  let work=bounded.maxSelectionWork,index;
  const spend=amount=>{if(amount>work)fail('NotionProjectConnectionSelectionLimit');work-=amount;};
  spend(1);spend(name.length);
  for(let i=0;i<count;i++){
    const candidate=call('clientProjectConnectionsName',originals.connections,i);
    if(!text(candidate))fail('ForeignNotionProjectConnection');
    spend(1);spend(candidate.length);
    if(candidate===name){
      if(index!==undefined)fail('ForeignNotionProjectConnection');
      index=i;
    }
  }
  if(index===undefined)fail('NotionProjectConnectionUnavailable');
  if(call('clientProjectConnectionsConnector',originals.connections,index)!=='notion')fail('NotionProjectConnectionConnectorMismatch');
  const wire=call('clientProjectConnectionsEntryOriginalJson',originals.connections,index);
  if(typeof wire!=='string'||!wire.isWellFormed())fail('ForeignNotionProjectConnection');
  if(wire.length>bounded.maxBytes||Buffer.byteLength(wire)>bounded.maxBytes)fail('NotionProjectConnectionInputLimit');
  if(acquisition.originalsForRuntime(moon)!==originals)fail('ForeignNotionProjectConnection');
  // The sole UTF-8 encode preserves the Common-selected original entry span.
  // Provider admission performs the closed grammar and aggregate Contract work.
  const connection=checked(Reflect.apply(provider.notionReadPublicConnection,providerMoon,[Buffer.from(wire),
    bounded.maxBytes,bounded.maxNodes,bounded.maxDepth,bounded.maxDataSources,bounded.maxProperties,
    bounded.maxIdentityBytes,bounded.maxNameBytes,bounded.maxContractNodes,bounded.maxContractDepth,
    bounded.maxContractTextBytes,bounded.maxColumns,bounded.maxWork,bounded.maxDatabases,bounded.maxCredentialReferenceBytes]));
  if(acquisition.originalsForRuntime(moon)!==originals)fail('ForeignNotionProjectConnection');
  const record=Object.freeze({project,projectConnections:originals,name,index,wire,connection});
  const state={references:{moon,providerMoon,acquisition,originals,record},retired:false,failure:undefined};
  const view=Object.freeze({
    originalsForRuntime(commonRuntime,providerRuntime){
      if(originalViews.get(this)!==state)fail('ForeignNotionProjectConnection');
      if(state.retired)fail('NotionProjectConnectionRetired');
      if(commonRuntime!==state.references.moon||providerRuntime!==state.references.providerMoon)fail('ForeignNotionProjectConnectionRuntime');
      current(state);return state.references.record;
    },
    retire(){
      if(originalViews.get(this)!==state)fail('ForeignNotionProjectConnection');
      state.retired=true;state.references=undefined;
    },
  });
  originalViews.set(view,state);return view;
}
