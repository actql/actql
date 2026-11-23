import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeContentRun} from './installed-content-run.mjs';
// @ts-expect-error TS7016: the shared runtime facade is still authored in JavaScript.
import {contentGenerationControl} from '../host-common/runtime-core.mjs';
import type {contentGenerationControl as createContentControl} from '../host-common/content-generation-control.mjs';

type Setup = Parameters<typeof installNodeContentRun>[0];
type Run = ReturnType<typeof installNodeContentRun>;
type Invocation = Parameters<Run>[0];
type Plan = Parameters<Run['prepareManagedKeyedRun']>[0]['plan'];
type KeyedLedger = Parameters<Run['prepareKeyedLedger']>[0];
type Execution = Parameters<Invocation['retainExecution']>[0];
type Control = Setup['core']['contentGenerationControl'];
type ManagedOriginal = NonNullable<ReturnType<NonNullable<Setup['prepareKeyedManagedRun']>>>;
type FixtureControl = Pick<Control, 'prefixCapacity' | 'prefix' | 'requestKeyedPrefixCapacity' |
  'startRequestKeyedPrefix' | 'cleanupRequestKeyedPrefix'> & {
  workspaceCapacity(): object;
  prefixCancel(value: Parameters<Control['prefixCancel']>[0]): boolean;
};
type FixtureSetup = Omit<Partial<Setup>, 'moon' | 'core' | 'assertRunCurrent' | 'prepareKeyedManagedRun'> & {
  moon: Pick<Setup['moon'], 'clientProgramKeyedAcquisitionMatchesProgram' | 'clientProgramInstalledManagedRunAccounting'> & {
    clientProgramAcquisitionLedger(): never;
  };
  core: {
    contentGenerationControl: FixtureControl;
    publicationControl: Pick<Setup['core']['publicationControl'], 'checkClientCompiledRunOwner' |
      'checkedClientSerializationGenerationLimits' | 'bindCheckedClientSerializationCapture'>;
  };
  assertRunCurrent(): number;
  prepareKeyedManagedRun(...args: Parameters<NonNullable<Setup['prepareKeyedManagedRun']>>):
    Omit<ManagedOriginal, 'runtime' | 'prepared' | 'request'>;
};
type PrefixMoon = Pick<Parameters<typeof createContentControl>[0], 'clientProgramEffectInputExportLimits' |
  'clientProgramPreparedInstalledKeyedPrefixRequirements' | 'clientProgramInstalledManagedKeyedSerializationPrefixStart' |
  'clientProgramInstalledManagedKeyedSerializationPrefixCleanup' | 'clientProgramSerializationPrefixCancel'>;

// Actual Content driver and retained execution cleanup with explicit native,
// Source/Store/current ports. This does not import a Common runtime or supply
// physical backing, source authority, publication or an external release ACK.
function fixture({returnPrefix=false}={}) {
  const preparedProgram={},request={},keyed={},compiled={},definition={},workspace={},selected={},value={},ledger={};
  const graph={task:0,step:1},source={},lookup={},prefix={},calls: string[]=[];
  const plan={kind:'serialization',compiled,serializationGraph:graph,
    runDefinition:{identity:'same-definition',wire:'{"valid_until":"2099-01-01T00:00:00.000Z"}'}} as unknown as Plan;
  const managed={value,selectedKeyed:selected,contentCompilation:compiled,closed:false};
  const primary=new Error('same keyed start lost return');let ready=false,execution: Execution | undefined,starts=0;
  const control: FixtureControl={workspaceCapacity:()=>workspace,
    prefixCapacity:()=>assert.fail('No prefix/provider capacity reconstruction at execution'),
    prefix:()=>assert.fail('No reconstructed prefix or scalar Ledger'),
    requestKeyedPrefixCapacity:s=>{assert.equal(s,selected);return{retainedBytes:7n,executionBytes:9n};},
    startRequestKeyedPrefix(r,p,s,actualSource,actualLookup){
      assert.deepEqual([r,p,s,actualSource,actualLookup],[value,preparedProgram,selected,source,lookup]);
      assert(execution,'Original execution cleanup must be retained BEFORE native start');
      calls.push('start');starts++;if(!returnPrefix)throw primary;return prefix;},
    cleanupRequestKeyedPrefix(r,s){assert.deepEqual([r,s],[value,selected]);
      assert.equal(calls.at(-1),'index');calls.push('cleanup');return ready;},
    prefixCancel:p=>{assert.equal(p,prefix);calls.push('cancel');return true;},
  };
  const run=installNodeContentRun({moon:{clientProgramKeyedAcquisitionMatchesProgram:(k,p)=>k===keyed&&p===preparedProgram,
    clientProgramInstalledManagedRunAccounting:r=>{assert.equal(r,value);return{$tag:1,_0:[1n]};},
    clientProgramAcquisitionLedger:()=>assert.fail('No standalone Content Ledger')},
    core:{contentGenerationControl:control,publicationControl:{checkClientCompiledRunOwner(c,p){assert.deepEqual([c,p],[compiled,preparedProgram]);},
      checkedClientSerializationGenerationLimits:()=>({maxRows:1,maxBytes:100}),
      bindCheckedClientSerializationCapture:()=>({})}},
    preparedRunRequired:true,assertRunCurrent:()=>calls.push('current'),ownerPrincipal:'principal',storeAuthorityCid:'store',
    now:()=> '2026-11-01T00:00:00.000Z',authorize:()=>true,
    retainPreparation(p,original){assert.equal(p,preparedProgram);original.inputHolder={};original.releaseSelection=()=>{};},
    prepareKeyedManagedRun(p,r,g,recipe,original){assert.deepEqual([p,r,g],[preparedProgram,request,graph]);
      assert.equal(original.contentControl,control);return managed;},
    borrowKeyedManagedLedger:()=>ledger,
    faultInjection:async name=>{assert.equal(name,'content_workspace_reserved');throw primary;},
  } satisfies FixtureSetup as unknown as Setup);
  run.prepareManagedKeyedCompilation({preparedProgram,request,serializationGraph:graph,keyedAcquisition:keyed});
  run.prepareManagedKeyedRun({preparedProgram,request,plan,keyedAcquisition:keyed});
  assert.equal(run.prepareKeyedLedger({preparedProgram,plan,direct:{} as KeyedLedger['direct'],acquisition:keyed,capacity:{} as KeyedLedger['capacity'],capturedContent:true}),ledger);
  const acquiredContent={ledger,keyedLookup:lookup,captured:{capture:{source:()=>source}}} as NonNullable<Invocation['acquiredContent']>;
  const store={storeAuthorityCid:'store',status:()=>({closed:false}),confirmCommittedIndex:async()=>{calls.push('index');return undefined;}} as unknown as Invocation['store'];
  return{run,primary,calls,managed,starts:()=>starts,ready:()=>{ready=true;},
    execution:()=>execution!,invoke:()=>run({preparedProgram,plan,store,principalId:'principal',acquiredContent,
      retainExecution:original=>{execution=original;}})};
}

