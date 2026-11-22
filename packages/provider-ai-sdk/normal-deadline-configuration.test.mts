import test from 'node:test';
import assert from 'node:assert/strict';
import {createOpenAIChatProvider, createRegisteredSdkProvider} from './_internal/normal-openai-chat.mjs';
import type {OriginalReadRecipeData, PhysicalTransportTimeouts} from './index.d.ts';

type Registration = ReturnType<typeof createOpenAIChatProvider>;
type Runtime = Parameters<Registration>[0];
type Context = Parameters<Registration>[1];
interface CapturedConfiguration {
  physicalLimits: {adapter_holding_bytes: number; adapter_workspace_bytes: number};
  budget: ReturnType<typeof options>['budget']; readRetainedBytes: bigint; readExecutionBytes: bigint;
}
interface ObservedContract {read_retained_bytes: string; read_execution_bytes: string;
  model_retained_bytes: string; model_execution_bytes: string; physical_profile: unknown}
type ReadRecipe = OriginalReadRecipeData & {nodeInstallation: {layout: {response_profile: unknown}}};
type ObservedModelBinding = Readonly<Record<string, unknown> & {model_id: string; adapter_kind: string; api_mode: string}>;
interface ObservedEntry {taskInstallations: readonly {entry: {
  originalReadRecipe: ReadRecipe; bindingOriginals: unknown;
}}[]}


const options = () => ({providerId: 'fixture', modelId: 'fixture', apiKeyFile: 'unread',
  observeEgress() {}, generation: {temperature: 0, topP: 1, maxOutputTokens: 4},
  budget: {maxCalls: 1n, maxRows: 1, maxTokens: 4n, maxCostUnits: 1n, maxDurationMs: 2000n}});
const settings = {connectMs: 1000, headersMs: 1000, bodyMs: 1000, callMs: 100};
const stop = Error('StopBeforeRuntimeIdentityAndIO');
const transfer = {clientProgramStandardInferModelTransferBytes: (attempts: bigint) => attempts * 131072n};
// Explicit context/quote doubles isolate configuration selection. The actual
// initial Resource, Common tariff and normal distribution have separate checks.
function context(captured: CapturedConfiguration[]) {
  const forbidden = () => assert.fail('No semantic/reader/Task operation expected');
  return {async prepareConfiguration(project: () => CapturedConfiguration) {const value = project(); captured.push(value); return value;},
    runtimeIdentity() {throw stop;}, artifactIdentity: forbidden, readText: forbidden,
    prepareBindingOriginals: forbidden, prepareTasks: forbidden, prepareRawPolicies: forbidden};
}

test('registered configuration cannot take route or credential values from caller options', async () => {
  const {providerId, generation, budget, observeEgress} = options();
  const config = {providerId, generation, budget, observeEgress,
    transportTimeouts: settings, dataHandlingContractWire: '{}'};
  let selections = 0;
  const moon = {...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity: () => [100n, 300n],
    clientProgramInstalledNodeModelDeadlineCapacity: () => [456n, 456n]};
  const original = {...context([]), async prepareRegisteredSdk(id: string) {
    assert.equal(id, providerId); selections++; return undefined;
  }};
  for (const override of [{modelId: 'foreign'}, {baseURL: 'https://foreign.invalid'}, {apiKeyFile: 'unread'}]) {
    await assert.rejects(createRegisteredSdkProvider({...config, ...override})(moon as unknown as Runtime, original as unknown as Context),
      {code: 'InvalidOpenAIProviderConfiguration'});
  }
  assert.equal(selections, 0);
  await assert.rejects(createRegisteredSdkProvider(config)(moon as unknown as Runtime, {...original,
    runtimeIdentity: () => 'runtime', artifactIdentity: () => 'layout'} as unknown as Context),
  {code: 'RegisteredSdkCredentialMismatch'});
  assert.equal(selections, 1);
});

