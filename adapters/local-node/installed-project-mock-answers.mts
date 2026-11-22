import {open} from 'node:fs/promises';
import {extname, resolve} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedProjectOriginalsForRuntime, resolveInstalledProjectTaskPath} from '../host-node/installed-project-configuration.mjs';
import {readBoundedConfigurationUtf8} from '../host-node/source-profile-json.mjs';
import type {selectInstalledProjectProfile} from '../host-node/installed-project-profile.mjs';
import type {loadInstalledProjectModelTasks} from '../host-node/installed-project-model-tasks.mjs';
import type {createDeclaredFileInstallationInventory} from './declared-file-installation.mjs';
import {assertDeclaredFileInstallationInventory} from './declared-file-installation.mjs';

type TaskCommon = Parameters<typeof loadInstalledProjectModelTasks>[0];
type Project = Parameters<typeof loadInstalledProjectModelTasks>[1];
type ProjectOriginal = ReturnType<typeof installedProjectOriginalsForRuntime>;
type Profile = ReturnType<typeof selectInstalledProjectProfile>;
type TaskBounds = Parameters<TaskCommon['clientProgramReadPublicModelTask']> extends
  [wire: string, format: string, ...infer Bounds] ? Bounds : never;
type NormalizedTask = Parameters<TaskCommon['clientProgramProjectPublicModelTaskEnvironment']>[2][number];
type AnswerBounds = [maxBytes: number, maxNodes: number, maxDepth: number, maxMembers: number,
  valueNodes: number, valueDepth: number, valueTextBytes: number, maxEntries: number, maxWork: number];
