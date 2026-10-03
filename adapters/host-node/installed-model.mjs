// Static ModelTask registration shares the installed checker composition.
// This metadata is neither a provider registration nor an egress grant. The
// common execution owner must separately admit dependencies and authority.
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openSync, readSync, closeSync} from 'node:fs';

// Physical observation only: the common account reader/evaluator decides
// authority. Bound reads even when the selected file grows during observation.
export function observeInstalledModelAccount(moon, authorization) {
  try {
    let wire = authorization?.accountConfiguration;
    if (authorization?.accountConfig !== undefined) {
      if (wire !== undefined) return moon.executionAuthorizationMissing();
      const fd = openSync(authorization.accountConfig, 'r');
      try {
        const buffer = Buffer.alloc(1000001);
        let used = 0;
        while (used < buffer.length) {
          const read = readSync(fd, buffer, used, buffer.length - used, used);
          if (read === 0) break;
          used += read;
        }
        if (used > 1000000) return moon.executionAuthorizationMissing();
        wire = new TextDecoder('utf-8', {fatal: true}).decode(buffer.subarray(0, used));
      } finally { closeSync(fd); }
    }
    return typeof wire === 'string' && Buffer.byteLength(wire) <= 1000000
      ? moon.executionAuthorizationAdmit(wire)
      : moon.executionAuthorizationMissing();
  } catch { return moon.executionAuthorizationMissing(); }
}

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
        Object.keys(entry).some(key => !['invoke', 'providerId', 'validatePrompt',
          'physicalPreflight', 'quantityCapacity', 'observeEgress'].includes(key)) ||
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
    let quantityCapacity;
    if (entry.quantityCapacity !== undefined) {
      const capacity = entry.quantityCapacity;
      if (capacity === null || typeof capacity !== 'object' ||
          Object.keys(capacity).sort().join(',') !== 'limits,perAttempt' ||
          ['limits', 'perAttempt'].some(scope => {
            const amount = capacity[scope];
            return amount === null || typeof amount !== 'object' ||
              Object.keys(amount).sort().join(',') !== 'costUnits,durationMs,tokens' ||
              Object.values(amount).some(value => typeof value !== 'bigint' ||
                value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER));
          })) {
        throw new TypeError('InvalidInstalledModelQuantityCapacity');
      }
      quantityCapacity = Object.freeze({
        limits: Object.freeze({...capacity.limits}),
        perAttempt: Object.freeze({...capacity.perAttempt}),
      });
    }
    result.set(entry.providerId, Object.freeze({provider,
      physicalPreflight: entry.physicalPreflight,
      quantityCapacity,
      observeEgress: typeof entry.observeEgress !== 'function' ? undefined : () => {
        try { return entry.observeEgress(); }
        catch { return undefined; }
      },
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
export function readInstalledModelExecution(moon, prepared, installation,
  occurrence) {
  const step = occurrence === undefined
    ? moon.clientProgramSelectedInferStep(prepared)
    : moon.clientProgramInferOccurrenceCoordinates(occurrence)._2;
  if (step === undefined) return undefined;
  const taskCid = occurrence === undefined
    ? moon.clientProgramInferModelTaskCid(prepared, step)
    : moon.clientProgramInferOccurrenceModelTaskCid(occurrence);
  const entry = installation === undefined ? undefined :
    checkInstallation(installation).find(item => item.modelTaskCid === taskCid);
  if (entry === undefined) {
    throw Object.assign(new Error('InstalledInferModelExecutionUnavailable'),
      {code: 'InstalledInferModelExecutionUnavailable'});
  }
  return Object.freeze({step, execution: checked(occurrence === undefined
    ? moon.clientProgramReadInferModelExecution(prepared, step, entry.bodyWire,
      entry.cid)
    : moon.clientProgramReadComposedInferModelExecution(occurrence,
      entry.bodyWire, entry.cid))});
}
