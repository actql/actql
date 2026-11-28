import test from 'node:test';
import assert from 'node:assert/strict';
import {createRegisteredSdkProvider, createRegisteredSdkProviders} from './_internal/normal-openai-chat.mjs';
import type {OriginalReadRecipeData} from './index.d.ts';

type Registration = ReturnType<typeof createRegisteredSdkProvider>;
type Runtime = Parameters<Registration>[0];
type Context = Parameters<Registration>[1];
interface CapturedConfiguration {
  physicalLimits: {adapter_holding_bytes: number; adapter_workspace_bytes: number};
  budget: ReturnType<typeof options>['budget']; readRetainedBytes: bigint; readExecutionBytes: bigint;
}
interface ObservedContract {read_retained_bytes: string; read_execution_bytes: string;
  model_retained_bytes: string; model_execution_bytes: string; physical_profile: unknown}
type ReadRecipe = OriginalReadRecipeData & {nodeInstallation: {layout: {response_profile: unknown}}};
type ObservedModelBinding = Readonly<{adapter_kind: string; structured_routes: Readonly<Record<string,
  Readonly<{model_id: string; api_mode: string}>>>}>;
interface ObservedEntry {taskInstallations: readonly {entry: {
  originalReadRecipe: ReadRecipe; bindingOriginals: unknown;
}}[]}


const options = () => ({providerId: 'fixture', transportTimeouts: settings, dataHandlingContractWire: '{}',
  observeEgress() {}, generation: {temperature: 0, topP: 1, maxOutputTokens: 4},
  budget: {maxCalls: 1n, maxRows: 1, maxTokens: 4n, maxCostUnits: 1n, maxDurationMs: 2000n}});
const settings = {connectMs: 1000, headersMs: 1000, bodyMs: 1000, callMs: 100};
const stop = Error('StopBeforeRuntimeIdentityAndIO');
const transfer = {clientProgramStandardInferModelTransferBytes: (attempts: bigint) => attempts * 131072n};
const deadline = {clientProgramInstalledNodeModelDeadlineCapacity: () => [456n, 456n]};
const credentialBytes = 1024n + 8n * 4096n;