test('normal deadline adds only the actual Common R/E quote and preserves unselected profile', async () => {
  for (const enabled of [false, true]) {
    let quotes = 0;
    const captured: CapturedConfiguration[] = [], config: ReturnType<typeof options> & {transportTimeouts?: PhysicalTransportTimeouts} = options();
    if (enabled) config.transportTimeouts = settings;
    const moon = {...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity(){return [100n,300n];},
      clientProgramInstalledNodeModelDeadlineCapacity() {quotes++; return [456n, 456n];}};
    await assert.rejects(createOpenAIChatProvider(config)(moon as unknown as Runtime, context(captured) as unknown as Context), error => error === stop);
    assert.equal(quotes, enabled ? 1 : 0);
    if (enabled) {
      assert.equal(captured[0].physicalLimits.adapter_holding_bytes, 8388608 + 100 + 456);
      assert.equal(captured[0].physicalLimits.adapter_workspace_bytes, 16777216 + 300 + 456);
      assert.equal(captured[0].budget.maxDurationMs, 2000n);
    } else {
      assert.equal(captured[0].physicalLimits.adapter_holding_bytes,8388608+100);
      assert.equal(captured[0].physicalLimits.adapter_workspace_bytes,16777216+300);
    }
  }
});

test('normal deadline missing invalid overflow or over-budget quote refuses before IO', async () => {
  for (const quote of [undefined, [], [1n, 0n], [2147483647n, 2147483647n], [1, 1]]) {
    const moon = {...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity(){return [100n,300n];},
      ...(quote === undefined ? {} : {clientProgramInstalledNodeModelDeadlineCapacity() {return quote;}})};
    const captured: CapturedConfiguration[] = [];
    await assert.rejects(createOpenAIChatProvider({...options(), transportTimeouts: settings})(moon as unknown as Runtime, context(captured) as unknown as Context),
      {code: quote?.[0] === 2147483647n ? 'OpenAIProviderRequestCapacityUnavailable' : 'OpenAIProviderDeadlineCapacityUnavailable'});
    assert.equal(captured.length, 0);
  }
  await assert.rejects(createOpenAIChatProvider({...options(), transportTimeouts: {...settings, callMs: 2001}})({} as Runtime, context([]) as unknown as Context),
    {code: 'OpenAIProviderTimeoutBudgetExceeded'});
});

test('SDK profile demand keeps retained wires and serial workspace distinct before any IO',async()=>{
  const captured: CapturedConfiguration[]=[];let calls=0;
  const moon={...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity(...bounds: unknown[]){
    assert.deepEqual(bounds,[2,32768,4096,32]);calls++;return [123n,789n];}};
  const config=options();config.budget.maxRows=2;
  await assert.rejects(createOpenAIChatProvider(config)(moon as unknown as Runtime,context(captured) as unknown as Context),error=>error===stop);
  assert.equal(calls,1);
  assert.equal(captured[0].readExecutionBytes-captured[0].readRetainedBytes,666n);
  assert.equal(captured[0].physicalLimits.adapter_holding_bytes,8388608+123);
  assert.equal(captured[0].physicalLimits.adapter_workspace_bytes,16777216+789);
  assert.deepEqual(captured[0].budget,config.budget);
});

test('missing invalid or overflowing SDK profile quote refuses before secret semantic or Task work',async()=>{
  for(const quote of [undefined,[],[1n,0n],[2147483647n,2147483647n],[1,1]]){
    const moon={...transfer, ...(quote===undefined?{}:{clientProgramInstalledNodeModelSdkV4RequestCapacity(){return quote;}})};
    const captured: CapturedConfiguration[]=[];
    await assert.rejects(createOpenAIChatProvider(options())(moon as unknown as Runtime,context(captured) as unknown as Context),
      {code:'OpenAIProviderRequestCapacityUnavailable'});
    assert.equal(captured.length,0);
  }
});

