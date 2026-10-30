// Pure composition inside the existing installed Effect owner. Original
// Core extents/Plan are DATA until the SAME Request completes and adopts them.
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {httpsCredentialResponseWindowBytes} from '../site-node/https-credential-resource.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
const fail = code => {throw Object.assign(new Error(code), {code});};
const text = value => typeof value === 'string' && value.length > 0;

// The selected Host supplies original typed extents from its actual implementation
// recipe. Names/limits alone cannot select a Plan. Preserve those same opaque
// Core values; this view creates no capacity, admission or permission.
export function captureInstalledEffectPlanRecipe(recipe, maxOperations) {
  if (recipe === undefined) return undefined;
  if (recipe === null || typeof recipe !== 'object' || nodeTypes.isProxy(recipe)) fail('InvalidInstalledEffectPlanRecipe');
  if (!Number.isSafeInteger(maxOperations) || maxOperations < 1) fail('InvalidInstalledEffectPlanRecipe');
  const own = (value, names) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        !Object.isFrozen(value)) fail('InvalidInstalledEffectPlanRecipe');
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== names.length ||
        names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    return fields;
  };
  const fields = own(recipe, Object.hasOwn(recipe, 'requestConstruction')
    ? ['memberOperations', 'rowOperations', 'requestConstruction'] : ['memberOperations', 'rowOperations']);
  const operations = name => {
    const values = fields[name].value;
    if (!Array.isArray(values) || values.length > maxOperations) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const entries = own(values, ['length', ...Array.from({length: values.length}, (_, index) => String(index))]);
    return Object.freeze(Array.from({length: values.length}, (_, index) => {
      const entry = own(entries[String(index)].value, ['operation', 'extent']);
      const operation = entry.operation.value, extent = entry.extent.value;
      if (!text(operation) || extent === null || typeof extent !== 'object' ||
          nodeTypes.isProxy(extent)) fail('InvalidInstalledEffectPlanRecipe');
      return Object.freeze({operation, extent});
    }));
  };
  const memberOperations = operations('memberOperations'), rowOperations = operations('rowOperations');
  if (memberOperations.length + rowOperations.length === 0 ||
      memberOperations.length + rowOperations.length > maxOperations) fail('InvalidInstalledEffectPlanRecipe');
  let requestConstruction;
  if (fields.requestConstruction !== undefined) {
    const selected = own(fields.requestConstruction.value, ['operationIndex']);
    const operationIndex = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= rowOperations.length) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    requestConstruction = Object.freeze({operationIndex});
  }
  return Object.freeze({memberOperations, rowOperations,
    ...(requestConstruction === undefined ? {} : {requestConstruction})});
}

export function prepareInstalledEffectManagedPlan({moon, facts, inputs, unit, members, recipeFor}) {
  if (facts?.prepared === undefined || facts.identity === undefined ||
      inputs?.installedContracts === undefined ||
      typeof inputs.values !== 'string' ||
      typeof moon.clientProgramInstalledEffectOperationDemandPrepare !== 'function') {
    fail('InstalledEffectOperationDemandUnavailable');
  }
  // Source acquisition originals cannot be inferred from profile DATA or
  // prepared again under another parent. This first existing connection
  // selects a Source-free Effect; Source/Model supply keeps its own owner.
  if (moon.clientProgramEffectAcquisitionCount(facts.prepared) !== 0 ||
      inputs.modelDemand !== undefined) fail('InstalledEffectPlanInputsUnavailable');
  const demands = members.map(member => {
    const recipe = recipeFor(member);
    if (recipe === undefined) fail('InstalledEffectOperationDemandUnavailable');
    return checked(moon.clientProgramInstalledEffectOperationDemandPrepare(
      facts.prepared, unit.stageIndex, member.effectId,
      recipe.memberOperations.map(entry => entry.extent),
      recipe.rowOperations.map(entry => entry.extent)));
  });
  const construct = facts.queryTimePreparation === undefined
    ? moon.clientProgramInstalledEffectManagedPlanPrepare
    : moon.clientProgramInstalledEffectManagedPlanPrepareAtQueryTime;
  if (typeof construct !== 'function') fail('InstalledEffectPlanRuntimeUnavailable');
  const original = [facts.prepared, facts.identity,
    ...(facts.queryTimePreparation === undefined ? [] : [facts.queryTimePreparation]),
    [], '', '', [], [], inputs.installedContracts,
    inputs.values, inputs.fragment, inputs.ordered, demands];
  // Empty query/evidence strings are unused arguments only for zero Sources;
  // they issue no query contract. Existing Core validates the checked graph.
  return checked(Reflect.apply(construct, moon, original));
}

