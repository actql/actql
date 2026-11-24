import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {httpsCredentialResponseWindowBytes, httpsCredentialResponseHeaderByteLimit, httpsCredentialResponseReadQuantum}
  from '../site-node/https-credential-resource.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';
import {ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {rejectInstalledEffectPlan as fail, installedEffectPlanText as text}
  from './installed-effect-recipe.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {NativePromise, nativePromiseThen} from './installed-effect-child-construction.mjs';

type CoreResult = Extract<SynchronousRuntimeData, object>;
type Runtime = Readonly<{
  clientProgramInstalledEffectManagedPlanOperation(plan: unknown, memberIndex: number,
    perRow: boolean, operationIndex: number, operation: string): CoreResult;
  clientProgramInstalledEffectOperationExtentPhysical(extent: unknown): boolean;
  clientProgramInstalledEffectOperationExtentTransfer(extent: unknown): bigint;
  clientProgramInstalledEffectOperationResponseBackingFits(extent: unknown, responseBytes: number,
    headerBytes: number, readQuantum: number): boolean;
  clientProgramInstalledEffectOperationBorrow(parent: unknown, prepared: unknown, request: unknown,
    plan: unknown, memberIndex: number, perRow: boolean, operationIndex: number, rowIndex: number,
    operation: string): CoreResult;
  clientProgramInstalledEffectOperationStart(token: unknown): CoreResult;
  clientProgramInstalledEffectOperationInputBegin?(token: unknown, extent: unknown): CoreResult;
  clientProgramInstalledEffectOperationResponseProjectionComplete?(token: unknown): CoreResult;
  clientProgramInstalledEffectOperationDiscardedResponseProjectionComplete?(token: unknown): CoreResult;
  clientProgramInstalledEffectOperationResponseHeadersRequire?(token: unknown,
    names: readonly string[], headerBytes: number): CoreResult;
  clientProgramInstalledEffectOperationCharge(token: unknown, bytes: bigint): CoreResult;
  clientProgramInstalledEffectOperationRetire(token: unknown, cleanupConfirmed: boolean): CoreResult;
}>;
type Run = Readonly<{
  runtime: Runtime;
  value: unknown;
  prepared: unknown;
  request: unknown;
  operationPlan: unknown;
  readPlan(parent: unknown, prepared: unknown, request: unknown): CoreResult;
  closed?: boolean;
  failure?: unknown;
}>;
type Scope = Readonly<Partial<Record<typeof credentialInvocationBindingKeys[number] | 'operation', unknown>>>;
type Authorization = Readonly<{scope: Scope; grant: unknown}>;
type Site = Readonly<{runtimeBundleCid: unknown; connectorRegistration: unknown; connectorRevision: unknown}>;
type Credential = Readonly<{binding?: unknown; control?: unknown; journal?: unknown; resolveSecret?: unknown}>;
type RequestOptions = Credential & Readonly<{
  grant: unknown;
  useId: string;
  scope?: Scope;
  maxRequestBytes: number;
  maxResponseBytes: number;
  operations: ReadonlyMap<string, unknown>;
}>;
type ResponseExtent = (bytes: number, body: Uint8Array, geometry: readonly unknown[] | undefined) => unknown;
type ResponsePreparation = Readonly<{
  prepare(body: Uint8Array): readonly unknown[] | undefined;
  retire(): undefined;
}>;
type Invoke<Value> = (input: Readonly<{
  authorization: Authorization & Readonly<{useId: string}>;
  credential: Credential;
  callResource(options: RequestOptions): unknown;
}>) => Value | Promise<Value>;
type CredentialChildOptions<Value> = Readonly<{
  run: Run;
  memberIndex: number;
  rowIndex: number;
  operationIndex: number;
  operation: string;
  perRow?: boolean;
  originalSite: Site;
  originalAuthorization: Authorization;
  useId: string;
  resource: string;
  purpose: 'read' | 'target-read' | 'effect';
  runInvocationCid: string;
  dispatchRequestCid: string;
  maxRequestBytes: number;
  maxResponseBytes: number;
  assertCurrent(): undefined;
  observeCurrent(): undefined | Promise<void>;
  requestsRetired(): boolean;
  invoke: Invoke<Value>;
  responseExtent?: ResponseExtent;
  responsePreparation?: ResponsePreparation;
  discardResponseProjection?: boolean;
}>;
type ReleasedInputs = 'originalSite' | 'originalAuthorization' | 'invoke';
type CredentialChild<Value> = Readonly<{
  prepare(): Promise<Value>;
  release(): boolean | Promise<boolean>;
  retry(): boolean | Promise<boolean>;
  status(): Readonly<{pending: boolean}>;
}>;
type State = 'fresh' | 'preparing' | 'prepared' | 'failed' | 'retired';
type PhysicalObservation = {ok: true; value: unknown} | {ok: false; error: unknown};

// Internal physical sibling of the same capture child. The original Site binds
// an ALREADY-issued read/effect authorization; this never signs another grant.
// One selected HTTP body operation and its binary response reader share one
// native occurrence. Form reads and writes must select separate occurrences.
export function prepareInstalledEffectCredentialChild<Value>(options: CredentialChildOptions<Value>): CredentialChild<Value>;
export function prepareInstalledEffectCredentialChild<Value>({run, memberIndex, rowIndex,
  operationIndex, operation, perRow = true, originalSite, originalAuthorization, useId, resource,
  purpose, runInvocationCid, dispatchRequestCid, maxRequestBytes, maxResponseBytes,
  assertCurrent, observeCurrent, requestsRetired, invoke: originalInvoke, responseExtent: originalResponseExtent, responsePreparation: originalResponsePreparation,
  discardResponseProjection = false}: Omit<CredentialChildOptions<Value>, ReleasedInputs> &
    Readonly<{[Key in ReleasedInputs]?: CredentialChildOptions<Value>[Key]}>) {
  if (run === undefined || typeof perRow !== 'boolean' || ![originalInvoke, assertCurrent, observeCurrent, requestsRetired]
      .every(value => typeof value === 'function') || !text(useId) || !text(resource) ||
      !['read', 'target-read', 'effect'].includes(purpose) || !text(runInvocationCid) || !text(dispatchRequestCid) ||
      ![maxRequestBytes,maxResponseBytes].every(value => Number.isSafeInteger(value) && value > 0)) {
    fail('InvalidInstalledEffectCredentialOperation');
  }
  const own = (value: unknown, name: PropertyKey): unknown => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) fail('InvalidInstalledEffectCredentialOperation');
    const field = Object.getOwnPropertyDescriptor(value,name);
    if (!field || !Object.hasOwn(field,'value')) fail('InvalidInstalledEffectCredentialOperation');
    return field.value;
  };
  const method = (value: unknown,name: PropertyKey) => {const fn=own(value,name);if(typeof fn!=='function')fail('InstalledEffectCredentialOperationUnavailable');return fn;};
  let site=originalSite,authorization=originalAuthorization,invoke=originalInvoke,responseExtent=originalResponseExtent,
    responsePreparation=originalResponsePreparation;
  let prepareResponse: ReturnType<typeof method> | undefined,retireResponse: ReturnType<typeof method> | undefined;
  if(responsePreparation!==undefined){
    if(typeof responseExtent!=='function')fail('InvalidInstalledEffectResponsePreparation');
    prepareResponse=method(responsePreparation,'prepare');retireResponse=method(responsePreparation,'retire');
    if([prepareResponse,retireResponse].some(fn=>nodeTypes.isProxy(fn)||nodeTypes.isAsyncFunction(fn)))fail('InvalidInstalledEffectResponsePreparation');
  }
  let bind: ReturnType<typeof method> | undefined=method(site,'bindRunAcquisition'),
    readPurpose: ReturnType<typeof method> | undefined=method(site,'authorizationPurpose'),
    referenceCurrent: ReturnType<typeof method> | undefined=method(site,'referenceCurrent'),
    physical: ReturnType<typeof method> | undefined=method(site,'callResource');
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
  let state: State='fresh',preparing=false,closing=false,accountingFailed=false,callStarted=false;
  let acquisition: unknown,closeBinding: ReturnType<typeof method> | undefined,
    boundCredential: Credential | undefined,bindingClosed=false,pendingFence: unknown,
    fenceFlight: Promise<void> | undefined,pendingClose: unknown,closeFlight: Promise<boolean> | undefined,
    physicalFlight: Promise<PhysicalObservation> | undefined;
  const retainFence=(value: unknown)=>{
    if(value===null||!['object','function'].includes(typeof value))return;
    pendingFence=value;
    if(nodeTypes.isPromise(value)){
      fenceFlight=new NativePromise<void>(resolve=>{
        const settled=()=>{pendingFence=undefined;resolve();};
        try{Reflect.apply(nativePromiseThen,value,[settled,settled]);}
        catch{resolve();} // Observation failure is not settlement of the retained task.
      });
    }else if(typeof (value as {then?: unknown}).then!=='function')pendingFence=undefined;
  };
  const check=()=>{
    nativeCurrent();
    if(pendingFence!==undefined)fail('InvalidInstalledEffectCurrentFence');
    const returned=assertCurrent();
    if(returned!==undefined){retainFence(returned);fail('InvalidInstalledEffectCurrentFence');}
    const current=Reflect.apply(referenceCurrent!,site,[]);
    if(current!==true){retainFence(current);fail('InstalledEffectCredentialNotCurrent');}
    nativeCurrent();
  };
  const observe=async()=>{check();await observeCurrent();check();};
  const chargeBytes=(bytes: bigint)=>{
    try{checked(Reflect.apply(charge,runtime,[token,bytes]));}
    catch(error){accountingFailed=true;throw error;}
  };
  const callResource=(options: RequestOptions)=>{
    if(closing||callStarted)fail('InstalledEffectOperationAlreadyUsed');
    check();
    const scope=authorization!.scope;
    if(options.grant!==authorization!.grant || options.useId!==useId ||
        credentialInvocationBindingKeys.some(key=>options.scope?.[key]!==scope[key]) ||
        options.scope?.operation!==operation || options.binding!==boundCredential!.binding ||
        options.control!==boundCredential!.control || options.journal!==boundCredential!.journal ||
        options.resolveSecret!==boundCredential!.resolveSecret || options.maxRequestBytes!==maxRequestBytes ||
        options.maxResponseBytes!==maxResponseBytes || !(options.operations instanceof Map) ||
        nodeTypes.isProxy(options.operations) || options.operations.size!==1)fail('ForeignInstalledEffectCredentialOperation');
    const selected=Map.prototype.get.call(options.operations,operation);
    if(selected===undefined || !Object.isFrozen(selected) || nodeTypes.isProxy(selected))fail('InvalidInstalledEffectHttpOperation');
    const fields=Object.getOwnPropertyDescriptors(selected) as Record<PropertyKey, PropertyDescriptor>;
    if(Reflect.ownKeys(fields).some(name=>!['method','path','body','headers','responseHeaders'].includes(name as string)||!Object.hasOwn(fields[name],'value'))) {
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
      checked(Reflect.apply(responseHeadersRequire!,runtime,[token,names,httpsCredentialResponseHeaderByteLimit]));
      originalRecord();
    }
    callStarted=true;
    chargeBytes(BigInt(bytes));
    // Preserve exact original method/path/headers/body/CID semantics. The
    // existing Resource still performs its own current/transport validation.
    const result=Reflect.apply(physical!,site,[{...options,operations:new Map([[operation,
      names===undefined?selected:Object.freeze({...selected,responseHeaders:names})]]),
      observeResponseBytes:(bytes: number)=>{chargeBytes(BigInt(bytes));}}]);
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
        Reflect.apply(prepareResponse!,responsePreparation,[value.body]);
      if(geometry!==undefined&&(!Array.isArray(geometry)||nodeTypes.isProxy(geometry))){
        retainFence(geometry);fail('InvalidInstalledEffectResponsePreparation');
      }
      originalRecord();
      const extent=responseExtent!(value.body.byteLength, value.body, geometry);
      originalRecord();
      checked(Reflect.apply(beginInput!,runtime,[token,extent]));
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
      const returned=Reflect.apply(retireResponse!,responsePreparation,[]);
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
        const originalPurpose=Reflect.apply(readPurpose!,site,[authorization]),scope=authorization?.scope;
        if(originalPurpose?.kind!==purpose||originalPurpose.resource!==resource||scope?.operation!==operation||
            scope.runInvocationCid!==runInvocationCid||scope.dispatchRequestCid!==dispatchRequestCid||
            scope.runtimeBundleCid!==site!.runtimeBundleCid||scope.connectorRegistration!==site!.connectorRegistration||
            scope.connectorRevision!==site!.connectorRevision)fail('ForeignInstalledEffectAuthorizationPurpose');
        // The exact issuer's synchronous factory performs no physical request;
        // the existing capture already retained this child before entry.
        acquisition=Reflect.apply(bind!,site,[authorization,{assertCurrent:check,observeCurrent:observe}]);
        if(acquisition===null||typeof acquisition!=='object'||nodeTypes.isProxy(acquisition))fail('InvalidInstalledEffectCredentialBinding');
        closeBinding=method(acquisition,'close');
        boundCredential=own(acquisition,'credential') as Credential | undefined;
        if(boundCredential===null||typeof boundCredential!=='object')fail('InvalidInstalledEffectCredentialBinding');
        check();
        checked(Reflect.apply(start,runtime,[token]));
        const result=await invoke!({authorization:Object.freeze({...authorization!,useId}),credential:boundCredential,callResource});
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
                const returned=Reflect.apply(retireResponse!,responsePreparation,[]);
                if(returned!==undefined){retainFence(returned);fail('InvalidInstalledEffectResponsePreparation');}
                responsePreparation=prepareResponse=retireResponse=undefined;
                invoke=responseExtent=undefined;
                check();checked(Reflect.apply(discardedResponseComplete!,runtime,[token]));check();
              }else {checked(Reflect.apply(responseComplete!,runtime,[token]));check();}
            }catch(error){state='failed';throw error;}
          }
        }finally{preparing=false;}
      }
    },
    release:drain,retry:drain,status:()=>Object.freeze({pending:state!=='retired'}),
  });
}