type Clock = () => string;
type MockRuntime = Pick<TaskCommon, 'clientProjectModelRegistryTaskCount' | 'clientProjectModelRegistryTaskName' |
  'clientProjectModelRegistryTaskFile' | 'clientProgramInstalledSourceConstructionCapacity' |
  'clientProgramPublicModelTaskName' | 'clientProgramReadPublicModelTask' |
  'clientProgramNormalizedPublicModelTaskMaterials' | 'clientProgramProjectPublicModelTaskEnvironment'> & Readonly<{
  clientProgramReadMockAnswers(task: unknown, wire: string, format: string, ...bounds: AnswerBounds): unknown;
  clientProgramRetireMockAnswers(answers: unknown, task: unknown): unknown;
  clientProgramNormalizeMockTask(task: unknown, profile: unknown, ...bounds: TaskBounds): unknown;
  clientProgramMockExecutionMaterials(profile: unknown, normalized: unknown, ...bounds: TaskBounds): unknown;
  clientProgramPrepareOriginalMock(profile: unknown, task: unknown, normalized: unknown, now: Clock): unknown;
  clientProgramInstallOriginalMock(profile: unknown, task: unknown, normalized: unknown, answers: unknown, now: Clock): unknown;
  clientProgramBindOriginalMockAnswers(installation: unknown, answers: unknown): unknown;
  clientProgramOriginalMockDeclaration(installation: unknown): unknown;
  clientProgramOriginalMockProvider(installation: unknown): unknown;
  clientProgramRetireOriginalMock(installation: unknown): unknown;
  clientProgramMockProfileOriginals(profile: unknown): unknown;
}>;
type RegistryRuntime = Pick<MockRuntime, 'clientProjectModelRegistryTaskCount' | 'clientProgramInstalledSourceConstructionCapacity'>;
type Inventory = Pick<ReturnType<typeof createDeclaredFileInstallationInventory>, 'prepareMetadataInput'>;
type FileOpen = (path: string, flags: string) => unknown;
type LoadOptions = Readonly<{
  limits?: unknown;
  assertCurrent?: () => unknown;
  openFile?: FileOpen;
  deferAnswers?: boolean;
  installationInventory?: Inventory;
}>;
type ProfilePorts = Readonly<{
  originals: Profile['originalsForRuntime'];
  locators: Profile['mockLocatorsForRuntime'];
  answer: Profile['mockAnswerForRuntime'];
}>;
type ProfileArguments = {originals: []; locators: []; answer: [index: number]};
type AnswerPorts = Readonly<{
  count: MockRuntime['clientProjectModelRegistryTaskCount'];
  task: MockRuntime['clientProjectModelRegistryTaskName'];
  file: MockRuntime['clientProjectModelRegistryTaskFile'];
  readTask: MockRuntime['clientProgramReadPublicModelTask'];
  name: MockRuntime['clientProgramPublicModelTaskName'];
  readAnswers: MockRuntime['clientProgramReadMockAnswers'];
  retire: MockRuntime['clientProgramRetireMockAnswers'];
}>;
type AnswerEntry = {
  task: unknown;
  answers: unknown;
  name: string;
  taskPath: string;
  answerPath: string;
  taskWire: string;
  answerWire: string | undefined;
  answerFailure: unknown;
};
type BoundEntry = AnswerEntry & {
  normalized: NormalizedTask;
  taskCid: string;
  promptWire: string;
  promptCid: string;
  executionWire: string;
  executionCid: string;
  retryWire: string;
  retryCid: string;
  backoffWire: string;
  backoffCid: string;
  installation: unknown;
  provider: unknown;
};
type Body = Readonly<{bodyWire: string; cid: string}>;
type BindingOriginal = Readonly<{wire: string; cid: string}>;
type BoundModels = Readonly<{
  originalsForRuntime(runtime: unknown): readonly Readonly<BoundEntry>[];
  providerBindingOriginalsForRuntime(runtime: unknown): Readonly<{
    installationRevision: BindingOriginal; configurationContract: BindingOriginal; configuration: BindingOriginal;
  }>;
  prepareAnswersForRuntime(runtime: unknown, installation: unknown): Promise<void>;
  forTaskCid(runtime: unknown, taskCid: string): Readonly<BoundEntry> | undefined;
  projectEnvironmentForRuntime(runtime: unknown, wire: string, evidenceCid: string):
    Readonly<{environmentWire: string; evidenceCid: string; work: number}>;
  modelInstallationForRuntime(runtime: unknown, wire: string, evidenceCid: string): Readonly<{
    environmentWire: string;
    executionContracts: readonly Readonly<Body & {modelTaskCid: string}>[];
    dependencyBodies: readonly Body[];
  }>;
}>;
type Answers = Readonly<{
  originalsForRuntime(runtime: unknown): readonly Readonly<AnswerEntry>[];
  bindModelsForRuntime(runtime: unknown, originalProfile: unknown, now: Clock): BoundModels;
  retire(runtime: unknown): void;
}>;
type ModelPorts = Readonly<{
  normalize: MockRuntime['clientProgramNormalizeMockTask'];
  materials: MockRuntime['clientProgramNormalizedPublicModelTaskMaterials'];
  execution: MockRuntime['clientProgramMockExecutionMaterials'];
  install: MockRuntime['clientProgramPrepareOriginalMock'] | MockRuntime['clientProgramInstallOriginalMock'];
  bind?: MockRuntime['clientProgramBindOriginalMockAnswers'];
  declaration?: MockRuntime['clientProgramOriginalMockDeclaration'];
  provider: MockRuntime['clientProgramOriginalMockProvider'];
  retire: MockRuntime['clientProgramRetireOriginalMock'];
  environment: MockRuntime['clientProgramProjectPublicModelTaskEnvironment'];
}>;
type ModelState = {
  profile: unknown;
  now: Clock | undefined;
  callbacks: ModelPorts | undefined;
  entries: BoundEntry[] | readonly BoundEntry[] | undefined;
  retireIndex: number;
  failed: boolean;
  failure: unknown;
  value: BoundModels | undefined;
  retired: boolean;
  answerFlight?: Promise<void>;
};
type CleanupCarrier = Readonly<{cleanupHandle?: {status(): {pending?: boolean} | undefined}}>;

const fail: (code: string) => never=code=>{throw Object.assign(new Error(code),{code});};
const fields=Object.freeze(['contractDepth','contractNodes','contractTextBytes','maxBytes',
  'maxDepth','maxEntries','maxMembers','maxNodes','maxTasks','maxWork',
  'valueDepth','valueNodes','valueTextBytes'] as const);

