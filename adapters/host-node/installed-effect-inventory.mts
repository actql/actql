import {installedSourceEnvironmentConstructionReader} from './installed-host-services.mjs';
import {composeInstalledInventoryEnvironment} from './installed-funded-environment.mjs';
// Private installation routing over published facts. Selecting an owner never
// prepares an Effect, acquires a provider, or grants an execution permission.
import {isAbsolute} from 'node:path';
import {verifyInstalledConnectorBindings}
  from './installed-check-environment.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {MAX_INSTALLED_EFFECT_PROFILES} from './installed-effect-limits.mjs';
import {contentCid} from './local-account-config.mjs';
// @ts-expect-error TS7016: the installed Row Effect owner is still authored in JavaScript.
import {composeInstalledRowEffectOwners, installedRowEffectOwnerBinding, installedRowEffectUpdateTargetReadAccess} from './installed-row-effect.mjs';

import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {issueUpdateTargetInstallation} from './update-target-original-shape.mjs';

type EnvironmentArguments = Parameters<typeof composeInstalledInventoryEnvironment>;
type NativeEnvironment = Exclude<NonNullable<EnvironmentArguments[3]>, string>;
type InventoryOptions = Readonly<{
  installationServices: EnvironmentArguments[0]; moon: EnvironmentArguments[1]; baseEnvironmentWire: EnvironmentArguments[2];
}>;
type EnvironmentOriginal = ReturnType<typeof composeInstalledInventoryEnvironment>;
type SelectorKind = 'create' | 'update' | 'upsert' | 'store';
type SelectionFields = Readonly<{target: string; effectId?: string}>;
type CommandSelector = SelectionFields & Readonly<{
  kind: 'command'; commandRef: string; commandCid: string;
  mappingRef?: never; mappingCid?: never; capabilityCid?: never;
}>;
type MappingSelector = SelectionFields & Readonly<{
  kind: SelectorKind; mappingRef: string; mappingCid: string; capabilityCid?: string;
  commandRef?: never; commandCid?: never;
}>;
type Selector = CommandSelector | MappingSelector;
type CandidateSelector = Readonly<Partial<Record<keyof Selector, unknown>>>;
type Mapping = Readonly<{
  mapping_ref: string; mapping_contract_cid: string; target_ref: string; connector_manifest_cid: string;
  permission_rules?: readonly Readonly<{effect_kind: string}>[];
}>;
type CommandIdentity = Readonly<{command_id: string; contract_cid: string}>;
type Command = CommandIdentity & Readonly<{connector_id: string; target: Readonly<{resource_kind: string}>}>;
type Environment = Readonly<{
  mapping_contracts: readonly Mapping[];
  command_contracts: readonly Command[];
  connector_catalogs: readonly Readonly<{connector_id: string; commands: readonly CommandIdentity[]}>[];
  connector_manifest?: Readonly<{connectors: readonly ManifestEntry[]}>;
}>;
type ManifestEntry = Readonly<{connector_id: string}>;
type ConnectorBinding = Readonly<{connectorId: string; bindingCid: string}>;
type Alias = Readonly<{
  name: string; targetRef: string; installationBindingCid?: string; installationOwnerCid?: string;
}>;
type BoundAlias = Readonly<Required<Alias>>;
type EffectRegistration = Readonly<{environmentWire: string; effectSelectors?: readonly Selector[]}>;
export type EffectOwner = EffectRegistration & Readonly<{
  connectorBindings?: readonly ConnectorBinding[]; environmentOriginal?: NativeEnvironment;
  queryUpdateTargets?: readonly Alias[]; queryTableBindings?: readonly unknown[]; queryTableWriteAccesses?: readonly unknown[];
}>;
type Inventory = EffectOwner & Readonly<{effects?: readonly EffectOwner[]}>;
type RoutingMember = Readonly<{effectSelectors: readonly Selector[]}>;
type CompoundInventory<Member> = Readonly<{
  effects: readonly Member[]; environmentWire?: string;
}>;
type ReadAccess = Readonly<{authorization: object; connection: string; resources: readonly string[]}>;
type ReadObservation = Readonly<{principalId: string; signal?: AbortSignal}>;
type InstallationBinding = ReturnType<typeof issueUpdateTargetInstallation>;
type Stage = Readonly<{
  environmentWire: string | undefined; assertPrepared(facts: unknown): void;
  prepareManagedPlan(facts: unknown, inputs: unknown): unknown;
  prepareCaptured(facts: unknown): unknown; prepareRecovered(facts: unknown): unknown;
}>;
type CleanupOwner = Readonly<{close(): unknown}>;
type CleanupHandle = Readonly<{retry(): unknown; status(): Readonly<{pending: boolean}>}>;
type CleanupFailure = Readonly<{
  message?: string; code?: unknown; primaryFailure?: unknown; cleanupHandle?: CleanupHandle; cleanupPending?: boolean;
}>;


