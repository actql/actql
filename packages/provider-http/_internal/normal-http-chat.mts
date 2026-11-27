import {types} from 'node:util';
import {createOriginalUndiciFetch, fixedOriginalTransportTimeouts, prepareOriginalUndiciFetch}
  from '@actql/local-node/_internal/model-http-transport';
import {runtimeTupleFromFields} from './compiler-binding.generated.mjs';
import {createInstalledPreparedHttpChatRegistration} from './installed-http-chat.mjs';
import type {HttpChatProviderOptions} from '@actql/local-node';

type Registration = ReturnType<typeof createInstalledPreparedHttpChatRegistration>;
type Runtime = Parameters<Registration>[0] & {
  clientProgramInstalledNodeModelDeadlineCapacity(): unknown;
  clientProgramStandardInferModelTransferBytes(attempts: bigint): unknown;
};
type Policies = HttpChatProviderOptions['rawPolicies'];
interface Task {
  name: string; providerId: string; taskCid: string; modelSelector: string;
  promptCid: string; outputSchemaCid: string; promptPayloadWire: string;
}
interface SelectedTasks {
  tasks: readonly Task[];
  verifyChatConfiguration(name: string, selector: string, modelId: string, endpoint: string, transport: 'portable-http'): Promise<void>;
  responseProfileFor(name: string, originalTemplate: () => string): Promise<{profile: unknown}>;
  executionOriginalsFor(name: string, policy: Readonly<Record<string, bigint>>): Promise<unknown>;
  bindingOriginalsFor(id: string): unknown;
  providerEntries<T>(project: () => T): Promise<T>;
}
interface HostConfiguration {
  prepareConfiguration<T>(project: () => T): Promise<T>;
  runtimeIdentity(): Promise<string>;
  artifactIdentity(locator: string): Promise<string>;
  prepareBindingOriginals(project: () => readonly [string, string, string]): Promise<unknown>;
  prepareTasks(bindings: readonly {providerId: string; bindingOriginals: unknown}[]): Promise<SelectedTasks>;
  prepareRawPolicies(originals: Policies): Promise<Readonly<Record<string, unknown>>>;
  registeredSdkSelected(id: string): boolean;
}
const fail: (code: string) => never = code => { throw Object.assign(new TypeError(code), {code}); };
const invalid = 'InvalidInstalledHttpChatProviderConfiguration';
const maxCredentialBytes = 4096;
const placeholder = 'actql-unbound-http-chat-credential';
const builderId = 'actql/node-portable-chat';
const codecId = 'actql/openai-chat-envelope';
const unboundCid = 'sha256:' + '0'.repeat(64);
const rawLifetimeMs = 86_400_000;
const physical = Object.freeze({request_bytes: 32768, response_bytes: 65536, chunk_bytes: 8192,
  chunks: 128, header_bytes: 8192, metadata_bytes: 8192, metadata_nodes: 512, metadata_depth: 16,
  parse_nodes: 4096, parse_depth: 32, parse_work: 2097152,
  adapter_holding_bytes: 8388608, adapter_workspace_bytes: 16777216, active_slots: 1, unsettled_slots: 1});
const requestLimits = Object.freeze({maxBytes: physical.request_bytes, maxHeaderBytes: physical.header_bytes, maxHeaders: 32});
const responseLimits = Object.freeze({maxBytes: physical.response_bytes, maxChunkBytes: physical.chunk_bytes,
  maxChunks: physical.chunks, maxHeaderBytes: physical.header_bytes, observedHeaders: ['content-type', 'x-request-id']});
const projectionLimits = Object.freeze({maxBytes: physical.request_bytes, maxNodes: physical.parse_nodes,
  maxDepth: physical.parse_depth, maxFrames: 4096, maxWork: physical.parse_work});
const physicalAcquisitionLimits = Object.freeze({maxPlaintextBytes: 131072, maxBorrowedBackingBytes: 262144, maxReads: 256});

function readData(value: unknown, required: readonly string[], optional: readonly string[] = []) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || types.isProxy(value)) fail(invalid);
  const fields = Object.getOwnPropertyDescriptors(value);
  if (required.some(name => !Object.hasOwn(fields, name)) ||
      Reflect.ownKeys(fields).some(name => typeof name !== 'string' ||
        !required.includes(name) && !optional.includes(name) || !fields[name].enumerable ||
        !Object.hasOwn(fields[name], 'value'))) fail(invalid);
  return Object.freeze(Object.fromEntries(Object.entries(fields).map(([name, field]) => [name, field.value])));
}

