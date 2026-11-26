import {types} from 'node:util';
import {fixedOriginalTransportTimeouts, unboundOpenAICredential} from './original-undici-transport.mjs';
import {createConfiguredUndiciOpenAIChatRegistration,
  createConfiguredUndiciRegisteredSdkRegistration} from './installed-openai-chat.mjs';
import {runtimeTupleFromFields} from './compiler-binding.generated.mjs';
import type {RegisteredSdk} from './model-port.mjs';
import type {OpenAIChatProviderOptions} from '../index.d.ts';

type ProjectSelection = Readonly<{providerId: string}>;
type Registration = ReturnType<typeof createConfiguredUndiciOpenAIChatRegistration>;
type Entry = ReturnType<Registration>[number];
type Runtime = Parameters<Registration>[0] & {
  clientProgramInstalledNodeModelSdkV4RequestCapacity?(rows: number, bytes: number, nodes: number, depth: number): unknown;
  clientProgramInstalledNodeModelDeadlineCapacity?(): unknown;
  clientProgramStandardInferModelTransferBytes?(maxCalls: bigint): unknown;
};
// Views of the original Host configuration ports and checked Task fields, not
// constructors, proof receipts or a replacement for the same Host's guards.
interface Task {name: string; providerId: string; taskCid: string; modelSelector: string;
  promptCid: string; outputSchemaCid: string; promptPayloadWire: string}
interface SelectedTasks {
  tasks: readonly Task[];
  verifyChatConfiguration(name: string, selector: string, modelId: string, endpoint: string): Promise<void>;
  responseProfileFor(name: string, project: () => string): Promise<{profile: unknown}>;
  executionOriginalsFor(name: string, limits: Readonly<Record<string, bigint>>): Promise<unknown>;
  bindingOriginalsFor(providerId: string): unknown;
  providerEntries<T extends readonly unknown[]>(project: () => T): T | Promise<T>;
}
type RegisteredProvider = Readonly<{defaultSelector: string; routes: readonly RegisteredSdk[]}>;
interface ConfigurationContext {
  [name: string]: unknown;
  projectOpenAIProvider?(): Promise<ProjectSelection>;
  registeredSdkSelected?(providerId: string): boolean;
  prepareRegisteredSdk?(providerId: string): Promise<RegisteredProvider | undefined>;
  prepareConfiguration<T>(project: () => T): Promise<T>;
  runtimeIdentity(): Promise<string>;
  artifactIdentity(path: string): Promise<string>;
  readText(path: string, limits: {maxBytes: number}): Promise<string>;
  prepareBindingOriginals(project: () => readonly [string, string, string]): Promise<unknown>;
  prepareTasks(bindings: readonly {providerId: string; bindingOriginals: unknown}[]): Promise<SelectedTasks>;
  prepareRawPolicies(originals: typeof policies): Promise<Readonly<Record<string, unknown>>>;
}

const refuse: (code: string) => never = code => {throw Object.assign(new TypeError(code), {code});};
const maxInt = 2147483647;
const maxSafe = 9007199254740991n;
const builderArtifactUrl = new URL('./openai-chat.mjs', import.meta.url).href;
const layoutArtifactUrl = import.meta.url;
const lockArtifactUrl = new URL('../npm-shrinkwrap.json', import.meta.url).href;
const data = (source: unknown, required: readonly string[], optional: readonly string[] = []): Readonly<Record<string, unknown>> => {
  if (source === null || typeof source !== 'object' || Array.isArray(source) || types.isProxy(source)) {
    refuse('InvalidOpenAIProviderConfiguration');
  }
  const fields = Object.getOwnPropertyDescriptors(source as object);
  if (required.some(key => !Object.hasOwn(fields, key)) || Reflect.ownKeys(fields).some(key =>
    !required.includes(key as string) && !optional.includes(key as string) || !fields[key as string].enumerable ||
      !Object.hasOwn(fields[key as string], 'value'))) refuse('InvalidOpenAIProviderConfiguration');
  return Object.fromEntries(Object.entries(fields).map(([key, field]) => [key, field.value as unknown]));
};
const text = (value: unknown, length: number) => typeof value === 'string' && value.length > 0 && value.length <= length;
const integer = (value: unknown, min: number, max = maxInt) => Number.isSafeInteger(value) && (value as number) >= min && (value as number) <= max;
const amount = (value: unknown): value is bigint => typeof value === 'bigint' && value > 0n && value <= maxSafe;
const unboundCid = 'sha256:' + '0'.repeat(64);
// Public policy DATA, with independently pinned canonical identity. It permits
// provider-contract retention, never training or nonpublic input. The actual
// Host observation and Source policy still participate in each Core admission.
const handling = Object.freeze({schema: 'actql.contract/0.1', id: 'openai-public-provider-contract',
  version: '1', kind: 'request_data_handling', body: Object.freeze({
    accepted_classifications: Object.freeze(['public']), allowed_regions: Object.freeze(['global']),
    retention: 'provider_contract', training_use: 'forbidden'}),
  cid: 'sha256:2c582952a0c9a6de0dc7fd58b1411207a0eac0c02fe75c2c61a39bf2e6942c54'});