function registeredRoute(cid: string, modelId: string, selector = 'fixture-alias') {
  const endpoint = 'https://api.openai.com/v1/chat/completions';
  return Object.freeze({defaultSelector: selector, routes: Object.freeze([Object.freeze({
    route: Object.freeze({providerId: 'fixture', selector, modelId, apiMode: 'chat_completions', endpoint}),
    structuredCapability: Object.freeze({operation: 'structured_generate', adapter: 'supported', model: 'supported'}),
    sdkPackage: '@ai-sdk/openai', sdkVersion: '4.0.91', sdkProvider: 'openai.chat', providerOptions: Object.freeze({}),
    lockArtifactCid: cid, adapterArtifactCid: cid, sdkArtifactCid: cid,
    credential: Object.freeze({profile: Object.freeze({reference: 'OPENAI_API_KEY'}), transport: Object.freeze({
      reference: 'OPENAI_API_KEY', header: 'authorization', endpoint,
      prefix: 'Bearer ', placeholder: 'fixture-marker'})}),
    createLanguageModel: () => assert.fail('No Model invocation expected'),
    verifyRequest: () => assert.fail('No Model invocation expected'),
  })])});
}
// Explicit context/quote doubles isolate configuration selection. The actual
// initial Resource, Common tariff and normal distribution have separate checks.
function context(captured: CapturedConfiguration[]) {
  const forbidden = () => assert.fail('No semantic/reader/Task operation expected');
  return {async prepareConfiguration(project: () => CapturedConfiguration) {const value = project(); captured.push(value); return value;},
    runtimeIdentity() {throw stop;}, artifactIdentity: forbidden, prepareRegisteredSdk: forbidden,
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

test('one registered batch prepares the original Tasks once with distinct binding originals', async () => {
  const {generation, budget, observeEgress} = options();
  const ids = ['first', 'second'];
  const modelGeneration = Object.freeze([Object.freeze({selector: 'selector-first',
    temperature: 0.25, topP: 0.5, maxOutputTokens: 2, taskMaxOutputTokens: 3})]);
  const configs = Object.freeze(ids.map(providerId => Object.freeze({providerId, generation, budget, observeEgress,
    transportTimeouts: settings, dataHandlingContractWire: '{}',
    ...(providerId === 'first' ? {modelGeneration} : {})})));
  const moon = {...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity: () => [100n, 300n],
    clientProgramInstalledNodeModelDeadlineCapacity: () => [456n, 456n]};
  const sdkSelections: string[] = [], originals: object[] = [];
  const fixture = {...context([]), runtimeIdentity: () => 'runtime', artifactIdentity: () => 'layout',
    async prepareRegisteredSdk(id: string) {
      sdkSelections.push(id);
      return {defaultSelector: 'selector-' + id, routes: [{
        adapterArtifactCid: 'adapter-' + id, sdkArtifactCid: 'sdk-' + id, lockArtifactCid: 'lock-' + id,
        credential: {profile: {reference: 'FIXTURE_' + id}},
        structuredCapability: {operation: 'structured_generate', adapter: 'supported',
          model: id === 'first' ? 'supported' : 'unsupported'},
        route: {selector: 'selector-' + id, modelId: 'model-' + id, apiMode: 'mode-' + id,
          endpoint: 'https://' + id + '.invalid/generate'}}]};
    },
    async prepareBindingOriginals(project: () => readonly [string, string, string]) {
      const wires = project().map(wire => JSON.parse(wire));
      const id = ids[originals.length];
      assert.equal(wires[0].provider_id, id);
      assert.equal(wires[0].sdk_entry_artifact_cid, 'sdk-' + id);
      assert.deepEqual(Object.keys(wires[2].structured_routes), ['selector-' + id]);
      const route = wires[2].structured_routes['selector-' + id];
      assert.equal(route.model_id, 'model-' + id);
      assert.equal(route.api_mode, 'mode-' + id);
      assert.equal(route.registered_credential.reference, 'FIXTURE_' + id);
      assert.deepEqual(route.structured_capability, {operation: 'structured_generate',
        adapter: 'supported', model: id === 'first' ? 'supported' : 'unsupported'});
      assert.deepEqual(wires[2].model_defaults.models, [{model: 'selector-' + id, data_handling: {},
        ...(id === 'first' ? {generation_config: {temperature: 0.25, top_p: 0.5, max_output_tokens: 2},
          max_task_output_tokens: 3} : {generation_config: {temperature: 0, top_p: 1, max_output_tokens: 4}})}]);
      const original = Object.freeze({wires});
      originals.push(original);
      return original;
    },
    async prepareTasks(bindings: readonly {providerId: string; bindingOriginals: unknown}[]) {
      assert.deepEqual(bindings.map(binding => binding.providerId), ids);
      for (const [index, binding] of bindings.entries()) assert.equal(binding.bindingOriginals, originals[index]);
      throw stop;
    }};
  const register = createRegisteredSdkProviders(configs);
  await assert.rejects(register(moon as unknown as Runtime, fixture as unknown as Context), error => error === stop);
  await assert.rejects(register(moon as unknown as Runtime, fixture as unknown as Context), {code: 'OpenAIProviderConfigurationReused'});
  await assert.rejects(createRegisteredSdkProviders(Object.freeze([configs[0], configs[0]]))(moon as unknown as Runtime, fixture as unknown as Context),
    {code: 'InvalidRegisteredSdkProviderConfigurations'});
  assert.deepEqual(sdkSelections, ids);
  assert.equal(originals.length, 2);
  for (const changed of [{taskMaxOutputTokens: 5}, {topP: 0}, {temperature: 2.1}]) {
    await assert.rejects(createRegisteredSdkProvider({...configs[0], modelGeneration:
      Object.freeze([{...modelGeneration[0], ...changed}])})(moon as unknown as Runtime, fixture as unknown as Context),
    {code: 'InvalidInstalledModelGenerationProfile'});
  }
  const inspectBinding = { ...fixture, prepareBindingOriginals(project: () => unknown) { return project(); }};
  await assert.rejects(createRegisteredSdkProvider({...configs[0], modelGeneration:
    Object.freeze([{...modelGeneration[0], selector: 'unselected'}])})(moon as unknown as Runtime, inspectBinding as unknown as Context),
  {code: 'InstalledModelGenerationRouteMismatch'});
});

test('registered deadline and credential custody add their exact separate Common demands', async () => {
  let quotes = 0;
  const captured: CapturedConfiguration[] = [];
  const moon = {...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity: () => [100n, 300n],
    clientProgramInstalledNodeModelDeadlineCapacity() { quotes++; return [456n, 456n]; }};
  await assert.rejects(createRegisteredSdkProvider(options())(moon as unknown as Runtime, context(captured) as unknown as Context),
    error => error === stop);
  assert.equal(quotes, 1);
  assert.equal(captured[0].physicalLimits.adapter_holding_bytes, Number(8388608n + 100n + 456n + credentialBytes));
  assert.equal(captured[0].physicalLimits.adapter_workspace_bytes, Number(16777216n + 300n + 456n + credentialBytes));
  assert.equal(captured[0].budget.maxDurationMs, 2000n);
  const {callMs: _omitted, ...phasesOnly} = settings;
  await assert.rejects(createRegisteredSdkProvider({...options(), transportTimeouts: phasesOnly})(
    moon as unknown as Runtime, context(captured) as unknown as Context), {code: 'InvalidRegisteredSdkTransportTimeouts'});
  assert.equal(quotes, 1);
});

test('normal deadline missing invalid overflow or over-budget quote refuses before IO', async () => {
  for (const quote of [undefined, [], [1n, 0n], [2147483647n, 2147483647n], [1, 1]]) {
    const moon = {...transfer, clientProgramInstalledNodeModelSdkV4RequestCapacity(){return [100n,300n];},
      ...(quote === undefined ? {} : {clientProgramInstalledNodeModelDeadlineCapacity() {return quote;}})};
    const captured: CapturedConfiguration[] = [];
    await assert.rejects(createRegisteredSdkProvider({...options(), transportTimeouts: settings})(moon as unknown as Runtime, context(captured) as unknown as Context),
      {code: quote?.[0] === 2147483647n ? 'OpenAIProviderRequestCapacityUnavailable' : 'OpenAIProviderDeadlineCapacityUnavailable'});
    assert.equal(captured.length, 0);
  }
  await assert.rejects(createRegisteredSdkProvider({...options(), transportTimeouts: {...settings, callMs: 2001}})({} as Runtime, context([]) as unknown as Context),
    {code: 'OpenAIProviderTimeoutBudgetExceeded'});
});

test('SDK profile demand keeps retained wires and serial workspace distinct before any IO',async()=>{
  const captured: CapturedConfiguration[]=[];let calls=0;
  const moon={...transfer, ...deadline, clientProgramInstalledNodeModelSdkV4RequestCapacity(...bounds: unknown[]){
    assert.deepEqual(bounds,[2,32768,4096,32]);calls++;return [123n,789n];}};
  const config=options();config.budget.maxRows=2;
  await assert.rejects(createRegisteredSdkProvider(config)(moon as unknown as Runtime,context(captured) as unknown as Context),error=>error===stop);
  assert.equal(calls,1);
  assert.equal(captured[0].readExecutionBytes-captured[0].readRetainedBytes,666n);
  assert.equal(captured[0].physicalLimits.adapter_holding_bytes,Number(8388608n + 123n + 456n + 2n * credentialBytes));
  assert.equal(captured[0].physicalLimits.adapter_workspace_bytes,Number(16777216n + 789n + 456n + 2n * credentialBytes));
  assert.deepEqual(captured[0].budget,config.budget);
});

test('missing invalid or overflowing SDK profile quote refuses before secret semantic or Task work',async()=>{
  for(const quote of [undefined,[],[1n,0n],[2147483647n,2147483647n],[1,1]]){
    const moon={...transfer, ...deadline, ...(quote===undefined?{}:{clientProgramInstalledNodeModelSdkV4RequestCapacity(){return quote;}})};
    const captured: CapturedConfiguration[]=[];
    await assert.rejects(createRegisteredSdkProvider(options())(moon as unknown as Runtime,context(captured) as unknown as Context),
      {code:'OpenAIProviderRequestCapacityUnavailable'});
    assert.equal(captured.length,0);
  }
});

test('missing or invalid Common transfer projection refuses before I/O', async () => {
  for (const value of [undefined, -1n, 0n, 9007199254740992n, 131072]) {
    await assert.rejects(createRegisteredSdkProvider(options())({
      ...(value === undefined ? {} : {clientProgramStandardInferModelTransferBytes(attempts: bigint) {
        assert.equal(attempts, 1n);
        return value;
      }}),
    } as unknown as Runtime, context([]) as unknown as Context), {code:'OpenAIProviderTransferCapacityUnavailable'});
  }
});

test('the same selected Chat alias binds a different physical model in the configuration', async () => {
  const cid = 'sha256:' + 'a'.repeat(64);
  const moon = {...transfer, ...deadline, clientProgramInstalledNodeModelSdkV4RequestCapacity() { return [100n, 300n]; }};
  async function originals(modelId: string) {
    let wires!: readonly [unknown, Readonly<Record<string, unknown>>, ObservedModelBinding];
    const f = {...context([]), runtimeIdentity: () => cid, artifactIdentity: () => cid,
      prepareRegisteredSdk: () => registeredRoute(cid, modelId),
      prepareBindingOriginals(project: Parameters<Context['prepareBindingOriginals']>[0]) {
        wires = project().map(wire => JSON.parse(wire)) as unknown as typeof wires;
        throw stop;
      }};
    await assert.rejects(createRegisteredSdkProvider(options())(moon as unknown as Runtime, f as unknown as Context),
      error => error === stop);
    return wires;
  }
  const first = await originals('first-model'), next = await originals('next-model');
  assert.deepEqual(next.slice(0, 2), first.slice(0, 2));
  assert.deepEqual(first[1].required, ['model_defaults', 'adapter_kind', 'structured_routes']);
  const original = first[2].structured_routes['fixture-alias'];
  assert.equal(original.model_id, 'first-model');
  assert.equal(original.api_mode, 'chat_completions');
  assert.equal(first[2].adapter_kind, 'ai-sdk');
  assert.deepEqual(next[2], {...first[2], structured_routes: {'fixture-alias': {...original, model_id: 'next-model'}}});
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
    prepareRegisteredSdk: async () => registeredRoute(cid, 'fixture-model'),
    prepareBindingOriginals:async (project: () => readonly string[])=>{contract=JSON.parse(project()[1]!) as ObservedContract;return bindingOriginals;},
    async prepareTasks() { phases.push('configuration'); return selected; },
    async prepareRawPolicies() {
      assert.deepEqual(phases,['configuration']);
      phases.push('raw');
      return Object.freeze({});
    }};
  const hooks=['clientProgramStartAdmittedStructuredSdkProjection','clientProgramAdmittedStructuredSdkRouteMatches',
    'clientProgramAdvanceOpenAIChatProjection','clientProgramRetireOpenAIChatProjection',
    'clientProgramInstallAsyncModelProvider','clientProgramModelRequestGeneration','clientProgramModelRequestPreflight',
    'clientProgramModelStructuredRequestPlan','clientProgramModelPhysicalCallForRequest',
    'clientProgramModelPhysicalPending','clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedStructured'];
  const moon: Record<string, unknown>=Object.fromEntries(hooks.map(name=>[name,()=>assert.fail('No Model or physical work')]));
  moon.clientProgramStandardInferModelTransferBytes = transfer.clientProgramStandardInferModelTransferBytes;
  moon.clientProgramInstalledNodeModelSdkV4RequestCapacity=(...bounds: unknown[])=>{
    assert.deepEqual(bounds,[1,32768,4096,32]);quoteCalls++;return [123n,789n];};
  moon.clientProgramModelResponseProfileTransportMatches=(actual: unknown)=>{assert.equal(actual,profile);return true;};
  Object.assign(moon, deadline);
  const entries=await createRegisteredSdkProvider(options())(moon as Runtime, f as unknown as Context) as unknown as readonly ObservedEntry[];
  assert.deepEqual(phases,['configuration','raw','profile']);
  assert.equal(quoteCalls,1);assert.equal(entries.length,1);
  const recipe=entries[0].taskInstallations[0].entry.originalReadRecipe;
  assert.equal(recipe.modelRetainedBytes,8388608n + 123n + 456n + credentialBytes);
  assert.equal(recipe.modelExecutionBytes,16777216n + 789n + 456n + credentialBytes);
  assert.equal(BigInt(contract.read_retained_bytes),recipe.nodeInstallation.layout.retained_bytes);
  assert.equal(BigInt(contract.read_execution_bytes),recipe.nodeInstallation.layout.execution_bytes);
  assert.equal(recipe.nodeInstallation.layout.execution_bytes-recipe.nodeInstallation.layout.retained_bytes,666n);
  assert.equal(BigInt(contract.model_retained_bytes),recipe.modelRetainedBytes);
  assert.equal(BigInt(contract.model_execution_bytes),recipe.modelExecutionBytes);
  assert.deepEqual(taskProfile.limits,contract.physical_profile);
  assert.equal(recipe.nodeInstallation.layout.response_profile,profile);
  assert.equal(entries[0].taskInstallations[0].entry.bindingOriginals,bindingOriginals);
});