function readConfiguration(value: unknown, moon: Runtime) {
  const selected = readData(value, ['providerId', 'modelSelector', 'modelId', 'endpoint', 'credentialEnvironment',
    'dataHandlingContractWire', 'rawPolicies', 'generation', 'budget', 'transportTimeouts', 'observeEgress']) as HttpChatProviderOptions;
  const generation = readData(selected.generation, ['temperature', 'topP', 'maxOutputTokens'], ['seed']) as HttpChatProviderOptions['generation'];
  const budget = readData(selected.budget, ['maxCalls', 'maxRows', 'maxTokens', 'maxCostUnits', 'maxDurationMs']) as HttpChatProviderOptions['budget'];
  const raw = readData(selected.rawPolicies, ['retention', 'metadata', 'clock', 'data']);
  const rawPolicies = Object.freeze(Object.fromEntries(Object.entries(raw).map(([role, body]) =>
    [role, readData(body, ['wire', 'cid'])]))) as Policies;
  const text = (field: unknown, max: number) => typeof field === 'string' && field.length > 0 && field.length <= max;
  const amount = (field: unknown): field is bigint => typeof field === 'bigint' && field > 0n && field <= 9007199254740991n;
  if (![selected.providerId, selected.modelSelector, selected.modelId].every(field => text(field, 256)) ||
      !text(selected.endpoint, 2048) || !text(selected.dataHandlingContractWire, 4096) ||
      !text(selected.credentialEnvironment, 256) || !/^[A-Z_][A-Z0-9_]*$/u.test(selected.credentialEnvironment) ||
      typeof selected.observeEgress !== 'function' ||
      !Number.isFinite(generation.temperature) || !Number.isFinite(generation.topP) ||
      !Number.isSafeInteger(generation.maxOutputTokens) || generation.maxOutputTokens < 1 ||
      generation.seed !== undefined && !Number.isSafeInteger(generation.seed) ||
      !Number.isSafeInteger(budget.maxRows) || budget.maxRows < 1 || budget.maxRows > 64 ||
      ![budget.maxCalls, budget.maxTokens, budget.maxCostUnits, budget.maxDurationMs].every(amount)) fail(invalid);
  let endpoint: URL;
  try { endpoint = new URL(selected.endpoint); } catch { fail(invalid); }
  if (endpoint.href !== selected.endpoint || endpoint.protocol !== 'https:' || endpoint.username ||
      endpoint.password || endpoint.hash || endpoint.search) fail(invalid);
  const timeouts = fixedOriginalTransportTimeouts(selected.transportTimeouts);
  if (timeouts?.callMs === undefined || Object.values(timeouts).some(ms => BigInt(ms) > budget.maxDurationMs)) fail(invalid);
  const transfer = moon.clientProgramStandardInferModelTransferBytes(budget.maxCalls);
  const deadline = moon.clientProgramInstalledNodeModelDeadlineCapacity();
  if (!amount(transfer) || !Array.isArray(deadline) || deadline.length !== 2 ||
      deadline.some(quote => typeof quote !== 'bigint' || quote < 0n || quote > 2147483647n) ||
      deadline[1] < deadline[0]) fail('InstalledHttpChatCapacityUnavailable');
  // Retain the same finite transport/reader bound used by the ordinary serial
  // Host. Direct Chat has no SDK-rendered payload, SDK alias or SDK quote.
  const credentials = BigInt(budget.maxRows) * (1024n + 8n * BigInt(maxCredentialBytes));
  const holding = BigInt(physical.adapter_holding_bytes) + deadline[0] + credentials;
  const execution = BigInt(physical.adapter_workspace_bytes) + deadline[1] + credentials;
  if (holding > 2147483647n || execution > 2147483647n) fail('InstalledHttpChatCapacityUnavailable');
  const readBytes = BigInt(budget.maxRows) * (16384n +
    8n * BigInt(physical.request_bytes + physical.response_bytes + physical.chunk_bytes + physical.header_bytes + physical.metadata_bytes) +
    256n * BigInt(physical.parse_nodes + physical.metadata_nodes)) + holding + execution;
  const amounts = Object.freeze({tokens: budget.maxTokens, costUnits: budget.maxCostUnits, durationMs: budget.maxDurationMs});
  return Object.freeze({...selected, generation, budget, rawPolicies, timeouts, transfer, holding, execution, readBytes, amounts,
    limits:Object.freeze({...physical, adapter_holding_bytes:Number(holding), adapter_workspace_bytes:Number(execution)})});
}