test('keyed Content lost start return keeps the same managed prefix cleanup and never reconstructs its provider',async()=>{
  const f=fixture();await assert.rejects(f.invoke,e=>e===f.primary);
  assert.equal(f.starts(),1);assert.equal(f.execution().cleanupPending(),true);
  assert.equal(await f.execution().cleanup(),false);assert.equal(f.execution().cleanupPending(),true);
  f.ready();assert.equal(await f.execution().cleanup(),true);assert.equal(f.execution().cleanupPending(),false);
  const cleanups=f.calls.filter(x=>x==='cleanup').length;assert.equal(await f.execution().cleanup(),true);
  assert.equal(f.calls.filter(x=>x==='cleanup').length,cleanups);assert.equal(f.starts(),1);
  await assert.rejects(f.invoke,/InstalledContentRunPreparationUnavailable/);assert.equal(f.starts(),1);
});

test('keyed Content returned prefix remains pending until its original cleanup ACK after original index observation',async()=>{
  const f=fixture({returnPrefix:true});await assert.rejects(f.invoke,e=>e===f.primary);
  assert.equal(f.starts(),1);assert.equal(await f.execution().cleanup(),false);
  assert.equal(f.calls.filter(x=>x==='cancel').length,1);
  f.ready();assert.equal(await f.execution().cleanup(),true);
  assert.equal(f.calls.filter(x=>x==='cancel').length,1,'JS alias is cut after physical ACK; native cleanup owns the same pending prefix');
  assert.equal(f.calls.filter(x=>x==='cleanup').length,2,'retry the same native cleanup rather than reenter the JS prefix');
  assert.equal(f.starts(),1);assert.deepEqual(f.execution().resourceUsage(),[1n]);
});


test('keyed prefix facade preserves the original native receiver, Result, capacity and pending cleanup',()=>{
  const run={},program={},selected={},source={},lookup={},prefix={},calls: string[]=[];
  const original=new Error('original native keyed prefix');let fail=false,pending=true,requirements=[0n,1n,0n,0n,7n,9n];
  const moon: PrefixMoon={clientProgramEffectInputExportLimits:()=>({}),
    clientProgramPreparedInstalledKeyedPrefixRequirements(s){assert.equal(this,moon);assert.equal(s,selected);
      return{$tag:1,_0:requirements};},
    clientProgramInstalledManagedKeyedSerializationPrefixStart(...args){assert.equal(this,moon);
      assert.deepEqual(args,[run,program,selected,source,lookup]);calls.push('start');if(fail)throw original;
      return{$tag:1,_0:prefix};},
    clientProgramInstalledManagedKeyedSerializationPrefixCleanup(r,s){assert.equal(this,moon);
      assert.deepEqual([r,s],[run,selected]);calls.push('cleanup');return{$tag:1,_0:!pending};},
    clientProgramSerializationPrefixCancel(p){assert.equal(p,prefix);return true;},
  };
  const control=(contentGenerationControl as typeof createContentControl)(
    moon as Parameters<typeof createContentControl>[0], {} as Parameters<typeof createContentControl>[1]);
  assert.deepEqual(control.requestKeyedPrefixCapacity(selected),{retainedBytes:7n,executionBytes:9n});
  assert.equal(control.startRequestKeyedPrefix(run,program,selected,source,lookup),prefix);
  assert.equal(control.prefixCancel(prefix),true);
  assert.equal(control.cleanupRequestKeyedPrefix(run,selected),false);
  pending=false;assert.equal(control.cleanupRequestKeyedPrefix(run,selected),true);
  requirements=[0n,0n,0n,0n,7n,9n];assert.throws(()=>control.requestKeyedPrefixCapacity(selected),/Invalid keyed/);
  fail=true;assert.throws(()=>control.startRequestKeyedPrefix(run,program,selected,source,lookup),e=>e===original);
  assert.deepEqual(calls,['start','cleanup','cleanup','start']);
});
