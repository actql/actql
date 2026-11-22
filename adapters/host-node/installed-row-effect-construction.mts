import {mkdir} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';
import {isInstalledConnectorTableEntry} from './installed-connectors.mjs';
import {assertInstalledSourceConstruction, retainInstalledSourceConstruction} from './installed-host-services.mjs';
import {checkedTableWriteBinding} from './table-write-binding.mjs';
import {deriveInstalledRowWrite} from './installed-row-effect-standard-write.mjs';
import {installedRowCredentialOperationSite} from './installed-row-source.mjs';
import {captureInstalledEffectPlanRecipe, selectInstalledEffectCredentialOperation,
  prepareInstalledStandardCreatePlanRecipe, prepareInstalledDeclaredUpdatePlanRecipe} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';
import type {InstalledConnectorEntry} from '../../packages/local-node/index.d.ts';
import type {createInstalledRowEffectDriverControls} from './installed-row-effect-driver.mjs';
import type {createInstalledRowEffectPlanCapture} from './installed-row-effect-plan-capture.mjs';

type DriverControls = ReturnType<typeof createInstalledRowEffectDriverControls>;
type PlanControls = ReturnType<typeof createInstalledRowEffectPlanCapture>;
type DriverInput = Parameters<DriverControls['checkDriver']>[0];
type DefinitionDriver = Parameters<PlanControls['captureManagedPlanDefinition']>[1];
type LegacyDriver = ReturnType<DriverControls['checkDriver']> & {kinds: readonly string[]};
type TargetRecipes = ReturnType<PlanControls['prepareInstalledTargetPlanRecipes']>;
type UpdatePlanInput = Parameters<typeof prepareInstalledDeclaredUpdatePlanRecipe>[0];
type StandardPlanInput = Parameters<typeof prepareInstalledStandardCreatePlanRecipe>[0];
type PlanLimits = UpdatePlanInput['limits'];
type Limits = PlanLimits & Readonly<{
  maxMembers: number; maxRows: number; maxWork: number; maxFrontierWork: number;
  maxPinnedResults: number; maxFields: number; planWork: number;
  key: PlanLimits['body']; locator: PlanLimits['body'];
}>;
type IdentityProfile = NonNullable<NonNullable<InstalledConnectorEntry['effect']>['identityProfile']>;
type CompiledStage = Readonly<{id?: unknown; effects?: object}>;
type CompiledProgram = Readonly<{id?: unknown; stages?: readonly CompiledStage[]}>;
type UnitRuntime = Readonly<{clientProgramEffectCompilationPlanWire(compilation: unknown): string}>;
type DescriptorRuntime = UnitRuntime & Parameters<typeof checkedTableWriteBinding>[0] & Readonly<{
  clientProgramEffectMemberDescriptor(prepared: unknown, stageIndex: number, effectId: string, maxWork: number): unknown;
}>;

