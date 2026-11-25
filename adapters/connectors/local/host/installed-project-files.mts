import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../../../host-common/runtime-result.mjs';
import {runtimeOptionalField} from '../../../host-common/compiler-binding.generated.mjs';
import {createInstalledRowSource,rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {composeInstalledCheckEnvironment} from '../../../host-node/installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {openLocalFileRoot,physicalReadChild} from '../site/root-filesystem.mjs';
import {localFileStoreDeclaration} from './local-file-store-declaration.mjs';
import {encodeLocalCsvPage, type LocalCsvRuntime} from './local-csv-table.mjs';
import {bindLocalProjectFilePreparation} from './local-project-file-preparation.mjs';
import {defaultFileMediaType as mime} from '../../../host-common/file-media-type.mjs';

type SourceOptions = Parameters<typeof createInstalledRowSource>[0];
type RowSource = Awaited<ReturnType<typeof createInstalledRowSource>>;
type Preparation = NonNullable<Awaited<ReturnType<typeof prepareInstalledProjectLocalFiles>>>;
type Bundle = ReturnType<Preparation['originalsForRuntime']> &
  Readonly<{fileReadDeclarations?: readonly unknown[]}>;
type Entry = Bundle['sources'][number];
type Authorization = SourceOptions['authorization'] & Readonly<{
  context: Readonly<{contextCid: string}>; assertAccountCurrent(decision: unknown): unknown;
}>;
type RawRead = Readonly<{close(): unknown; retainChild(child: Physical): unknown}>;
type Occurrence = Parameters<NonNullable<SourceOptions['prepareSourceRead']>>[0]['occurrence'];
type Provider = Readonly<{
  assertCurrent(): unknown;
  prepareRead(prepared: unknown, declaration: unknown, run: unknown, occurrence: Occurrence, request: unknown): RawRead;
  prepareKeyedRead(prepared: unknown, declaration: unknown, run: unknown, request: unknown): RawRead;
}>;
type Physical = ReturnType<typeof physicalReadChild>;
type ReadState = {
  raw?: RawRead; entry?: Entry; owner?: Run; index: unknown; value?: unknown;
  physical?: Physical; reader?: ReturnType<Physical['start']>; close?: RawRead['close']; retain?: RawRead['retainChild'];
  closeCaptured: boolean; closed: boolean; attempted: boolean; keyed?: true;
  externalClosed?: boolean; externalClosing?: Promise<void>;
};
type RetainedRead = Readonly<{run: Run; read: ReadState; entry?: undefined; keyed?: undefined; externalClosed?: undefined}> |
  Readonly<{run?: undefined; read?: undefined; entry?: Entry; keyed: boolean; externalClosed: true}>;
type HostRun = Readonly<{prepared: unknown; request: unknown; retiringContent?: boolean; selectedKeyed?: unknown;
  value?: unknown; original?: unknown}>;
type ContentPreparation = {
  prepared: unknown; inputHolder: unknown; localPreparation?: Run; contentControl?: unknown;
};
type Recipe = Readonly<{keyedAcquisition?: unknown; registry: unknown; task: unknown; step: unknown;
  prefixLimits: unknown; workspace: unknown; values: string; fragment: string | undefined; ordered: string | undefined}>;
type Run = {
  prepared: unknown; request: unknown; value?: unknown; effectful: boolean;
  reads: Map<unknown, ReadState | undefined>; retired?: boolean; failed?: boolean; failure?: unknown;
  recipe?: Recipe; graph?: unknown; hostRun?: HostRun; original?: unknown; inputHolder?: unknown;
  contentPreparation?: ContentPreparation; keyed?: unknown; contentEntry?: Entry; selected?: unknown;
};
type Capacity = Readonly<{transferBytes: bigint; executionBytes: bigint; maxBytes: number; maxWork: number}>;
type Direct = Readonly<{capacity: unknown; transferBytes: bigint; executionBytes: bigint}>;
type PrepareRun = Readonly<{preparedProgram: unknown; requestIdentity: unknown; prepareInvocation?: unknown}>;
type Declaration = Omit<SourceOptions['declared'], 'views'> & Parameters<typeof rowSourceCheckEnvironment>[1] &
  Readonly<{views: readonly Readonly<{source_ref: string; resource: string;
    view_cid: string; carrier_schema_cid: string}>[]}>;
type RetainedAlias = Readonly<{name: string; sourceRef: string; sourceViewContractCid: string; schemaContractCid: string}>;
type FileSource = RowSource & Readonly<{queryAliases: readonly RetainedAlias[]; requiresRunContentCapture: true;
  managedCaptureCapacity(requirement: unknown): Direct}>;
type ProfileView = Readonly<{realizationKey: 'installed-multi-acquired'; environmentWire?: string;
  sources: readonly FileSource[]; fileReadDeclarations?: Bundle['fileReadDeclarations'];
  originalsForProjectEffects?(runtime: unknown, preparation: unknown): Bundle;
  connectorBindings: RowSource['connectorBindings']; queryAliases: readonly RetainedAlias[];
  admitsSource(ref: string): boolean;
  prepareManagedRun(facts: PrepareRun): unknown;
  prepareManagedContentRun(prepared: unknown, request: unknown, recipe: Recipe, graph: unknown,
    preparation: ContentPreparation): HostRun | undefined;
  managedContentLedger(prepared: unknown, request: unknown, recipe: Recipe, direct: Direct,
    keyed: unknown, capacity: Capacity | undefined): unknown;
  close(): Promise<void>;
}>;
type SharedReadPages = Readonly<{
  resource: string; requestWire: string; signal?: AbortSignal; verifyRead(): unknown;
  rowRun: Readonly<{originalRead?: unknown; originalKeyedRead?: unknown}>;
  listing?: Readonly<{beginRequest(token?: string | null): unknown;
    consumePage(body: Uint8Array, options: Readonly<{charge: unknown}>): unknown}>;
  beginRequest?(body: Uint8Array): unknown;
  capturedResourcePath?(): Promise<string>;
  captureContent?(input: Readonly<{bytes: Uint8Array; mediaType: string; contentCid: string}>): unknown;
  chargePage(body: Uint8Array): unknown;
  consumeObservation?(charge: unknown): unknown;
  consumePageWire?(wire: string, options: Readonly<{charge: unknown}>): unknown;
  consumePage(rows: unknown): unknown;
}>;
type CurrentMethod = (read: unknown) => unknown;
type ManagedRunCheck = (run: unknown, prepared: unknown, request: unknown) => unknown;
type FileAdmission = (declaration: unknown, requirement: unknown, queryContract: string, evidenceContract: string,
  listingPolicy?: unknown) => unknown;
type Runtime = SourceOptions['moon'] & Parameters<typeof composeInstalledCheckEnvironment>[0] & Partial<LocalCsvRuntime> & Readonly<{
  clientProgramLocalFileTimestamp(seconds: bigint, nanos: number): string | undefined;
  clientProgramInstalledEffectManagedRunCheck: ManagedRunCheck;
  clientProgramInstalledManagedRunCheck: ManagedRunCheck;
  clientProgramPreparationBorrowRead(holder: unknown): unknown;
  clientProgramPreparationBorrowRetirementStarted(holder: unknown): boolean;
  clientProgramKeyedAcquisitionMatchesProgram(keyed: unknown, prepared: unknown): boolean;
  clientProgramKeyedDirectAcquisitionCoordinates(keyed: unknown): unknown;
  clientProgramSelectInstalledSourceInput(prepared: unknown, request: unknown, stage: number, input: number): unknown;
  clientProgramSelectedSourceInputKind(source: unknown): string;
  clientProgramSelectedSourceInputRef(source: unknown): unknown;
  clientProgramKeyedAcquisitionSourceEvidenceFacts(keyed: unknown): unknown;
  clientProgramInstalledManagedKeyedContentCheckPreparation(selected: unknown, prepared: unknown): unknown;
  clientProgramInstalledManagedRunPrepareLedger(run: unknown, prepared: unknown, request: unknown,
    capacities: readonly unknown[], transferBytes: readonly bigint[], executionBytes: readonly bigint[],
    registry: unknown, values: string, fragment: string | undefined, ordered: string | undefined): unknown;
  clientProgramInstalledKeyedSourceReadRetire: CurrentMethod;
  clientProgramInstalledSourceReadRetire: CurrentMethod;
  clientProgramRowSourceReadProfileConstructionCapacity(declaration: unknown): unknown;
  clientProgramRowSourceBindReadProfile(declaration: unknown, sourceRef: string): unknown;
  clientProgramComposeInstalledSourceConstructionCapacity(capacity: unknown, entries: readonly unknown[]): unknown;
  clientProgramInstalledSourceConstructionCapacity(retainedNodes: bigint, retainedTextBytes: bigint, retainedWireBytes: bigint,
    workspaceNodes: bigint, workspaceTextBytes: bigint, workspaceWireBytes: bigint): unknown;
  clientProgramResourceReferenceIssuer(owns: (kind: string, wire: string) => boolean, current: (wire: string) => boolean): unknown;
  clientProgramKeyedAcquisitionMatchesEffectProgram(keyed: unknown, prepared: unknown): boolean;
  clientProgramInstalledManagedEffectKeyedSourceRead(run: unknown, keyed: unknown, request: unknown,
    declaration: unknown, bytes: number, text: number, work: number): unknown;
  clientProgramInstalledManagedKeyedSourceRead(run: unknown, keyed: unknown, request: unknown, declaration: unknown): unknown;
  clientProgramInstalledKeyedSourceReadCheckCurrent: CurrentMethod;
  clientProgramInstalledSourceReadCheckCurrent: CurrentMethod;
  clientProgramRowSourcePrepareAcquisition: FileAdmission;
  clientProgramInstalledRowCaptureCapacity(acquisition: unknown): unknown;
}>;
type Options = Readonly<{moon: Runtime; preparation: Preparation; sourceManaged: Provider;
  baseEnvironmentWire: string; authorizationFor(connection: string): Authorization | PromiseLike<Authorization>;
  nativeFilesystem: unknown;
  prepareManagedRun?(request: PrepareRun & Readonly<{sourceProfile: ProfileView | undefined}>): unknown;
  prepareManagedContentRun?(prepared: unknown, request: unknown, graph: unknown, recipe: Recipe,
    constructPlan: (parent: unknown, requestInput: unknown) => unknown, contentPreparation: ContentPreparation): HostRun | undefined;
  construction?: Readonly<{prepareNativeInput<Result extends Extract<SynchronousRuntimeData, object>>(plan: Readonly<{capacity(): unknown; project(): Result}>): Result}>;
}>;
type FileRequest = Readonly<{resource: unknown; version: string}>;
type FileLimits = keyof Entry['limits'];

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const canonical = (value: unknown) => canonicalJson(value, {dataKeys: true});
const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const text = (value: unknown, maximum: number): value is string => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !value.includes('\0') && Buffer.byteLength(value) <= maximum;
// Selected service ceilings only. The Host must still admit the same actual
// Source/Compute parent and retain physical children before covered work.
// These do not select a numerical release profile or authorize file access.
export const LOCAL_FILES_DEFAULT_LIMITS=Object.freeze({maxEntries:10000,maxDepth:32,
  maxPathBytes:4096,maxFiles:1000,maxFileBytes:16777216,maxReadBytes:67108864,
  maxPages:64,maxPageBytes:1048576,maxPageRows:256,maxAttempts:64,
  maxDurationMs:30000,maxListingBytes:16777216});
export const prepareInstalledProjectLocalFiles=bindLocalProjectFilePreparation({fail,canonical,cid,positive,text});

const acknowledged = (value: unknown) => value !== null && typeof value === 'object' &&
  Object.getOwnPropertyDescriptor(value,'pending')?.value === false;

// The real Local Source consumer. Common retains original checked preparation,
// Run/Ledger/RowRun and Reference admission; the Source supplier retains the
// same physical reader before any post-acquisition current check.
export async function installPreparedProjectLocalFiles({moon,preparation,sourceManaged,
  baseEnvironmentWire,authorizationFor,nativeFilesystem,prepareManagedRun,prepareManagedContentRun,construction}: Options) {
  if(typeof authorizationFor!=='function'||typeof sourceManaged?.assertCurrent!=='function'||
      typeof sourceManaged?.prepareRead!=='function'||
      typeof moon?.clientProgramLocalFileTimestamp!=='function') fail('LocalFilesManagedReadUnavailable');
  const originalBundle=preparation.originalsForRuntime(moon);
  if (originalBundle.sources.some(source => source.tables.length !== 0) &&
      typeof moon.clientProgramLocalCsvPage !== 'function') fail('LocalCsvRuntimeUnavailable');
  let bundle: Bundle=originalBundle;
  const sources: FileSource[]=[],reads=new WeakMap<object, RetainedRead>();
  // Weak lookup is provenance only. The shared Host owns ordinary Runs; this
  // Connector retains only its actual native children until their close ACK.
  const sharedRuns=new WeakMap<object, Run>(),sharedReads=new Set<ReadState>();
  let profile: ProfileView | undefined;
  // The same received file overlaps its native chunk and the Store writer's
  // exact append snapshot. Row decoding has its existing page workspace in
  // addition. These are demand on the original Content Ledger, not an issuer.
  const keyedTransports=bundle.sources.map(entry=>Object.freeze({
    transferBytes:BigInt(entry.limits.maxReadBytes)+
      BigInt(entry.limits.maxPages)*BigInt(entry.limits.maxPageBytes),
    // Original file plus Store append snapshot; then one selected maximum
    // response/owned-copy/raw snapshot and bounded field-enumeration controls.
    // Confirmation additionally overlaps encrypted envelope E<=128+4*ceil(P/3),
    // its UTF16 wire/parsed/base64 strings, ciphertext and plaintext beside P.
    // 24P+64KiB covers those peaks together (including encoder/writer backing);
    // the SAME RowRun admission precedes construction and retains its credit
    // until actual raw/prepared/reader/codec duties have returned their ACKs.
    executionBytes:2n*BigInt(entry.limits.maxFileBytes)+65536n+24n*BigInt(entry.limits.maxPageBytes),
  }));
  const keyedTransport=(entry: Entry)=>{
    const index=bundle.sources.indexOf(entry);
    if(index<0)fail('ForeignLocalFilesPreparation');
    return keyedTransports[index];
  };
  const [queryContract,evidenceContract]=await Promise.all(
    ['actql-query-acquisition.json','actql-query-process-evidence.json'].map(name=>
      readFile(new URL('../../../../spec/contracts/'+name,import.meta.url),'utf8')));
  let closing=false;
  const current=()=>{
    if(closing)fail('LocalFilesInstallationClosing');
    sourceManaged.assertCurrent();
    if(preparation.originalsForRuntime(moon)!==originalBundle)fail('ForeignLocalFilesPreparation');
  };
  const sameRun=(prepared: unknown,request?: unknown)=>{
    current();const run=sharedRuns.get(prepared as object);
    if(run?.retired)fail('LocalFilesPreparationRetired');
    if(run?.failed)throw run.failure;
    if(run===undefined||run.value===undefined)fail('LocalFilesManagedReadUnavailable');
    const value=run.value,originalRequest=run.request,effectful=run.effectful;
    checked((run.effectful?moon.clientProgramInstalledEffectManagedRunCheck:moon.clientProgramInstalledManagedRunCheck)
      (value,prepared,request===undefined?originalRequest:request));
    // The Core current callback may reenter the Host. Keep this original
    // lookup after it without issuing another current observation.
    if(sharedRuns.get(prepared as object)!==run||run.retired||run.value!==value||run.request!==originalRequest||run.effectful!==effectful)
      fail('ForeignLocalFilesPreparation');
    if(run.failed)throw run.failure;
    return run;
  };
  function prepareRun(facts: PrepareRun){
    if(arguments.length!==1||facts?.preparedProgram===undefined||facts.requestIdentity===undefined)
      fail('InvalidInstalledManagedRunRequest');
    const {preparedProgram:prepared,requestIdentity:request,prepareInvocation}=facts;
    current();
    if(sharedRuns.get(prepared as object)?.recipe!==undefined||typeof prepareManagedRun!=='function')fail('LocalFilesManagedReadUnavailable');
    // The same Host retains its actual partial/adopted Run before returning.
    // No Connector Root, admission, numeric quote or run-count ceiling exists.
    const value=Reflect.apply(prepareManagedRun,undefined,[Object.freeze({preparedProgram:prepared,
      requestIdentity:request,sourceProfile:profile,prepareInvocation})]);
    if(value===undefined)fail('LocalFilesManagedReadUnavailable');
    const prior=sharedRuns.get(prepared as object);
    if(prior!==undefined&&(prior.value!==value||prior.request!==request))fail('ForeignLocalFilesPreparation');
    if(prior===undefined)sharedRuns.set(prepared as object,{prepared,request,value,effectful:false,reads:new Map()});
    current();
    return value;
  }
  function releaseContentAliases(this: Run,managed: HostRun | undefined,inputHolder: unknown){
    const run=this;if(run.retired===true)return;
    if(sharedRuns.get(run.prepared as object)!==run||run.contentPreparation?.localPreparation!==run)
      fail('ForeignLocalFilesContentPreparation');
    if(managed!==undefined){
      if(run.hostRun!==managed||managed.retiringContent!==true||managed.prepared!==run.prepared||managed.request!==run.request)
        fail('LocalFileCleanupPending');
    }else if(run.hostRun?.value!==undefined||inputHolder===undefined||run.inputHolder!==inputHolder||
        moon.clientProgramPreparationBorrowRead(inputHolder)!==run.prepared||
        moon.clientProgramPreparationBorrowRetirementStarted(inputHolder)!==true)fail('LocalFileCleanupPending');
    for(const read of run.reads.values())if(read!==undefined&&!read.closed)fail('LocalFileCleanupPending');
    for(const key of Object.keys(run))(run as Record<string, unknown>)[key]=undefined;
    run.retired=true;
  }
  function contentSourceEntry(resource: string,reference: unknown){
    // These are the SAME declaration aliases captured by installation below.
    // Keep their existing order; do not parse/reconstruct declarations at the
    // Request constructor or select another connection after a refusal.
    const index=sources.findIndex((source,index)=>source.queryAliases.some((alias,slot)=>
      bundle.sources[index].queryAliases[slot].resource===resource&&alias.sourceRef===reference));
    return index<0?undefined:bundle.sources[index];
  }
  function prepareContentRun(prepared: unknown,request: unknown,recipe: Recipe,graph: unknown,contentPreparation: ContentPreparation){
    current();
    if(typeof prepareManagedContentRun!=='function')fail('ForeignLocalFilesContentPreparation');
    const prior=sharedRuns.get(prepared as object);
    if(prior!==undefined){
      if(request===undefined||prior.retired||prior.recipe!==recipe||prior.graph!==graph)fail('ForeignLocalFilesContentPreparation');
      const hostRun=prior.hostRun;
      if(sameRun(prepared,request)!==prior||prior.recipe!==recipe||prior.graph!==graph||prior.hostRun!==hostRun)
        fail('ForeignLocalFilesContentPreparation');
      return hostRun;
    }
    if(contentPreparation?.prepared!==prepared||contentPreparation.inputHolder===undefined||contentPreparation.localPreparation!==undefined)
      fail('ForeignLocalFilesContentPreparation');
    const run: Run={prepared,request,effectful:false,recipe,graph,hostRun:undefined,original:undefined,value:undefined,
      inputHolder:contentPreparation.inputHolder,contentPreparation,reads:new Map(),retired:false,failed:false,failure:undefined};
    Object.defineProperty(run,'releaseAliases',{value:releaseContentAliases});
    contentPreparation.localPreparation=run;
    sharedRuns.set(prepared as object,run);
    try{
      run.hostRun=Reflect.apply(prepareManagedContentRun,undefined,[prepared,request,graph,recipe,(parent: unknown,requestInput: unknown)=>{
        const control=Object.getOwnPropertyDescriptor(contentPreparation,'contentControl')?.value;
        const construct=control===undefined?undefined:Object.getOwnPropertyDescriptor(control,'prepareRequestKeyedPlan')?.value;
        if(typeof construct!=='function')fail('LocalFilesContentPreparationUnavailable');
        const keyed=recipe.keyedAcquisition;
        if(keyed===undefined||moon.clientProgramKeyedAcquisitionMatchesProgram(keyed,prepared)!==true)
          fail('ForeignLocalFilesContentPreparation');
        const coordinates=moon.clientProgramKeyedDirectAcquisitionCoordinates(keyed);
        const stage=runtimeOptionalField(coordinates,0),input=runtimeOptionalField(coordinates,1);
        if(!Number.isSafeInteger(stage)||!Number.isSafeInteger(input))fail('LocalFilesContentPreparationUnavailable');
        const source=checked(moon.clientProgramSelectInstalledSourceInput(prepared,request,stage as number,input as number));
        if(moon.clientProgramSelectedSourceInputKind(source)!=='query')fail('LocalFilesContentPreparationUnavailable');
        const directRef=moon.clientProgramSelectedSourceInputRef(source);
        if(typeof directRef!=='string')fail('LocalFilesContentPreparationUnavailable');
        const facts=checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyed)) as readonly [string, ...unknown[]];
        const direct=contentSourceEntry('files',directRef);
        const content=contentSourceEntry('contents',facts[0]);
        if(direct===undefined||content===undefined)fail('LocalFilesContentPreparationUnavailable');
        run.keyed=keyed;run.contentEntry=content;
        run.selected=Reflect.apply(construct,control,[parent,requestInput,request,keyed,
          direct.declaration,content.declaration,content.limits.maxPageBytes,1000000,queryContract,evidenceContract,
          [BigInt(direct.limits.maxPages)*BigInt(direct.limits.maxPageBytes),keyedTransport(content).transferBytes],
          [BigInt(direct.limits.maxPageBytes),keyedTransport(content).executionBytes],
          recipe.registry,recipe.task,recipe.step,recipe.prefixLimits,recipe.workspace]);
        return run.selected;
      },contentPreparation]);
      if(run.hostRun===undefined||run.hostRun.selectedKeyed!==run.selected||run.hostRun.value===undefined)
        fail('LocalFilesContentPreparationUnavailable');
      run.original=run.hostRun.original;run.value=run.hostRun.value;
      sameRun(prepared);return run.hostRun;
    }catch(cause){run.failed=true;run.failure=cause;throw cause;}
  }
  function contentLedger(prepared: unknown,request: unknown,recipe: Recipe,direct: Direct,keyed: unknown,capacity: Capacity | undefined){
    const run=sameRun(prepared);
    if(run.recipe!==recipe||run.keyed!==keyed||capacity===undefined)fail('ForeignLocalFilesContentPreparation');
    const transport=keyedTransport(run.contentEntry!);
    if(capacity.transferBytes!==transport.transferBytes||capacity.executionBytes!==transport.executionBytes||
        capacity.maxBytes!==run.contentEntry!.limits.maxPageBytes||capacity.maxWork!==1000000)
      fail('ForeignLocalFilesContentPreparation');
    checked(moon.clientProgramInstalledManagedKeyedContentCheckPreparation(run.selected,prepared));
    return checked(moon.clientProgramInstalledManagedRunPrepareLedger(run.value,prepared,request,
      [direct.capacity],[direct.transferBytes],[direct.executionBytes],
      recipe.registry,recipe.values,recipe.fragment,recipe.ordered));
  }
  function captureClose(read: ReadState){
    if(!read.closeCaptured){read.close=read.raw!.close;read.closeCaptured=true;}
    if(typeof read.close!=='function')fail('LocalFilesManagedReadUnavailable');
  }
  async function closeSharedReadExternal(read: ReadState){
    if(read.closed||read.externalClosed)return;
    if(read.externalClosing!==undefined)return await read.externalClosing;
    // Retain the same close before entering an original external method.
    // Concurrent/reentrant cleanup awaits it; a pending ACK stays retryable.
    const work=Promise.resolve().then(async()=>{
      if(read.physical!==undefined&&!acknowledged(await read.physical.close()))fail('LocalFileCleanupPending');
      captureClose(read);
      if(!acknowledged(await Reflect.apply(read.close!,read.raw,[])))fail('LocalFileCleanupPending');
      read.externalClosed=true;
    });
    read.externalClosing=work;
    try{await work;}finally{if(read.externalClosing===work)read.externalClosing=undefined;}
  }
  function releaseSharedRead(read: ReadState){
    if(read.closed)return;
    // The Core session still owns its original read and RowRun retirement.
    // Keep only a weak-key close tombstone and the consumed occurrence, not
    // another strong path to the Prepared graph or closed native controls.
    if(read.value!==undefined)reads.set(read.value as object,{entry:read.entry,keyed:read.keyed===true,externalClosed:true});
    read.owner!.reads.set(read.index,undefined);
    sharedReads.delete(read);read.closed=true;
    read.owner=read.value=read.raw=read.entry=read.reader=read.physical=read.close=read.retain=undefined;
  }
  async function closeSourceRead(original: unknown){
    const retained=reads.get(original as object);
    if(retained===undefined||retained.keyed===true||retained.read?.keyed===true)fail('ForeignLocalFilesSourcePreparation');
    if(retained.externalClosed===true)return Object.freeze({pending:false});
    const read=retained.read;
    if(!sharedReads.has(read!))fail('ForeignLocalFilesSourcePreparation');
    await closeSharedReadExternal(read!);releaseSharedRead(read!);
    return Object.freeze({pending:false});
  }
  async function closeRead(read: ReadState){
    if(read.closed)return;
    if(sharedReads.has(read)){
      await closeSharedReadExternal(read);
      if(read.closed)return;
      if(read.value!==undefined){
        const retire=read.keyed?moon.clientProgramInstalledKeyedSourceReadRetire:moon.clientProgramInstalledSourceReadRetire;
        checked(Reflect.apply(retire,moon,[read.value]));
      }
      releaseSharedRead(read);return;
    }else{
      if(read.physical!==undefined&&!acknowledged(await read.physical.close()))fail('LocalFileCleanupPending');
      captureClose(read);
      if(!acknowledged(await Reflect.apply(read.close!,read.raw,[])))fail('LocalFileCleanupPending');
      if(read.value!==undefined){
        const retire=read.keyed?moon.clientProgramInstalledKeyedSourceReadRetire:
          moon.clientProgramInstalledSourceReadRetire;
        checked(Reflect.apply(retire,moon,[read.value]));
      }
    }
    read.closed=true;sharedReads.delete(read);
  }
  async function close(){
    closing=true;const errors=[];
    for(const read of sharedReads)try{await closeRead(read);}catch(cause){errors.push(cause);}
    if(errors.length)throw new AggregateError(errors,'LocalFilesCleanupPending');
  }
  try{
    if(construction!==undefined){
      if(typeof construction.prepareNativeInput!=='function'||
          typeof moon.clientProgramRowSourceReadProfileConstructionCapacity!=='function'||
          typeof moon.clientProgramRowSourceBindReadProfile!=='function')fail('LocalFilesReadExecutionUnavailable');
      // The existing Source material reserves descriptor, declaration export,
      // JSON view, arrays and retained original tuple BEFORE constructing them.
      bundle=construction.prepareNativeInput(Object.freeze({
        capacity(){
          let quantity;
          for(const entry of originalBundle.sources){
            const next=moon.clientProgramRowSourceReadProfileConstructionCapacity(entry.declaration);
            if(next===undefined)fail('LocalFilesReadExecutionUnavailable');
            quantity=quantity===undefined?next:checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(quantity,[next]));
          }
          // The returned profile's original-evidence method/closure/field and
          // conditional carrier coexist with this SAME retained declaration.
          const handoff=checked(moon.clientProgramInstalledSourceConstructionCapacity(8n,0n,0n,0n,0n,0n));
          return checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(quantity,[handoff]));
        },
        project(){
          const entries=originalBundle.sources.map(entry=>{
            const prior=JSON.parse(entry.wire) as Declaration;
            const response=prior.views.find(view=>view.resource==='contents');
            if(response===undefined)fail('LocalFilesReadExecutionUnavailable');
            const declaration=checked(moon.clientProgramRowSourceBindReadProfile(entry.declaration,response.source_ref));
            const exported=moon.clientProgramRowSourceDeclarationJson(declaration);
            const store=localFileStoreDeclaration(exported,{connectorId:entry.connection,rootPath:entry.rootPath,maxBytes:131072});
            return Object.freeze({...entry,declaration,wire:store.declarationWire});
          });
          return Object.freeze({...originalBundle,sources:Object.freeze(entries),
            fileReadDeclarations:Object.freeze(entries.map(entry=>entry.declaration))});
        },
      }));
      current();
    }
    if(bundle.sources.length!==originalBundle.sources.length)fail('ForeignLocalFilesPreparation');
    for(let entryIndex=0;entryIndex<bundle.sources.length;entryIndex++){
      const entry=bundle.sources[entryIndex],originalEntry=originalBundle.sources[entryIndex];
      // The funded map changes only read declaration/export DATA. Keep this
      // exact original entry/order and retained installation aliases for the
      // physical connection shared with STORE; equal CIDs cannot replace it.
      if(entry.queryAliases!==originalEntry.queryAliases||entry.limits!==originalEntry.limits||
          entry.connection!==originalEntry.connection||entry.connectorId!==originalEntry.connectorId||
          entry.rootPath!==originalEntry.rootPath||entry.scopeCid!==originalEntry.scopeCid||
          entry.tables!==originalEntry.tables||entry.csvTransports!==originalEntry.csvTransports)
        fail('ForeignLocalFilesPreparation');
      current();
      const authorization=await authorizationFor(entry.connection);current();
      const assertAccountCurrent=authorization.assertAccountCurrent;
      if(typeof assertAccountCurrent!=='function')fail('LocalFilesAuthorizationUnavailable');
      const declared=JSON.parse(entry.wire) as Declaration,environment=rowSourceCheckEnvironment(baseEnvironmentWire,declared);
      const known=new Set<string>(),preparedRuns=new WeakMap<object, Run>();
      const issuer=moon.clientProgramResourceReferenceIssuer((kind,wire)=>kind==='file'&&known.has(wire),()=>{
        try{current();return true;}catch{return false;}
      });
      const resourceFor=(path: string)=>{
        const value=Object.freeze({$actql_ref:'resource',version:'actql-resource-ref/0.1',
          provider_namespace:'local',resource_kind:'file',provider_identity_cid:entry.scopeCid,
          authority_scope_cid:authorization.context.contextCid,boundary_cid:entry.scopeCid,
          identity_cid:cid({root_scope:entry.scopeCid,path})});
        known.add(canonical(value));return value;
      };
      const adapter=await createInstalledRowSource({moon,declaration:entry.declaration,declared,
        environmentWire:environment.wire,connectorId:entry.connectorId,connectorRegistration:'local',
        connectorRevision:'local/0.1',bindingCid:cid({scope:originalEntry.scopeCid,declaration:originalEntry.wire,
          account_context:authorization.context.contextCid}),authorization,readOperation:'read',referenceIssuer:issuer,
        site:Object.freeze({connection:entry.connection,
          issueReadGrant({operation,decision,resource,runInvocationCid,dispatchRequestCid,maxUses}:
            Parameters<SourceOptions['site']['issueReadGrant']>[0]){
            current();
            if(operation!=='read'||!declared.views.some(view=>view.resource===resource)||
                !/^sha256:[0-9a-f]{64}$/u.test(runInvocationCid)||
                !/^sha256:[0-9a-f]{64}$/u.test(dispatchRequestCid)||!positive(maxUses)||
                decision?.action!=='dispatch'||decision.boundary!=='acquisition'||
                decision.tuple?.connection!==entry.connection||decision.tuple?.resource!==resource||
                decision.tuple?.operation!=='read'||
                decision.contextCid!==authorization.context.contextCid)fail('LocalFilesReadGrantNotAuthorized');
            // The original Account gate verifies its own decision and current
            // configuration; a copied tuple or historical Allow is not a grant.
            Reflect.apply(assertAccountCurrent,authorization,[decision]);
            return Object.freeze({runInvocationCid,dispatchRequestCid});
          },
          async close(){
            for(const read of sharedReads)if(read.entry===entry)await closeRead(read);}}),
        physicalTarget:(resource,fields)=>{
          const table=entry.tables.find(table=>table.resource===resource);
          return {connection:entry.connection,root:entry.rootPath,resource,fields:[...fields],scope_cid:entry.scopeCid,
            ...(table===undefined?{}:{relative_path:table.path})};
        },
        limits:{maxPages:entry.limits.maxPages,maxPageBytes:entry.limits.maxPageBytes,
          maxPageRows:entry.limits.maxPageRows,maxCaptureRows:entry.limits.maxFiles},
        // The funded declaration projection preserves this exact Source order.
        ...(entry.tables.length===0?{}:{originalReadTransports:entry.csvTransports}),
        originalKeyedTransport:keyedTransport(entry),
        prepareSourceRead({checkedOwner,effectful,declaration,occurrence,managedRun,originalRead,requestIdentity}){
          current();
          let run=sharedRuns.get(checkedOwner as object);
          if(run===undefined&&effectful===true&&managedRun!==undefined&&originalRead!==undefined&&requestIdentity!==undefined){
            // The shared Source has already checked this exact Effect
            // Run/Prepared/Request and selected its original read. Retain only
            // local child provenance; the Host still owns admission/lifetime.
            run={prepared:checkedOwner,request:requestIdentity,value:managedRun,effectful:true,reads:new Map()};
            sharedRuns.set(checkedOwner as object,run);
          }
          const index=occurrence?.task;
          if(run===undefined||run.retired||run.failed||effectful!==run.effectful||
              declaration!==entry.declaration||
              !['stage','input','task'].every(name=>Number.isSafeInteger(occurrence?.[name as keyof Occurrence])&&occurrence[name as keyof Occurrence]!>=0)||
              !Number.isSafeInteger(occurrence.computeTask??index)||(occurrence.computeTask??index)<0||
              !Number.isSafeInteger(index)||index<0||run.reads.has(index)||
              managedRun!==run.value||originalRead===undefined||
              requestIdentity!==run.request)fail('LocalFilesSourcePreparationMismatch');
          // The original Host validates its own adopted parent before it
          // retains the physical child. No second Core current callback is
          // needed between the shared read selection and this same handoff.
          // Physical child custody belongs to the exact original Project
          // declaration. The checked execution below retains its funded read
          // profile; it does not replace that installation owner.
          const raw=sourceManaged.prepareRead(checkedOwner,originalEntry.declaration,run.value,occurrence,run.request);
          const read: ReadState={raw,entry,owner:run,index,value:originalRead,reader:undefined,physical:undefined,close:undefined,closeCaptured:false,
            retain:undefined,closed:false,attempted:false};
          run.reads.set(index,read);
          sharedReads.add(read);
          // Retain the same physical child control before callback getters or
          // currentness can reject it. The Host remains the sole Run owner.
          captureClose(read);read.retain=read.raw!.retainChild;
          if(typeof read.retain!=='function')fail('LocalFilesManagedReadUnavailable');
          current();
          reads.set(read.value as object,{run,read});return read.value;
        },
        async closeSourceRead(original: unknown){
          const retained=reads.get(original as object);
          if(retained===undefined||retained.entry!==undefined&&retained.entry!==entry||
              retained.read!==undefined&&retained.read.entry!==entry)fail('ForeignLocalFilesSourcePreparation');
          return closeSourceRead(original);
        },
        prepareKeyedSourceRead({checkedOwner,keyedAcquisition,request,declaration,managedRun,rowLimits}){
          const run=sameRun(checkedOwner);
          if((run.effectful ? managedRun!==run.value||
              moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition,checkedOwner)!==true
              : run.recipe===undefined||run.keyed!==keyedAcquisition||run.contentEntry!==entry)||
              declaration!==entry.declaration||run.reads.has(request))fail('LocalFilesSourcePreparationMismatch');
          const raw=sourceManaged.prepareKeyedRead(checkedOwner,originalEntry.declaration,run.effectful?run.value:run.original,request);
          const read: ReadState={raw,entry,owner:run,index:request,keyed:true,value:undefined,reader:undefined,physical:undefined,
            close:undefined,closeCaptured:false,retain:undefined,closed:false,attempted:false};
          run.reads.set(request,read);sharedReads.add(read);captureClose(read);read.retain=raw.retainChild;
          if(typeof read.retain!=='function')fail('LocalFilesManagedReadUnavailable');
          sameRun(checkedOwner);
          read.value=checked(run.effectful
            ? moon.clientProgramInstalledManagedEffectKeyedSourceRead(run.value,keyedAcquisition,request,declaration,
              rowLimits.maxPageBytes,rowLimits.maxTextBytes,rowLimits.maxWork)
            : moon.clientProgramInstalledManagedKeyedSourceRead(run.value,keyedAcquisition,request,declaration));
          reads.set(read.value as object,{run,read});return read.value;
        },
        async closeKeyedSourceRead(original){
          const retained=reads.get(original as object);
          if(retained?.externalClosed===true){
            if(!retained.keyed||retained.entry!==entry)fail('ForeignLocalFilesContentPreparation');
            return Object.freeze({pending:false});
          }
          if(retained===undefined||!retained.read?.keyed||retained.read.entry!==entry)
            fail('ForeignLocalFilesContentPreparation');
          await closeRead(retained.read);return Object.freeze({pending:false});
        },
        async readPages(options: SharedReadPages){
          if(options.resource==='contents'){
            const retained=reads.get(options.rowRun.originalKeyedRead as object);
            if(retained===undefined||!retained.read?.keyed||retained.read.entry!==entry||
                typeof options.capturedResourcePath!=='function'||typeof options.captureContent!=='function')
              fail('LocalFilesSourcePreparationMismatch');
            const {run,read}=retained;sameRun(run.prepared);
            if(read.closed||read.attempted)fail('LocalFilesSourcePreparationMismatch');
            read.attempted=true;
            let entered=false;
            try{
              const path=await options.capturedResourcePath();
              const request=JSON.parse(options.requestWire) as FileRequest;
              if(!text(path,entry.limits.maxPathBytes)||
                  canonical(request.resource)!==canonical(resourceFor(path))||
                  typeof request.version!=='string')fail('LocalFilesContentResourceMismatch');
              await options.verifyRead();options.signal?.throwIfAborted();sameRun(run.prepared);
              await options.beginRequest!(Buffer.from(options.requestWire));entered=true;
              const checkRead=(): undefined=>{sameRun(run.prepared);
                checked(moon.clientProgramInstalledKeyedSourceReadCheckCurrent(read.value));};
              read.physical=physicalReadChild({namespace:nativeFilesystem,path:entry.rootPath,assertCurrent:checkRead},
                fail,acknowledged,openLocalFileRoot);
              Reflect.apply(read.retain!,read.raw,[read.physical]);checkRead();
              const limits=Object.fromEntries(['maxEntries','maxDepth','maxPathBytes','maxFiles','maxFileBytes','maxReadBytes']
                .map(name=>[name,entry.limits[name as FileLimits]]));
              read.reader=read.physical.start({limits,signal:options.signal,assertCurrent:checkRead});
              const file=await read.reader.read(path,{expectedVersion:request.version,
                contentVersion:entry.versionMode==='content'});
              checkRead();
              // This is the same native body, not synthetic encoded output.
              // Each bounded slice consumes its own ticket before the next;
              // configured file and aggregate read ceilings remain unchanged.
              for(let offset=0;offset<file.bytes.length;offset+=entry.limits.maxPageBytes){
                const charge=options.chargePage(file.bytes.subarray(offset,offset+entry.limits.maxPageBytes));
                options.consumeObservation!(charge);
              }
              const mediaType=mime(path),content=await options.captureContent({bytes:file.bytes,
                mediaType,contentCid:'sha256:'+createHash('sha256').update(file.bytes).digest('hex')});
              await options.consumePage([{resource:request.resource,version:file.version,path,
                media_type:mediaType,content}]);
              if(!acknowledged(await read.physical.close()))fail('LocalFileCleanupPending');
              return;
            }catch(cause){
              let stopped=false;
              const cleanup=async()=>{stopped=read.physical===undefined||acknowledged(await read.physical.close());return stopped;};
              try{await cleanup();}catch{/* The same native owner remains pending. */}
              throw new AcquisitionOpenError(cause,stopped?(entered?'stopped':'not_started'):'unknown',
                stopped?undefined:Object.freeze({close:cleanup,cleanup,cleanupPending:()=>!stopped}));
            }
          }
          const csv=entry.tables.find(table=>table.resource===options.resource);
          if(csv===undefined&&(options.resource!=='files'||options.listing===undefined))fail('LocalFilesContentReadUnavailable');
          const retained=reads.get(options.rowRun.originalRead as object);
          if(retained?.read===undefined)fail('LocalFilesSourcePreparationMismatch');
          const {run,read}=retained;sameRun(run.prepared);
          if(read.closed||read.attempted||read.entry!==entry)fail('LocalFilesSourcePreparationMismatch');
          const shared=sharedRuns.get(run.prepared as object)===run;
          let entered=false;
          try{
            read.attempted=true;
            await options.verifyRead();options.signal?.throwIfAborted();sameRun(run.prepared);
            const fileLimits=Object.fromEntries(['maxEntries','maxDepth','maxPathBytes','maxFiles','maxFileBytes','maxReadBytes']
              .map(name=>[name,entry.limits[name as FileLimits]]));
            if(csv!==undefined)fileLimits.maxReadBytes=fileLimits.maxFileBytes=csv.maxBytes;
            const checkRead=(): undefined=>{sameRun(run.prepared);checked(moon.clientProgramInstalledSourceReadCheckCurrent(read.value));};
            read.physical=physicalReadChild({namespace:nativeFilesystem,path:entry.rootPath,assertCurrent:checkRead},
              fail,acknowledged,openLocalFileRoot);
            Reflect.apply(read.retain!,read.raw,[read.physical]);
            sameRun(run.prepared);
            // The same raw Source child owns the physical constructor BEFORE
            // it opens this Root. Account/current checks above precede the first
            // directory open; initialization is not listing or Content credit.
            entered=true;
            read.reader=read.physical.start({limits:fileLimits,signal:options.signal,assertCurrent:checkRead});
            if(csv!==undefined){
              if(typeof options.consumePageWire!=='function')fail('LocalFilesContentReadUnavailable');
              const file=await read.reader.read(csv.path);
              checkRead();
              const charge=options.chargePage(file.bytes);
              await options.consumePageWire(encodeLocalCsvPage(moon as Runtime & LocalCsvRuntime,file.bytes,csv,entry.limits.maxPageBytes),{charge});
              checkRead();
              if(shared)await closeSourceRead(read.value);
              return;
            }
            let items: object[]=[],page=0,token: string | null | undefined;
            const flush=async (final: boolean)=>{
              const next=final?null:String(++page);
              const body=Buffer.from(JSON.stringify({items,request_token:token??null,next_token:next}));
              if(body.length>entry.limits.maxPageBytes)fail('LocalFilesPageBytesLimit');
              const charge=options.chargePage(body);
              await options.listing!.consumePage(body,{charge});
              items=[];token=next;
              if(!final)await options.listing!.beginRequest(token);
            };
            await options.listing!.beginRequest(undefined);
            await read.reader.list({contentVersion:entry.versionMode==='content',async onFile(file){
              const timestamp=moon.clientProgramLocalFileTimestamp(file.metadata.modifiedSeconds,Number(file.metadata.modifiedNanos));
              if(typeof timestamp!=='string')fail('LocalFileTimestampUnavailable');
              const item={resource:resourceFor(file.path),version:file.version,name:file.path,path:file.path,
                size:String(file.metadata.size),modified_time:timestamp,media_type:mime(file.path),
                size_bytes:file.metadata.size<=BigInt(Number.MAX_SAFE_INTEGER)?Number(file.metadata.size):null,
                modified_at:timestamp};
              const candidate=[...items,item];
              if(Buffer.byteLength(JSON.stringify({items:candidate,request_token:token??null,next_token:String(page+1)}))>
                  entry.limits.maxPageBytes){if(items.length===0)fail('LocalFilesPageBytesLimit');await flush(false);}
              items.push(item);
              if(items.length===entry.limits.maxPageRows)await flush(false);
            }});
            await flush(true);sameRun(run.prepared);
            if(shared)await closeSourceRead(read.value);
          }catch(cause){
            if(!shared)throw cause;
            let stopped=false;
            const cleanup=async()=>{if(!read.closed)await closeSourceRead(read.value);stopped=true;return true;};
            try{await cleanup();}catch{/* Same original native/raw child remains pending. */}
            throw new AcquisitionOpenError(cause,stopped?(entered?'stopped':'not_started'):'unknown',
              stopped?undefined:Object.freeze({close:cleanup,cleanup,cleanupPending:()=>!stopped}));
          }
        }});
      const queryAliases=Object.freeze(entry.queryAliases.map(alias=>{
        const view=declared.views.find(view=>view.resource===alias.resource);
        return Object.freeze({name:alias.name,sourceRef:view!.source_ref,sourceViewContractCid:view!.view_cid,
          schemaContractCid:view!.carrier_schema_cid});
      }));
      // Keyed Local contents are captured by the existing Run-owned Store
      // frame. Dispatch must retain that frame before opening file bytes.
      sources.push(Object.freeze({...adapter,queryAliases,requiresRunContentCapture:true,
        managedCaptureCapacity(requirement: unknown){
          current();
          // The actual shared Plan retains this one original acquisition.
          // Prepare/ledger projection later consumes that SAME tuple.
          const acquisition=checked((moon.clientProgramRowSourcePrepareAcquisition as FileAdmission)(
            entry.declaration,requirement,queryContract,evidenceContract));
          const capacity=moon.clientProgramInstalledRowCaptureCapacity(acquisition);
          if(capacity===undefined)fail('LocalFilesManagedReadUnavailable');
          const sourceRef=entry.tables.length===0?undefined:moon.clientProgramQueryRequirementSourceRef(requirement);
          const transport=(typeof sourceRef==='string'?entry.csvTransports[sourceRef]:undefined)??
            {transferBytes:BigInt(entry.limits.maxPages)*BigInt(entry.limits.maxPageBytes),
              executionBytes:BigInt(entry.limits.maxPageBytes)};
          return Object.freeze({capacity,...transport});
        },
        async prepare(facts: Parameters<RowSource['prepare']>[0]){
          const owner=facts.preparedEffect??facts.preparedProgram;
          let original=sharedRuns.get(owner as object);
          if(original===undefined){
            // Only the actual shared Effect selection may establish this
            // local provenance record. Its Core getter and the Host read
            // consumer validate the original tuple before acquiring a child.
            if(facts.preparedEffect===undefined||facts.preparedProgram!==undefined||
                facts.managedRun===undefined||facts.requestIdentity===undefined)
              fail('LocalFilesManagedReadUnavailable');
          }else if(original.failed)throw original.failure;
          if(original!==undefined&&((facts.managedRun!==undefined&&facts.managedRun!==original.value)||
              (facts.requestIdentity!==undefined&&facts.requestIdentity!==original.request)))
            fail('LocalFilesSourcePreparationMismatch');
          // A consumed occurrence keeps its original read and any pending
          // cleanup. Reject before another Core getter can return that same
          // read and a failed second preparation could retire the first.
          if(original?.reads.has(facts.occurrence?.task))fail('LocalFilesSourcePreparationMismatch');
          const forwarded=original===undefined?facts:Object.freeze({...facts,
            managedRun:original.value,requestIdentity:original.request});
          const prepared=await adapter.prepare(forwarded);
          original??=sharedRuns.get(owner as object);
          if(sameRun(owner)!==original)fail('LocalFilesSourcePreparationMismatch');
          preparedRuns.set(prepared,original!);return prepared;},
        ledgerCapacity(prepared: Parameters<RowSource['ledgerCapacity']>[0]){const run=preparedRuns.get(prepared);
          if(run===undefined||run!==sameRun(run.prepared))fail('LocalFilesSourcePreparationMismatch');
          return Object.freeze({...adapter.ledgerCapacity(prepared),managedRun:run.value});}}));
    }
    let environmentWire: string | undefined;
    for(const source of sources)environmentWire=composeInstalledCheckEnvironment(moon,baseEnvironmentWire,
      environmentWire,source.environmentWire);
    current();
    profile=Object.freeze({realizationKey:bundle.realizationKey,environmentWire,sources:Object.freeze(sources),
      ...(bundle.fileReadDeclarations===undefined?{}:{fileReadDeclarations:bundle.fileReadDeclarations}),
      ...(construction===undefined?{}:{originalsForProjectEffects(runtime: unknown,originalPreparation: unknown){
        if(this!==profile||runtime!==moon||originalPreparation!==preparation)
          fail('ForeignLocalFilesPreparation');
        current();
        if(closing)fail('LocalFilesInstallationClosing');
        return bundle;
      }}),
      connectorBindings:Object.freeze(sources.flatMap(source=>source.connectorBindings)),
      queryAliases:Object.freeze(sources.flatMap(source=>source.queryAliases)),
      admitsSource:(ref: string)=>sources.some(source=>source.admitsSource(ref)),
      prepareManagedRun:prepareRun,
      prepareManagedContentRun:prepareContentRun,managedContentLedger:contentLedger,close});
    return profile;
  }catch(cause){throw await retainInstalledHostInitializationFailure(cause,{sourceProfile:{close}});}
}