// The callback runs only inside the existing installed Host configuration
// owner. Endpoint/credential/policies come from its explicit deployment data.
export function createHttpChatProvider(options: HttpChatProviderOptions) {
  let used = false;
  return async (moon: Runtime, context: HostConfiguration) => {
    if (used) fail('InstalledHttpChatProviderConfigurationReused');
    used = true;
    const config = await context.prepareConfiguration(() => readConfiguration(options, moon));
    if (context.registeredSdkSelected(config.providerId)) fail('InvalidInstalledHttpChatProviderConfiguration');
    const runtimeCid = await context.runtimeIdentity();
    const builderCid = await context.artifactIdentity(new URL('./original-chat-request.mjs', import.meta.url).href);
    const layoutCid = await context.artifactIdentity(import.meta.url);
    const binding = await context.prepareBindingOriginals(() => [
      JSON.stringify({provider_id:config.providerId, implementation:'@actql/local-node',
        runtime_artifact_cid:runtimeCid, builder_artifact_cid:builderCid}),
      JSON.stringify({provider_id:config.providerId, required:['endpoint', 'selector', 'model_id', 'adapter_kind',
        'api_mode', 'model_defaults', 'credential_reference'], physical_profile:config.limits,
        prepared_rows:config.budget.maxRows, transport:'undici-serial-chat', transport_timeouts:config.timeouts,
        runtime_artifact_cid:runtimeCid, layout_artifact_cid:layoutCid,
        read_retained_bytes:String(config.readBytes), read_execution_bytes:String(config.readBytes),
        model_retained_bytes:String(config.holding), model_execution_bytes:String(config.execution)}),
      JSON.stringify({provider_id:config.providerId, selector:config.modelSelector, model_id:config.modelId,
        endpoint:config.endpoint, adapter_kind:'portable-http', api_mode:'chat-completions',
        credential_reference:config.credentialEnvironment, transport_timeouts:config.timeouts,
        model_defaults:{default_model:config.modelSelector, models:[{model:config.modelSelector,
          data_handling:JSON.parse(config.dataHandlingContractWire),
          generation_config:{temperature:config.generation.temperature, top_p:config.generation.topP,
            max_output_tokens:config.generation.maxOutputTokens,
            ...(config.generation.seed === undefined ? {} : {seed_requested:config.generation.seed})}}]}}),
    ]);
    const selected = await context.prepareTasks([{providerId:config.providerId,bindingOriginals:binding}]);
    const tasks = await context.prepareConfiguration(() => selected.tasks.filter(task => task.providerId === config.providerId));
    if (!tasks.length || tasks.length !== selected.tasks.length) fail('InstalledHttpChatProviderTasksUnavailable');
    const originals = await context.prepareRawPolicies(config.rawPolicies);
    const prepared = await context.prepareConfiguration((): {task: Task; profile: unknown}[] => []);
    for (const task of tasks) {
      if (task.modelSelector !== config.modelSelector) fail('InstalledModelResolvedConfigurationMismatch');
      await selected.verifyChatConfiguration(task.name, task.modelSelector, config.modelId, config.endpoint, 'portable-http');
      const {profile} = await selected.responseProfileFor(task.name, () => JSON.stringify({
        version:'actql-model-response-profile/0.1',
        adapter:{builder_id:builderId,builder_revision:'1',codec_id:codecId,codec_revision:'1',
          build_artifact_cid:builderCid,port_abi:'model-physical-port/1',sdk:null},
        operation:{endpoint:config.endpoint,method:'POST',streaming:false},
        task:{contract_cid:unboundCid,kind:'structured_generate',input_schema_cid:unboundCid,output_schema_cid:unboundCid},
        completion:{validator_id:codecId,validator_revision:'1',validator_artifact_cid:runtimeCid,
          basis:'generation_finish',transport_eof:true,endpoint_envelope:true,output_contract:true},
        probability:null, observations:['provider_request_id','provider_reported_model_id','finish_reason','input_tokens','output_tokens','provider_metadata'],
        limits:config.limits,
        controls:{model_requests:1,retry:false,fallback:false,hedging:false,tools:false,repair:false,
          cache:false,media_fetch:false,workflow_restore:false,sdk_telemetry:false,redirect:false},
      }));
      await selected.executionOriginalsFor(task.name, {maxAttempts:config.budget.maxCalls,
        maxCostUnits:config.amounts.costUnits,maxDurationMs:config.amounts.durationMs,
        maxWireBytes:config.transfer,maxTokens:config.amounts.tokens});
      prepared.push({task, profile});
    }
    return selected.providerEntries(() => {
      const entries = prepared.map(({task,profile}) => Object.freeze({taskCid:task.taskCid,
        entry:buildEntry(moon, selected, config, task, originals, profile, runtimeCid, builderCid, layoutCid)}));
      return [Object.freeze({...entries[0]!.entry,
        validatePrompt:(task:unknown, selector:unknown, payload:unknown) => entries.some(value =>
          typeof value.entry.validatePrompt === 'function' && value.entry.validatePrompt(task,selector,payload) === true),
        taskInstallations:Object.freeze(entries)})];
    });
  };
}