test('missing or invalid Common transfer projection refuses before I/O', async () => {
  for (const value of [undefined, -1n, 0n, 9007199254740992n, 131072]) {
    await assert.rejects(createOpenAIChatProvider(options())({
      ...(value === undefined ? {} : {clientProgramStandardInferModelTransferBytes(attempts: bigint) {
        assert.equal(attempts, 1n);
        return value;
      }}),
    } as unknown as Runtime, context([]) as unknown as Context), {code:'OpenAIProviderTransferCapacityUnavailable'});
  }
});

test('an explicit selector binds the resolved Chat model even when defaults and profile are unchanged', async () => {
  const cid = 'sha256:' + 'a'.repeat(64);
  const moon = {...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity() { return [100n, 300n]; }};
  async function originals(modelId: string, modelSelector: string | undefined) {
    let wires!: readonly [Readonly<Record<string, unknown>>, Readonly<Record<string, unknown>>, ObservedModelBinding];
    const f = {...context([]), runtimeIdentity: () => cid, artifactIdentity: () => cid,
      readText: () => 'synthetic-only',
      prepareBindingOriginals(project: Parameters<Context['prepareBindingOriginals']>[0]) { wires = project().map(wire => JSON.parse(wire)) as unknown as typeof wires; throw stop; }};
    await assert.rejects(createOpenAIChatProvider({...options(), modelId, modelSelector})(moon as unknown as Runtime, f as unknown as Context),
      error => error === stop);
    assert.equal(JSON.stringify(wires).includes('synthetic-only'), false);
    return wires;
  }
  const first = await originals('first-model', 'shared-alias');
  const next = await originals('next-model', 'shared-alias');
  assert.deepEqual(next.slice(0, 2), first.slice(0, 2));
  assert.deepEqual(first[1].required, ['endpoint', 'selector', 'model_defaults', 'model_id', 'adapter_kind', 'api_mode']);
  assert.deepEqual(first[2], {...next[2], model_id: 'first-model'});
  assert.equal(next[2].selector, 'shared-alias');
  assert.equal(next[2].model_id, 'next-model');
  assert.equal(next[2].adapter_kind, 'ai-sdk');
  assert.equal(next[2].api_mode, 'chat_completions');
  const direct = await originals('shared-alias', undefined);
  assert.deepEqual(direct[1], first[1]);
  assert.deepEqual(direct[2], {...first[2], model_id: 'shared-alias'});
  const {model_id, adapter_kind, api_mode, ...historical} = first[2];
  assert.deepEqual([model_id, adapter_kind, api_mode], ['first-model', 'ai-sdk', 'chat_completions']);
  // Both choices had the same historical configuration even though their
  // SDK requests used different models.
  assert.deepEqual(historical, Object.fromEntries(Object.entries(direct[2])
    .filter(([key]) => !['model_id', 'adapter_kind', 'api_mode'].includes(key))));
  assert.notDeepEqual(historical, direct[2]);
});