// This fixed selection borrows the already admitted registry original. It
// allocates no taskCount-sized list and does not read/normalize unused Tasks.
// The SAME working Source material funds the new control/result before the
// count projection; neither a caller number nor a copied inventory admits it.
export function prepareInstalledMockRegistrySelection(moon: RegistryRuntime,project: unknown,inventory: Inventory){
  const original=installedProjectOriginalsForRuntime(project,moon);
  assertDeclaredFileInstallationInventory(inventory,moon,original);
  const count=moon?.clientProjectModelRegistryTaskCount;
  const quote=moon?.clientProgramInstalledSourceConstructionCapacity;
  if(typeof count!=='function'||typeof quote!=='function')fail('InstalledProjectRuntimeUnavailable');
  const check=()=>{
    assertDeclaredFileInstallationInventory(inventory,moon,original);
    if(installedProjectOriginalsForRuntime(project,moon)!==original){
      fail('ForeignInstalledMockAnswerOriginal');
    }
  };
  const selected=inventory.prepareMetadataInput(Object.freeze({
    // Existing generic native-input recipe: the fixed projection/result,
    // closures/Some/control carriers. No registry body is parsed or copied.
    capacity:()=>checked(Reflect.apply(quote,moon,[8n,0n,0n,4n,0n,0n])),
    project(){
      check();
      const tasks=original.modelRegistry===undefined?0:Reflect.apply(count,moon,[original.modelRegistry]);
      if(!Number.isSafeInteger(tasks)||tasks<0)fail('InstalledMockAnswerCountLimit');
      return Object.freeze({registry:original.modelRegistry,count:tasks});
    },
  }));
  check();
  if(selected.registry!==original.modelRegistry)fail('ForeignInstalledMockAnswerOriginal');
  return selected;
}

type LimitName = typeof fields[number];

function snapshotLimits(value: unknown){
  if(value===null||typeof value!=='object'||Array.isArray(value))fail('InvalidInstalledMockAnswerLimits');
  const keys=Object.keys(value).sort();
  if(keys.length!==fields.length||keys.some((key,index)=>key!==fields[index]))fail('InvalidInstalledMockAnswerLimits');
  const result: Partial<Record<LimitName, number>>={};
  for(const key of fields){const n=(value as Record<LimitName, number>)[key];
    if(!Number.isSafeInteger(n)||n<0||n>2147483647)fail('InvalidInstalledMockAnswerLimits');
    result[key]=n;
  }
  return Object.freeze(result) as Readonly<Record<LimitName, number>>;
}

function format(path: string){
  const extension=extname(path);
  if(extension==='.json')return 'json';
  if(extension==='.yaml'||extension==='.yml')return 'yaml';
  fail('InstalledMockAnswerFormatUnavailable');
}

