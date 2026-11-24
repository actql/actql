import {installModelProviders, prepareInstalledModelProviderDefaults} from './installed-model.mjs';
import {prepareInstalledProjectModelTasks} from './installed-project-model-tasks.mjs';
import {installedProjectOriginalsForRuntime} from './installed-project-configuration.mjs';
import {installedSourceConfigurationReader, reserveInstalledSourceRuntimeIdentity} from './installed-host-services.mjs';
import {fileURLToPath} from 'node:url';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {isDeepStrictEqual, types as nodeTypes} from 'node:util';
import packageCustody from './initial-control-package-custody.cjs';

type ProviderInstaller = typeof installModelProviders;
type TaskPreparation = typeof prepareInstalledProjectModelTasks;
type Defaults = ReturnType<typeof prepareInstalledModelProviderDefaults>;
type CandidateTasks = Awaited<ReturnType<TaskPreparation>>;
type PrepareCapability = NonNullable<Parameters<ProviderInstaller>[6]>;
type RawSelection = Parameters<PrepareCapability>[4];
type SourceReader = NonNullable<ReturnType<typeof installedSourceConfigurationReader>>;
type FundedInput<Value extends object> = Readonly<{capacity(): unknown; project(): Value; retained(value: NoInfer<Value>): unknown}>;
type ModelReader = Omit<SourceReader, 'prepareModelTaskInput'> & {
  prepareModelTaskInput<Value extends object>(input: FundedInput<Value>): Value;
};
type Current = () => unknown;
type Binding = Readonly<{value: unknown; originals: Readonly<{configuration: Body; installationRevision: Body}>}>;
type Body = Readonly<{wire: string; cid: string}>;
type ArtifactHolder = {path: string; value: string | undefined};
type Execution = Readonly<{modelTaskCid: string; execution: Body; retry: Body; backoff: Body; prompt: Body}>;
type TaskData = Readonly<{name: string; providerId: string; taskCid: string; promptCid: string;
  outputSchemaCid: string; modelSelector: string; promptPayloadWire: string}>;
type CapabilityRuntime = Parameters<ProviderInstaller>[0] & Parameters<TaskPreparation>[0] &
  Readonly<{
    clientProgramInstalledSourceConstructionCapacity(nodes: bigint, text: bigint, wire: bigint,
      workspaceNodes: bigint, workspaceText: bigint, workspaceWire: bigint): unknown;
    clientProjectModelRegistryDefaultProvider(registry: unknown): unknown;
    clientProjectModelRegistryProviderCount(registry: unknown): number;
    clientProjectModelRegistryProviderName(registry: unknown, index: number): unknown;
    clientProjectModelRegistryProviderType(registry: unknown, index: number): unknown;
    clientProjectModelRegistryProviderKeyEnvironment(registry: unknown, index: number): unknown;
    clientProgramPrepareModelProviderOriginals(installation: string, contract: string, configuration: string,
      bytes: number, nodes: number, depth: number, work: number): unknown;
    clientProgramModelRawOriginalRetainedCapacity(value: unknown, nodes: number, depth: number, bytes: number): unknown;
    clientProgramAdmitEffectDependencyBody(kind: string, cid: string, wire: string,
      bytes: number, nodes: number, depth: number): unknown;
    clientProgramNormalizedPublicModelTaskProviderData(task: unknown, bytes: number, nodes: number, depth: number, work: number): unknown;
    clientProgramInstalledChatConfigurationMatches(binding: unknown, configuration: string, provider: string,
      selector: unknown, modelId: unknown, endpoint: unknown): unknown;
    clientProgramNormalizedPublicModelTaskResponseProfile(task: unknown, profile: unknown,
      bytes: number, nodes: number, depth: number, work: number): unknown;
    clientProgramNormalizedPublicModelTaskNoRetryMaterials(task: unknown, ...limits: (bigint | number)[]): unknown;
    clientProgramPrepareInstalledStructuredSdkCapability(provider: unknown, binding: unknown, config: string,
      selector: unknown, model: unknown, mode: unknown, endpoint: unknown, profile: unknown): unknown;
  }>;
type ModelLimits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxMembers: number; maxWork: number}>;
type SdkInstallation = NonNullable<ReturnType<typeof packageCustody.ordinaryModelSdkInstallation>>;
type VerifiedImage = NonNullable<ReturnType<SdkInstallation['verifiedSdkInstallations']['get']>>;
type VerifiedSdk = VerifiedImage & Readonly<{
  sdk: VerifiedImage['sdk'] & Readonly<{packageName: string; version: string; exportName: string}>;
  route: Readonly<{providerId: string; selector: string; modelId: string; apiMode: string; endpoint: string}>;
  providerOptions: unknown;
  credential?: Readonly<{reference: unknown; header: unknown}>;
}>;
type SdkFile = Readonly<{path: unknown; cid: unknown}>;
type SdkAdapter = Readonly<{createLanguageModel?: unknown; verifyRequest?: unknown; sdkProvider?: unknown;
  readReportedUsage?: unknown; optionNamespace?: unknown; optionSchema?: unknown; credentialBinding?: unknown}>;
type ImageRead = NonNullable<ReturnType<typeof packageCustody.readVerifiedSdkImage>>;
type Credentials = Readonly<{transport: object; profile: object}>;
type Registration = Readonly<{route: VerifiedSdk['route']; providerOptions: object;
  credential?: Credentials; sdkPackage: string; sdkVersion: string; sdkArtifactCid: unknown;
  adapterArtifactCid: unknown; lockArtifactCid: unknown}>;
type SdkSelection = Readonly<{installation: Readonly<{build_artifact_cid?: unknown; endpoint?: unknown;
  sdk?: Readonly<{package_name?: unknown; version?: unknown; interface?: unknown; lock_artifact_cid?: unknown}>}>; profile: unknown}>;