// An internal child of the EXISTING capture retainer, not a cleanup/permission
// Owner. The selected implementation's native occurrence is debited before the
// constructor. Its output stays charged until the enclosing original route and
// request aliases have actually retired, including failed constructor prefixes.
export function prepareInstalledEffectRequestChild({run, memberIndex, rowIndex,
  operationIndex, operation, construct: originalConstruct, requestsRetired}) {
  if (run === undefined || typeof originalConstruct !== 'function' ||
      typeof requestsRetired !== 'function') fail('InstalledEffectConstructorUnavailable');
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run;
  const borrow = runtime?.clientProgramInstalledEffectOperationBorrow;
  const retire = runtime?.clientProgramInstalledEffectOperationRetire;
  if (![borrow, retire, readPlan].every(method => typeof method === 'function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const current = () => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.runtime !== runtime || run.value !== parent || run.prepared !== prepared ||
        run.request !== request || run.operationPlan !== plan || run.readPlan !== readPlan ||
        checked(Reflect.apply(readPlan, runtime, [parent, prepared, request])) !== plan) {
      fail('ForeignInstalledEffectManagedRun');
    }
    // The native current callback can invalidate its original Node record.
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.runtime !== runtime || run.value !== parent || run.prepared !== prepared ||
        run.request !== request || run.operationPlan !== plan || run.readPlan !== readPlan) {
      fail('ForeignInstalledEffectManagedRun');
    }
  };
  current();
  let token = checked(Reflect.apply(borrow, runtime,
    [parent, prepared, request, plan, memberIndex, true, operationIndex, rowIndex, operation]));
  let construct = originalConstruct;
  let state = 'fresh';
  let preparing = false;
  const drain = () => {
    if (state === 'retired') return true;
    if (preparing || requestsRetired() !== true) return false;
    // Clear this child's last input/callback references BEFORE the same native
    // body token may settle. The enclosing capture has already severed output.
    construct = undefined;
    if (checked(Reflect.apply(retire, runtime, [token, true])) !== true) return false;
    token = undefined;
    state = 'retired';
    return true;
  };
  return Object.freeze({
    prepare() {
      if (state === 'retired') fail('InstalledEffectRequestChildRetired');
      if (state !== 'fresh') fail('InstalledEffectRequestChildAlreadyPrepared');
      state = 'preparing';
      preparing = true;
      try {
        current();
        const value = construct();
        const then = value !== null && (typeof value === 'object' || typeof value === 'function')
          ? value.then : undefined;
        if (typeof then === 'function') {
          // Invalid async work remains joined to the SAME retained child until
          // settlement. A rejected/fulfilled Promise is still not a sync value.
          return new Promise((resolve, reject) => Reflect.apply(then, value, [resolve, reject]))
            .then(() => {fail('InstalledEffectConstructorNotSynchronous');},
              () => {fail('InstalledEffectConstructorNotSynchronous');})
            .finally(() => {preparing = false; state = 'failed';});
        }
        current();
        state = 'prepared';
        preparing = false;
        return value;
      } catch (error) {
        preparing = false;
        state = 'failed';
        throw error;
      }
    },
    release: drain, retry: drain,
    status: () => Object.freeze({pending: state !== 'retired'}),
  });
}