type MappingInput = Readonly<{resource: string; mappingRef: string; mappingCid: string; body: string}>;
type CommandInput = Readonly<{resource: string; commandRef: string; commandCid: string; body: string}>;
type StorePair = Readonly<{catalog_cid: string; command_ref: string; command_contract_cid: string}>;
type MappingBody = Readonly<{
  mapping_contract_cid: string; minimum_approval: 'required' | 'none'; target_ref: string; primary_identity?: unknown;
  permission_rules?: readonly Readonly<{effect_kind: string; permissions?: readonly string[]}>[]; store_command?: StorePair;
}>;
type CommandBody = Readonly<{
  command_id: string; contract_cid: string; connector_id: string;
  target: Readonly<{resource_kind: string}>; permissions: readonly string[];
}>;
type Catalog = Readonly<{catalog_cid: string; commands: readonly {command_id: string; contract_cid: string}[]}>;
type Callable = (...args: never[]) => unknown;
type CredentialSite = Readonly<{issueEffectGrant: Callable; issueReadGrant: Callable; credential?: unknown}>;
type Authorization = Readonly<{authorize: Callable}>;
type InstallOptions = Readonly<{
  moon: object; providerMoon?: object; mappings?: readonly MappingInput[]; commands?: readonly CommandInput[];
  environmentWire: string; sourceInitialization?: object; declaration?: unknown; declared?: unknown;
  environment?: Readonly<{wire?: unknown}>; connectorId: string; connectorRegistration: string;
  connectorRevision: string; connection: string; site: CredentialSite; authorization: Authorization;
  runtimeBundleCid: string; bindingCid: string; driver?: unknown; write?: unknown; ledgerRoot: string;
  installation?: InstalledConnectorEntry; continuationBinding?: string; limits?: Partial<Limits>;
  effectResources?: unknown; issueOriginalCollectionReference?: Callable; managedPlanDefinition?: unknown;
  managedPlanRecipe?: unknown; managedPlanRecipes?: unknown; managedTargetPlanRecipes?: TargetRecipes;
  managedPlanConstruction?: unknown;
}>;
type Installation = Pick<InstallOptions,'moon'|'environmentWire'|'connectorId'|'connectorRegistration'|
  'connectorRevision'|'connection'|'site'|'authorization'|'runtimeBundleCid'|'bindingCid'|'ledgerRoot'|
  'issueOriginalCollectionReference'|'sourceInitialization'|'managedTargetPlanRecipes'> & Readonly<{
  limits: Limits; owned: ReturnType<DriverControls['checkDriver']>; profile: IdentityProfile;
  updateWriteSlot: ReturnType<typeof selectInstalledEffectCredentialOperation>;
  configuredMaxRows: number | undefined; configuredMaxMembers: number | undefined;
  installed: readonly MappingInput[]; installedCommands: readonly CommandInput[]; storeMappings: readonly MappingInput[];
  continuationBinding: string; resources: ReturnType<DriverControls['captureEffectResources']>;
  managedPlanDefinition: ReturnType<PlanControls['captureManagedPlanDefinition']>;
  managedPlanRecipe: InstalledEffectPlanRecipe | undefined; managedPlanRecipes: ReturnType<PlanControls['captureManagedPlanRecipes']>;
  beforeSendCheck: ReturnType<DriverControls['captureBeforeSendCheck']>;
  responseConfirmation: ReturnType<DriverControls['captureResponseConfirmation']>;
}>;
type Controls<Adapter> = Pick<DriverControls, 'captureEffectResources'|'checkDriver'|'captureBeforeSendCheck'|'captureResponseConfirmation'> &
  Pick<PlanControls, 'captureManagedPlanDefinition'|'captureManagedPlanRecipes'|'captureManagedDriverConstruction'> & Readonly<{
    fail(code: string, cause?: unknown): never;
    text(value: unknown): value is string;
    optionalFunction(value: unknown): boolean;
    cid(value: unknown): string;
    cidPattern: RegExp;
    defaultProfile: IdentityProfile;
    defaultLimits: Limits;
    localContractLimits: Readonly<{maxNodes: number}>;
    installedRowEffectConstructionLimits(supplied: Partial<Limits> | undefined): Limits;
    managedTargetPlanOriginals: Pick<WeakMap<TargetRecipes, readonly unknown[]>, 'get'>;
    createRowEffectStage(owners: readonly [Installation], environmentWire: string): Adapter;
  }>;