const fail: (code: string) => never = code => { throw Object.assign(new TypeError(code), {code}); };
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const cid = (value: unknown) => /^sha256:[0-9a-f]{64}$/u.test((value ?? '') as string);
const kinds = new Set<unknown>(['create', 'update', 'upsert', 'store']);
const selectorKeys = new Set(['kind', 'target', 'mappingRef', 'mappingCid', 'effectId', 'capabilityCid']);
const commandSelectorKeys = new Set(['kind', 'target', 'commandRef', 'commandCid', 'effectId']);

export function validPluralEffectPaths(paths: unknown): paths is readonly string[] {
  return Array.isArray(paths) && paths.length >= 2 &&
    paths.length <= MAX_INSTALLED_EFFECT_PROFILES &&
    Array.from(paths).every(path => typeof path === 'string' && isAbsolute(path)) &&
    new Set(paths).size === paths.length;
}

function validSelector(selector: CandidateSelector | null | undefined): selector is Selector {
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

function ownedContracts(effect: EffectRegistration) {
  const selectors = effect.effectSelectors;
  if (!Array.isArray(selectors) || selectors.length === 0 ||
      !Object.isFrozen(selectors)) fail('InvalidInstalledEffectSelectors');
  const environment = JSON.parse(effect.environmentWire) as Environment;
  const mappings = environment.mapping_contracts;
  const owned = new Map<string, string>();
  const exact = new Set();
  for (const selector of selectors as readonly Selector[]) {
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
export function installedUpdateTargets<Target extends Alias>(effect: Inventory, aliases: readonly Target[],
  environmentWire = effect.environmentWire): readonly Readonly<Target & BoundAlias>[] {
  if (!Array.isArray(aliases) || aliases.length > 1024) fail('InvalidInstalledUpdateTargets');
  if (aliases.length === 0) return Object.freeze([]);
  const owned = ownedContracts(effect.effects === undefined ? effect : {
    environmentWire: effect.environmentWire,
    effectSelectors: Object.freeze(effect.effects.flatMap(owner => owner.effectSelectors!)),
  });
  verifyInstalledConnectorBindings(undefined, effect);
  const environment = JSON.parse(environmentWire) as Environment;
  const manifest = environment.connector_manifest?.connectors;
  if (!Array.isArray(manifest)) fail('InvalidInstalledUpdateTargets');
  const bindings = new Map((effect.connectorBindings ?? []).map(binding =>
    [binding.connectorId, binding.bindingCid]));
  const manifestEntries = new Map<string, ManifestEntry>();
  for (const entry of manifest as readonly ManifestEntry[]) {
    const identity = contentCid(entry);
    if (manifestEntries.has(identity)) fail('InvalidInstalledUpdateTargets');
    manifestEntries.set(identity, entry);
  }
  const targetMappings = new Map<string, Mapping[]>();
  for (const mapping of environment.mapping_contracts) {
    const members = targetMappings.get(mapping.target_ref) ?? [];
    members.push(mapping);
    targetMappings.set(mapping.target_ref, members);
  }
  const targetBindings = new Map<string, string>();
  const targetOwners = new Map<string, string>();
  const owners = effect.effects ?? [effect];
  return Object.freeze((aliases as readonly Target[]).map(alias => {
    if (!targetBindings.has(alias.targetRef)) {
      const mappings = targetMappings.get(alias.targetRef);
      if (mappings === undefined) fail('InvalidInstalledUpdateTargets');
      let installationBindingCid: string | undefined;
      let installationOwnerCid: string | undefined;
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
        const matches = owners.filter(owner => owner.effectSelectors!.some(selector =>
          selector.mappingRef === mapping.mapping_ref &&
          selector.mappingCid === mapping.mapping_contract_cid &&
          selector.target === mapping.target_ref));
        const original = matches.length === 1
          ? installedRowEffectOwnerBinding(matches[0]) as InstallationBinding | undefined : undefined;
        if (original === undefined || installationOwnerCid !== undefined &&
            installationOwnerCid !== original.cid) fail('InvalidInstalledUpdateTargets');
        installationOwnerCid = original.cid;
      }
      targetBindings.set(alias.targetRef, installationBindingCid!);
      targetOwners.set(alias.targetRef, installationOwnerCid!);
    }
    const installationBindingCid = targetBindings.get(alias.targetRef);
    const installationOwnerCid = targetOwners.get(alias.targetRef);
    if (alias.installationBindingCid !== undefined &&
        alias.installationBindingCid !== installationBindingCid ||
        alias.installationOwnerCid !== undefined &&
        alias.installationOwnerCid !== installationOwnerCid) {
      fail('InvalidInstalledUpdateTargets');
    }
    return Object.freeze({...alias, installationBindingCid, installationOwnerCid}) as Readonly<Target & BoundAlias>;
  }));
}

// Checking discloses metadata under the original target's read scope. It does
// not request Effect approval, issue a credential/grant or execute a provider.
// The Host supplies the same publication's current fence across every await.
export function installedUpdateTargetDisclosure<Target extends BoundAlias>(effect: Inventory | undefined,
  targets: readonly Target[], principalId: string, assertCurrent: () => SynchronousRuntimeData) {
  if (!Array.isArray(targets) || targets.length > 1024 ||
      typeof assertCurrent !== 'function') fail('InvalidInstalledUpdateTargets');
  const owners = effect === undefined ? [] : effect.effects ?? [effect];
  return Object.freeze({async visibleFor({principalId: actual, signal}: ReadObservation) {
    if (actual !== principalId) return [];
    assertCurrent();
    const visible: Target[] = [];
    for (const target of targets as readonly Target[]) {
      signal?.throwIfAborted();
      let access: ReadAccess | undefined;
      for (const owner of owners) {
        const candidate = installedRowEffectUpdateTargetReadAccess(owner, target) as ReadAccess | undefined;
        if (candidate === undefined) continue;
        if (access !== undefined) return [];
        access = candidate;
      }
      if (access === undefined) continue;
      const {authorization, connection, resources} = access;
      const authorize = Object.getOwnPropertyDescriptor(authorization, 'authorize')?.value;
      const current = Object.getOwnPropertyDescriptor(authorization, 'assertConfigurationCurrent')?.value;
      if (typeof authorize !== 'function' || typeof current !== 'function') continue;
      let allowed = true;
      for (const resource of resources) {
        assertCurrent();
        let decision: Readonly<{action?: unknown}> | undefined;
        try {
          Reflect.apply(current, authorization, []);
          decision = await Reflect.apply(authorize, authorization, ['acquisition',
            {connection, resource, operation: 'read'},
            {subjectCid: target.installationOwnerCid, signal, allowDeferral: false}]);
          Reflect.apply(current, authorization, []);
        } catch (cause) {
          if (signal?.aborted) throw cause;
          allowed = false;
        }
        signal?.throwIfAborted();
        assertCurrent();
        if (!allowed || decision?.action !== 'dispatch') {allowed = false; break;}
      }
      if (allowed) visible.push(target);
    }
    assertCurrent();
    return visible;
  }});
}

// The loader records each returned child before validating it. A module that
// fails before returning may instead retain a cleanup handle on its failure.
// Both kinds of owner are independent and are attempted on every drain; only
// failed owners remain pending. Concurrent closes share the same flight.
function inventoryCleanup() {
  const pending = new Set<CleanupOwner | undefined>();
  let flight: Promise<void> | undefined;
  const status = () => Object.freeze({pending: pending.size !== 0});
  async function drain() {
    const errors: unknown[] = [];
    for (const owner of pending) {
      try { await owner!.close(); pending.delete(owner); }
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
  const retain = (owner: CleanupOwner | undefined) => { pending.add(owner); };
  const retainFailure = (cause: CleanupFailure | null | undefined) => {
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

export async function composeInstalledEffects<Path, Options extends InventoryOptions, Member extends EffectOwner>(
  paths: readonly Path[], options: Options,
  load: (path: Path, options: Readonly<Options>, retain: (owner: CleanupOwner | undefined) => void) => Member | PromiseLike<Member>) {
  // Capture the options once: later callbacks cannot switch the admitted
  // service/runtime or revive a missing-services diagnostic path.
  options = Object.freeze({...options});
  installedSourceEnvironmentConstructionReader(options?.installationServices, options?.moon);
  const effects: Member[] = [];
  const cleanup = inventoryCleanup();
  const refs = new Set<string>(), cids = new Set<string>(), bindings = new Map<string, ConnectorBinding>();
  let environmentWire: string | undefined, environmentOriginal: EnvironmentOriginal | undefined;
  try {
    for (const path of paths) {
      const effect = await load(path, options, cleanup.retain);
      // Compose and validate every member before loading the next. The common
      // composer independently admits the publication and the growing result.
      const combinedOriginal = composeInstalledInventoryEnvironment(options.installationServices, options.moon,
          options.baseEnvironmentWire, environmentOriginal, effect.environmentOriginal ?? effect.environmentWire, () => {
            verifyInstalledConnectorBindings(environmentWire === undefined ? undefined :
              {environmentWire, connectorBindings: [...bindings.values()]}, effect);
            for (const [ref, identity] of ownedContracts(effect)) {
              if (refs.has(ref) || cids.has(identity)) fail('InstalledEffectMappingAmbiguous');
              refs.add(ref);
              cids.add(identity);
            }
            return effects.length + 1 === paths.length;
      });
      const combined = combinedOriginal.wire;
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
      effectSelectors: Object.freeze(effects.flatMap(effect => effect.effectSelectors!))} as Inventory,
    effects.flatMap(effect => effect.queryUpdateTargets ?? []));
    return Object.freeze({effects: Object.freeze(effects), environmentWire, environmentOriginal, queryUpdateTargets,
      queryTableBindings: Object.freeze(effects.flatMap(effect => effect.queryTableBindings ?? [])),
      queryTableWriteAccesses: Object.freeze(effects.flatMap(effect => effect.queryTableWriteAccesses ?? [])),
      connectorBindings, close: cleanup.close});
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cleanup.retainFailure(cause as CleanupFailure | null | undefined),
      {installedEffect: {close: cleanup.close}});
  }
}

export function installedEffectFor<Member extends object>(inventory: (Member & {effects?: undefined}) |
  CompoundInventory<Member & RoutingMember> | undefined, descriptors: unknown): Member | Stage {
  // Legacy singular installations keep their original adapter admission and
  // need not publish the metadata required only by plural installation.
  if (inventory === undefined) fail('InstalledEffectProgramMismatch');
  if (inventory.effects === undefined) return inventory;
  if (!Array.isArray(descriptors) || descriptors.length === 0) {
    fail('InstalledEffectProgramMismatch');
  }
  let owner: Member | undefined;
  const owners: Member[] = [];
  for (const descriptor of descriptors as readonly CandidateSelector[]) {
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
    return composeInstalledRowEffectOwners(owners, descriptors, inventory.environmentWire) as Stage;
  }
  return owner!;
}