function buildEntry(moon: Runtime, selected: SelectedTasks, config: ReturnType<typeof readConfiguration>,
  task: Task, originals: Readonly<Record<string, unknown>>, profile: unknown,
  runtimeCid: string, builderCid: string, layoutCid: string) {
  const installation = Object.freeze({builder_id:builderId,builder_revision:'1',codec_id:codecId,codec_revision:'1',
    // The typed Common installation uses the compiled Option representation.
    build_artifact_cid:builderCid,sdk:undefined,endpoint:config.endpoint,http_method:'POST',streaming:false,
    validator_id:codecId,validator_revision:'1',validator_artifact_cid:runtimeCid,completion_basis:'generation_finish'});
  const now = Date.now(), at = (ms: number) => new Date(now + ms).toISOString();
  const transport = createOriginalUndiciFetch({endpoint:config.endpoint,requestLimits,responseLimits,
    physicalAcquisitionLimits,transportTimeouts:config.timeouts,registeredCredential:{endpoint:config.endpoint,
      reference:config.credentialEnvironment,header:'authorization',prefix:'Bearer ',placeholder,maxBytes:maxCredentialBytes}});
  return createInstalledPreparedHttpChatRegistration({
    providerId:config.providerId,modelSelector:task.modelSelector,modelId:config.modelId,endpoint:config.endpoint,
    headers:[['content-type','application/json'],['authorization','Bearer ' + placeholder]], needsCredential:true,
    taskCid:task.taskCid,promptCid:task.promptCid,outputSchemaCid:task.outputSchemaCid,promptPayloadWire:task.promptPayloadWire,
    bindingOriginals:selected.bindingOriginalsFor(config.providerId),requestLimits,responseLimits,projectionLimits,
    quantityCapacity:Object.freeze({limits:config.amounts,perAttempt:config.amounts}),
    originalReadRecipe:Object.freeze({
      bootstrap:Object.freeze({bootstrapRetainedBytes:1048576n,bootstrapExecutionBytes:1048576n,maxReservations:256,maxHoldings:256,maxDelegations:256}),
      modelRetainedBytes:config.holding,modelExecutionBytes:config.execution,
      nodeInstallation:Object.freeze({runtimeArtifactCid:runtimeCid,layoutArtifactCid:layoutCid,installation,probability:undefined,
        layout:Object.freeze({runtime_artifact_cid:runtimeCid,layout_artifact_cid:layoutCid,response_profile:profile,
          prepared_rows:BigInt(config.budget.maxRows),retained_bytes:config.readBytes,execution_bytes:config.readBytes})}),
      metadataAcquisition:Object.freeze({retainedBytes:2097152n,workspaceBytes:2097152n,
        metadata:Object.freeze({maxWireBytes:1048576,maxLedgerEntries:4096}),
        directory:Object.freeze({maxWireBytes:1048576,maxDirectoryEntries:4096})}),
      storeBootstrap:Object.freeze({maxWireBytes:1048576,maxDirectoryEntries:4096}),
      publicationCapacity:Object.freeze({retainedBytes:16777216n,workspaceBytes:16777216n}),
      currentStateCodec:Object.freeze({quantum:4096,comparisonWork:770,decode:Object.freeze({maxWork:2097152,
        parse:Object.freeze({max_input_bytes:1048576,max_nodes:16384,max_depth:64}),
        tree:Object.freeze({max_nodes:16384,max_depth:64,max_string_bytes:1048576,max_total_string_bytes:1048576})})}),
    }),
    rawCaptureSelection:Object.freeze({...originals,profile,installation,probability:undefined,
      selectedAt:at(0),availableUntil:at(rawLifetimeMs),deleteBy:at(2*rawLifetimeMs),
      extensionCeilingAt:at(2*rawLifetimeMs),metadataDeleteBy:at(3*rawLifetimeMs),
      selectionAvailable:() => Date.now() < now + rawLifetimeMs}),
    observeAt:() => new Date().toISOString(),
    observeEgress() {
      const value = config.observeEgress();
      if (value === null || typeof value !== 'object' || types.isProxy(value)) return undefined;
      const fields = ['classification','region','providerRetention','trainingUse']
        .map(key => Object.getOwnPropertyDescriptor(value,key));
      if (fields.some(field => !field?.enumerable || !Object.hasOwn(field, 'value'))) return undefined;
      return runtimeTupleFromFields(Object.fromEntries(fields.map((field,index) => [index,field!.value])));
    },
  }, (endpoint, init, limits, controller) =>
    prepareOriginalUndiciFetch(transport, endpoint, init, limits, controller))(moon)[0]!;
}