// Actual ordinary factory and registration assembler; explicit Common/context
// ports only. This checks forwarding, not Core admission or physical adequacy.
test('normal binding profile and original Read recipe consume the same separate SDK R E demand',async()=>{
  const cid='sha256:'+'a'.repeat(64),profile=Object.freeze({});
  let contract!: ObservedContract,taskProfile!: {limits: unknown},quoteCalls=0;
  const phases: string[] = [];
  const bindingOriginals=Object.freeze(Object.fromEntries(['configuration','configurationContract','installationRevision']
    .map(name=>[name,Object.freeze({wire:'{}',cid})])));
  const task={providerId:'fixture',name:'task',taskCid:cid,promptCid:cid,outputSchemaCid:cid,
    modelSelector:'fixture-alias',promptPayloadWire:'{}'};
  const selected={tasks:[task],
    async verifyChatConfiguration(...original: [string, string, string, string]) {
      assert.deepEqual(original,['task','fixture-alias','fixture-model',
        'https://api.openai.com/v1/chat/completions']);
      await Promise.resolve();
      phases.push('configuration');
    },
    async responseProfileFor(name: string, project: () => string) {
      assert.deepEqual(phases,['configuration','raw']);
      assert.equal(name,'task');
      taskProfile=JSON.parse(project()) as typeof taskProfile;
      phases.push('profile');
      return {profile};
    },
    async executionOriginalsFor(name: string, policy: Readonly<Record<string, bigint>>){
      assert.equal(name,'task');
      assert.equal(policy.maxAttempts, 1n);
      assert.equal(policy.maxWireBytes, 131072n);
    },
    bindingOriginalsFor(id: string){assert.equal(id,'fixture');return bindingOriginals;},
    providerEntries<T>(project: () => T){return project();}};
  const f={...context([]),runtimeIdentity:async()=>cid,artifactIdentity:async()=>cid,
    readText:async()=> 'fixture-only-never-sent',
    prepareBindingOriginals:async (project: () => readonly string[])=>{contract=JSON.parse(project()[1]!) as ObservedContract;return bindingOriginals;},
    prepareTasks:async()=>selected,
    async prepareRawPolicies() {
      assert.deepEqual(phases,['configuration']);
      phases.push('raw');
      return Object.freeze({});
    }};
  const hooks=['clientProgramStartOpenAIChatProjection','clientProgramAdvanceOpenAIChatProjection',
    'clientProgramRetireOpenAIChatProjection','clientProgramFinishOpenAIChatSdkV4Projection',
    'clientProgramInstallAsyncModelProvider','clientProgramModelRequestGeneration','clientProgramModelRequestPreflight',
    'clientProgramModelAsyncPhysicalRequestPlan','clientProgramModelPhysicalCallForRequest',
    'clientProgramModelPhysicalPending','clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedChat'];
  const moon: Record<string, unknown>=Object.fromEntries(hooks.map(name=>[name,()=>assert.fail('No Model or physical work')]));
  moon.clientProgramStandardInferModelTransferBytes = transfer.clientProgramStandardInferModelTransferBytes;
  moon.clientProgramInstalledNodeModelSdkV4RequestCapacity=(...bounds: unknown[])=>{
    assert.deepEqual(bounds,[1,32768,4096,32]);quoteCalls++;return [123n,789n];};
  moon.clientProgramModelResponseProfileTransportMatches=(actual: unknown)=>{assert.equal(actual,profile);return true;};
  const entries=await createOpenAIChatProvider({...options(),
    modelSelector:'fixture-alias',modelId:'fixture-model'})(moon as Runtime, f as unknown as Context) as unknown as readonly ObservedEntry[];
  assert.deepEqual(phases,['configuration','raw','profile']);
  assert.equal(quoteCalls,1);assert.equal(entries.length,1);
  const recipe=entries[0].taskInstallations[0].entry.originalReadRecipe;
  assert.equal(recipe.modelRetainedBytes,8388608n+123n);
  assert.equal(recipe.modelExecutionBytes,16777216n+789n);
  assert.equal(BigInt(contract.read_retained_bytes),recipe.nodeInstallation.layout.retained_bytes);
  assert.equal(BigInt(contract.read_execution_bytes),recipe.nodeInstallation.layout.execution_bytes);
  assert.equal(recipe.nodeInstallation.layout.execution_bytes-recipe.nodeInstallation.layout.retained_bytes,666n);
  assert.equal(BigInt(contract.model_retained_bytes),recipe.modelRetainedBytes);
  assert.equal(BigInt(contract.model_execution_bytes),recipe.modelExecutionBytes);
  assert.deepEqual(taskProfile.limits,contract.physical_profile);
  assert.equal(recipe.nodeInstallation.layout.response_profile,profile);
  assert.equal(entries[0].taskInstallations[0].entry.bindingOriginals,bindingOriginals);
});