export function createInstalledRowEffectConstruction<Adapter extends {close(): unknown}>({
  fail, text, optionalFunction, cid, cidPattern, defaultProfile, defaultLimits, localContractLimits,
  installedRowEffectConstructionLimits, managedTargetPlanOriginals, createRowEffectStage,
  captureEffectResources, checkDriver, captureBeforeSendCheck, captureResponseConfirmation,
  captureManagedPlanDefinition, captureManagedPlanRecipes, captureManagedDriverConstruction,
}: Controls<Adapter>) {
  const reject: Controls<Adapter>['fail'] = fail;

  // The identity profile of an installation: the one its connector registered
  // in the installed connector table, or the common default. Only an entry of
  // the generated table or a snapshot admitted by the table owner is accepted.
  function profileOf(installation: InstalledConnectorEntry | undefined) {
    if (installation === undefined) return defaultProfile;
    if ((!(installedConnectors as readonly unknown[]).includes(installation) &&
        !isInstalledConnectorTableEntry(installation)) ||
        installation.effect === undefined) {
      reject('InvalidInstalledRowEffectInstallation');
    }
    return installation.effect.identityProfile ?? defaultProfile;
  }

  // The one Effect Unit of a compiled Program: its Program id, the stage id and
  // index, and its Effect ids in declaration order. A Program with Effects in
  // more than one stage is not this scope.
  function installedRowEffectUnit(moon: UnitRuntime, compilation: unknown) {
    let program: CompiledProgram | undefined;
    try {
      program = JSON.parse(moon.clientProgramEffectCompilationPlanWire(
        compilation)).execution_material?.program as CompiledProgram | undefined;
    } catch (error) { reject('InstalledRowEffectUnitUnsupported', error); }
    const stages: readonly CompiledStage[] = Array.isArray(program?.stages) ? program.stages : [];
    const units = stages.flatMap((stage, stageIndex) =>
      stage?.effects === undefined ? [] : [{stage, stageIndex}]);
    if (!text(program?.id) || units.length !== 1 || !text(units[0].stage.id)) {
      reject('InstalledRowEffectUnitUnsupported');
    }
    const {stage, stageIndex} = units[0];
    return Object.freeze({programId: program.id, stageId: stage.id, stageIndex,
      effectIds: Object.freeze(Object.keys(stage.effects!))});
  }

  // Host installation selection consumes the already checked member descriptor.
  // It does not prepare provider requests or widen the existing plan-work bound.
  function installedRowEffectDescriptors(moon: DescriptorRuntime, prepared: unknown, compilation: unknown) {
    const unit = installedRowEffectUnit(moon, compilation);
    return Object.freeze(unit.effectIds.map(effectId => {
      const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
        prepared, unit.stageIndex, effectId, defaultLimits.planWork));
      const tableBinding = checkedTableWriteBinding(moon, prepared,
        unit.stageIndex, effectId, defaultLimits.planWork);
      if (runtimeField(descriptor, 2) === 'command') {
        return Object.freeze({effectId: runtimeField(descriptor, 1) as string, kind: 'command',
          target: runtimeField(descriptor, 3) as string, commandRef: runtimeField(descriptor, 4) as string, commandCid: runtimeField(descriptor, 5) as string});
      }
      return Object.freeze({effectId: runtimeField(descriptor, 1) as string, kind: runtimeField(descriptor, 2) as string,
        target: runtimeField(descriptor, 3) as string, mappingRef: runtimeField(descriptor, 4) as string, mappingCid: runtimeField(descriptor, 5) as string,
        ...(tableBinding === undefined ? {} : {capabilityCid: runtimeField(tableBinding, 4) as string})});
    }));
  }

  // The installed Effect over `mappings` (each `{resource, mappingRef,
  // mappingCid, body}`, checked by the Check Environment it is installed in)
  // on the credential `site` and installation gate `authorization`.
  // `installation` is the connector's installed table entry, whose registered
  // identity profile names the identities issued here; `continuationBinding`
  // is the value the continuation binds the installation by.
  async function createInstalledRowEffect({moon, providerMoon, mappings = [], commands = [],
    environmentWire, sourceInitialization, declaration, declared, environment,
    connectorId, connectorRegistration, connectorRevision,
    connection, site, authorization, runtimeBundleCid, bindingCid, driver, write,
    ledgerRoot, installation, continuationBinding = bindingCid,
    limits: suppliedLimits, effectResources, issueOriginalCollectionReference, managedPlanDefinition, managedPlanRecipe, managedPlanRecipes,
    managedTargetPlanRecipes, managedPlanConstruction}: InstallOptions) {
    if (sourceInitialization !== undefined) {
      assertInstalledSourceConstruction(sourceInitialization, declaration, declared, environment, undefined, mappings, commands);
      if (environment?.wire !== environmentWire) reject('ForeignInstalledSourceConstruction');
    }
    const resources = captureEffectResources(effectResources);
    const limits = installedRowEffectConstructionLimits(suppliedLimits);
    const configuredMaxRows = Object.hasOwn(suppliedLimits ?? {}, 'maxRows') ? limits.maxRows : undefined;
    const configuredMaxMembers = Object.hasOwn(suppliedLimits ?? {}, 'maxMembers') ? limits.maxMembers : undefined;
    if (write !== undefined && driver !== undefined) reject('InvalidInstalledRowEffectDriver');
    // The installed UPDATE declaration borrows the same provider codec and
    // managed plan. In the shared stage only the Host invokes the write.
    const declaredUpdate = write !== null && typeof write === 'object' && !nodeTypes.isProxy(write) &&
      Object.getOwnPropertyDescriptor(write, 'kind')?.value === 'update';
    const standard = write === undefined || declaredUpdate ? undefined
      : deriveInstalledRowWrite(write, connectorRegistration);
    const owned = checkDriver((write === undefined ? driver : standard?.driver ?? write) as DriverInput, declaredUpdate);
    if (declaredUpdate && (managedPlanDefinition !== undefined ||
        managedTargetPlanRecipes !== undefined || owned.check !== undefined || owned.confirmResponse !== undefined)) {
      reject('InvalidInstalledEffectPlanRecipe');
    }
    const planDefinition = captureManagedPlanDefinition(managedPlanDefinition, owned as DefinitionDriver);
    const suppliedRecipe = captureInstalledEffectPlanRecipe(managedPlanRecipe, localContractLimits.maxNodes);
    const suppliedRecipes = captureManagedPlanRecipes(managedPlanRecipes, owned as DefinitionDriver,
      localContractLimits.maxNodes, declaredUpdate);
    if (suppliedRecipe !== undefined && suppliedRecipes !== undefined) reject('InvalidInstalledEffectPlanRecipe');
    const automaticUpdate = declaredUpdate && suppliedRecipe === undefined && suppliedRecipes === undefined;
    if (automaticUpdate && (providerMoon === undefined || owned.describe !== undefined ||
        owned.finalizeRequest !== undefined || managedPlanConstruction !== undefined)) {
      reject('InvalidInstalledEffectPlanRecipe');
    }
    const checkedUpdateWrite = (recipe: InstalledEffectPlanRecipe | undefined) => {
      const slot = selectInstalledEffectCredentialOperation(recipe, 'write');
      if (slot?.maxTargetBytes === undefined || recipe!.physicalWrite !== undefined ||
          recipe!.rowOperations[slot.operationIndex]?.operation !== owned.operation) reject('InvalidInstalledEffectPlanRecipe');
      return slot;
    };
    const suppliedUpdateWrite = declaredUpdate && !automaticUpdate
      ? checkedUpdateWrite(suppliedRecipes?.update ?? suppliedRecipe) : undefined;
    if (managedTargetPlanRecipes !== undefined && (standard !== undefined || !Array.isArray(commands) || commands.length !== 0 ||
        suppliedRecipe !== undefined || suppliedRecipes !== undefined || planDefinition !== undefined ||
        managedPlanConstruction !== undefined || managedTargetPlanOriginals.get(managedTargetPlanRecipes) !== mappings ||
        (owned as LegacyDriver).kinds.length !== 1 || (owned as LegacyDriver).kinds[0] !== 'update' ||
        owned.check !== undefined || owned.confirmResponse !== undefined)) reject('InvalidInstalledEffectPlanRecipe');
    if (managedPlanConstruction !== undefined && (standard !== undefined || suppliedRecipe !== undefined || suppliedRecipes !== undefined)) {
      reject('InvalidInstalledEffectDriverConstruction');
    }
    const construction = standard?.construction ?? captureManagedDriverConstruction(
      managedPlanConstruction, planDefinition, owned as DefinitionDriver, providerMoon);
    const automatic = suppliedRecipe === undefined && suppliedRecipes === undefined && construction !== undefined && providerMoon !== undefined &&
      construction.check !== null;
    // Preserve the existing explicit/legacy refusal order. The new automatic
    // path waits only for its same validated installation resource names.
    const suppliedBeforeSendCheck = automatic ? undefined : captureBeforeSendCheck(owned as LegacyDriver, suppliedRecipe);
    const profile = profileOf(installation);
    if (!moon || !Array.isArray(mappings) || !Array.isArray(commands) ||
        mappings.length + commands.length === 0 ||
        !text(environmentWire) || !text(connectorId) ||
        !text(connectorRegistration) || !text(connectorRevision) ||
        (installation !== undefined &&
          (installation.registration !== connectorRegistration ||
            installation.revision !== connectorRevision)) ||
        !text(connection) || typeof site?.issueEffectGrant !== 'function' ||
        typeof site.issueReadGrant !== 'function' ||
        typeof authorization?.authorize !== 'function' ||
        !optionalFunction(issueOriginalCollectionReference) ||
        !cidPattern.test(runtimeBundleCid ?? '') ||
        !text(bindingCid) || !text(continuationBinding) || !text(ledgerRoot)) {
      reject('InvalidInstalledRowEffect');
    }
    const installed = Object.freeze((mappings as readonly MappingInput[]).map(mapping => {
      const body = JSON.parse(mapping.body) as MappingBody;
      if (!text(mapping.resource) || !text(mapping.mappingRef) ||
          !text(mapping.mappingCid) || body.mapping_contract_cid !==
            mapping.mappingCid ||
          !['required', 'none'].includes(body.minimum_approval)) {
        reject('InvalidInstalledRowEffect');
      }
      return Object.freeze({...mapping, target: body.target_ref,
        primaryIdentity: body.primary_identity,
        rules: Object.freeze(body.permission_rules ?? []),
        ...(body.store_command === undefined ? {} : {
          storeCommand: Object.freeze({...body.store_command})}),
        approval: body.minimum_approval});
    }));
    if (managedTargetPlanRecipes !== undefined) for (const mapping of installed) {
      const operation = managedTargetPlanRecipes.byMapping[mapping.mappingCid]?.writeOperation;
      if (operation === undefined ||
          !mapping.rules.some(rule => rule.effect_kind === 'update' && rule.permissions?.includes(operation))) {
        reject('InvalidInstalledEffectPlanRecipe');
      }
    }
    const installedCommands = Object.freeze((commands as readonly CommandInput[]).map(command => {
      const body = JSON.parse(command.body) as CommandBody;
      const {contract_cid: selfCid, ...preimage} = body;
      if (!text(command.resource) || !text(command.commandRef) ||
          !cidPattern.test(command.commandCid ?? '') ||
          body.command_id !== command.commandRef || selfCid !== command.commandCid ||
          cid(preimage) !== selfCid || body.connector_id !== connectorId ||
          !text(body.target?.resource_kind) ||
          !Array.isArray(body.permissions) ||
          Object.hasOwn(body, 'minimum_approval')) {
        reject('InvalidInstalledRowEffectCommand');
      }
      return Object.freeze({...command, target: body.target.resource_kind,
        permissions: Object.freeze([...body.permissions])});
    }));
    if (new Set(installedCommands.map(item => item.commandRef)).size !==
        installedCommands.length) reject('InvalidInstalledRowEffectCommand');
    // STORE's checked Mapping resolves to a Command, but it remains a distinct
    // original selection purpose. Retain the exact published pair beside its
    // actual Command driver; a generic command or UPDATE flag is not STORE.
    const storeMappings = Object.freeze(declaredUpdate || !(owned as LegacyDriver).kinds.includes('command') ? [] :
      installed.filter(mapping => mapping.storeCommand !== undefined).map(mapping => {
        const pair = mapping.storeCommand!;
        const catalogs = JSON.parse(environmentWire).connector_catalogs as readonly Catalog[] | undefined;
        const commands = installedCommands.filter(command => command.commandRef === pair.command_ref &&
          command.commandCid === pair.command_contract_cid && command.resource === mapping.resource);
        const {mapping_contract_cid: self, ...body} = JSON.parse(mapping.body);
        if (Object.keys(pair).sort().join('\0') !==
            ['catalog_cid', 'command_contract_cid', 'command_ref'].join('\0') ||
            self !== mapping.mappingCid || cid(body) !== self || commands.length !== 1 ||
            !Array.isArray(catalogs) || catalogs.filter((catalog: Catalog) => catalog.catalog_cid === pair.catalog_cid &&
              catalog.commands.some(command => command.command_id === pair.command_ref &&
                command.contract_cid === pair.command_contract_cid)).length !== 1) {
          reject('InvalidInstalledRowEffectStoreMapping');
        }
        return mapping;
      }));
    let resourceTextUnits = 0;
    if (automatic || automaticUpdate) {
      for (const selected of installed) resourceTextUnits += selected.resource.length;
      for (const selected of installedCommands) resourceTextUnits += selected.resource.length;
    }
    const planRecipe = automaticUpdate ? prepareInstalledDeclaredUpdatePlanRecipe({moon, providerMoon,
      write: owned, credentialSite: installedRowCredentialOperationSite(site.credential),
      limits, resourceTextUnits, connectorRegistration} as UpdatePlanInput)
      : automatic ? prepareInstalledStandardCreatePlanRecipe({moon, providerMoon,
        construction, credentialSite: installedRowCredentialOperationSite(site.credential),
        limits: limits.preview, resourceTextUnits,
        requestInput:Object.freeze({maxWireBytes:limits.body.maxBytes,
          maxNodes:limits.body.maxNodes,maxDepth:limits.body.maxDepth})} as StandardPlanInput) : suppliedRecipe;
    const updateWriteSlot = automaticUpdate ? checkedUpdateWrite(planRecipe) : suppliedUpdateWrite;
    // The driver hook applies to each checked kind. A kind-specific recipe is
    // not the absent legacy recipe: require its own distinct finalization slot.
    for (const recipe of suppliedRecipes === undefined ? [planRecipe] : Object.values(suppliedRecipes)) {
      if (owned.finalizeRequest !== undefined &&
          (recipe?.requestFinalization === undefined ||
            recipe.requestFinalization.operationIndex === recipe.requestConstruction?.operationIndex)) {
        reject('InstalledEffectRequestFinalizationPlanUnavailable');
      }
    }
    const beforeSendCheck = automatic ? captureBeforeSendCheck(owned as LegacyDriver, planRecipe) : suppliedBeforeSendCheck;
    const responseConfirmation = captureResponseConfirmation(owned, planRecipe);
    await mkdir(ledgerRoot, {recursive: true, mode: 0o700});
    if (sourceInitialization !== undefined) {
      // The await may retire the installer. This local association check does
      // not invoke current or repeat Mapping/Environment admission.
      assertInstalledSourceConstruction(sourceInitialization, declaration, declared, environment, undefined, mappings, commands);
    }
    const adapter = createRowEffectStage([Object.freeze({moon, limits, owned, profile, updateWriteSlot,
      configuredMaxRows, configuredMaxMembers,
      installed, installedCommands, storeMappings, environmentWire, connectorId,
      connectorRegistration, connectorRevision, connection, site, authorization,
      runtimeBundleCid, bindingCid, ledgerRoot, continuationBinding, resources,
      managedPlanDefinition: planDefinition, managedPlanRecipe: planRecipe, managedPlanRecipes: suppliedRecipes,
      managedTargetPlanRecipes, beforeSendCheck, responseConfirmation,
      issueOriginalCollectionReference, sourceInitialization})], environmentWire);
    if (sourceInitialization !== undefined) {
      retainInstalledSourceConstruction(sourceInitialization, adapter, declaration, declared, environment);
    }
    return adapter;
  }

  return {installedRowEffectUnit, installedRowEffectDescriptors, createInstalledRowEffect};
}