type Options = Partial<SdkInstallation> & Readonly<{
  moon: CapabilityRuntime; register?: (runtime: CapabilityRuntime, context: object) => unknown;
  project?: Parameters<TaskPreparation>[1]; taskLimits: ModelLimits; installationServices?: object;
  assertCurrent: Current; assertHostRuntime?: Current; assertNewHostRuntime?: Current;
  bindSdkStaticOriginals?: Parameters<ProviderInstaller>[4]; runtimeUrl?: string;
}>;
type Writer = Readonly<{putSemantic(wire: string, cid: string): unknown}>;
const fail: (code: string) => never = code => { throw Object.assign(new TypeError(code), {code}); };
const invalidSdkInstallation = 'InvalidInstalledModelSdkInstallation';
const plainSdkRecord = (value: unknown): value is Readonly<Record<PropertyKey, unknown>> => value !== null && typeof value === 'object' &&
  !nodeTypes.isProxy(value) && Object.getPrototypeOf(value) === Object.prototype;

function originalSdkRecord(value: unknown, keys: readonly PropertyKey[], optional: readonly PropertyKey[] = []) {
  if (!plainSdkRecord(value) || !Object.isFrozen(value) ||
      Reflect.ownKeys(value).some(key => !keys.includes(key) && !optional.includes(key)) ||
      [...keys, ...optional.filter(key => Object.hasOwn(value, key))].some(key => {
        const field = Object.getOwnPropertyDescriptor(value, key);
        return !field?.enumerable || !Object.hasOwn(field, 'value');
      })) fail(invalidSdkInstallation);
  return value;
}

function sdkProviderOptions(values: unknown, namespace: unknown, schema: unknown) {
  if (!plainSdkRecord(values) || !Object.isFrozen(values) || !plainSdkRecord(schema) ||
      !Object.isFrozen(schema) || typeof namespace !== 'string' ||
      !/^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/u.test(namespace)) fail(invalidSdkInstallation);
  const keys = Reflect.ownKeys(values);
  if (keys.length > 32) fail(invalidSdkInstallation);
  const snapshot: Record<string, unknown> = {};
  for (const key of keys) {
    if (typeof key !== 'string' || !/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/u.test(key) ||
        Object.hasOwn(Object.prototype, key)) fail(invalidSdkInstallation);
    const field = Object.getOwnPropertyDescriptor(values, key);
    const rule = Object.getOwnPropertyDescriptor(schema, key);
    if (!field?.enumerable || !Object.hasOwn(field, 'value') ||
        !rule?.enumerable || !Object.hasOwn(rule, 'value')) fail('UnsupportedInstalledModelSdkOption');
    const value = field.value, allowed = rule.value;
    if (!(typeof value === 'boolean' || Number.isSafeInteger(value) && !Object.is(value, -0) ||
          typeof value === 'string' && value.length <= 256) ||
        !Array.isArray(allowed) || nodeTypes.isProxy(allowed) || !Object.isFrozen(allowed) ||
        allowed.length > 32 || !Array.prototype.includes.call(allowed, value)) {
      fail('UnsupportedInstalledModelSdkOption');
    }
    snapshot[key] = value;
  }
  return Object.freeze({[namespace]: Object.freeze(snapshot)});
}