// Internal physical sibling of the same capture child. The original Site binds
// an ALREADY-issued read/effect authorization; this never signs another grant.
// One selected HTTP body operation and its binary response reader share one
// native occurrence. Form reads and writes must select separate occurrences.
export function prepareInstalledEffectCredentialChild({run, memberIndex, rowIndex,
  operationIndex, operation, originalSite, originalAuthorization, useId, resource,
  purpose, runInvocationCid, dispatchRequestCid, maxRequestBytes, maxResponseBytes,
  assertCurrent, observeCurrent, requestsRetired, invoke: originalInvoke}) {
  if (run === undefined || ![originalInvoke, assertCurrent, observeCurrent, requestsRetired]
      .every(value => typeof value === 'function') || !text(useId) || !text(resource) ||
      !['read', 'target-read', 'effect'].includes(purpose) || !text(runInvocationCid) || !text(dispatchRequestCid) ||
      ![maxRequestBytes,maxResponseBytes].every(value => Number.isSafeInteger(value) && value > 0)) {
    fail('InvalidInstalledEffectCredentialOperation');
  }
  const own = (value, name) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) fail('InvalidInstalledEffectCredentialOperation');
    const field = Object.getOwnPropertyDescriptor(value,name);
    if (!field || !Object.hasOwn(field,'value')) fail('InvalidInstalledEffectCredentialOperation');
    return field.value;
  };
  const method = (value,name) => {const fn=own(value,name);if(typeof fn!=='function')fail('InstalledEffectCredentialOperationUnavailable');return fn;};
  let site=originalSite,authorization=originalAuthorization,invoke=originalInvoke;
  let bind=method(site,'bindRunAcquisition'),readPurpose=method(site,'authorizationPurpose'),
    referenceCurrent=method(site,'referenceCurrent'),physical=method(site,'callResource');
  originalSite=originalAuthorization=originalInvoke=undefined;
  const {runtime,value:parent,prepared,request,operationPlan:plan,readPlan}=run;
  const select=runtime?.clientProgramInstalledEffectManagedPlanOperation,
    isPhysical=runtime?.clientProgramInstalledEffectOperationExtentPhysical,
    transfer=runtime?.clientProgramInstalledEffectOperationExtentTransfer,
    borrow=runtime?.clientProgramInstalledEffectOperationBorrow,
    start=runtime?.clientProgramInstalledEffectOperationStart,
    charge=runtime?.clientProgramInstalledEffectOperationCharge,
    retire=runtime?.clientProgramInstalledEffectOperationRetire;
  if (![readPlan,select,isPhysical,transfer,borrow,start,charge,retire].every(value=>typeof value==='function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const nativeCurrent=()=>{
    const same=()=>run.closed!==true && run.runtime===runtime && run.value===parent && run.prepared===prepared &&
      run.request===request && run.operationPlan===plan && run.readPlan===readPlan;
    if(Object.hasOwn(run,'failure'))throw run.failure;
    if(!same()||checked(Reflect.apply(readPlan,runtime,[parent,prepared,request]))!==plan)fail('ForeignInstalledEffectManagedRun');
    if(Object.hasOwn(run,'failure'))throw run.failure;
    if(!same())fail('ForeignInstalledEffectManagedRun');
  };
  nativeCurrent();
  const extent=checked(Reflect.apply(select,runtime,[plan,memberIndex,true,operationIndex,operation]));
  const declaredTransfer=Reflect.apply(transfer,runtime,[extent]);
  if(Reflect.apply(isPhysical,runtime,[extent])!==true || typeof declaredTransfer!=='bigint' ||
      declaredTransfer<BigInt(maxRequestBytes)+httpsCredentialResponseWindowBytes(maxResponseBytes)) {
    fail('InsufficientInstalledEffectOperationTransfer');
  }
  let token=checked(Reflect.apply(borrow,runtime,[parent,prepared,request,plan,memberIndex,true,operationIndex,rowIndex,operation]));
  let state='fresh',preparing=false,closing=false,accountingFailed=false,callStarted=false;
  let acquisition,closeBinding,boundCredential,bindingClosed=false,pendingFence,closeFlight,physicalFlight;
  const retainFence=value=>{
    const then=value!==null&&(typeof value==='object'||typeof value==='function')?value.then:undefined;
    if(typeof then==='function')pendingFence=new Promise((yes,no)=>Reflect.apply(then,value,[yes,no])).then(()=>undefined,()=>undefined);
  };
  const check=()=>{
    nativeCurrent();
    const returned=assertCurrent();
    if(returned!==undefined){retainFence(returned);fail('InvalidInstalledEffectCurrentFence');}
    const current=Reflect.apply(referenceCurrent,site,[]);
    if(current!==true){retainFence(current);fail('InstalledEffectCredentialNotCurrent');}
    nativeCurrent();
  };
  const observe=async()=>{check();await observeCurrent();check();};
  const chargeBytes=bytes=>{
    try{checked(Reflect.apply(charge,runtime,[token,bytes]));}
    catch(error){accountingFailed=true;throw error;}
  };
  const callResource=options=>{
    if(closing||callStarted)fail('InstalledEffectOperationAlreadyUsed');
    check();
    const scope=authorization.scope;
    if(options.grant!==authorization.grant || options.useId!==useId ||
        credentialInvocationBindingKeys.some(key=>options.scope?.[key]!==scope[key]) ||
        options.scope?.operation!==operation || options.binding!==boundCredential.binding ||
        options.control!==boundCredential.control || options.journal!==boundCredential.journal ||
        options.resolveSecret!==boundCredential.resolveSecret || options.maxRequestBytes!==maxRequestBytes ||
        options.maxResponseBytes!==maxResponseBytes || !(options.operations instanceof Map) ||
        nodeTypes.isProxy(options.operations) || options.operations.size!==1)fail('ForeignInstalledEffectCredentialOperation');
    const selected=Map.prototype.get.call(options.operations,operation);
    if(selected===undefined || !Object.isFrozen(selected) || nodeTypes.isProxy(selected))fail('InvalidInstalledEffectHttpOperation');
    const fields=Object.getOwnPropertyDescriptors(selected);
    if(Reflect.ownKeys(fields).some(name=>!['method','path','body','headers','responseHeaders'].includes(name)||!Object.hasOwn(fields[name],'value'))) {
      fail('UnsupportedInstalledEffectHttpRepresentation');
    }
    const body=fields.body?.value;
    if(body!==undefined&&typeof body!=='string')fail('UnsupportedInstalledEffectHttpRepresentation');
    const bytes=body===undefined?0:Buffer.byteLength(body);
    if(bytes>maxRequestBytes)fail('InstalledEffectRequestByteLimit');
    callStarted=true;
    chargeBytes(BigInt(bytes));
    // Preserve exact original method/path/headers/body/CID semantics. The
    // existing Resource still performs its own current/transport validation.
    const result=Reflect.apply(physical,site,[{...options,operations:new Map([[operation,selected]]),
      observeResponseBytes:bytes=>{chargeBytes(BigInt(bytes));}}]);
    // Join the SAME call even if a provider omits its await or throws after
    // starting it. The envelope keeps rejection handled without discarding it;
    // prepare below still reports it when no earlier failure was thrown.
    physicalFlight=Promise.resolve(result).then(value=>({ok:true,value}),error=>({ok:false,error}));
    return result;
  };
  const drain=()=>{
    if(state==='retired')return true;
    closing=true;
    if(closeFlight!==undefined)return closeFlight;
    if(pendingFence!==undefined)return false;
    if(acquisition!==undefined&&!bindingClosed){
      if(closeBinding===undefined)return false;
      const result=Reflect.apply(closeBinding,acquisition,[]);
      if(result==='closed')bindingClosed=true;
      else if(result!=='pending'){
        const then=result!==null&&(typeof result==='object'||typeof result==='function')?result.then:undefined;
        if(typeof then!=='function')fail('InvalidInstalledEffectBindingCleanup');
        closeFlight=new Promise((yes,no)=>Reflect.apply(then,result,[yes,no])).then(()=>false,()=>false)
          .finally(()=>{closeFlight=undefined;});
        return closeFlight;
      }
    }
    if(preparing||accountingFailed||(acquisition!==undefined&&!bindingClosed)||requestsRetired()!==true)return false;
    invoke=authorization=acquisition=boundCredential=closeBinding=bind=readPurpose=referenceCurrent=physical=site=physicalFlight=undefined;
    if(checked(Reflect.apply(retire,runtime,[token,true]))!==true)return false;
    token=undefined;state='retired';return true;
  };
  return Object.freeze({
    async prepare(){
      if(state!=='fresh'||closing)fail('InstalledEffectOperationAlreadyPrepared');
      state='preparing';preparing=true;
      let primaryFailed=false;
      try{
        check();
        const originalPurpose=Reflect.apply(readPurpose,site,[authorization]),scope=authorization?.scope;
        if(originalPurpose?.kind!==purpose||originalPurpose.resource!==resource||scope?.operation!==operation||
            scope.runInvocationCid!==runInvocationCid||scope.dispatchRequestCid!==dispatchRequestCid||
            scope.runtimeBundleCid!==site.runtimeBundleCid||scope.connectorRegistration!==site.connectorRegistration||
            scope.connectorRevision!==site.connectorRevision)fail('ForeignInstalledEffectAuthorizationPurpose');
        // The exact issuer's synchronous factory performs no physical request;
        // the existing capture already retained this child before entry.
        acquisition=Reflect.apply(bind,site,[authorization,{assertCurrent:check,observeCurrent:observe}]);
        if(acquisition===null||typeof acquisition!=='object'||nodeTypes.isProxy(acquisition))fail('InvalidInstalledEffectCredentialBinding');
        closeBinding=method(acquisition,'close');
        boundCredential=own(acquisition,'credential');
        if(boundCredential===null||typeof boundCredential!=='object')fail('InvalidInstalledEffectCredentialBinding');
        check();
        checked(Reflect.apply(start,runtime,[token]));
        const result=await invoke({authorization:Object.freeze({...authorization,useId}),credential:boundCredential,callResource});
        if(!callStarted)fail('InstalledEffectPhysicalOperationUnavailable');
        check();state='prepared';return result;
      }catch(error){primaryFailed=true;state='failed';throw error;}
      finally{
        const observed=physicalFlight===undefined?undefined:await physicalFlight;
        if(pendingFence!==undefined){await pendingFence;pendingFence=undefined;}
        preparing=false;
        if(!primaryFailed&&observed?.ok===false){state='failed';throw observed.error;}
      }
    },
    release:drain,retry:drain,status:()=>Object.freeze({pending:state!=='retired'}),
  });
}
