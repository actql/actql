// Private installation routing over published facts. Selecting an owner never
// prepares an Effect, acquires a provider, or grants an execution permission.
import {isAbsolute} from 'node:path';
import {composeInstalledCheckEnvironment, verifyInstalledConnectorBindings}
  from './installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {MAX_INSTALLED_EFFECT_PROFILES} from './installed-effect-limits.mjs';
import {contentCid} from './local-account-config.mjs';

const fail = code => { throw Object.assign(new TypeError(code), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const cid = value => /^sha256:[0-9a-f]{64}$/u.test(value ?? '');
const kinds = new Set(['create', 'update', 'upsert', 'store']);
const selectorKeys = new Set(['kind', 'target', 'mappingRef', 'mappingCid', 'effectId', 'capabilityCid']);
const commandSelectorKeys = new Set(['kind', 'target', 'commandRef', 'commandCid', 'effectId']);

export function validPluralEffectPaths(paths) {
  return Array.isArray(paths) && paths.length >= 2 &&
    paths.length <= MAX_INSTALLED_EFFECT_PROFILES &&
    Array.from(paths).every(path => typeof path === 'string' && isAbsolute(path)) &&
    new Set(paths).size === paths.length;
}

function validSelector(selector) {
  if (selector === null || typeof selector !== 'object' || Array.isArray(selector)) return false;
  if (selector.kind === 'command') {
    return Object.keys(selector).every(key => commandSelectorKeys.has(key)) &&
      text(selector.target) && text(selector.commandRef) && cid(selector.commandCid) &&
      (selector.effectId === undefined || text(selector.effectId));
  }
  return Object.keys(selector).every(key => selectorKeys.has(key)) &&
    kinds.has(selector.kind) && text(selector.target) && text(selector.mappingRef) &&
    cid(selector.mappingCid) &&
    (selector.effectId === undefined || text(selector.effectId)) &&
    (selector.capabilityCid === undefined || cid(selector.capabilityCid));
}

function ownedContracts(effect) {
  const selectors = effect.effectSelectors;
  if (!Array.isArray(selectors) || selectors.length === 0 ||
      !Object.isFrozen(selectors)) fail('InvalidInstalledEffectSelectors');
  const environment = JSON.parse(effect.environmentWire);
  const mappings = environment.mapping_contracts;
  const owned = new Map();
  const exact = new Set();
  for (const selector of selectors) {
    if (!validSelector(selector) || !Object.isFrozen(selector)) {
      fail('InvalidInstalledEffectSelectors');
    }
    if (selector.kind === 'command') {
      const matches = environment.command_contracts.filter(command =>
        command.command_id === selector.commandRef);
      if (matches.length !== 1) fail('InvalidInstalledEffectSelectors');
      const command = matches[0];
      const {contract_cid: commandCid, ...body} = command;
      const catalogMatches = environment.connector_catalogs.filter(catalog =>
        catalog.connector_id === command.connector_id &&
        catalog.commands.some(item => item.command_id === selector.commandRef &&
          item.contract_cid === selector.commandCid));
      if (commandCid !== selector.commandCid || commandCid !== contentCid(body) ||
          command.target.resource_kind !== selector.target || catalogMatches.length !== 1) {
        fail('InvalidInstalledEffectSelectors');
      }
      const key = JSON.stringify(['command', selector.target, selector.commandRef,
        selector.commandCid, selector.effectId ?? null]);
      if (exact.has(key)) fail('InvalidInstalledEffectSelectors');
      exact.add(key);
      owned.set(selector.commandRef, selector.commandCid);
      continue;
    }
    const matches = mappings.filter(mapping => mapping.mapping_ref === selector.mappingRef);
    if (matches.length !== 1) fail('InvalidInstalledEffectSelectors');
    const mapping = matches[0];
    const {mapping_contract_cid: mappingCid, ...body} = mapping;
    if (mapping.mapping_contract_cid !== selector.mappingCid ||
        mappingCid !== contentCid(body) ||
        mapping.target_ref !== selector.target ||
        !Array.isArray(mapping.permission_rules) ||
        !mapping.permission_rules.some(rule => rule.effect_kind === selector.kind)) {
      fail('InvalidInstalledEffectSelectors');
    }
    // Exact strings retain their published meanings, including Unicode form.
    const key = JSON.stringify([selector.kind, selector.target, selector.mappingRef,
      selector.mappingCid, selector.effectId ?? null, selector.capabilityCid ?? null]);
    if (exact.has(key)) fail('InvalidInstalledEffectSelectors');
    exact.add(key);
    owned.set(selector.mappingRef, selector.mappingCid);
  }
  return owned;
}

// The loader records each returned child before validating it. A module that
// fails before returning may instead retain a cleanup handle on its failure.
// Both kinds of owner are independent and are attempted on every drain; only
// failed owners remain pending. Concurrent closes share the same flight.
function inventoryCleanup() {
  const pending = new Set();
  let flight;
  const status = () => Object.freeze({pending: pending.size !== 0});
  async function drain() {
    const errors = [];
    for (const owner of pending) {
      try { await owner.close(); pending.delete(owner); }
      catch (error) { errors.push(error); }
    }
    if (errors.length) {
      throw Object.assign(new AggregateError(errors, 'InstalledEffectCleanupPending'),
        {code: 'InstalledEffectCleanupPending', cleanupPending: true,
          cleanupHandle: Object.freeze({status, retry: close})});
    }
  }
  function close() {
    if (flight === undefined) flight = drain().finally(() => { flight = undefined; });
    return flight;
  }
  const retain = owner => { pending.add(owner); };
  const retainFailure = cause => {
    if (cause?.cleanupHandle === undefined && cause?.cleanupPending !== true) return cause;
    retain({async close() {
      if (typeof cause.cleanupHandle?.retry !== 'function' ||
          typeof cause.cleanupHandle?.status !== 'function') {
        fail('InstalledHostInitializationCleanupOwnerMissing');
      }
      await cause.cleanupHandle.retry();
      if (cause.cleanupHandle.status().pending !== false) {
        fail('InstalledHostInitializationCleanupPending');
      }
    }});
    // Move this independent cleanup into the aggregate custody. Passing the
    // original cleanup handle as an initialization dependency would postpone
    // closing otherwise independent, successfully loaded siblings.
    return Object.assign(new Error(cause.message, {cause}), {
      code: cause.code, primaryFailure: cause.primaryFailure ?? cause});
  };
  return {retain, retainFailure, close};
}

export async function composeInstalledEffects(paths, options, load) {
  const effects = [];
  const cleanup = inventoryCleanup();
  const refs = new Set(), cids = new Set(), bindings = new Map();
  let environmentWire;
  try {
    for (const path of paths) {
      const effect = await load(path, options, cleanup.retain);
      // Compose and validate every member before loading the next. The common
      // composer independently admits the publication and the growing result.
      const combined = composeInstalledCheckEnvironment(options.moon,
        options.baseEnvironmentWire, environmentWire, effect.environmentWire);
      verifyInstalledConnectorBindings(environmentWire === undefined ? undefined :
        {environmentWire, connectorBindings: [...bindings.values()]}, effect);
      for (const [ref, identity] of ownedContracts(effect)) {
        if (refs.has(ref) || cids.has(identity)) fail('InstalledEffectMappingAmbiguous');
        refs.add(ref);
        cids.add(identity);
      }
      environmentWire = combined;
      for (const binding of effect.connectorBindings ?? []) {
        if (!bindings.has(binding.connectorId)) bindings.set(binding.connectorId, binding);
      }
      effects.push(effect);
    }
    return Object.freeze({effects: Object.freeze(effects), environmentWire,
      queryTableBindings: Object.freeze(effects.flatMap(effect => effect.queryTableBindings ?? [])),
      queryTableWriteAccesses: Object.freeze(effects.flatMap(effect => effect.queryTableWriteAccesses ?? [])),
      connectorBindings: Object.freeze([...bindings.values()]), close: cleanup.close});
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cleanup.retainFailure(cause),
      {installedEffect: {close: cleanup.close}});
  }
}

export function installedEffectFor(inventory, descriptors) {
  // Legacy singular installations keep their original adapter admission and
  // need not publish the metadata required only by plural installation.
  if (inventory === undefined) fail('InstalledEffectProgramMismatch');
  if (inventory.effects === undefined) return inventory;
  if (!Array.isArray(descriptors) || descriptors.length === 0) {
    fail('InstalledEffectProgramMismatch');
  }
  let owner;
  for (const descriptor of descriptors) {
    if (!validSelector(descriptor)) fail('InstalledEffectProgramMismatch');
    const matches = inventory.effects.filter(effect => effect.effectSelectors.some(selector =>
      selector.kind === descriptor.kind && selector.target === descriptor.target &&
      (descriptor.kind === 'command'
        ? selector.commandRef === descriptor.commandRef && selector.commandCid === descriptor.commandCid
        : selector.mappingRef === descriptor.mappingRef && selector.mappingCid === descriptor.mappingCid) &&
      (descriptor.capabilityCid === undefined
        ? selector.effectId === undefined || selector.effectId === descriptor.effectId
        : selector.capabilityCid === descriptor.capabilityCid)));
    if (matches.length !== 1) fail('InstalledEffectProgramMismatch');
    if (owner !== undefined && owner !== matches[0]) fail('InstalledEffectSetOwnerMismatch');
    owner = matches[0];
  }
  return owner;
}