// Same installation and original Model/defaults owners. This callback context
// is not a Provider registry, a Resource, permission or a physical profile.
// Only trusted Host configuration supplies paths and registration callbacks.
export async function installConfiguredModelProviders({moon, register, project,
  taskLimits, installationServices, assertCurrent, assertHostRuntime,
  assertNewHostRuntime = assertHostRuntime, bindSdkStaticOriginals, runtimeUrl,
  verifiedSdkInstallations, sdkImageCustody}: Options) {
  if (register === undefined) return {providers: new Map() as ReturnType<ProviderInstaller>, projectTasks: undefined};
  if (typeof register !== 'function' || typeof assertCurrent !== 'function') {
    fail('InvalidInstalledModelProviderRegistration');
  }
  let phase = 'registering', failure: {cause: unknown} | undefined, preparing = false;
  let defaults: Map<string, Defaults>, candidates: CandidateTasks | undefined;
  const executionOriginals = new Map<string, Execution>();
  let preparedSdkIds: Set<string> | undefined, preparedSdkRegistrations: Map<string, Registration> | undefined;
  const pending = new Set<Promise<unknown>>();
  const track = <Value,>(operation: () => Promise<Value>) => {
    // A sealed context cannot create even a new asynchronous child from an
    // entry accessor or installation callback after the original drain.
    if (phase !== 'registering') check();
    const promise = operation();
    pending.add(promise);
    promise.then(() => pending.delete(promise), cause => {
      failure ??= {cause};
      pending.delete(promise);
    });
    return promise;
  };
  const check = () => {
    if (failure !== undefined) throw failure.cause;
    if (phase !== 'registering') fail('InstalledModelConfigurationClosed');
    assertCurrent();
    assertNewHostRuntime?.();
  };
  const reader = () => {
    if (installationServices === undefined) fail('InstalledModelTaskConstructionUnavailable');
    const value = installedSourceConfigurationReader(installationServices);
    if (value === undefined) fail('InstalledModelTaskConstructionUnavailable');
    return value as ModelReader;
  };
  const capacity = (nodes: bigint, text = 0n, wire = 0n,
    workspaceNodes = 0n, workspaceText = 0n, workspaceWire = 0n) =>
    checked(moon.clientProgramInstalledSourceConstructionCapacity(
      nodes, text, wire, workspaceNodes, workspaceText, workspaceWire));
  const bodyLimits = Object.freeze({maxBytes: 65536, maxNodes: 4096,
    maxDepth: 32, maxMembers: 256, maxWork: 2097152});
  const body = (value: unknown): Body => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) {
      fail('InvalidInstalledModelOriginalBody');
    }
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== 2 || ['wire', 'cid'].some(key =>
      !fields[key]?.enumerable || !Object.hasOwn(fields[key], 'value') ||
      typeof fields[key].value !== 'string')) fail('InvalidInstalledModelOriginalBody');
    const {wire: {value: wire}, cid: {value: cid}} = fields;
    if (wire.length > bodyLimits.maxBytes || cid.length !== 71) fail('InvalidInstalledModelOriginalBody');
    return {wire, cid};
  };
  const artifactIdentity = (value: unknown) => track(async () => {
    check();
    const construction = reader();
    if (typeof value !== 'string' || value.length > 8192 || !value.startsWith('file:')) {
      fail('InvalidInstalledModelArtifact');
    }
    // Retain the exact software locator and digest under the SAME initial
    // Owner. URL/path conversion itself allocates, so it also follows reserve.
    // The reader separately owns its bounded buffer/FD/failed-close protocol.
    const holder = construction.prepareModelTaskInput<ArtifactHolder>(Object.freeze({
      capacity: () => capacity(8n, BigInt(value.length + 71), 0n, 8n, BigInt(value.length)),
      project: (): ArtifactHolder => ({path: fileURLToPath(value), value: undefined}),
      retained: original => capacity(8n, BigInt(original.path.length + 71)),
    }));
    const read = reserveInstalledSourceRuntimeIdentity(installationServices!);
    if (read === undefined) fail('InstalledModelTaskConstructionUnavailable');
    holder.value = await read(holder.path);
    check();
    return holder.value;
  });
  const context = Object.freeze({
    runtimeIdentity() { return artifactIdentity(runtimeUrl); },
    artifactIdentity,
    registeredSdkSelected(providerId: string) {
      check();
      return verifiedSdkInstallations?.has(providerId) === true;
    },
    prepareRegisteredSdk(providerId: string) {
      return track(async () => {
        check();
        const construction = reader();
        // Only the original Host installer supplies independently verified
        // file identities. The configuration callback selects by ID alone.
        if (arguments.length !== 1 || typeof providerId !== 'string' ||
            providerId.length < 1 || providerId.length > 256) {
          fail(invalidSdkInstallation);
        }
        const original = verifiedSdkInstallations?.get(providerId) as VerifiedSdk | undefined;
        if (original === undefined) fail(invalidSdkInstallation);
        const requireOriginal = () => {
          if (verifiedSdkInstallations!.get(providerId) !== original) fail(invalidSdkInstallation);
        };
        construction.prepareModelTaskInput(Object.freeze({
          capacity: () => capacity(16n),
          project() {
            preparedSdkIds ??= new Set();
            if (preparedSdkIds.has(providerId)) fail(invalidSdkInstallation);
            preparedSdkIds.add(providerId);
            originalSdkRecord(original, ['adapter', 'sdk', 'lock', 'route', 'providerOptions'], ['credential']);
            if (Object.hasOwn(original, 'credential')) originalSdkRecord(original.credential, ['reference', 'header']);
            originalSdkRecord(original.adapter, ['path', 'cid']);
            originalSdkRecord(original.lock, ['path', 'cid']);
            originalSdkRecord(original.sdk, ['path', 'cid', 'packageName', 'version', 'exportName']);
            originalSdkRecord(original.route, ['providerId', 'selector', 'modelId', 'apiMode', 'endpoint']);
            const {route, sdk} = original;
            if (route.providerId !== providerId ||
                [route.selector, route.modelId, route.apiMode, sdk.packageName, sdk.version, sdk.exportName]
                  .some(value => typeof value !== 'string' || value.length === 0 || value.length > 256) ||
                typeof route.endpoint !== 'string' || route.endpoint.length > 2048) {
              fail(invalidSdkInstallation);
            }
            return Object.freeze({});
          },
          retained: () => capacity(16n),
        }));
        const explicitCredential = Object.hasOwn(original, 'credential');
        const credentialNodes = explicitCredential ? 16n : 0n;
        return construction.prepareModelTaskInput(Object.freeze({
          capacity: () => capacity(64n + credentialNodes, 10304n, 0n, 128n + credentialNodes, 10304n),
          project() {
            // Borrow module originals only from the package custody already
            // held by this Host. A registration cannot supply a loader, a
            // namespace, a file URL or an independent package search.
            const read = (name: unknown, file: SdkFile, kind: string): ImageRead => {
              const image = packageCustody.readVerifiedSdkImage(sdkImageCustody, name, file.path, file.cid, kind);
              check();
              requireOriginal();
              return image;
            };
            const adapterName = '@actql/provider-ai-sdk';
            read(adapterName, original.lock, 'lock');
            const sdkImage = read(original.sdk.packageName, original.sdk, 'module');
            if (sdkImage.version !== original.sdk.version) fail(invalidSdkInstallation);
            const sdk = sdkImage.namespace as Readonly<Record<string, unknown>>;
            const adapter = read(adapterName, original.adapter, 'module').namespace as SdkAdapter;
            sdkImageCustody!.assertCurrent();
            const factory = sdk[original.sdk.exportName];
            const {createLanguageModel, verifyRequest, sdkProvider, readReportedUsage} = adapter;
            if (!Object.hasOwn(sdk, original.sdk.exportName) || typeof factory !== 'function' ||
                typeof createLanguageModel !== 'function' || typeof verifyRequest !== 'function' ||
                typeof sdkProvider !== 'string' || sdkProvider.length < 1 || sdkProvider.length > 256 ||
                readReportedUsage !== undefined && typeof readReportedUsage !== 'function') {
              fail(invalidSdkInstallation);
            }
            const providerOptions = sdkProviderOptions(original.providerOptions,
              adapter.optionNamespace, adapter.optionSchema);
            let credential: Credentials | undefined;
            if (explicitCredential) {
              // Borrow the nonsecret route contract from the same verified
              // adapter. User Task options never supply an environment key.
              const declared = originalSdkRecord(adapter.credentialBinding,
                ['reference', 'header', 'endpoint', 'prefix', 'placeholder']);
              if (declared.reference !== original.credential!.reference ||
                  declared.header !== original.credential!.header || declared.endpoint !== original.route.endpoint) {
                fail('RegisteredSdkCredentialMismatch');
              }
              credential = Object.freeze({transport: declared,
                profile: Object.freeze({reference: declared.reference, header: declared.header,
                  endpoint: declared.endpoint, prefix: declared.prefix})});
            }
            check();
            const registration = Object.freeze({route: original.route, providerOptions, sdkProvider, readReportedUsage,
              ...(credential === undefined ? {} : {credential}),
              sdkPackage: original.sdk.packageName,
              sdkVersion: original.sdk.version, sdkArtifactCid: original.sdk.cid,
              adapterArtifactCid: original.adapter.cid, lockArtifactCid: original.lock.cid,
              createLanguageModel(fetch: unknown) {
                assertCurrent();
                assertNewHostRuntime?.();
                requireOriginal();
                sdkImageCustody!.assertCurrent();
                return createLanguageModel(factory, original.route.modelId, fetch, original.route);
              },
              verifyRequest(wire: string, call: unknown) {
                assertCurrent();
                assertNewHostRuntime?.();
                requireOriginal();
                sdkImageCustody!.assertCurrent();
                return verifyRequest(wire, call, original.route, providerOptions);
              }});
            preparedSdkRegistrations ??= new Map();
            preparedSdkRegistrations.set(providerId, registration);
            return registration;
          },
          retained: () => capacity(64n + credentialNodes, 10304n),
        }));
      });
    },
    projectOpenAIProvider() {
      return track(async () => {
        check();
        const construction = reader();
        return construction.prepareModelTaskInput(Object.freeze({
          // The selection borrows the original registry strings. No key,
          // credential source or new Provider authority belongs to this view.
          capacity: () => capacity(1n, 0n, 0n, 8n),
          project() {
            if (project === undefined) fail('InstalledProjectOpenAIProviderUnavailable');
            const original = installedProjectOriginalsForRuntime(project, moon);
            const registry = original.modelRegistry;
            if (registry === undefined) fail('InstalledProjectOpenAIProviderUnavailable');
            const providerId = moon.clientProjectModelRegistryDefaultProvider(registry);
            const count = moon.clientProjectModelRegistryProviderCount(registry);
            if (typeof providerId !== 'string' || providerId.length === 0 || providerId.length > 256 ||
                !Number.isSafeInteger(taskLimits?.maxMembers) || !Number.isSafeInteger(count) ||
                count < 1 || count > taskLimits.maxMembers) {
              fail('InstalledProjectOpenAIProviderUnavailable');
            }
            for (let index = 0; index < count; index++) {
              if (moon.clientProjectModelRegistryProviderName(registry, index) !== providerId) continue;
              if (moon.clientProjectModelRegistryProviderType(registry, index) !== 'openai' ||
                  moon.clientProjectModelRegistryProviderKeyEnvironment(registry, index) !== 'OPENAI_API_KEY') {
                fail('InstalledProjectOpenAIProviderUnavailable');
              }
              check();
              if (installedProjectOriginalsForRuntime(project, moon) !== original) {
                fail('ForeignInstalledProjectOriginal');
              }
              return Object.freeze({providerId});
            }
            fail('InstalledProjectOpenAIProviderUnavailable');
          },
          retained: () => capacity(1n),
        }));
      });
    },
    prepareConfiguration(project: () => object) {
      return track(async () => {
        check();
        const construction = reader();
        if (typeof project !== 'function') fail('InvalidInstalledModelConfiguration');
        return construction.prepareModelTaskInput(Object.freeze({
          capacity: () => capacity(1024n, 16384n, 0n, 1024n, 16384n),
          project() {const value = project(); check(); return value;},
          retained: () => capacity(1024n, 16384n),
        }));
      });
    },
    // The existing bounded reader owns the actual FD, decode, retention and
    // pending-close responsibility. Secrets are never added to binding DATA.
    readText(path: string, {maxBytes}: {maxBytes?: number} = {}) {
      return track(async () => {
        check();
        if (typeof path !== 'string' || !path ||
            !Number.isSafeInteger(maxBytes) || maxBytes! <= 0 || maxBytes! > 2147483647) {
          fail('InvalidInstalledModelConfigurationRead');
        }
        const value = await reader().readUtf8(path, {maxBytes});
        check();
        return value;
      });
    },
    prepareBindingOriginals(installationWire: string | (() => unknown), contractWire?: string, configurationWire?: string) {
      return track(async () => {
        check();
        const construction = reader();
        const projectOriginals = typeof installationWire === 'function' &&
          contractWire === undefined && configurationWire === undefined ? installationWire : undefined;
        if (projectOriginals === undefined && [installationWire, contractWire, configurationWire].some(value =>
          typeof value !== 'string' || value.length > bodyLimits.maxBytes)) {
          fail('InvalidInstalledModelOriginalBody');
        }
        if (typeof moon.clientProgramPrepareModelProviderOriginals !== 'function') {
          fail('InstalledModelBindingRuntimeUnavailable');
        }
        return construction.prepareModelTaskInput<Readonly<Record<string, Body>>>(Object.freeze({
          capacity: () => capacity(32n, 3n * 65536n, 0n,
            12n * 4096n, 12n * 65536n, 6n * 65536n),
          project() {
            // The trusted normal installer may encode its nonsecret DATA
            // here, after funding, rather than allocate an unfunded preimage.
            const wires = projectOriginals === undefined
              ? [installationWire, contractWire, configurationWire] : projectOriginals();
            if (!Array.isArray(wires) || nodeTypes.isProxy(wires) || wires.length !== 3 ||
                Reflect.ownKeys(wires).length !== 4) fail('InvalidInstalledModelOriginalBody');
            for (let index = 0; index < 3; index++) {
              const field = Object.getOwnPropertyDescriptor(wires, String(index));
              if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string' ||
                  field.value.length > bodyLimits.maxBytes) fail('InvalidInstalledModelOriginalBody');
            }
            const values = checked(moon.clientProgramPrepareModelProviderOriginals(
              ...wires as [string, string, string], bodyLimits.maxBytes,
              bodyLimits.maxNodes, bodyLimits.maxDepth, bodyLimits.maxWork));
            return Object.freeze(Object.fromEntries(
              ['installationRevision', 'configurationContract', 'configuration'].map((key, index) =>
                [key, Object.freeze({wire: runtimeField(values, index * 2) as string,
                  cid: runtimeField(values, index * 2 + 1) as string})]))) as Readonly<Record<string, Body>>;
          },
          retained: value => capacity(32n, Object.values(value).reduce((sum, item) =>
            sum + BigInt(item.wire.length + item.cid.length), 0n)),
        }));
      });
    },
    prepareRawPolicies(originals: unknown) {
      return track(async () => {
        check();
        const construction = reader();
        if (originals === null || typeof originals !== 'object' || nodeTypes.isProxy(originals)) {
          fail('InvalidInstalledModelRawOriginals');
        }
        const fields = Object.getOwnPropertyDescriptors(originals);
        const entries = [['retention', 'retention_contract'], ['metadata', 'metadata_retention_policy'],
          ['clock', 'clock_contract'], ['data', 'data_policy']];
        if (Reflect.ownKeys(fields).length !== entries.length || entries.some(([key]) =>
          !fields[key]?.enumerable || !Object.hasOwn(fields[key], 'value'))) {
          fail('InvalidInstalledModelRawOriginals');
        }
        if (typeof moon.clientProgramModelRawOriginalRetainedCapacity !== 'function') {
          fail('InstalledModelRawPolicyRuntimeUnavailable');
        }
        const retained = construction.prepareModelTaskInput(Object.freeze({
          capacity: () => capacity(8n), project: (): Record<string, unknown> => ({}), retained: () => capacity(8n),
        }));
        for (const [key, kind] of entries) {
          const original = body(fields[key].value);
          retained[key] = construction.prepareModelTaskInput(Object.freeze({
            capacity: () => capacity(0n, 0n, 0n,
              4n * 4096n, 4n * 65536n, 4n * 65536n),
            project: () => checked(moon.clientProgramAdmitEffectDependencyBody(kind,
              original.cid, original.wire, bodyLimits.maxBytes, bodyLimits.maxNodes, bodyLimits.maxDepth)) as object,
            retained: value => checked(moon.clientProgramModelRawOriginalRetainedCapacity(value,
              bodyLimits.maxNodes, bodyLimits.maxDepth, 4 * bodyLimits.maxBytes)),
          }));
          check();
        }
        return Object.freeze(retained);
      });
    },
    prepareTasks(bindings: unknown) {
      return track(async () => {
        check();
        if (preparing || candidates !== undefined || project === undefined ||
            !Array.isArray(bindings) || bindings.length === 0 ||
            !Number.isSafeInteger(taskLimits?.maxMembers) ||
            bindings.length > taskLimits.maxMembers) {
          fail('InvalidInstalledModelTaskPreparation');
        }
        // Mark before any caller descriptors or actual file await. A failed
        // preparation cannot become a second initialization attempt.
        preparing = true;
        const construction = reader();
        const construct = <Value extends object,>(project: () => Value, retainedNodes: bigint, workspaceNodes = 0n) =>
          construction.prepareModelTaskInput(Object.freeze({
            capacity: () => capacity(retainedNodes, 0n, 0n, workspaceNodes), project,
            retained: () => capacity(retainedNodes),
          }));
        defaults = new Map();
        for (const binding of bindings) {
          if (binding === null || typeof binding !== 'object' || Array.isArray(binding)) {
            fail('InvalidInstalledModelTaskPreparation');
          }
          const fields = Object.getOwnPropertyDescriptors(binding);
          if (Reflect.ownKeys(fields).length !== 2 ||
              ['providerId', 'bindingOriginals'].some(key => !fields[key]?.enumerable ||
                !Object.hasOwn(fields[key], 'value'))) {
            fail('InvalidInstalledModelTaskPreparation');
          }
          const {providerId: {value: id}, bindingOriginals: {value: originals}} = fields;
          if (typeof id !== 'string' || !id || defaults.has(id)) {
            fail('InvalidInstalledModelTaskPreparation');
          }
          defaults.set(id, construct(() => prepareInstalledModelProviderDefaults(moon, id, originals,
            {assertCurrent: assertNewHostRuntime ?? assertCurrent}), 32n, 64n));
        }
        candidates = await prepareInstalledProjectModelTasks(moon, project, defaults,
          {limits: taskLimits, assertCurrent, installationServices});
        check();
        if (typeof moon.clientProgramNormalizedPublicModelTaskProviderData !== 'function') {
          fail('InstalledModelProviderDataUnavailable');
        }
        const originals = candidates.originalsForRuntime(moon);
        const taskFor = (name: string) => {
          check();
          const original = originals.find(value => value.name === name);
          if (original === undefined) fail('InvalidInstalledModelTaskSelection');
          return original;
        };
        const tasks = construct((): TaskData[] => [], 2n + BigInt(originals.length));
        for (const task of originals) {
          const projectData = () => {
            const data = checked(moon.clientProgramNormalizedPublicModelTaskProviderData(
              task.normalized, taskLimits.maxBytes, taskLimits.maxNodes,
              taskLimits.maxDepth, taskLimits.maxWork));
            return Object.freeze({name: task.name, providerId: task.providerId,
              taskCid: task.taskCid, promptCid: task.promptCid,
              outputSchemaCid: runtimeField(data, 0) as string, modelSelector: runtimeField(data, 1) as string,
              promptPayloadWire: runtimeField(data, 2) as string});
          };
          // This bounded encoder's workspace ends here. Only the emitted DATA
          // record/payload remains; Task/schema/selector strings stay borrowed.
          // These are conservative constructor quantities, not Model funding,
          // execution fuel, physical RSS or permission to call the Provider.
          const material = construction.prepareModelTaskInput<TaskData>(Object.freeze({
              capacity: () => capacity(8n, BigInt(taskLimits.maxBytes), 0n,
                4n * BigInt(taskLimits.maxNodes), 4n * BigInt(taskLimits.maxBytes),
                2n * BigInt(taskLimits.maxBytes)),
              project: projectData,
              retained: value => capacity(8n, BigInt(value.promptPayloadWire.length)),
            }));
          tasks.push(material);
        }
        preparing = false;
        return Object.freeze({tasks: Object.freeze(tasks),
          verifyChatConfiguration(name: string, selector: string, modelId: string, endpoint: string) {
            return track(async () => {
              const original = taskFor(name);
              if (typeof moon.clientProgramInstalledChatConfigurationMatches !== 'function') {
                fail('InstalledModelBindingRuntimeUnavailable');
              }
              // Read the same funded configuration and binding already used
              // to normalize this Task. Return no retained parser workspace.
              const binding = original.defaults.binding as Binding;
              construction.prepareModelTaskInput(Object.freeze({
                capacity: () => capacity(4n, 0n, 0n, 8n * 4096n,
                  8n * 65536n, 6n * 65536n),
                project() {
                  if (moon.clientProgramInstalledChatConfigurationMatches(binding.value,
                    binding.originals.configuration.wire, original.providerId,
                    selector, modelId, endpoint) !== true) fail('InstalledModelResolvedConfigurationMismatch');
                  return Object.freeze({});
                },
                retained: () => capacity(4n),
              }));
            });
          },
          responseProfileFor(name: string, originalTemplate: unknown) {
            return track(async () => {
              const original = taskFor(name);
              const template = typeof originalTemplate === 'string' || typeof originalTemplate === 'function'
                ? originalTemplate : body(originalTemplate);
              if (typeof template === 'string' && template.length > bodyLimits.maxBytes) {
                fail('InvalidInstalledModelOriginalBody');
              }
              if (typeof moon.clientProgramNormalizedPublicModelTaskResponseProfile !== 'function') {
                fail('InstalledModelResponseProfileRuntimeUnavailable');
              }
              const control = runtimeCore(moon).publicationControl;
              const limits = {maxWireBytes: bodyLimits.maxBytes, maxNodes: bodyLimits.maxNodes,
                maxDepth: bodyLimits.maxDepth, maxMembers: bodyLimits.maxMembers, maxWork: bodyLimits.maxWork};
              return construction.prepareModelTaskInput(Object.freeze({
                capacity: () => capacity(128n, 2n * 65536n, 0n,
                  12n * 4096n, 12n * 65536n, 8n * 65536n),
                project() {
                  const input = typeof template === 'function' ? template() : template;
                  if (typeof input === 'string' && input.length > bodyLimits.maxBytes ||
                      typeof template === 'function' && typeof input !== 'string') {
                    fail('InvalidInstalledModelOriginalBody');
                  }
                  // Plain Host physical DATA uses the existing Common sealer;
                  // canonical encoding, identity and full validation stay Core.
                  const sealed = typeof input === 'string'
                    ? control.sealRunEvidence('model_response_profile', input, limits) : input;
                  const admitted = control.readInstalledModelResponseProfile((sealed as Body).wire,
                    typeof input === 'string' ? (sealed as Body & {identity: string}).identity : (sealed as Body).cid, limits);
                  const values = checked(moon.clientProgramNormalizedPublicModelTaskResponseProfile(
                    original.normalized, admitted, bodyLimits.maxBytes, bodyLimits.maxNodes,
                    bodyLimits.maxDepth, bodyLimits.maxWork));
                  const wire = runtimeField(values, 0) as string, cid = runtimeField(values, 1) as string;
                  // The emitted DATA still enters the original full reader.
                  // Later Request admission binds the same Task/installation.
                  return Object.freeze({wire, cid,
                    profile: control.readInstalledModelResponseProfile(wire, cid, limits)});
                },
                retained: value => capacity(128n, 2n * BigInt(value.wire.length) + BigInt(value.cid.length)),
              }));
            });
          },
          executionOriginalsFor(name: string, policy: unknown) {
            return track(async () => {
              const original = taskFor(name);
              if (executionOriginals.has(original.taskCid)) fail('InstalledModelExecutionAlreadyPrepared');
              if (policy === null || typeof policy !== 'object' || nodeTypes.isProxy(policy)) {
                fail('InvalidInstalledModelExecutionPolicy');
              }
              const fields = Object.getOwnPropertyDescriptors(policy);
              const keys = ['maxAttempts', 'maxCostUnits', 'maxDurationMs', 'maxWireBytes', 'maxTokens'];
              if (Reflect.ownKeys(fields).length !== keys.length || keys.some(key =>
                !fields[key]?.enumerable || !Object.hasOwn(fields[key], 'value') ||
                typeof fields[key].value !== 'bigint')) fail('InvalidInstalledModelExecutionPolicy');
              if (typeof moon.clientProgramNormalizedPublicModelTaskNoRetryMaterials !== 'function') {
                fail('InstalledModelExecutionRuntimeUnavailable');
              }
              return construction.prepareModelTaskInput(Object.freeze({
                capacity: () => capacity(32n, BigInt(bodyLimits.maxBytes), 0n,
                  4n * 4096n, 4n * 65536n, 4n * 65536n),
                project() {
                  const values = checked(moon.clientProgramNormalizedPublicModelTaskNoRetryMaterials(
                    original.normalized, ...keys.map(key => fields[key].value), bodyLimits.maxBytes,
                    bodyLimits.maxNodes, bodyLimits.maxDepth, bodyLimits.maxWork));
                  const value = Object.freeze({modelTaskCid: original.taskCid,
                    execution: Object.freeze({wire: runtimeField(values, 0) as string, cid: runtimeField(values, 1) as string}),
                    retry: Object.freeze({wire: runtimeField(values, 2) as string, cid: runtimeField(values, 3) as string}),
                    backoff: Object.freeze({wire: runtimeField(values, 4) as string, cid: runtimeField(values, 5) as string}),
                    prompt: Object.freeze({wire: original.promptWire, cid: original.promptCid})});
                  executionOriginals.set(original.taskCid, value);
                  return value;
                },
                // Shared retry/backoff and the original prompt remain borrowed.
                retained: value => capacity(32n, BigInt(value.execution.wire.length + value.execution.cid.length)),
              }));
            });
          },
          providerEntries(project: () => unknown) {
            return track(async () => {
              check();
              if (typeof project !== 'function') fail('InvalidInstalledModelProviderRegistration');
              // Finite normal Host declarations, closures, arrays and aliases
              // are built before any Run under this original initial Owner.
              // This funds construction DATA, never physical call buffers or
              // a Model allowance. The per-Run readers still admit all bounds.
              const nodes = 128n + 2048n * BigInt(originals.length);
              const text = 131072n * BigInt(originals.length);
              return construction.prepareModelTaskInput(Object.freeze({
                capacity: () => capacity(nodes, text, 0n, nodes, text),
                project() {
                  const value = project();
                  check();
                  if (!Array.isArray(value) || nodeTypes.isProxy(value) ||
                      value.length > originals.length) fail('InvalidInstalledModelProviderRegistration');
                  return value;
                },
                retained: () => capacity(nodes, text),
              }));
            });
          },
          bindingOriginalsFor(providerId: string) {
            check();
            const value = defaults.get(providerId);
            if (value === undefined) fail('InstalledModelDefaultsUnavailable');
            return value.bindingOriginals;
          }});
      });
    },
  });
  try {
    check();
    // Legacy synchronous callbacks keep their existing Array path. A normal
    // plugin can await bounded configuration/Task preparation on this context.
    const selected = register(moon, context);
    const entries = Array.isArray(selected) ? selected : await selected;
    if (pending.size !== 0) {
      // A forgotten await cannot install a Provider while its original read
      // still owns an FD. Observe those same children, then refuse this caller.
      await Promise.allSettled([...pending]);
      check();
      fail('InstalledModelConfigurationPending');
    }
    check();
    if (preparing) fail('InstalledModelTaskPreparationPending');
    // Entry descriptors and trusted installation callbacks may reenter JS.
    // They cannot reuse the initial configuration context after its sole
    // callback and all previously owned children have settled.
    phase = 'sealed';
    if (candidates !== undefined) {
      if (!Array.isArray(entries)) fail('InvalidInstalledModelProviderRegistration');
      for (const entry of entries) {
        const original = defaults!.get(entry?.providerId);
        if (original === undefined) fail('InstalledModelDefaultsForeignOriginal');
        original.bindRegistration(entry);
      }
    }
    const taskOriginals = candidates?.originalsForRuntime(moon);
    const prepareSdkCapability = preparedSdkRegistrations === undefined ? undefined :
      (registration: Registration, providerId: string, taskCid: string, provider: unknown, raw: RawSelection) => {
        const original = taskOriginals?.find(task => task.taskCid === taskCid && task.providerId === providerId);
        if (preparedSdkRegistrations!.get(providerId) !== registration || original === undefined ||
            typeof moon.clientProgramPrepareInstalledStructuredSdkCapability !== 'function' ||
            typeof moon.clientProgramAdmitInstalledStructuredSdkCapability !== 'function') {
          fail(invalidSdkInstallation);
        }
        assertCurrent(); assertNewHostRuntime?.();
        const {route} = registration, {binding} = original.defaults as {binding: Binding};
        const revision = JSON.parse(binding.originals.installationRevision.wire);
        const configuration = JSON.parse(binding.originals.configuration.wire);
        const {installation} = raw as unknown as SdkSelection;
        const sdk = installation.sdk;
        if (revision.sdk_entry_artifact_cid !== registration.sdkArtifactCid ||
            revision.builder_artifact_cid !== registration.adapterArtifactCid ||
            revision.lock_artifact_cid !== registration.lockArtifactCid ||
            !isDeepStrictEqual(configuration.provider_options, registration.providerOptions) ||
            !isDeepStrictEqual(configuration.registered_credential, registration.credential?.profile) ||
            installation.build_artifact_cid !== registration.adapterArtifactCid ||
            installation.endpoint !== route.endpoint || sdk?.package_name !== registration.sdkPackage ||
            sdk.version !== registration.sdkVersion || sdk.interface !== 'v4' ||
            sdk.lock_artifact_cid !== registration.lockArtifactCid) {
          fail(invalidSdkInstallation);
        }
        const opaque = checked(moon.clientProgramPrepareInstalledStructuredSdkCapability(
          provider, binding.value, binding.originals.configuration.wire,
          route.selector, route.modelId, route.apiMode, route.endpoint, (raw as unknown as SdkSelection).profile));
        return Object.freeze({opaque, installation});
      };
    const install = () => installModelProviders(moon, () => entries, assertHostRuntime,
      assertNewHostRuntime, bindSdkStaticOriginals, taskOriginals, prepareSdkCapability as PrepareCapability | undefined);
    let registeredTaskNodes = 0n;
    if (preparedSdkRegistrations !== undefined && taskOriginals !== undefined) {
      for (const task of taskOriginals) {
        if (preparedSdkRegistrations.has(task.providerId)) registeredTaskNodes += 24n;
      }
    }
    const providerNodes = candidates === undefined ? 0n : 64n +
      64n * BigInt((entries as readonly unknown[]).length) + 128n * BigInt(taskOriginals!.length) + registeredTaskNodes;
    // Install all provider views in the same original constructor. Each
    // capability remains retained, while one Task at a time borrows canonical
    // binding material and checks the two DATA bodies and their Common CID.
    const providers = candidates === undefined ? install() : reader().prepareModelTaskInput(Object.freeze({
      capacity: () => registeredTaskNodes === 0n
        ? capacity(providerNodes, 0n, 0n, providerNodes)
        : capacity(providerNodes, 0n, 0n, providerNodes + 12n * BigInt(bodyLimits.maxNodes),
          12n * BigInt(bodyLimits.maxBytes), 8n * BigInt(bodyLimits.maxBytes)),
      project: install, retained: () => capacity(providerNodes),
    }));
    const projectTasks = candidates?.bindInstalledProviders(providers);
    let materialized = false;
    const modelInstallationForRuntime = executionOriginals.size === 0 ? undefined : (runtime: unknown, environmentWire: unknown) => {
      // This private Host assembly runs before the initial constructor ends.
      // It is separate from the sealed public configuration context, and may
      // not allocate another installation after initialization/reentry.
      if (runtime !== moon || typeof environmentWire !== 'string' || materialized) {
        fail('ForeignInstalledModelConfiguration');
      }
      assertCurrent(); assertNewHostRuntime?.();
      projectTasks!.originalsForRuntime(runtime);
      materialized = true;
      return reader().prepareModelTaskInput(Object.freeze({
        capacity: () => capacity(16n + 24n * BigInt(executionOriginals.size), 0n, 0n,
          16n + 16n * BigInt(executionOriginals.size)),
        project() {
          const contracts = [], bodies = new Map();
          for (const value of executionOriginals.values()) {
            contracts.push(Object.freeze({modelTaskCid: value.modelTaskCid,
              bodyWire: value.execution.wire, cid: value.execution.cid}));
            for (const dependency of [value.prompt, value.retry, value.backoff]) {
              const previous = bodies.get(dependency.cid);
              if (previous !== undefined && previous !== dependency.wire) {
                fail('InstalledModelDependencyConflict');
              }
              bodies.set(dependency.cid, dependency.wire);
            }
          }
          // Repeated exact no-retry/backoff originals share one inventory
          // member. No body, CID or Environment text is rebuilt in JavaScript.
          return Object.freeze({environmentWire,
            executionContracts: Object.freeze(contracts),
            dependencyBodies: Object.freeze([...bodies].map(([cid, bodyWire]) =>
              Object.freeze({cid, bodyWire})))});
        },
        retained: () => capacity(16n + 24n * BigInt(executionOriginals.size)),
      }));
    };
    // Only the new prepared configuration path owns this installation step.
    // Preserve legacy registrations' explicit persistence contract. Project
    // the four admitted bodies while the same initialization owner is open;
    // the strings remain borrowed from their original Common owners.
    const policyInventory = candidates === undefined ? undefined : reader().prepareModelTaskInput(Object.freeze({
      capacity: () => capacity(16n + 64n * BigInt(taskOriginals!.length), 0n, 0n,
        16n + 64n * BigInt(taskOriginals!.length)),
      project() {
        const owners = [], bodies = new Map();
        for (const installed of providers.values()) {
          for (const provider of installed.taskOriginals?.() ?? [installed]) {
            if (provider.rawCaptureSelection === undefined) continue;
            owners.push(provider);
            const originals = runtimeCore(moon).publicationControl
              .installedModelRawSelectionOriginals(provider.rawCaptureSelection);
            for (const original of originals) {
              const previous = bodies.get(original.cid);
              if (previous !== undefined && previous.wire !== original.wire) {
                fail('InstalledModelDependencyConflict');
              }
              if (previous === undefined) bodies.set(original.cid, original);
            }
          }
        }
        // Exact immutable policy DATA can share one Store inventory entry;
        // every actual view still keeps its own current/physical/Run duties.
        return Object.freeze({owners: Object.freeze(owners), bodies: Object.freeze([...bodies.values()])});
      },
      retained: () => capacity(16n + 64n * BigInt(taskOriginals!.length)),
    }));
    const persistOriginals = policyInventory === undefined || policyInventory.bodies.length === 0
      ? undefined : async (store: Writer) => {
        // The existing Store owns write funding, digest validation, durability
        // and pending cleanup. This installs policy DATA, never a raw grant,
        // Account permission, approval or authority to send a Model request.
        const current = () => {
          assertCurrent(); assertNewHostRuntime?.();
          for (const provider of policyInventory.owners) provider.assertNewTrustedRuntime?.();
        };
        current();
        for (const original of policyInventory.bodies) {
          current();
          await store.putSemantic(original.wire, original.cid);
          current();
        }
      };
    phase = 'installed';
    return {providers, projectTasks, persistOriginals, modelInstallationForRuntime};
  } catch (cause) {
    failure ??= {cause};
    // Preserve the original error while actual pending configuration children
    // settle; neither rejection nor callback completion is physical-close ACK.
    if (pending.size !== 0) await Promise.allSettled([...pending]);
    throw failure.cause;
  } finally {
    // No callback retained by a plugin can start another configuration read or
    // Task constructor after registration/failed initialization has ended.
    phase = 'closed';
  }
}
