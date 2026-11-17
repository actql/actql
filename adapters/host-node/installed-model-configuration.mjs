import {installModelProviders, prepareInstalledModelProviderDefaults} from './installed-model.mjs';
import {prepareInstalledProjectModelTasks} from './installed-project-model-tasks.mjs';
import {installedSourceConfigurationReader} from './installed-host-services.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const fail = code => { throw Object.assign(new TypeError(code), {code}); };

// Same installation and original Model/defaults owners. This callback context
// is not a Provider registry, a Resource, permission or a physical profile.
// Only trusted Host configuration supplies paths and registration callbacks.
export async function installConfiguredModelProviders({moon, register, project,
  taskLimits, installationServices, assertCurrent, assertHostRuntime,
  assertNewHostRuntime = assertHostRuntime, bindSdkStaticOriginals}) {
  if (register === undefined) return {providers: new Map(), projectTasks: undefined};
  if (typeof register !== 'function' || typeof assertCurrent !== 'function') {
    fail('InvalidInstalledModelProviderRegistration');
  }
  let phase = 'registering', failure, preparing = false;
  let defaults, candidates;
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
  const context = Object.freeze({
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
        const capacity = (nodes, text = 0n, wire = 0n,
          workspaceNodes = 0n, workspaceText = 0n, workspaceWire = 0n) =>
          checked(moon.clientProgramInstalledSourceConstructionCapacity(
            nodes, text, wire, workspaceNodes, workspaceText, workspaceWire));
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
    const providers = installModelProviders(moon, () => entries, assertHostRuntime,
      assertNewHostRuntime, bindSdkStaticOriginals);
    const projectTasks = candidates?.bindInstalledProviders(providers);
    // Only the new prepared configuration path owns this installation step.
    // Preserve legacy registrations' explicit persistence contract. Project
    // the four admitted bodies while the same initialization owner is open;
    // the strings remain borrowed from their original Common owners.
    const policyOriginals = [];
    if (candidates !== undefined) {
      for (const provider of providers.values()) {
        if (provider.rawCaptureSelection === undefined) continue;
        const construction = reader();
        const originals = construction.prepareModelTaskInput(Object.freeze({
          capacity: () => checked(moon.clientProgramInstalledSourceConstructionCapacity(
            32n, 0n, 0n, 16n, 0n, 0n)),
          project: () => runtimeCore(moon).publicationControl
            .installedModelRawSelectionOriginals(provider.rawCaptureSelection),
          retained: () => checked(moon.clientProgramInstalledSourceConstructionCapacity(
            32n, 0n, 0n, 0n, 0n, 0n)),
        }));
        policyOriginals.push({provider, originals});
      }
    }
    const persistOriginals = policyOriginals.length === 0 ? undefined : async store => {
      // The existing Store owns write funding, digest validation, durability
      // and pending cleanup. This installs policy DATA, never a raw grant,
      // Account permission, approval or authority to send a Model request.
      assertCurrent();
      assertNewHostRuntime?.();
      for (const {provider, originals} of policyOriginals) {
        for (const original of originals) {
          assertCurrent(); provider.assertNewTrustedRuntime?.();
          await store.putSemantic(original.wire, original.cid);
          assertCurrent(); provider.assertNewTrustedRuntime?.();
        }
      }
    };
    phase = 'installed';
    return {providers, projectTasks, persistOriginals};
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
