// Static ModelTask registration shares the installed checker composition.
// This metadata is neither a provider registration nor an egress grant. The
// common execution owner must separately admit dependencies and authority.
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {checked} from '../host-common/runtime-result.mjs';

function checkInstallation(installation) {
  if (installation === null || typeof installation !== 'object' ||
      Array.isArray(installation) ||
      Object.keys(installation).some(key =>
        !['environmentWire', 'executionContracts', 'dependencyBodies'].includes(key)) ||
      typeof installation.environmentWire !== 'string') {
    throw new TypeError('InvalidInstalledModelConfiguration');
  }
  const entries = installation.executionContracts ?? [];
  if (!Array.isArray(entries) || entries.length > 128) {
    throw new TypeError('InvalidInstalledModelExecutionConfiguration');
  }
  const tasks = new Set();
  for (const entry of entries) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'bodyWire,cid,modelTaskCid' ||
        typeof entry.bodyWire !== 'string' ||
        typeof entry.cid !== 'string' ||
        typeof entry.modelTaskCid !== 'string' ||
        tasks.has(entry.modelTaskCid)) {
      throw new TypeError('InvalidInstalledModelExecutionConfiguration');
    }
    tasks.add(entry.modelTaskCid);
  }
  const bodies = installation.dependencyBodies ?? [];
  if (!Array.isArray(bodies) || bodies.length > 384) {
    throw new TypeError('InvalidInstalledModelDependencyConfiguration');
  }
  const references = new Set();
  for (const entry of bodies) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'bodyWire,cid' ||
        typeof entry.bodyWire !== 'string' || typeof entry.cid !== 'string' ||
        references.has(entry.cid)) {
      throw new TypeError('InvalidInstalledModelDependencyConfiguration');
    }
    references.add(entry.cid);
  }
  return entries;
}

// Registration remains physical Host capability. The common admission owner
// subsequently binds the selected callback to its exact Task and prompt.
export function installModelProviders(moon, register) {
  if (register === undefined) return new Map();
  if (typeof register !== 'function') {
    throw new TypeError('InvalidInstalledModelProviderRegistration');
  }
  const entries = register(moon);
  if (!Array.isArray(entries) || entries.length > 128) {
    throw new TypeError('InvalidInstalledModelProviderRegistration');
  }
  const result = new Map();
  for (const entry of entries) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry) ||
        Object.keys(entry).sort().join(',') !== 'invoke,providerId,validatePrompt' ||
        typeof entry.providerId !== 'string' ||
        typeof entry.invoke !== 'function' ||
        typeof entry.validatePrompt !== 'function' ||
        result.has(entry.providerId)) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    const provider = moon.clientProgramInstallModelProvider(entry.providerId,
      entry.invoke);
    if (provider === undefined) {
      throw new TypeError('InvalidInstalledModelProviderRegistration');
    }
    const validatePrompt = entry.validatePrompt;
    result.set(entry.providerId, Object.freeze({provider,
      validatePrompt: (...args) => validatePrompt(...args) === true}));
  }
  return result;
}

export function readInstalledModelDependencies(moon, execution, installation) {
  checkInstallation(installation);
  const references = moon.clientProgramInferDependencyReferences(execution);
  const bodies = new Map((installation.dependencyBodies ?? [])
    .map(entry => [entry.cid, entry.bodyWire]));
  return checked(moon.clientProgramReadInferModelDependencies(execution,
    bodies.get(references._0), bodies.get(references._1),
    bodies.get(references._2)));
}

export function admitInstalledModelProvider(moon, execution, dependencies,
  providers) {
  const selected = providers.get(moon.clientProgramInferProviderId(execution));
  if (selected === undefined) {
    throw Object.assign(new Error('InstalledInferModelProviderUnavailable'),
      {code: 'InstalledInferModelProviderUnavailable'});
  }
  return checked(moon.clientProgramAdmitModelProvider(selected.provider,
    execution, dependencies, selected.validatePrompt));
}

export function installedModelEnvironment(moon, baseWire, currentWire,
  installation) {
  if (installation === undefined) return currentWire;
  checkInstallation(installation);
  // Both full documents are independently admitted by the common checker;
  // selectors and capacities retain the existing conflict checks.
  return composeInstalledCheckEnvironment(moon, baseWire, currentWire,
    installation.environmentWire);
}

// Normal submit uses its original prepared owner. The metadata lookup does
// not admit a body: MoonBit checks canonical bytes, self-CID, exact Task and
// ceilings. Returning this contract does not admit prompt/retry/egress policy.
export function readInstalledModelExecution(moon, prepared, installation) {
  const step = moon.clientProgramTerminalInferStep(prepared);
  if (step === undefined) return undefined;
  const taskCid = moon.clientProgramInferModelTaskCid(prepared, step);
  const entry = installation === undefined ? undefined :
    checkInstallation(installation).find(item => item.modelTaskCid === taskCid);
  if (entry === undefined) {
    throw Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
      {code: 'InstalledInferModelExecutionUnavailable'});
  }
  return Object.freeze({step, execution: checked(
    moon.clientProgramReadInferModelExecution(prepared, step,
      entry.bodyWire, entry.cid))});
}