// Existing installation DATA acquisition only. This does not install mock
// Source/Effect/Model execution, a Provider, handling policy or physical funds.
// The caller funds all original wires/trees/checked values and read workspace.
export async function loadInstalledProjectMockAnswers(moon: MockRuntime,project: Project | undefined,profile: Profile | undefined,
  {limits,assertCurrent,openFile=open as FileOpen | undefined,deferAnswers=false,installationInventory}: LoadOptions={}){
  let original: ProjectOriginal | undefined=installedProjectOriginalsForRuntime(project,moon);
  const bounds=snapshotLimits(limits);
  if(typeof deferAnswers!=='boolean'||typeof assertCurrent!=='function'||typeof openFile!=='function'||
      typeof project!.directory!=='string'||
      typeof profile?.originalsForRuntime!=='function'||
      typeof profile?.mockLocatorsForRuntime!=='function'||
      typeof profile?.mockAnswerForRuntime!=='function')fail('InvalidInstalledMockAnswerInstallation');
  let profilePorts: ProfilePorts | undefined=Object.freeze({originals:profile.originalsForRuntime,
    locators:profile.mockLocatorsForRuntime,answer:profile.mockAnswerForRuntime});
  let ports: AnswerPorts | undefined=Object.freeze({count:moon?.clientProjectModelRegistryTaskCount,
    task:moon?.clientProjectModelRegistryTaskName,file:moon?.clientProjectModelRegistryTaskFile,
    readTask:moon?.clientProgramReadPublicModelTask,name:moon?.clientProgramPublicModelTaskName,
    readAnswers:moon?.clientProgramReadMockAnswers,retire:moon?.clientProgramRetireMockAnswers});
  if(!Object.values(ports).every(port=>typeof port==='function'))fail('InstalledProjectRuntimeUnavailable');
  const call=<Name extends keyof AnswerPorts>(name: Name,...args: Parameters<AnswerPorts[Name]>)=>
    Reflect.apply(ports![name] as (...args: Parameters<AnswerPorts[Name]>) => ReturnType<AnswerPorts[Name]>,moon,args);
  const select=<Name extends keyof ProfilePorts>(name: Name,...args: ProfileArguments[Name])=>
    Reflect.apply(profilePorts![name] as (runtime: unknown, ...args: ProfileArguments[Name]) =>
      ReturnType<ProfilePorts[Name]>,profile,[moon,...args]);
  let selection: ReturnType<ProfilePorts['originals']> | undefined=select('originals');
  const check=()=>{
    assertCurrent!();
    if(installedProjectOriginalsForRuntime(project,moon)!==original||
        select('originals').selection!==selection!.selection||
        selection!.configuration!==original!.configuration||selection!.selected!=='mock'){
      fail('ForeignInstalledMockAnswerOriginal');
    }
  };
  check();
  const answerCount=select('locators').answerCount;
  const registered=installationInventory===undefined?undefined:
    prepareInstalledMockRegistrySelection(moon,project!,installationInventory);
  check();
  const taskCount=registered===undefined
    ? original.modelRegistry===undefined?0:call('count',original.modelRegistry) : registered.count;
  if(!Number.isSafeInteger(taskCount)||taskCount<0||
      registered===undefined&&taskCount>bounds.maxTasks||
      !Number.isSafeInteger(answerCount)||answerCount<0||answerCount>bounds.maxTasks){
    fail('InstalledMockAnswerCountLimit');
  }
  if(answerCount>0&&typeof project!.registryPath!=='string')fail('InstalledMockAnswerTaskUnavailable');
  const taskBounds: TaskBounds=[bounds.maxBytes,bounds.maxNodes,bounds.maxDepth,bounds.maxMembers,
    bounds.contractNodes,bounds.contractDepth,bounds.contractTextBytes,bounds.maxWork];
  const answerBounds: AnswerBounds=[bounds.maxBytes,bounds.maxNodes,bounds.maxDepth,bounds.maxMembers,
    bounds.valueNodes,bounds.valueDepth,bounds.valueTextBytes,bounds.maxEntries,bounds.maxWork];
  let retained: AnswerEntry[] | readonly AnswerEntry[] | undefined=[],selectionWork=bounds.maxWork;
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
      const taskPath=resolveInstalledProjectTaskPath(project!,moon,taskFile);
      const answerPath=resolve(project!.directory,locator.file);
      const taskFormat=format(taskPath),answerFormat=format(answerPath);
      const taskWire=await readBoundedConfigurationUtf8(taskPath,{maxBytes:bounds.maxBytes,openFile});
      check();
      const task=checked(call('readTask',taskWire,taskFormat,...taskBounds));
      if(call('name',task)!==locator.task)fail('InstalledMockAnswerTaskMismatch');
      let answerWire,answers;
      if(!deferAnswers){
        answerWire=await readBoundedConfigurationUtf8(answerPath,{maxBytes:bounds.maxBytes,openFile});
        check();
        answers=checked(call('readAnswers',task,answerWire,answerFormat,...answerBounds));
      }
      const entry={task,answers,name:locator.task,taskPath,answerPath,taskWire,answerWire,answerFailure:undefined};
      (retained as AnswerEntry[]).push(deferAnswers?Object.seal(entry):Object.freeze(entry));
      check();
    }
  }catch(error){
    const retirement=[];
    for(const entry of retained!){try{if(entry.answers!==undefined)checked(call('retire',entry.answers,entry.task));}catch(cause){retirement.push(cause);}}
    if(retirement.length){
      // Preserve the original read/close carrier and exact unretired DATA.
      // No physical acknowledgement or new cleanup authority is manufactured.
      const failure=new AggregateError([error,...retirement],'InstalledMockAnswerRetirementPending',{cause:error}) as
        AggregateError & {originalAnswerCustody: readonly AnswerEntry[]};
      failure.originalAnswerCustody=Object.freeze(retained);
      throw failure;
    }
    throw error;
  }
  retained=Object.freeze(retained);
  let retired=false,retireIndex=0,view: Answers,modelBinding: ModelState | undefined;
  const same=(runtime: unknown,receiver: unknown)=>{
    if(runtime!==moon||receiver!==view)fail('ForeignInstalledMockAnswerOriginal');
  };
  view=Object.freeze({
    originalsForRuntime(runtime){
      same(runtime,this);
      if(retired)fail('InstalledMockAnswersRetired');
      check();return retained!;
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
        modelBinding.value!.originalsForRuntime(runtime);
        return modelBinding.value!;
      }
      // This SAME answer owner retains each actual Model installation before
      // its next fallible operation. Neither CID lookup nor these callbacks
      // supplies startup, an Account decision, dispatch or physical capacity.
      const callbacks=Object.freeze({normalize:moon.clientProgramNormalizeMockTask,
        materials:moon.clientProgramNormalizedPublicModelTaskMaterials,
        execution:moon.clientProgramMockExecutionMaterials,
        install:deferAnswers?moon.clientProgramPrepareOriginalMock:moon.clientProgramInstallOriginalMock,
        ...(deferAnswers?{bind:moon.clientProgramBindOriginalMockAnswers,
          declaration:moon.clientProgramOriginalMockDeclaration}:{}),
        provider:moon.clientProgramOriginalMockProvider,
        retire:moon.clientProgramRetireOriginalMock,
        environment:moon.clientProgramProjectPublicModelTaskEnvironment});
      if(!Object.values(callbacks).every(callback=>typeof callback==='function')){
        fail('InstalledMockModelRuntimeUnavailable');
      }
      const state: ModelState={profile:originalProfile,now,callbacks,entries:[],retireIndex:0,
        failed:false,failure:undefined,value:undefined,retired:false};
      modelBinding=state;
      const modelCall=<Name extends keyof ModelPorts>(name: Name,...args: Parameters<NonNullable<ModelPorts[Name]>>)=>
        Reflect.apply(state.callbacks![name] as (...args: Parameters<NonNullable<ModelPorts[Name]>>) => unknown,moon,args);
      const profileOriginalsPort=moon.clientProgramMockProfileOriginals;
      const currentModels=(runtime: unknown,receiver: unknown)=>{
        if(runtime!==moon||receiver!==state.value)fail('ForeignInstalledMockModelOriginal');
        if(retired||state.retired)fail('InstalledMockModelsRetired');
        check();
        if(modelBinding!==state)fail('ForeignInstalledMockModelOriginal');
        if(state.failed)throw state.failure;
        // The portable Model owner checks the SAME retained profile, Task and
        // answers; a replacement/copy cannot become a valid Provider here.
        for(const entry of state.entries!){
          const same=deferAnswers
            ? checked(modelCall('declaration',entry.installation))===entry.normalized
            : checked(modelCall('provider',entry.installation))===entry.provider;
          if(!same)fail('ForeignInstalledMockModelOriginal');
        }
        return state.entries!;
      };
      try{
        for(const entry of retained!){
          check();
          const normalized=checked(modelCall('normalize',entry.task,originalProfile,...taskBounds)) as NormalizedTask;
          const material=modelCall('materials',normalized);
          const taskWire=runtimeField(material,0) as string,taskCid=runtimeField(material,1) as string;
          const promptWire=runtimeField(material,2) as string,promptCid=runtimeField(material,3) as string;
          if([taskWire,taskCid,promptWire,promptCid].some(value=>typeof value!=='string')){
            fail('InvalidHostRuntimeResult');
          }
          const execution=modelCall('execution',originalProfile,normalized,...taskBounds);
          const executionMaterial=checked(execution);
          const [executionWire,executionCid,retryWire,retryCid,backoffWire,backoffCid]=
            Array.from({length:6},(_,index)=>runtimeField(executionMaterial,index) as string);
          if([executionWire,executionCid,retryWire,retryCid,backoffWire,backoffCid]
            .some(value=>typeof value!=='string'))fail('InvalidHostRuntimeResult');
          const installation=checked(deferAnswers
            ? modelCall('install',originalProfile,entry.task,normalized,now)
            : modelCall('install',originalProfile,entry.task,normalized,entry.answers,now));
          const bound: BoundEntry={...entry,normalized,taskWire,taskCid,promptWire,promptCid,
            executionWire,executionCid,retryWire,retryCid,backoffWire,backoffCid,
            installation,provider:undefined};
          (state.entries as BoundEntry[]).push(bound);
          bound.provider=checked(modelCall('provider',installation));
          Object.freeze(bound);
          check();
        }
        state.entries=Object.freeze(state.entries!);
        state.value=Object.freeze({
          originalsForRuntime(runtime){return currentModels(runtime,this);},
          providerBindingOriginalsForRuntime(runtime){
            currentModels(runtime,this);
            if(typeof profileOriginalsPort!=='function')fail('InstalledMockModelRuntimeUnavailable');
            const material=Reflect.apply(profileOriginalsPort,moon,[state.profile]);
            if(material===undefined)fail('ForeignInstalledMockModelOriginal');
            const fields=Array.from({length:6},(_,index)=>runtimeField(material,index) as string);
            if(fields.some(value=>typeof value!=='string'))fail('InvalidHostRuntimeResult');
            currentModels(runtime,this);
            return Object.freeze({
              installationRevision:Object.freeze({wire:fields[0],cid:fields[1]}),
              configurationContract:Object.freeze({wire:fields[2],cid:fields[3]}),
              configuration:Object.freeze({wire:fields[4],cid:fields[5]}),
            });
          },
          async prepareAnswersForRuntime(runtime,installation){
            const entries=currentModels(runtime,this);
            const bound=entries.find(entry=>entry.installation===installation);
            if(bound===undefined)fail('ForeignInstalledMockModelOriginal');
            if(!deferAnswers)return;
            // One same-owner physical preparation flight, not a new answer
            // registry/cache. Recheck this original after another flight ends.
            while(state.answerFlight!==undefined)await state.answerFlight;
            currentModels(runtime,this);
            const input=retained!.find(entry=>entry.task===bound.task);
            if(input===undefined)fail('ForeignInstalledMockAnswerOriginal');
            if(input.answerFailure!==undefined)throw input.answerFailure;
            if(input.answers!==undefined)return;
            const flight=Promise.resolve().then(async()=>{
              try{
                const wire=await readBoundedConfigurationUtf8(input.answerPath,
                  {maxBytes:bounds.maxBytes,openFile});
                currentModels(runtime,state.value);
                const answers=checked(call('readAnswers',input.task,wire,
                  format(input.answerPath),...answerBounds));
                // Retain the original DATA before a fallible binding/current
                // check; failure keeps its same answer/file retirement duty.
                input.answers=answers;input.answerWire=wire;
                checked(modelCall('bind',installation,answers));
                currentModels(runtime,state.value);
              }catch(error){input.answerFailure=error;throw error;}
            });
            state.answerFlight=flight;
            try{await flight;}finally{if(state.answerFlight===flight)state.answerFlight=undefined;}
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
            const work=runtimeField(projection,2) as number;
            if(typeof environmentWire!=='string'||typeof identity!=='string'||
                !Number.isSafeInteger(work)||work<0)fail('InvalidHostRuntimeResult');
            currentModels(runtime,this);
            return Object.freeze({environmentWire,evidenceCid:identity,work});
          },
          modelInstallationForRuntime(runtime,wire,evidenceCid){
            const entries=currentModels(runtime,this);
            const projected=this.projectEnvironmentForRuntime(runtime,wire,evidenceCid);
            const dependencyBodies: Body[]=[];
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
      // An answer-input failure belongs to its original DATA/read, not to
      // immutable Task metadata needed by other stored outcomes.
      for(const entry of retained!){
        if((entry.answerFailure as CleanupCarrier | undefined)?.cleanupHandle?.status()?.pending===true)throw entry.answerFailure;
      }
      if(modelBinding!==undefined&&!modelBinding.retired){
        if(modelBinding.answerFlight!==undefined)fail('InstalledMockModelsCleanupPending');
        if((modelBinding.failure as CleanupCarrier | undefined)?.cleanupHandle?.status()?.pending===true)throw modelBinding.failure;
        while(modelBinding.retireIndex<modelBinding.entries!.length){
          const entry=modelBinding.entries![modelBinding.retireIndex];
          if(checked(Reflect.apply(modelBinding.callbacks!.retire,moon,
            [entry.installation]))!==true)fail('InstalledMockModelsCleanupPending');
          modelBinding.retireIndex++;
        }
        modelBinding.retired=true;
        modelBinding.entries=modelBinding.profile=modelBinding.now=modelBinding.callbacks=undefined;
      }
      // The same view finalizes once. A foreign/copied view cannot consume it.
      while(retireIndex<retained!.length){
        const entry=retained![retireIndex];
        if(entry.answers!==undefined)checked(call('retire',entry.answers,entry.task));retireIndex++;
      }
      retained=undefined;retired=true;
      modelBinding=undefined;
      original=selection=project=profile=profilePorts=ports=assertCurrent=openFile=undefined;
    },
  });
  return view;
}
