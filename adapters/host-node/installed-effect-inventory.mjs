import {installedSourceEnvironmentConstructionReader} from './installed-host-services.mjs';
import {composeInstalledSourceEnvironment} from './installed-funded-environment.mjs';
// Private installation routing over published facts. Selecting an owner never
// prepares an Effect, acquires a provider, or grants an execution permission.
import {isAbsolute} from 'node:path';
import {verifyInstalledConnectorBindings}
  from './installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {MAX_INSTALLED_EFFECT_PROFILES} from './installed-effect-limits.mjs';
import {contentCid} from './local-account-config.mjs';
import {composeInstalledRowEffectOwners, installedRowEffectOwnerBinding} from './installed-row-effect.mjs';

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

// The existing installation inventory establishes ownership, not Mapping
// eligibility or authority. Every Mapping for a published target must be in
// this owner's registrations; the common owner still resolves over ALL bodies.
// An admitted final Host environment may add Source/model facts. Revalidation
// checks that full inventory against the original Effect registrations only.
export function installedUpdateTargets(effect, aliases, environmentWire = effect.environmentWire) {
  if (!Array.isArray(aliases) || aliases.length > 1024) fail('InvalidInstalledUpdateTargets');
  if (aliases.length === 0) return Object.freeze([]);
  const owned = ownedContracts(effect.effects === undefined ? effect : {
    environmentWire: effect.environmentWire,
    effectSelectors: Object.freeze(effect.effects.flatMap(owner => owner.effectSelectors)),
  });
  verifyInstalledConnectorBindings(undefined, effect);
  const environment = JSON.parse(environmentWire);
  const manifest = environment.connector_manifest?.connectors;
  if (!Array.isArray(manifest)) fail('InvalidInstalledUpdateTargets');
  const bindings = new Map((effect.connectorBindings ?? []).map(binding =>
    [binding.connectorId, binding.bindingCid]));
  const manifestEntries = new Map();
  for (const entry of manifest) {
    const identity = contentCid(entry);
    if (manifestEntries.has(identity)) fail('InvalidInstalledUpdateTargets');
    manifestEntries.set(identity, entry);
  }
  const targetMappings = new Map();
  for (const mapping of environment.mapping_contracts) {
    const members = targetMappings.get(mapping.target_ref) ?? [];
    members.push(mapping);
    targetMappings.set(mapping.target_ref, members);
  }
  const targetBindings = new Map();
  const targetOwners = new Map();
  const owners = effect.effects ?? [effect];
  return Object.freeze(aliases.map(alias => {
    if (!targetBindings.has(alias.targetRef)) {
      const mappings = targetMappings.get(alias.targetRef);
      if (mappings === undefined) fail('InvalidInstalledUpdateTargets');
      let installationBindingCid;
      let installationOwnerCid;
      for (const mapping of mappings) {
        if (owned.get(mapping.mapping_ref) !== mapping.mapping_contract_cid) {
          fail('InvalidInstalledUpdateTargets');
        }
        const entry = manifestEntries.get(mapping.connector_manifest_cid);
        if (entry === undefined ||
            !alias.targetRef.startsWith(`connector://${entry.connector_id}/`)) {
          fail('InvalidInstalledUpdateTargets');
        }
        const bindingCid = bindings.get(entry.connector_id);
        if (!cid(bindingCid) || installationBindingCid !== undefined &&
            installationBindingCid !== bindingCid) {
          fail('InvalidInstalledUpdateTargets');
        }
        installationBindingCid = bindingCid;
        // The existing private row owner fixes the runtime, registration and
        // publication generation. A site binding alone does not fix them.
        const matches = owners.filter(owner => owner.effectSelectors.some(selector =>
          selector.mappingRef === mapping.mapping_ref &&
          selector.mappingCid === mapping.mapping_contract_cid &&
          selector.target === mapping.target_ref));
        const original = matches.length === 1
          ? installedRowEffectOwnerBinding(matches[0]) : undefined;
        if (original === undefined || installationOwnerCid !== undefined &&
            installationOwnerCid !== original.cid) fail('InvalidInstalledUpdateTargets');
        installationOwnerCid = original.cid;
      }
      targetBindings.set(alias.targetRef, installationBindingCid);
      targetOwners.set(alias.targetRef, installationOwnerCid);
    }
    const installationBindingCid = targetBindings.get(alias.targetRef);
    const installationOwnerCid = targetOwners.get(alias.targetRef);
    if (alias.installationBindingCid !== undefined &&
        alias.installationBindingCid !== installationBindingCid ||
        alias.installationOwnerCid !== undefined &&
        alias.installationOwnerCid !== installationOwnerCid) {
      fail('InvalidInstalledUpdateTargets');
    }
    return Object.freeze({...alias, installationBindingCid, installationOwnerCid});
  }));
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
  // Capture the options once: later callbacks cannot switch the admitted
  // service/runtime or revive a missing-services diagnostic path.
  options = Object.freeze({...options});
  installedSourceEnvironmentConstructionReader(options?.installationServices, options?.moon);
  const effects = [];
  const cleanup = inventoryCleanup();
  const refs = new Set(), cids = new Set(), bindings = new Map();
  let environmentWire, environmentOriginal;
  try {
    for (const path of paths) {
      const effect = await load(path, options, cleanup.retain);
      // Compose and validate every member before loading the next. The common
      // composer independently admits the publication and the growing result.
      const combinedOriginal = composeInstalledSourceEnvironment(options.installationServices, options.moon,
          options.baseEnvironmentWire, environmentOriginal, effect.environmentOriginal ?? effect.environmentWire);
      const combined = combinedOriginal.wire;
      verifyInstalledConnectorBindings(environmentWire === undefined ? undefined :
        {environmentWire, connectorBindings: [...bindings.values()]}, effect);
      for (const [ref, identity] of ownedContracts(effect)) {
        if (refs.has(ref) || cids.has(identity)) fail('InstalledEffectMappingAmbiguous');
        refs.add(ref);
        cids.add(identity);
      }
      environmentWire = combined;
      environmentOriginal = combinedOriginal;
      for (const binding of effect.connectorBindings ?? []) {
        if (!bindings.has(binding.connectorId)) bindings.set(binding.connectorId, binding);
      }
      effects.push(effect);
    }
    const connectorBindings = Object.freeze([...bindings.values()]);
    // Recheck coverage in the full composed inventory: an unregistered body
    // in another installation cannot disappear behind the alias owner's view.
    // Keep conflicting names intact so the common resolver sees ambiguity.
    const queryUpdateTargets = installedUpdateTargets({effects, environmentWire, connectorBindings,
      effectSelectors: Object.freeze(effects.flatMap(effect => effect.effectSelectors))},
    effects.flatMap(effect => effect.queryUpdateTargets ?? []));
    return Object.freeze({effects: Object.freeze(effects), environmentWire, environmentOriginal, queryUpdateTargets,
      queryTableBindings: Object.freeze(effects.flatMap(effect => effect.queryTableBindings ?? [])),
      queryTableWriteAccesses: Object.freeze(effects.flatMap(effect => effect.queryTableWriteAccesses ?? [])),
      connectorBindings, close: cleanup.close});
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
  const owners = [];
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
    owners.push(matches[0]);
    owner = matches[0];
  }
  if (owners.some(value => value !== owner)) {
    return composeInstalledRowEffectOwners(owners, descriptors, inventory.environmentWire);
  }
  return owner;
}
