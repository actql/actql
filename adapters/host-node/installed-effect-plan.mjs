import {registerInstalledEffectDependencyOriginal,retireInstalledEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
// Pure composition inside the existing installed Effect owner. Original
// Core extents/Plan are DATA until the SAME Request completes and adopts them.
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {isEffectPreparationRefusal} from '../host-common/effect-preparation-result.mjs';
import {httpsCredentialResponseWindowBytes, httpsCredentialResponseHeaderByteLimit, httpsCredentialResponseReadQuantum}
  from '../site-node/https-credential-resource.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
import {ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {rejectInstalledEffectPlan as fail, installedEffectPlanText as text}
  from './installed-effect-recipe.mjs';
export {captureInstalledEffectPlanRecipe, selectInstalledEffectCredentialOperation,
  installedEffectSavedControlEntryLimit, installedEffectSavedControlResponseLimit,
  installedEffectRecipeForControlEntryLimit} from './installed-effect-recipe.mjs';
export {prepareInstalledEffectManagedPlan} from './installed-effect-managed-plan.mjs';
export {effectRecoveryPreviewBounds, captureInstalledStandardCreateLimits, prepareInstalledStandardCreatePlanRecipe,
  prepareInstalledDeclaredUpdatePlanRecipe, prepareInstalledPhysicalWritePlanRecipe,
  captureDeclaredUpdateTargetCapacity} from './installed-effect-recipe-construction.mjs';
import {NativePromise, nativePromiseThen} from './installed-effect-child-construction.mjs';
export {prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectRequestChild,
  prepareInstalledEffectCaptureChild} from './installed-effect-child-construction.mjs';

// Internal physical sibling of the same capture child. The original Site binds
// an ALREADY-issued read/effect authorization; this never signs another grant.
// One selected HTTP body operation and its binary response reader share one
// native occurrence. Form reads and writes must select separate occurrences.
export function prepareInstalledEffectCredentialChild({run, memberIndex, rowIndex,
  operationIndex, operation, perRow = true, originalSite, originalAuthorization, useId, resource,
  purpose, runInvocationCid, dispatchRequestCid, maxRequestBytes, maxResponseBytes,
  assertCurrent, observeCurrent, requestsRetired, invoke: originalInvoke, responseExtent: originalResponseExtent, responsePreparation: originalResponsePreparation,
  discardResponseProjection = false}) {
  if (run === undefined || typeof perRow !== 'boolean' || ![originalInvoke, assertCurrent, observeCurrent, requestsRetired]
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
  let site=originalSite,authorization=originalAuthorization,invoke=originalInvoke,responseExtent=originalResponseExtent,
    responsePreparation=originalResponsePreparation;
  let prepareResponse,retireResponse;
  if(responsePreparation!==undefined){
    if(typeof responseExtent!=='function')fail('InvalidInstalledEffectResponsePreparation');
    prepareResponse=method(responsePreparation,'prepare');retireResponse=method(responsePreparation,'retire');
    if([prepareResponse,retireResponse].some(fn=>nodeTypes.isProxy(fn)||nodeTypes.isAsyncFunction(fn)))fail('InvalidInstalledEffectResponsePreparation');
  }
  let bind=method(site,'bindRunAcquisition'),readPurpose=method(site,'authorizationPurpose'),
    referenceCurrent=method(site,'referenceCurrent'),physical=method(site,'callResource');
  originalSite=originalAuthorization=originalInvoke=originalResponseExtent=originalResponsePreparation=undefined;
  const {runtime,value:parent,prepared,request,operationPlan:plan,readPlan}=run;
  const select=runtime?.clientProgramInstalledEffectManagedPlanOperation,
    isPhysical=runtime?.clientProgramInstalledEffectOperationExtentPhysical,
    transfer=runtime?.clientProgramInstalledEffectOperationExtentTransfer,
    responseBackingFits=runtime?.clientProgramInstalledEffectOperationResponseBackingFits,
    borrow=runtime?.clientProgramInstalledEffectOperationBorrow,
    start=runtime?.clientProgramInstalledEffectOperationStart,
    beginInput=runtime?.clientProgramInstalledEffectOperationInputBegin,
    responseComplete=runtime?.clientProgramInstalledEffectOperationResponseProjectionComplete,
    discardedResponseComplete=runtime?.clientProgramInstalledEffectOperationDiscardedResponseProjectionComplete,
    responseHeadersRequire=runtime?.clientProgramInstalledEffectOperationResponseHeadersRequire,
    charge=runtime?.clientProgramInstalledEffectOperationCharge,
    retire=runtime?.clientProgramInstalledEffectOperationRetire;
  if (![readPlan,select,isPhysical,transfer,responseBackingFits,borrow,start,charge,retire].every(value=>typeof value==='function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  if(responseExtent!==undefined&&(typeof responseExtent!=='function'||typeof beginInput!=='function'||typeof responseComplete!=='function')){
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  if (discardResponseProjection && (typeof discardedResponseComplete !== 'function' || responsePreparation === undefined)) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  if (responseHeadersRequire !== undefined && typeof responseHeadersRequire !== 'function') {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const originalRecord=()=>{
    const same=()=>run.closed!==true && run.runtime===runtime && run.value===parent && run.prepared===prepared &&
      run.request===request && run.operationPlan===plan && run.readPlan===readPlan;
    if(Object.hasOwn(run,'failure'))throw run.failure;
    if(!same())fail('ForeignInstalledEffectManagedRun');
  };
  const nativeCurrent=()=>{
    originalRecord();
    if(checked(Reflect.apply(readPlan,runtime,[parent,prepared,request]))!==plan)fail('ForeignInstalledEffectManagedRun');
    originalRecord();
  };
  originalRecord();
  try {
    // These original extent projections inspect immutable Plan DATA only.
    // The atomic borrow below owns the successful current/reservation boundary.
    const extent=checked(Reflect.apply(select,runtime,[plan,memberIndex,perRow,operationIndex,operation]));
    const declaredTransfer=Reflect.apply(transfer,runtime,[extent]);
    if(Reflect.apply(isPhysical,runtime,[extent])!==true || typeof declaredTransfer!=='bigint' ||
        declaredTransfer<BigInt(maxRequestBytes)+httpsCredentialResponseWindowBytes(maxResponseBytes)) {
      fail('InsufficientInstalledEffectOperationTransfer');
    }
    if(maxResponseBytes>2147483647 || !Number.isSafeInteger(httpsCredentialResponseHeaderByteLimit) ||
        httpsCredentialResponseHeaderByteLimit<1 || httpsCredentialResponseHeaderByteLimit>2147483647 ||
        Reflect.apply(responseBackingFits,runtime,[extent,maxResponseBytes,httpsCredentialResponseHeaderByteLimit,httpsCredentialResponseReadQuantum])!==true) {
      fail('InsufficientInstalledEffectResponseBacking');
    }
  } catch(error) {
    // No borrow follows a metadata refusal. Preserve its original current and
    // Unknown precedence, including an original failure whose value is undefined.
    nativeCurrent();
    throw error;
  }
  originalRecord();
  let token=checked(Reflect.apply(borrow,runtime,[parent,prepared,request,plan,memberIndex,perRow,operationIndex,rowIndex,operation]));
  let state='fresh',preparing=false,closing=false,accountingFailed=false,callStarted=false;
  let acquisition,closeBinding,boundCredential,bindingClosed=false,pendingFence,fenceFlight,pendingClose,closeFlight,physicalFlight;
  const retainFence=value=>{
    if(value===null||!['object','function'].includes(typeof value))return;
    pendingFence=value;
    if(nodeTypes.isPromise(value)){
      fenceFlight=new NativePromise(resolve=>{
        const settled=()=>{pendingFence=undefined;resolve();};
        try{Reflect.apply(nativePromiseThen,value,[settled,settled]);}
        catch{resolve();} // Observation failure is not settlement of the retained task.
      });
    }else if(typeof value.then!=='function')pendingFence=undefined;
  };
  const check=()=>{
    nativeCurrent();
    if(pendingFence!==undefined)fail('InvalidInstalledEffectCurrentFence');
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
    // Freeze the same declared names through the existing exchange owner;
    // Common checks only its original empty-selection constraint, no pricing.
    const names=responseHeadersRequire===undefined?undefined:
      ownResponseHeaderNames(fields.responseHeaders?.value);
    if(names!==undefined) {
      checked(Reflect.apply(responseHeadersRequire,runtime,[token,names,httpsCredentialResponseHeaderByteLimit]));
      originalRecord();
    }
    callStarted=true;
    chargeBytes(BigInt(bytes));
    // Preserve exact original method/path/headers/body/CID semantics. The
    // existing Resource still performs its own current/transport validation.
    const result=Reflect.apply(physical,site,[{...options,operations:new Map([[operation,
      names===undefined?selected:Object.freeze({...selected,responseHeaders:names})]]),
      observeResponseBytes:bytes=>{chargeBytes(BigInt(bytes));}}]);
    // Join the SAME call even if a provider omits its await or throws after
    // starting it. The envelope keeps rejection handled without discarding it;
    // prepare below still reports it when no earlier failure was thrown.
    // Grow before the SAME response escapes to any provider decoder. The
    // received body remains in this already-retained physical child's custody
    // if quantity selection, current or resize refuses.
    const response = responseExtent === undefined ? result : Promise.resolve(result).then(value=>{
      originalRecord();
      if(!Buffer.isBuffer(value?.body)&&!(value?.body instanceof Uint8Array))fail('InvalidInstalledEffectResponseBody');
      // This same physical child prepaid the fixed Source preflight before
      // receiving bytes. The provider keeps its opaque cursor; only sizing
      // scalars cross into the independently installed Common constructor.
      const geometry=responsePreparation===undefined?undefined:
        Reflect.apply(prepareResponse,responsePreparation,[value.body]);
      if(geometry!==undefined&&(!Array.isArray(geometry)||nodeTypes.isProxy(geometry))){
        retainFence(geometry);fail('InvalidInstalledEffectResponsePreparation');
      }
      originalRecord();
      const extent=responseExtent(value.body.byteLength, value.body, geometry);
      originalRecord();
      checked(Reflect.apply(beginInput,runtime,[token,extent]));
      originalRecord();return value;
    });
    physicalFlight=Promise.resolve(response).then(value=>({ok:true,value}),error=>({ok:false,error}));
    return response;
  };
  const drain=()=>{
    if(state==='retired')return true;
    closing=true;
    if(closeFlight!==undefined)return closeFlight;
    if(pendingFence!==undefined||pendingClose!==undefined)return false;
    if(acquisition!==undefined&&!bindingClosed){
      if(closeBinding===undefined)return false;
      const result=Reflect.apply(closeBinding,acquisition,[]);
      if(result==='closed')bindingClosed=true;
      else if(result!=='pending'){
        if(result!==null&&['object','function'].includes(typeof result))pendingClose=result;
        if(nodeTypes.isPromise(result)){
          closeFlight=new NativePromise(resolve=>{
            const settled=()=>{pendingClose=undefined;closeFlight=undefined;resolve(false);};
            try{Reflect.apply(nativePromiseThen,result,[settled,settled]);}
            catch{resolve(false);} // Keep the unjoined original; never infer a close ACK.
          });
          return closeFlight;
        }
        fail('InvalidInstalledEffectBindingCleanup');
      }
    }
    if(preparing||accountingFailed||(acquisition!==undefined&&!bindingClosed)||requestsRetired()!==true)return false;
    if(retireResponse!==undefined){
      const returned=Reflect.apply(retireResponse,responsePreparation,[]);
      if(returned!==undefined){retainFence(returned);fail('InvalidInstalledEffectResponsePreparation');}
    }
    responsePreparation=prepareResponse=retireResponse=undefined;
    invoke=responseExtent=authorization=acquisition=boundCredential=closeBinding=bind=readPurpose=referenceCurrent=physical=site=physicalFlight=undefined;
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
        if(discardResponseProjection && result!==undefined)fail('InvalidInstalledEffectDiscardedProjection');
        check();state='prepared';return result;
      }catch(error){primaryFailed=true;state='failed';throw error;}
      finally{
        const observed=physicalFlight===undefined?undefined:await physicalFlight;
        if(fenceFlight!==undefined){await fenceFlight;fenceFlight=undefined;}
        try{
          if(!primaryFailed&&observed?.ok===false){state='failed';throw observed.error;}
          if(!primaryFailed&&responseExtent!==undefined){
            try{
              // The SAME request flight and provider projection both settled.
              // Keep all body/output retention and physical cleanup pending;
              // this typed original cut returns only private parser workspace.
              check();
              if(discardResponseProjection){
                // The actual Unit projector and request flight returned. Retire
                // its SAME staged Reader then sever every projection callback
                // before Core releases only the original Plan-bound material.
                const returned=Reflect.apply(retireResponse,responsePreparation,[]);
                if(returned!==undefined){retainFence(returned);fail('InvalidInstalledEffectResponsePreparation');}
                responsePreparation=prepareResponse=retireResponse=undefined;
                invoke=responseExtent=undefined;
                check();checked(Reflect.apply(discardedResponseComplete,runtime,[token]));check();
              }else {checked(Reflect.apply(responseComplete,runtime,[token]));check();}
            }catch(error){state='failed';throw error;}
          }
        }finally{preparing=false;}
      }
    },
    release:drain,retry:drain,status:()=>Object.freeze({pending:state!=='retired'}),
  });
}


// The existing Run owns this synchronous control frame, its original methods
// and any invalid borrowed task. This is not a grant, new owner or caller fee.
export function prepareInstalledEffectControlConstruction(run) {
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run ?? {};
  const begin = runtime?.clientProgramInstalledEffectOperationControlConstructionBegin;
  const nativeBegin = runtime?.clientProgramInstalledEffectOperationNativeConstructionBegin;
  const receiptBegin = runtime?.clientProgramInstalledEffectOperationMemberReceiptConstructionBegin;
  const complete = runtime?.clientProgramInstalledEffectOperationControlConstructionComplete;
  const grantBegin = runtime?.clientProgramInstalledEffectOperationGrantConstructionBegin;
  const requestProjectionBegin = runtime?.clientProgramInstalledEffectOperationRequestProjectionBegin;
  const footprintBegin = runtime?.clientProgramInstalledEffectOperationFootprintConstructionBegin;
  const ledgerOpenBegin = runtime?.clientProgramInstalledEffectOperationLedgerOpenBegin;
  const ledgerFamilyBegin = runtime?.clientProgramInstalledEffectOperationLedgerFamilyBegin;
  const ledgerRowBegin = runtime?.clientProgramInstalledEffectOperationLedgerRowBegin;
  const ledgerHistoryGrow = runtime?.clientProgramInstalledEffectOperationLedgerHistoryGrow;
  const beginInput = runtime?.clientProgramInstalledEffectOperationControlInputBegin;
  const codecBegin = runtime?.clientProgramInstalledEffectOperationLedgerCodecBegin;
  const receiptCodecBegin = runtime?.clientProgramInstalledEffectOperationReceiptCodecBegin;
  const codecComplete = runtime?.clientProgramInstalledEffectOperationLedgerCodecComplete;
  const hasHostInput = runtime?.clientProgramInstalledEffectManagedPlanHasHostInput;
  const retainInventory = runtime?.clientProgramInstalledEffectCapturedInputInventoryRetain;
  const shape = runtime?.clientProgramInstalledEffectManagedPlanShape;
  const keyAuthor = runtime?.clientProgramAuthorInstalledEffectPreview;
  const keyRecovery = runtime?.clientProgramInstalledEffectRecoveredPreviewKeys;
  const parseJson = JSON.parse;
  const jsonReceiver = JSON;
  if (![begin, complete, readPlan].every(method => typeof method === 'function') || parent === undefined || plan === undefined) {
    fail('InstalledEffectControlRuntimeUnavailable');
  }
  let working = false, codecWorking = false, historyWorking = false, failed = false, retired = false, primary, pending, work;
  let previewInputWire, previewInput;
  const sameRecord = () => !run.closed && run.runtime === runtime && run.value === parent &&
    run.prepared === prepared && run.request === request && run.operationPlan === plan &&
    run.readPlan === readPlan && run.controlConstruction === work;
  const originalRecord = () => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (!sameRecord()) fail('ForeignInstalledEffectManagedRun');
  };
  const retainInvalid = value => {
    if (value === null || !['object', 'function'].includes(typeof value)) return;
    pending = value;
    const settled = () => {pending = undefined; run.selecting = false;};
    if (nodeTypes.isPromise(value)) {
      // Native original first. A species/join refusal leaves the same task
      // unobserved and the existing Run retirement latch held, never an ACK.
      Reflect.apply(nativePromiseThen, value, [settled, settled]);
      fail('InvalidInstalledEffectControlConstruction');
    }
    const then = value.then;
    if (typeof then !== 'function') {pending = undefined; return;}
    const joined = new NativePromise((yes, no) => Reflect.apply(then, value, [yes, no]));
    Reflect.apply(nativePromiseThen, joined, [settled, settled]);
    fail('InvalidInstalledEffectControlConstruction');
  };
  const invoke = (receiver, method, args, inputWire, grant = false, requestProjection, footprintProjection, ledgerRoot, ledgerFamily, nativeConstruction, memberReceipt = false, ledgerRow) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    if (typeof method !== 'function' || !Array.isArray(args)) fail('InvalidInstalledEffectControlConstruction');
    if (nativeConstruction !== undefined && (nativeConstruction === null || typeof nativeConstruction !== 'object' || nodeTypes.isProxy(nativeConstruction))) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    if (typeof memberReceipt !== 'boolean' || memberReceipt && nativeConstruction === undefined) fail('InvalidInstalledEffectControlConstruction');
    if (nativeConstruction !== undefined && typeof (memberReceipt ? receiptBegin : nativeBegin) !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    // These exact installing Core entrances own their Resource cut: the
    // borrowed Plan getter, or a key constructor that grows this SAME parent
    // before allocation. No arbitrary callback or Host count selects it.
    const metadata = nativeConstruction === undefined && ledgerRow === undefined && ledgerFamily === undefined && ledgerRoot === undefined && !grant && requestProjection === undefined && footprintProjection === undefined && inputWire === undefined && receiver === runtime &&
      !nodeTypes.isProxy(method) && !nodeTypes.isProxy(args) &&
      (method === shape && Object.getOwnPropertyDescriptor(args, 'length')?.value === 1 &&
        Object.getOwnPropertyDescriptor(args, '0')?.value === plan ||
       (method === keyAuthor && Object.getOwnPropertyDescriptor(args, 'length')?.value === 19 ||
        method === keyRecovery && Object.getOwnPropertyDescriptor(args, 'length')?.value === 15) &&
        Object.getOwnPropertyDescriptor(args, '0')?.value === parent &&
        Object.getOwnPropertyDescriptor(args, '1')?.value === prepared &&
        Object.getOwnPropertyDescriptor(args, '2')?.value === request &&
        Object.getOwnPropertyDescriptor(args, '3')?.value === plan);
    const observePlan = () => {
      const current = Reflect.apply(readPlan, runtime, [parent, prepared, request]);
      retainInvalid(current);
      if (checked(current) !== plan) fail('ForeignInstalledEffectManagedRun');
      originalRecord();
    };
    working = true;
    let invoking = false;
    // The existing parent retirement already refuses this latch. Retain it
    // through native-task settlement if an invalid asynchronous result escapes.
    run.selecting = true;
    try {
      originalRecord();
      if (metadata) observePlan();
      else checked(Reflect.apply(nativeConstruction !== undefined ? memberReceipt ? receiptBegin : nativeBegin :
        ledgerRow !== undefined && ledgerRowBegin !== undefined ? ledgerRowBegin :
        ledgerFamily !== undefined && ledgerFamilyBegin !== undefined ? ledgerFamilyBegin :
        ledgerRoot !== undefined && ledgerOpenBegin !== undefined ? ledgerOpenBegin :
        footprintProjection !== undefined && footprintBegin !== undefined ? footprintBegin :
        requestProjection !== undefined && requestProjectionBegin !== undefined ? requestProjectionBegin :
        grant && grantBegin !== undefined ? grantBegin :
        inputWire === undefined ? begin : beginInput, runtime,
        [parent, prepared, request, plan, ...(ledgerRow !== undefined && ledgerRowBegin !== undefined
          ? ledgerRow : ledgerFamily !== undefined && ledgerFamilyBegin !== undefined
          ? ledgerFamily : ledgerRoot !== undefined && ledgerOpenBegin !== undefined
          ? [ledgerRoot] : footprintProjection !== undefined && footprintBegin !== undefined
          ? footprintProjection : requestProjection !== undefined && requestProjectionBegin !== undefined
            ? requestProjection : inputWire === undefined ? [] : [inputWire]),
          ...(nativeConstruction === undefined ? [] : [nativeConstruction])]));
      originalRecord();
      invoking = true;
      const value = Reflect.apply(method, receiver, metadata && method === shape ? [plan] : args);
      invoking = false;
      if (failed) throw primary;
      retainInvalid(value);
      // These closed key entrances return Core Results. Preserve an actual
      // resource/semantic refusal before another current callback can replace
      // its cause; a later call cannot reconstruct the failed key cohort.
      if (metadata && method !== shape) checked(value);
      originalRecord();
      if (metadata) observePlan();
      else checked(Reflect.apply(complete, runtime, [parent, prepared, request, plan]));
      originalRecord();
      return value;
    } catch (cause) {
      if (invoking && !failed && pending === undefined && !codecWorking &&
          isEffectPreparationRefusal(cause)) {
        // This observed semantic refusal is the synchronous projector's
        // original DATA result. Its retained output stays on the SAME token;
        // only a successful original completion returns constructor scratch.
        // Keep the error for the existing Ledger/CAS/no-send decision outside
        // this frame. It grants neither a terminal Run nor physical cleanup.
        try {
          originalRecord();
          if (metadata) observePlan();
          else checked(Reflect.apply(complete, runtime, [parent, prepared, request, plan]));
          originalRecord();
        } catch (completionFailure) {
          // Scratch retirement is a separate result. Preserve even a thrown
          // undefined alongside the original refusal; the aggregate is NOT
          // marked as a completed semantic result and keeps this frame failed.
          failed = true;
          primary = Object.assign(new AggregateError([cause, completionFailure],
            'InstalledEffectControlConstructionPending', {cause}),
          {code: 'InstalledEffectControlConstructionPending',
            primaryFailure: cause, cleanupPending: true});
          throw primary;
        }
        throw cause;
      }
      failed = true; primary = cause;
      // Failed-prefix workspace remains on the SAME Core control reservation.
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  // The installing constructor owns this optional opaque Common quote. No
  // Host scalar pricing or provider-runtime opaque value crosses the seam.
  work = (receiver, method, args, nativeConstruction, memberReceipt = false) =>
    invoke(receiver, method, args, undefined, false, undefined, undefined, undefined, undefined, nativeConstruction, memberReceipt);
  // Installing Site issuers alone use this fixed Core constructor family.
  // Legacy runtimes keep the complete generic frame; JS quotes no quantities.
  const grant = (receiver, method, args) => invoke(receiver, method, args, undefined, true);
  // Core resolves these SAME Plan coordinates to its completed original
  // request child. JavaScript selects no quantity or replacement capability.
  // A legacy runtime still reserves the complete generic control frame.
  const requestProjection = (member, operation, row, receiver, method, args) => {
    if (![member, operation, row].every(value => Number.isSafeInteger(value) && value >= 0)) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    return invoke(receiver, method, args, undefined, false, [member, operation, row]);
  };
  // Fixed declared member footprint only; Core reads its original scratch.
  const footprint = (member, operation, receiver, method, args) => {
    if (![member, operation].every(value => Number.isSafeInteger(value) && value >= 0)) fail('InvalidInstalledEffectControlConstruction');
    return invoke(receiver, method, args, undefined, false, undefined, [member, operation]);
  };
  // Exact original openEffectLedger caller; Common owns all quantity math.
  const ledgerOpen = (root, receiver, method, args) => {
    if (typeof root !== 'string' || !Array.isArray(args) || nodeTypes.isProxy(args) ||
        Object.getOwnPropertyDescriptor(args, 'length')?.value !== 1) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    const options = Object.getOwnPropertyDescriptor(args, '0')?.value;
    if (options === null || typeof options !== 'object' || nodeTypes.isProxy(options) ||
        Object.getOwnPropertyDescriptor(options, 'root')?.value !== root) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    return invoke(receiver, method, args, undefined, false, undefined, undefined, root);
  };
  // Called only by the closed standard Ledger wrapper below. The frozen
  // lengths/policy scalars are geometry, not permission or completed checks.
  // All byte pricing, policy-family selection and coheld lifetimes are Core.
  const ledgerFamily = (receiver, method, args, counts, entries, bytes, nodes, depth) =>
    invoke(receiver, method, args, undefined, false, undefined, undefined,
      undefined, [counts, entries, bytes, nodes, depth]);
  const ledgerRow = (receiver, method, args, kind, bytes, nodes, depth, responseBytes) => {
    if (!['entry', 'response', 'receipt', 'quantity'].includes(kind) ||
        ![bytes, nodes, depth, responseBytes].every(value => Number.isSafeInteger(value) && value > 0)) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    return invoke(receiver, method, args, undefined, false, undefined, undefined,
      undefined, undefined, undefined, false, [kind, bytes, nodes, depth, responseBytes]);
  };
  // The original SQLite history reader invokes this before materializing its
  // same-transaction rows. It extends the active frame, never another owner.
  const ledgerHistory = (count, wireUnits) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (!working || !run.selecting || codecWorking || historyWorking) fail('InstalledEffectControlConstructionPending');
    if (!Number.isSafeInteger(count) || count < 0 || count > 2147483647 || !Number.isSafeInteger(wireUnits) || wireUnits < 0 ||
        typeof ledgerHistoryGrow !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    historyWorking = true;
    try {
      originalRecord();
      checked(Reflect.apply(ledgerHistoryGrow, runtime, [parent, prepared, request, plan, count, BigInt(wireUnits)]));
      originalRecord();
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally { historyWorking = false; }
  };
  // Only the original Ledger invokes this nested synchronous seam. The outer
  // control frame retains every output. The selected Ledger family adds its
  // coheld snapshot/array demand; generic frames retain the full family floor.
  // No Preview one-use identity or physical occurrence is reused.
  const ledgerCodec = (receiver, method, args, wire, nodes = 512, depth = 16, receiptWire) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (!working || !run.selecting || codecWorking) fail('InstalledEffectControlConstructionPending');
    if (typeof method !== 'function' || !Array.isArray(args) ||
        wire !== undefined && typeof wire !== 'string' ||
        !Number.isSafeInteger(nodes) || nodes < 1 || nodes > 4096 ||
        !Number.isSafeInteger(depth) || depth < 1 || depth > 32 ||
        receiptWire !== undefined && (typeof receiptWire !== 'boolean' || typeof wire !== 'string') ||
        typeof (receiptWire === undefined ? codecBegin : receiptCodecBegin) !== 'function' || typeof codecComplete !== 'function') {
      fail('InstalledEffectControlRuntimeUnavailable');
    }
    codecWorking = true;
    try {
      originalRecord();
      checked(Reflect.apply(receiptWire === undefined ? codecBegin : receiptCodecBegin, runtime,
        [parent, prepared, request, plan, wire, nodes, depth, ...(receiptWire === undefined ? [] : [receiptWire])]));
      originalRecord();
      const value = Reflect.apply(method, receiver, args);
      if (failed) throw primary;
      retainInvalid(value);
      originalRecord();
      checked(Reflect.apply(codecComplete, runtime, [parent, prepared, request, plan]));
      originalRecord();
      return value;
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally { codecWorking = false; }
  };
  const receiptCodec = (receiver, method, args, wire, nodes, depth, receiptWire) => {
    if (typeof receiptWire !== 'boolean') fail('InstalledEffectControlRuntimeUnavailable');
    return ledgerCodec(receiver, method, args, wire, nodes, depth, receiptWire);
  };
  const parsePreview = (wire, borrowOriginal = false) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    originalRecord();
    if (typeof wire !== 'string' || typeof borrowOriginal !== 'boolean' || typeof hasHostInput !== 'function') {
      fail('InstalledEffectControlRuntimeUnavailable');
    }
    // Hot recovery borrows the SAME funded forest. A cold owner has no such
    // original and must enter its first one-use constructor below.
    if (borrowOriginal && previewInputWire !== undefined) {
      if (wire !== previewInputWire) fail('ForeignInstalledEffectManagedRun');
      working = true;
      run.selecting = true;
      try {
        const current = Reflect.apply(readPlan, runtime, [parent, prepared, request]);
        retainInvalid(current);
        if (checked(current) !== plan) fail('ForeignInstalledEffectManagedRun');
        originalRecord();
        return previewInput;
      } catch (cause) {
        if (pending !== undefined) {failed = true; primary = cause;}
        throw cause;
      } finally {
        working = false;
        if (pending === undefined) run.selecting = false;
      }
    }
    // Other installed recipes retain their unchanged fixed parser envelope.
    // Only the typed opted-in Plan can refine this existing control token.
    const selected = Reflect.apply(hasHostInput, runtime, [plan]);
    if (typeof selected !== 'boolean') fail('InvalidHostRuntimeResult');
    if (!selected) {
      originalRecord();
      return Reflect.apply(parseJson, jsonReceiver, [wire]);
    }
    if (typeof beginInput !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    const parsed = invoke(jsonReceiver, parseJson, [wire], wire);
    previewInputWire = wire;
    previewInput = parsed;
    return parsed;
  };
  const retainInputs = inputs => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    if (typeof retainInventory !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    working = true;
    run.selecting = true;
    try {
      originalRecord();
      const result = Reflect.apply(retainInventory, runtime, [parent, prepared, request, plan, inputs]);
      retainInvalid(result);
      checked(result);
      originalRecord();
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  const retainRecoveredInputs = (control, allowed, definition, invocation, preview) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    const retain = control?.retainInstalledEffectRecoveredInputInventory;
    if (typeof retain !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    working = true;
    run.selecting = true;
    try {
      originalRecord();
      // This grows the existing control token before entering a constructor;
      // invoking work() here would incorrectly open that constructor first.
      const result = Reflect.apply(retain, control,
        [parent, prepared, request, plan, allowed, definition, invocation, preview]);
      retainInvalid(result);
      originalRecord();
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  const retire = () => {
    if (retired) return true;
    if (!sameRecord() || run.retireControlConstruction !== retire) fail('ForeignInstalledEffectManagedRun');
    if (working || pending !== undefined || run.selecting) return false;
    // Recovered requests remain on their original member constructor tokens
    // while any hot observation can borrow them. A stage close is not their
    // final retirement. Drop aliases and retire those SAME children before
    // returning this control/parent backing; pending cleanup stays pending.
    const recovery = run.recoveredRequestInput;
    if (recovery !== undefined) {
      if (recovery.retire() !== true) return false;
      if (run.recoveredRequestInput !== recovery || !sameRecord()) fail('ForeignInstalledEffectManagedRun');
      run.recoveredRequestInput = undefined;
    }
    // Actual complete dispatch retirement calls this before returning its
    // Core control backing. A retained Error may itself keep a heavy prefix.
    primary = undefined;
    previewInputWire = previewInput = undefined;
    retireInstalledEffectDependencyOriginal(work);
    retired = true;
    return true;
  };
  registerInstalledEffectDependencyOriginal(work,{runtime,parent,prepared,request,plan,current:originalRecord});
  return Object.freeze(Object.assign(work, {retire, parsePreview, ledgerCodec, grant, requestProjection, footprint, ledgerOpen, ledgerFamily,
    ...(typeof ledgerRowBegin === 'function' ? {ledgerRow} : {}),
    ...(typeof ledgerHistoryGrow === 'function' ? {ledgerHistory} : {}),
    ...(typeof receiptCodecBegin === 'function' ? {receiptCodec} : {}),
    retainInputs, retainRecoveredInputs}));
}