const policies = Object.freeze({
  retention: Object.freeze({wire: '{"name":"openai-normal-retention","version":"actql-installed-local-policy/0.1"}',
    cid: 'sha256:156c8cd1a13296c1f107bc8ccfa895c2bbf9d117672b2ecf76e40af01a605f22'}),
  metadata: Object.freeze({wire: '{"name":"openai-normal-metadata","version":"actql-installed-local-policy/0.1"}',
    cid: 'sha256:53dcd2a09eeb0bb31dd2f3e9a91306f67be00a2f5c6632c30f31868d4967a3e0'}),
  clock: Object.freeze({wire: '{"name":"openai-normal-clock","version":"actql-installed-local-policy/0.1"}',
    cid: 'sha256:f678da7ae0f31b6024cdbf250f304af1a29d395501bb07bf5e6a51e18aa2ab3f'}),
  data: Object.freeze({wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}',
    cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563'}),
});
// One finite serial text-only Host profile. These declarations do not grant
// bytes, calls, authority or coverage. Core must fund the complete checked
// all-row bounds plus these Node controls through the original Request Owner.
const limits = Object.freeze({request_bytes: 32768, response_bytes: 65536, chunk_bytes: 8192,
  chunks: 128, header_bytes: 8192, metadata_bytes: 8192, metadata_nodes: 512, metadata_depth: 16,
  parse_nodes: 4096, parse_depth: 32, parse_work: 2097152,
  adapter_holding_bytes: 8388608, adapter_workspace_bytes: 16777216, active_slots: 1, unsettled_slots: 1});
const controls = Object.freeze({model_requests: 1, retry: false, fallback: false, hedging: false,
  tools: false, repair: false, cache: false, media_fetch: false, workflow_restore: false,
  sdk_telemetry: false, redirect: false});
const bodyLimits = Object.freeze({maxBytes: 65536, maxNodes: 4096, maxDepth: 32,
  maxFrames: 4096, maxWork: 2097152});
const readEnvelopeBytes = (rows: number, physical = limits) => BigInt(rows) * (16384n +
  8n * BigInt(limits.request_bytes + limits.response_bytes + limits.chunk_bytes +
    limits.header_bytes + limits.metadata_bytes) +
  256n * BigInt(limits.parse_nodes + limits.metadata_nodes)) +
  BigInt(physical.adapter_holding_bytes + physical.adapter_workspace_bytes);

function configuration(options: unknown, project: ProjectSelection | undefined, registeredMode: boolean) {
  const required = ['generation', 'budget', 'observeEgress'];
  const optional = ['maxSecretBytes', 'transportTimeouts'];
  if (registeredMode) {
    required.push('providerId', 'dataHandlingContractWire');
  } else {
    required.push('modelId');
    optional.push('modelSelector');
  }
  if (!registeredMode && project === undefined) {
    required.push('providerId', 'apiKeyFile');
    optional.push('baseURL');
  }
  const value = data(options, required, optional) as unknown as OpenAIChatProviderOptions & {dataHandlingContractWire: string};
  const generation = data(value.generation, ['temperature', 'topP', 'maxOutputTokens'], ['seed']) as unknown as OpenAIChatProviderOptions['generation'];
  const budget = data(value.budget, ['maxCalls', 'maxRows', 'maxTokens', 'maxCostUnits', 'maxDurationMs']) as unknown as OpenAIChatProviderOptions['budget'];
  const selector = value.modelSelector ?? value.modelId;
  const baseURL = registeredMode ? undefined
    : (project === undefined ? value.baseURL : undefined) ?? 'https://api.openai.com/v1';
  const maxSecretBytes = value.maxSecretBytes ?? 4096;
  const providerId = project === undefined ? value.providerId : project.providerId;
  const transportTimeouts = fixedOriginalTransportTimeouts(value.transportTimeouts);
  if (!text(providerId, 256) ||
      (registeredMode ? !text(value.dataHandlingContractWire, 4096) :
        !text(value.modelId, 256) || !text(selector, 256) || !text(baseURL, 2048) ||
        project === undefined && !text(value.apiKeyFile, 4096)) ||
      !integer(maxSecretBytes, 1, 4096) || typeof value.observeEgress !== 'function' ||
      !Number.isFinite(generation.temperature) || !Number.isFinite(generation.topP) ||
      !integer(generation.maxOutputTokens, 1) ||
      generation.seed !== undefined && !Number.isSafeInteger(generation.seed) ||
      !integer(budget.maxRows, 1, 64) ||
      ![budget.maxCalls, budget.maxTokens, budget.maxCostUnits, budget.maxDurationMs].every(amount)) {
    refuse('InvalidOpenAIProviderConfiguration');
  }
  if (transportTimeouts !== undefined && Object.values(transportTimeouts).some(ms => BigInt(ms) > budget.maxDurationMs)) {
    refuse('OpenAIProviderTimeoutBudgetExceeded');
  }
  if (!registeredMode) {
    const endpoint = new URL(baseURL + '/chat/completions');
    if (!['https:', 'http:'].includes(endpoint.protocol) || endpoint.username || endpoint.password ||
        endpoint.search || endpoint.hash || endpoint.href !== baseURL + '/chat/completions' || baseURL!.endsWith('/')) {
      refuse('InvalidOpenAIProviderConfiguration');
    }
  }
  if ((project !== undefined || registeredMode) && transportTimeouts?.callMs === undefined) {
    refuse('InvalidProjectOpenAIProviderConfiguration');
  }
  return Object.freeze({...value, providerId, modelSelector: selector, baseURL, maxSecretBytes,
    generation: Object.freeze(generation), budget: Object.freeze(budget),
    ...(transportTimeouts === undefined ? {} : {transportTimeouts})});
}

function observation(callback: () => unknown) {
  return () => {
    const value = callback();
    if (value === undefined || value === null || typeof value !== 'object' || types.isProxy(value)) return undefined;
    const fields = ['classification', 'region', 'providerRetention', 'trainingUse']
      .map(key => Object.getOwnPropertyDescriptor(value, key));
    if (fields.some(field => !field?.enumerable || !Object.hasOwn(field, 'value'))) return undefined;
    return runtimeTupleFromFields(Object.fromEntries(fields.map((field, index) => [index, field!.value as unknown])));
  };
}

// Ordinary Host configuration, not a runtime factory. All semantic identities
// come from the actual initial Common owner and each actual Task declaration.
// The original low-level explicit-material installers remain unchanged.
export function createOpenAIChatProvider(options: unknown):
  (moon: Runtime, context: ConfigurationContext) => Promise<readonly Readonly<Record<string, unknown>>[]> {
  return configureSdkProvider(options, false);
}

export function createProjectOpenAIChatProvider(options: unknown):
  (moon: Runtime, context: ConfigurationContext) => Promise<readonly Readonly<Record<string, unknown>>[]> {
  return configureSdkProvider(options, true);
}

export function createRegisteredSdkProvider(options: unknown):
  (moon: Runtime, context: ConfigurationContext) => Promise<readonly Readonly<Record<string, unknown>>[]> {
  return configureSdkProvider(options, false, true);
}

type PreparedProvider = Awaited<ReturnType<typeof prepareSdkProvider>>;
type PreparedProviderTasks = Awaited<ReturnType<typeof prepareSdkProviderTasks>>;
type ProviderBatch = {configurations: object[]; originals: PreparedProvider[];
  bindings: PreparedProvider['binding'][]; installations: PreparedProviderTasks[]};

export function createRegisteredSdkProviders(options: unknown):
  (moon: Runtime, context: ConfigurationContext) => Promise<readonly Readonly<Record<string, unknown>>[]> {
  let used = false;
  return async (moon: Runtime, context: ConfigurationContext) => {
    if (used) refuse('OpenAIProviderConfigurationReused');
    used = true;
    requireConfigurationContext(context, false, true);
    const batch = await context.prepareConfiguration<ProviderBatch>(() => {
      if (!Array.isArray(options) || types.isProxy(options) || !Object.isFrozen(options) ||
          !integer(options.length, 1, 64) || Reflect.ownKeys(options).length !== options.length + 1) {
        refuse('InvalidRegisteredSdkProviderConfigurations');
      }
      const configurations: object[] = [];
      const ids = new Set<string>();
      for (let index = 0; index < options.length; index++) {
        const field = Object.getOwnPropertyDescriptor(options, index);
        if (!field?.enumerable || !Object.hasOwn(field, 'value')) refuse('InvalidRegisteredSdkProviderConfigurations');
        const option = field.value;
        if (option === null || typeof option !== 'object' || types.isProxy(option) || !Object.isFrozen(option)) {
          refuse('InvalidRegisteredSdkProviderConfigurations');
        }
        const id = Object.getOwnPropertyDescriptor(option, 'providerId');
        if (!id?.enumerable || !Object.hasOwn(id, 'value') || !text(id.value, 256) || ids.has(id.value)) {
          refuse('InvalidRegisteredSdkProviderConfigurations');
        }
        ids.add(id.value);
        configurations.push(option);
      }
      return {configurations, originals: [], bindings: [], installations: []};
    });
    for (const options of batch.configurations) {
      const original = await prepareSdkProvider(moon, context, options, false, true, true);
      batch.originals.push(original);
      batch.bindings.push(original.binding);
    }
    const selected = await context.prepareTasks(batch.bindings);
    for (const original of batch.originals) {
      batch.installations.push(await prepareSdkProviderTasks(context, selected, original, true));
    }
    return selected.providerEntries(() => batch.installations.map(prepared =>
      createSdkProviderEntry(moon, selected, prepared)));
  };
}

function configureSdkProvider(options: unknown, projectMode: boolean, registeredMode = false) {
  let used = false;
  return async (moon: Runtime, context: ConfigurationContext) => {
    if (used) refuse('OpenAIProviderConfigurationReused');
    used = true;
    requireConfigurationContext(context, projectMode, registeredMode);
    const original = await prepareSdkProvider(moon, context, options, projectMode, registeredMode);
    const selected = await context.prepareTasks([original.binding]);
    const prepared = await prepareSdkProviderTasks(context, selected, original);
    return selected.providerEntries(() => [createSdkProviderEntry(moon, selected, prepared)]);
  };
}

function requireConfigurationContext(context: ConfigurationContext, projectMode: boolean, registeredMode: boolean) {
  if (!['prepareConfiguration', 'runtimeIdentity', 'artifactIdentity',
    'prepareBindingOriginals', 'prepareTasks', 'prepareRawPolicies'].every(key => typeof context?.[key] === 'function')) {
    refuse('OpenAIProviderConfigurationContextUnavailable');
  }
  if (projectMode && typeof context.projectOpenAIProvider !== 'function') {
    refuse('OpenAIProviderConfigurationContextUnavailable');
  }
  if (registeredMode ? typeof context.prepareRegisteredSdk !== 'function' : typeof context.readText !== 'function') {
    refuse('OpenAIProviderConfigurationContextUnavailable');
  }
}

async function prepareSdkProvider(moon: Runtime, context: ConfigurationContext, options: unknown,
  projectMode: boolean, registeredMode: boolean, batch = false) {
  const project = projectMode ? await context.projectOpenAIProvider!() : undefined;
  const config = await context.prepareConfiguration(() => {
    const selected = configuration(options, project, registeredMode);
    const maxWireBytes = moon.clientProgramStandardInferModelTransferBytes?.(selected.budget.maxCalls);
    if (!amount(maxWireBytes)) {
      refuse('OpenAIProviderTransferCapacityUnavailable');
    }
    if (typeof moon.clientProgramInstalledNodeModelSdkV4RequestCapacity !== 'function') {
      refuse('OpenAIProviderRequestCapacityUnavailable');
    }
    const sdkQuote = moon.clientProgramInstalledNodeModelSdkV4RequestCapacity(
      selected.budget.maxRows, limits.request_bytes, bodyLimits.maxNodes, bodyLimits.maxDepth);
    const validQuote = (quote: unknown): quote is readonly [bigint, bigint] => Array.isArray(quote) && quote.length === 2 && quote.every((value: unknown) =>
      typeof value === 'bigint' && value >= 0n && value <= BigInt(maxInt)) && quote[1] >= quote[0];
    if (!validQuote(sdkQuote) || sdkQuote[0] === 0n) refuse('OpenAIProviderRequestCapacityUnavailable');
    let deadline: readonly [bigint, bigint] = [0n, 0n];
    if (selected.transportTimeouts?.callMs !== undefined) {
      if (typeof moon.clientProgramInstalledNodeModelDeadlineCapacity !== 'function') {
        refuse('OpenAIProviderDeadlineCapacityUnavailable');
      }
      deadline = moon.clientProgramInstalledNodeModelDeadlineCapacity() as readonly [bigint, bigint];
      if (!validQuote(deadline)) refuse('OpenAIProviderDeadlineCapacityUnavailable');
    }
    // A prepared request retains the extra callback and header binding.
    // Also cover the bounded key and final Bearer string while they overlap.
    const credentialHolding = projectMode || registeredMode
      ? BigInt(selected.budget.maxRows) * (1024n + 8n * BigInt(selected.maxSecretBytes)) : 0n;
    const holding = BigInt(limits.adapter_holding_bytes) + sdkQuote[0] + deadline[0] + credentialHolding;
    const execution = BigInt(limits.adapter_workspace_bytes) + sdkQuote[1] + deadline[1] + credentialHolding;
    if (holding > BigInt(maxInt) || execution > BigInt(maxInt)) {
      refuse('OpenAIProviderRequestCapacityUnavailable');
    }
    // Preserve the entire previous Read base (including selected deadline
    // overlap). Add all-row expected wires only to retained; the SAME serial
    // writer/parse/compare workspace contributes only to execution peak.
    // These are demands on the original initial Owner, never a budget uplift.
    const previousRead = readEnvelopeBytes(selected.budget.maxRows) + deadline[0] + deadline[1] + credentialHolding;
    return Object.freeze({...selected, maxWireBytes,
      readRetainedBytes: previousRead + sdkQuote[0],
      readExecutionBytes: previousRead + sdkQuote[1],
      physicalLimits: Object.freeze({...limits,
        adapter_holding_bytes: Number(holding), adapter_workspace_bytes: Number(execution)})});
  });
  const physicalLimits = config.physicalLimits;
  const runtimeCid = await context.runtimeIdentity();
  const registeredProvider = registeredMode || context.registeredSdkSelected?.(config.providerId)
    ? await context.prepareRegisteredSdk!(config.providerId) : undefined;
  const registeredSdk = registeredProvider?.routes.find(item => item.route.selector === registeredProvider.defaultSelector);
  if (registeredProvider !== undefined && registeredSdk === undefined) {
    refuse('InstalledModelResolvedConfigurationMismatch');
  }
  const builderCid = registeredMode ? registeredSdk?.adapterArtifactCid : await context.artifactIdentity(builderArtifactUrl);
  const layoutCid = await context.artifactIdentity(layoutArtifactUrl);
  const lockCid = registeredMode ? registeredSdk?.lockArtifactCid : await context.artifactIdentity(lockArtifactUrl);
  if (!registeredMode && registeredSdk !== undefined && (!projectMode || registeredProvider!.routes.length !== 1 ||
      registeredSdk.adapterArtifactCid !== builderCid ||
      registeredSdk.lockArtifactCid !== lockCid || registeredSdk.sdkPackage !== '@ai-sdk/openai' ||
      registeredSdk.sdkVersion !== '4.0.91' || registeredSdk.route.selector !== config.modelSelector ||
      registeredSdk.route.modelId !== config.modelId || registeredSdk.route.apiMode !== 'chat_completions' ||
      registeredSdk.route.endpoint !== config.baseURL + '/chat/completions')) {
    refuse('InstalledModelResolvedConfigurationMismatch');
  }
  if (registeredMode && (registeredProvider === undefined || registeredProvider.routes.some(item => item.credential === undefined)) ||
      !registeredMode && registeredSdk?.credential !== undefined && registeredSdk.credential.profile.reference !== 'OPENAI_API_KEY') {
    refuse('RegisteredSdkCredentialMismatch');
  }
  const apiKey = registeredMode ? undefined : projectMode ? unboundOpenAICredential
    : await context.readText(config.apiKeyFile, {maxBytes: config.maxSecretBytes});
  const route = registeredMode ? registeredSdk!.route : undefined;
  const endpoint = route?.endpoint ?? config.baseURL + '/chat/completions';
  const selector = route?.selector ?? config.modelSelector;
  const modelId = route?.modelId ?? config.modelId;
  const apiMode = route?.apiMode ?? 'chat_completions';
  const builderId = registeredMode ? 'actql/registered-sdk' : 'actql/openai-chat';
  const codecId = registeredMode ? 'actql/registered-sdk-output' : 'actql/openai-chat-envelope';
  const sdk = Object.freeze({package_name: registeredMode ? registeredSdk!.sdkPackage : '@ai-sdk/openai',
    version: registeredMode ? registeredSdk!.sdkVersion : '4.0.91', interface: 'v4', lock_artifact_cid: lockCid});
  // The same original selector could formerly name different Chat models.
  // Record the resolved route even when the selector equals the model ID so
  // a current fixed route cannot match a historical selector-only binding.
  const bindings = await context.prepareBindingOriginals(() => {
    const generation = {temperature: config.generation.temperature, top_p: config.generation.topP,
      max_output_tokens: config.generation.maxOutputTokens,
      ...(config.generation.seed === undefined ? {} : {seed_requested: config.generation.seed})};
    const dataHandling: unknown = registeredMode ? JSON.parse(config.dataHandlingContractWire) : handling;
    const modelDefault = (model: string) => ({model, data_handling: dataHandling, generation_config: generation});
    const configuration = {provider_id: config.providerId, adapter_kind: 'ai-sdk',
      ...(registeredMode ? {} : {endpoint, selector, model_id: modelId, api_mode: apiMode}),
      ...(!registeredMode && projectMode ? {credential_reference: 'OPENAI_API_KEY'} : {}),
      ...(config.transportTimeouts === undefined ? {} : {transport_timeouts: config.transportTimeouts}),
      model_defaults: {default_model: selector, models: registeredMode ? [] : [modelDefault(selector)]}};
    let configurationWire: string;
    if (registeredProvider === undefined) {
      configurationWire = JSON.stringify(configuration);
    } else {
      const routes = Object.create(null) as Record<string, unknown>;
      // Bound the aggregate before copying it into one configuration wire.
      // A partial route encoding is temporary and the policy is parsed once.
      let remaining = bodyLimits.maxBytes -
        Buffer.byteLength(JSON.stringify({...configuration, structured_routes: {}}));
      for (const item of [...registeredProvider.routes].sort((a, b) =>
        a.route.selector < b.route.selector ? -1 : a.route.selector > b.route.selector ? 1 : 0)) {
        const alias = item.route.selector;
        const route = {model_id: item.route.modelId, api_mode: item.route.apiMode, endpoint: item.route.endpoint,
          provider_options: item.providerOptions, structured_capability: item.structuredCapability,
          ...(item.credential === undefined ? {} : {registered_credential: item.credential.profile})};
        const defaults = registeredMode ? modelDefault(alias) : undefined;
        remaining -= Buffer.byteLength(JSON.stringify({[alias]: route})) +
          (defaults === undefined ? 0 : Buffer.byteLength(JSON.stringify(defaults)) + 1);
        if (remaining < 0) refuse('InstalledModelConfigurationSizeLimit');
        routes[alias] = route;
        if (defaults !== undefined) configuration.model_defaults.models.push(defaults);
      }
      configurationWire = JSON.stringify({...configuration, structured_routes: routes});
    }
    return [
      JSON.stringify({provider_id: config.providerId, implementation: '@actql/provider-ai-sdk',
        runtime_artifact_cid: runtimeCid, builder_artifact_cid: builderCid, lock_artifact_cid: lockCid,
        ...(registeredSdk === undefined ? {} : {sdk_entry_artifact_cid: registeredSdk.sdkArtifactCid})}),
      JSON.stringify({provider_id: config.providerId,
        required: registeredMode ? ['model_defaults', 'adapter_kind', 'structured_routes']
          : ['endpoint', 'selector', 'model_defaults', 'model_id', 'adapter_kind', 'api_mode',
            ...(registeredProvider === undefined ? [] : ['structured_routes'])],
        physical_profile: physicalLimits, prepared_rows: config.budget.maxRows,
        transport: registeredMode ? 'undici-serial-sdk' : 'undici-serial-chat',
        ...(config.transportTimeouts === undefined ? {} : {transport_timeouts: config.transportTimeouts}),
        runtime_artifact_cid: runtimeCid, layout_artifact_cid: layoutCid,
        read_retained_bytes: String(config.readRetainedBytes),
        read_execution_bytes: String(config.readExecutionBytes),
        model_retained_bytes: String(physicalLimits.adapter_holding_bytes),
        model_execution_bytes: String(physicalLimits.adapter_workspace_bytes)}),
      configurationWire,
    ];
  });
  const borrow = () => ({binding: {providerId: config.providerId, bindingOriginals: bindings}, config, runtimeCid,
    builderCid, layoutCid, lockCid, registeredProvider, apiKey, endpoint, selector,
    modelId, builderId, codecId, sdk, projectMode, registeredMode});
  // In a batch these borrowed references survive another Provider's preparation.
  return batch ? context.prepareConfiguration(borrow) : borrow();
}

async function prepareSdkProviderTasks(context: ConfigurationContext, selected: SelectedTasks,
  original: PreparedProvider, batch = false) {
  const {config, runtimeCid, builderCid, lockCid, endpoint, selector, modelId, builderId, codecId,
    sdk, registeredMode} = original;
  const physicalLimits = config.physicalLimits;
  const select = () => ({original,
    owned: selected.tasks.filter(task => task.providerId === config.providerId),
    profiles: new Map<string, {profile: unknown; selectedSdk: RegisteredSdk | undefined; endpoint: string;
      codecId: string}>(), raw: undefined as Awaited<ReturnType<ConfigurationContext['prepareRawPolicies']>> | undefined});
  // The Host caps its Task list. Fund this extra per-Provider index under the
  // initial configuration owner while later Providers prepare their Tasks.
  const prepared = batch ? await context.prepareConfiguration(select) : select();
  const {owned, profiles} = prepared;
  if (owned.length === 0) refuse('OpenAIProviderTasksUnavailable');
  if (!registeredMode) await selected.verifyChatConfiguration(owned[0].name, selector, modelId, endpoint);
  prepared.raw = await context.prepareRawPolicies(policies);
  for (const task of owned) {
    const selectedSdk = original.registeredProvider?.routes.find(route => route.route.selector === task.modelSelector);
    if (original.registeredProvider !== undefined && selectedSdk === undefined) {
      refuse('InstalledModelResolvedConfigurationMismatch');
    }
    const taskEndpoint = selectedSdk?.route.endpoint ?? endpoint;
    const taskCodec = selectedSdk?.sdkProvider === 'openai.responses' && selectedSdk.route.apiMode === 'responses'
      ? 'actql/openai-responses-envelope' : codecId;
    const profile = await selected.responseProfileFor(task.name, () => JSON.stringify({
      version: 'actql-model-response-profile/0.1', adapter: {builder_id: builderId, builder_revision: '1',
        codec_id: taskCodec, codec_revision: '1', build_artifact_cid: builderCid,
        port_abi: 'model-physical-port/1', sdk: {package: sdk.package_name, version: sdk.version,
          interface: sdk.interface, lock_artifact_cid: lockCid}},
      operation: {endpoint: taskEndpoint, method: 'POST', streaming: false},
      // Unbound template DATA is never installed or used for a Request.
      // The same normalized Core Task supplies all three final identities.
      task: {contract_cid: unboundCid, kind: 'structured_generate', input_schema_cid: unboundCid, output_schema_cid: unboundCid},
      completion: {validator_id: taskCodec, validator_revision: '1',
        validator_artifact_cid: runtimeCid, basis: 'generation_finish', transport_eof: true,
        endpoint_envelope: true, output_contract: true}, probability: null,
      observations: ['provider_request_id', 'provider_reported_model_id', 'finish_reason',
        'input_tokens', 'output_tokens', 'provider_metadata'], limits: physicalLimits, controls,
    }));
    profiles.set(task.taskCid, {profile: profile.profile, selectedSdk, endpoint: taskEndpoint, codecId: taskCodec});
    await selected.executionOriginalsFor(task.name, {maxAttempts: config.budget.maxCalls,
      maxCostUnits: config.budget.maxCostUnits, maxDurationMs: config.budget.maxDurationMs,
      maxWireBytes: config.maxWireBytes,
      maxTokens: config.budget.maxTokens});
  }
  return prepared;
}

function createSdkProviderEntry(moon: Runtime, selected: SelectedTasks, {original, owned, profiles, raw}: PreparedProviderTasks) {
  const {config, runtimeCid, builderCid, layoutCid, apiKey, builderId, sdk, projectMode} = original;
  const physicalLimits = config.physicalLimits;
  const bindingOriginals = selected.bindingOriginalsFor(config.providerId);
  const now = Date.now(), at = (ms: number) => new Date(ms).toISOString();
  const quantityCapacity = Object.freeze({limits: Object.freeze({tokens: config.budget.maxTokens,
    costUnits: config.budget.maxCostUnits, durationMs: config.budget.maxDurationMs}),
    perAttempt: Object.freeze({tokens: config.budget.maxTokens, costUnits: config.budget.maxCostUnits,
      durationMs: config.budget.maxDurationMs})});
  // Eight byte representations cover live request/response/chunk/header/
  // metadata copies; 256-byte controls cover bounded parsed nodes, plus a
  // separate fixed shell. This is finite trusted Host profile DATA. The
  // actual native all-row/Model bounds are added, never replaced by it.
  // Keep the adapter's complete declared live holding/workspace in
  // addition to every prepared row; neither minimum can replace the other.
  const entries = owned.map(task => {
    const {profile, selectedSdk, endpoint, codecId} = profiles.get(task.taskCid)!;
    const installation = Object.freeze({builder_id: builderId, builder_revision: '1',
      codec_id: codecId, codec_revision: '1', build_artifact_cid: builderCid, sdk,
      endpoint, http_method: 'POST', streaming: false,
      validator_id: codecId, validator_revision: '1',
      validator_artifact_cid: runtimeCid, completion_basis: 'generation_finish'});
    const originalReadRecipe = Object.freeze({
      bootstrap: Object.freeze({bootstrapRetainedBytes: 1048576n, bootstrapExecutionBytes: 1048576n,
        maxReservations: 256, maxHoldings: 256, maxDelegations: 256}),
      modelRetainedBytes: BigInt(physicalLimits.adapter_holding_bytes),
      modelExecutionBytes: BigInt(physicalLimits.adapter_workspace_bytes),
      nodeInstallation: Object.freeze({runtimeArtifactCid: runtimeCid,
        layoutArtifactCid: layoutCid, installation, probability: undefined,
        layout: Object.freeze({runtime_artifact_cid: runtimeCid, layout_artifact_cid: layoutCid,
          response_profile: profile, prepared_rows: BigInt(config.budget.maxRows),
          retained_bytes: config.readRetainedBytes, execution_bytes: config.readExecutionBytes})}),
      metadataAcquisition: Object.freeze({retainedBytes: 2097152n, workspaceBytes: 2097152n,
        metadata: Object.freeze({maxWireBytes: 1048576, maxLedgerEntries: 4096}),
        directory: Object.freeze({maxWireBytes: 1048576, maxDirectoryEntries: 4096})}),
      storeBootstrap: Object.freeze({maxWireBytes: 1048576, maxDirectoryEntries: 4096}),
      publicationCapacity: Object.freeze({retainedBytes: 16777216n, workspaceBytes: 16777216n}),
      currentStateCodec: Object.freeze({quantum: 4096, comparisonWork: 770, decode: Object.freeze({
        maxWork: 2097152, parse: Object.freeze({max_input_bytes: 1048576, max_nodes: 16384, max_depth: 64}),
        tree: Object.freeze({max_nodes: 16384, max_depth: 64, max_string_bytes: 1048576, max_total_string_bytes: 1048576})})}),
    });
    const rawCaptureSelection = Object.freeze({...raw, profile, installation, probability: undefined,
      selectedAt: at(now), availableUntil: at(now + 86400000), deleteBy: at(now + 172800000),
      extensionCeilingAt: at(now + 172800000), metadataDeleteBy: at(now + 259200000),
      selectionAvailable: () => Date.now() < now + 86400000});
    const physical = {providerId: config.providerId,
      taskCid: task.taskCid, promptCid: task.promptCid, outputSchemaCid: task.outputSchemaCid,
      promptPayloadWire: task.promptPayloadWire, bindingOriginals, quantityCapacity, originalReadRecipe, rawCaptureSelection,
      projectionLimits: bodyLimits, requestLimits: {maxBytes: limits.request_bytes, maxHeaderBytes: limits.header_bytes, maxHeaders: 32},
      responseLimits: {maxBytes: limits.response_bytes, maxChunkBytes: limits.chunk_bytes, maxChunks: limits.chunks,
        maxHeaderBytes: limits.header_bytes, observedHeaders: ['content-type', 'x-request-id']},
      physicalAcquisitionLimits: {maxPlaintextBytes: 131072, maxBorrowedBackingBytes: 262144, maxReads: 256},
      observeAt: () => new Date().toISOString(), observeEgress: observation(config.observeEgress)};
    const register = selectedSdk?.credential === undefined
      ? createConfiguredUndiciOpenAIChatRegistration({...physical,
        modelSelector: task.modelSelector, modelId: config.modelId, baseURL: config.baseURL, apiKey,
        originalStringLimits: {maxApiKeyCodeUnits: projectMode ? unboundOpenAICredential.length : config.maxSecretBytes,
          maxBaseURLCodeUnits: 2048, maxModelIdCodeUnits: 256}},
      config.transportTimeouts, projectMode ? config.maxSecretBytes : undefined, selectedSdk)
      : createConfiguredUndiciRegisteredSdkRegistration(physical,
        config.transportTimeouts, config.maxSecretBytes, selectedSdk);
    return Object.freeze({taskCid: task.taskCid, entry: register(moon)[0]});
  });
  return Object.freeze({...entries[0]!.entry,
    validatePrompt: (...args: Parameters<Entry['validatePrompt']>) => entries.some(value => value.entry.validatePrompt(...args)),
    taskInstallations: Object.freeze(entries)});
}
