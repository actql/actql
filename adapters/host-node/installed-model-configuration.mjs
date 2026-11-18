import {installModelProviders, prepareInstalledModelProviderDefaults} from './installed-model.mjs';
import {prepareInstalledProjectModelTasks} from './installed-project-model-tasks.mjs';
import {installedSourceConfigurationReader, reserveInstalledSourceRuntimeIdentity} from './installed-host-services.mjs';
import {fileURLToPath} from 'node:url';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {types as nodeTypes} from 'node:util';

const fail = code => { throw Object.assign(new TypeError(code), {code}); };

// Same installation and original Model/defaults owners. This callback context
// is not a Provider registry, a Resource, permission or a physical profile.
// Only trusted Host configuration supplies paths and registration callbacks.
export async function installConfiguredModelProviders({moon, register, project,
  taskLimits, installationServices, assertCurrent, assertHostRuntime,
  assertNewHostRuntime = assertHostRuntime, bindSdkStaticOriginals, runtimeUrl}) {
  if (register === undefined) return {providers: new Map(), projectTasks: undefined};
  if (typeof register !== 'function' || typeof assertCurrent !== 'function') {
    fail('InvalidInstalledModelProviderRegistration');
  }
  let phase = 'registering', failure, preparing = false;
  let defaults, candidates;
  const executionOriginals = new Map();
  const pending = new Set();
  const track = operation => {
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
    return value;
  };
  const capacity = (nodes, text = 0n, wire = 0n,
    workspaceNodes = 0n, workspaceText = 0n, workspaceWire = 0n) =>
    checked(moon.clientProgramInstalledSourceConstructionCapacity(
      nodes, text, wire, workspaceNodes, workspaceText, workspaceWire));
  const bodyLimits = Object.freeze({maxBytes: 65536, maxNodes: 4096,
    maxDepth: 32, maxMembers: 256, maxWork: 2097152});
  const body = value => {
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
  const artifactIdentity = value => track(async () => {
    check();
    const construction = reader();
    if (typeof value !== 'string' || value.length > 8192 || !value.startsWith('file:')) {
      fail('InvalidInstalledModelArtifact');
    }
    // Retain the exact software locator and digest under the SAME initial
    // Owner. URL/path conversion itself allocates, so it also follows reserve.
    // The reader separately owns its bounded buffer/FD/failed-close protocol.
    const holder = construction.prepareModelTaskInput(Object.freeze({
      capacity: () => capacity(8n, BigInt(value.length + 71), 0n, 8n, BigInt(value.length)),
      project: () => ({path: fileURLToPath(value), value: undefined}),
      retained: original => capacity(8n, BigInt(original.path.length + 71)),
    }));
    const read = reserveInstalledSourceRuntimeIdentity(installationServices);
    if (read === undefined) fail('InstalledModelTaskConstructionUnavailable');
    holder.value = await read(holder.path);
    check();
    return holder.value;
  });
  const context = Object.freeze({
    runtimeIdentity() { return artifactIdentity(runtimeUrl); },
    artifactIdentity,
    prepareConfiguration(project) {
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
    readText(path, {maxBytes} = {}) {
      return track(async () => {
        check();
        if (typeof path !== 'string' || !path ||
            !Number.isSafeInteger(maxBytes) || maxBytes <= 0 || maxBytes > 2147483647) {
          fail('InvalidInstalledModelConfigurationRead');
        }
        const value = await reader().readUtf8(path, {maxBytes});
        check();
        return value;
      });
    },
    prepareBindingOriginals(installationWire, contractWire, configurationWire) {
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
        return construction.prepareModelTaskInput(Object.freeze({
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
              ...wires, bodyLimits.maxBytes,
              bodyLimits.maxNodes, bodyLimits.maxDepth, bodyLimits.maxWork));
            return Object.freeze(Object.fromEntries(
              ['installationRevision', 'configurationContract', 'configuration'].map((key, index) =>
                [key, Object.freeze({wire: runtimeField(values, index * 2),
                  cid: runtimeField(values, index * 2 + 1)})])));
          },
          retained: value => capacity(32n, Object.values(value).reduce((sum, item) =>
            sum + BigInt(item.wire.length + item.cid.length), 0n)),
        }));
      });
    },
    prepareRawPolicies(originals) {
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
          capacity: () => capacity(8n), project: () => ({}), retained: () => capacity(8n),
        }));
        for (const [key, kind] of entries) {
          const original = body(fields[key].value);
          retained[key] = construction.prepareModelTaskInput(Object.freeze({
            capacity: () => capacity(0n, 0n, 0n,
              4n * 4096n, 4n * 65536n, 4n * 65536n),
            project: () => checked(moon.clientProgramAdmitEffectDependencyBody(kind,
              original.cid, original.wire, bodyLimits.maxBytes, bodyLimits.maxNodes, bodyLimits.maxDepth)),
            retained: value => checked(moon.clientProgramModelRawOriginalRetainedCapacity(value,
              bodyLimits.maxNodes, bodyLimits.maxDepth, 4 * bodyLimits.maxBytes)),
          }));
          check();
        }
        return Object.freeze(retained);
      });
    },
    prepareTasks(bindings) {
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
        const construct = (project, retainedNodes, workspaceNodes = 0n) =>
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
        const taskFor = name => {
          check();
          const original = originals.find(value => value.name === name);
          if (original === undefined) fail('InvalidInstalledModelTaskSelection');
          return original;
        };
        const tasks = construct(() => [], 2n + BigInt(originals.length));
        for (const task of originals) {
          const projectData = () => {
            const data = checked(moon.clientProgramNormalizedPublicModelTaskProviderData(
              task.normalized, taskLimits.maxBytes, taskLimits.maxNodes,
              taskLimits.maxDepth, taskLimits.maxWork));
            return Object.freeze({name: task.name, providerId: task.providerId,
              taskCid: task.taskCid, promptCid: task.promptCid,
              outputSchemaCid: runtimeField(data, 0), modelSelector: runtimeField(data, 1),
              promptPayloadWire: runtimeField(data, 2)});
          };
          // This bounded encoder's workspace ends here. Only the emitted DATA
          // record/payload remains; Task/schema/selector strings stay borrowed.
          // These are conservative constructor quantities, not Model funding,
          // execution fuel, physical RSS or permission to call the Provider.
          const material = construction.prepareModelTaskInput(Object.freeze({
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
          responseProfileFor(name, originalTemplate) {
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
                  const admitted = control.readInstalledModelResponseProfile(sealed.wire,
                    typeof input === 'string' ? sealed.identity : sealed.cid, limits);
                  const values = checked(moon.clientProgramNormalizedPublicModelTaskResponseProfile(
                    original.normalized, admitted, bodyLimits.maxBytes, bodyLimits.maxNodes,
                    bodyLimits.maxDepth, bodyLimits.maxWork));
                  const wire = runtimeField(values, 0), cid = runtimeField(values, 1);
                  // The emitted DATA still enters the original full reader.
                  // Later Request admission binds the same Task/installation.
                  return Object.freeze({wire, cid,
                    profile: control.readInstalledModelResponseProfile(wire, cid, limits)});
                },
                retained: value => capacity(128n, 2n * BigInt(value.wire.length) + BigInt(value.cid.length)),
              }));
            });
          },
          executionOriginalsFor(name, policy) {
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
                    execution: Object.freeze({wire: runtimeField(values, 0), cid: runtimeField(values, 1)}),
                    retry: Object.freeze({wire: runtimeField(values, 2), cid: runtimeField(values, 3)}),
                    backoff: Object.freeze({wire: runtimeField(values, 4), cid: runtimeField(values, 5)}),
                    prompt: Object.freeze({wire: original.promptWire, cid: original.promptCid})});
                  executionOriginals.set(original.taskCid, value);
                  return value;
                },
                // Shared retry/backoff and the original prompt remain borrowed.
                retained: value => capacity(32n, BigInt(value.execution.wire.length + value.execution.cid.length)),
              }));
            });
          },
          providerEntries(project) {
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
          bindingOriginalsFor(providerId) {
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
        const original = defaults.get(entry?.providerId);
        if (original === undefined) fail('InstalledModelDefaultsForeignOriginal');
        original.bindRegistration(entry);
      }
    }
    const taskOriginals = candidates?.originalsForRuntime(moon);
    const install = () => installModelProviders(moon, () => entries, assertHostRuntime,
      assertNewHostRuntime, bindSdkStaticOriginals, taskOriginals);
    const providerNodes = candidates === undefined ? 0n : 64n +
      64n * BigInt(entries.length) + 128n * BigInt(taskOriginals.length);
    const providers = candidates === undefined ? install() : reader().prepareModelTaskInput(Object.freeze({
      capacity: () => capacity(providerNodes, 0n, 0n, providerNodes),
      project: install, retained: () => capacity(providerNodes),
    }));
    const projectTasks = candidates?.bindInstalledProviders(providers);
    let materialized = false;
    const modelInstallationForRuntime = executionOriginals.size === 0 ? undefined : (runtime, environmentWire) => {
      // This private Host assembly runs before the initial constructor ends.
      // It is separate from the sealed public configuration context, and may
      // not allocate another installation after initialization/reentry.
      if (runtime !== moon || typeof environmentWire !== 'string' || materialized) {
        fail('ForeignInstalledModelConfiguration');
      }
      assertCurrent(); assertNewHostRuntime?.();
      projectTasks.originalsForRuntime(runtime);
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
      capacity: () => capacity(16n + 64n * BigInt(taskOriginals.length), 0n, 0n,
        16n + 64n * BigInt(taskOriginals.length)),
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
      retained: () => capacity(16n + 64n * BigInt(taskOriginals.length)),
    }));
    const persistOriginals = policyInventory === undefined || policyInventory.bodies.length === 0
      ? undefined : async store => {
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
