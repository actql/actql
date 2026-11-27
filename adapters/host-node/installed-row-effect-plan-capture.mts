import {types as nodeTypes} from 'node:util';
import {effectLedgerImplementationBounds} from './effect-ledger-implementation-bounds.mjs';
import {captureInstalledEffectPlanRecipe, installedEffectRecipeForControlEntryLimit} from './installed-effect-recipe.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';

type Operation<Role extends string> = Readonly<{role: Role; operation: string}>;
type ManagedPlanDefinition = Readonly<{memberOperations: readonly []}> & (
  Readonly<{kind: 'update'; rowOperations: readonly [Operation<'target-read'>, Operation<'write'>]}> |
  Readonly<{kind: 'command'; rowOperations: readonly [Operation<'write'>]}>
);
type DefinitionDriver = Readonly<{kinds: readonly string[]; targetRead?: Readonly<{operation: string}>}>;
type CapturedRecipes = Readonly<Partial<Record<string, InstalledEffectPlanRecipe>>>;
type TargetRecipe = Readonly<{
  recipe: InstalledEffectPlanRecipe;
  fallback: InstalledEffectPlanRecipe | undefined;
  entryLimit: number;
  responseLimit: number;
  writeOperation: string;
  targetReadOperation: string | undefined;
}>;
type PreparedTargetRecipes = Readonly<{
  byMapping: Readonly<Partial<Record<string, TargetRecipe>>>;
  maxEntryBytes: number;
  maxResponseBytes: number;
}>;
type CommandConstruction = Readonly<{
  write: Readonly<{operation: string; maxRequestBytes: number; maxResponseBytes: number}>;
  check: undefined;
  metadataTextUnits: number;
}>;
type CaptureOptions = Readonly<{
  fail(code: string): never;
  text(value: unknown): value is string;
}>;

export function createInstalledRowEffectPlanCapture({fail, text}: CaptureOptions) {
  const reject: CaptureOptions['fail'] = fail;

  // Closed operation-name DATA from the same installed provider. This keeps the
  // original descriptor; it neither counts physical calls nor supplies capacity.
  function captureManagedPlanDefinition(definition: unknown, driver: DefinitionDriver): ManagedPlanDefinition | undefined {
    if (definition === undefined) return undefined;
    const fields = (value: unknown, names: readonly string[]) => {
      if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
          !Object.isFrozen(value)) fail('InvalidInstalledEffectPlanDefinition');
      const descriptors = Object.getOwnPropertyDescriptors(value);
      if (Reflect.ownKeys(descriptors).length !== names.length ||
          names.some(name => !Object.hasOwn(descriptors[name] ?? {}, 'value'))) {
        fail('InvalidInstalledEffectPlanDefinition');
      }
      return descriptors;
    };
    const selected = fields(definition, ['kind', 'memberOperations', 'rowOperations']);
    const kind: string = selected.kind.value;
    if (!['update', 'command'].includes(kind) || !driver.kinds.includes(kind)) {
      fail('InvalidInstalledEffectPlanDefinition');
    }
    const roles = kind === 'update' ? ['target-read', 'write'] : ['write'];
    for (const [name, expected] of [['memberOperations', []], ['rowOperations', roles]] as const) {
      const original = selected[name].value;
      if (!Array.isArray(original) || nodeTypes.isProxy(original) ||
          !Object.isFrozen(original) || original.length !== expected.length) {
        fail('InvalidInstalledEffectPlanDefinition');
      }
      const array = fields(original, ['length', ...expected.map((_, index) => String(index))]);
      for (let index = 0; index < expected.length; index++) {
        const operation = fields(array[String(index)].value, ['role', 'operation']);
        if (operation.role.value !== expected[index] || !text(operation.operation.value) ||
            !operation.operation.value.isWellFormed() ||
            expected[index] === 'target-read' && operation.operation.value !== driver.targetRead?.operation) {
          fail('InvalidInstalledEffectPlanDefinition');
        }
      }
    }
    return definition as ManagedPlanDefinition;
  }

  // A retained-request Command supplies the SAME constructor metadata and
  // native profile held by its actual driver. The existing standard composer
  // then owns capture/request/HTTP/recovery quantities; this introduces no
  // alternative calculator, row count, reservation, permission or cleanup owner.
  function captureManagedDriverConstruction(construction: unknown, definition: ManagedPlanDefinition | undefined,
      driver: Pick<DefinitionDriver, 'kinds'>, provider: unknown): CommandConstruction | undefined {
    if (construction === undefined) return undefined;
    const own = (value: unknown, names: readonly string[]) => {
      if (!value || typeof value !== 'object' || nodeTypes.isProxy(value) || !Object.isFrozen(value)) {
        fail('InvalidInstalledEffectDriverConstruction');
      }
      const fields = Object.getOwnPropertyDescriptors(value);
      if (Reflect.ownKeys(fields).length !== names.length || names.some(name =>
        !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('InvalidInstalledEffectDriverConstruction');
      return fields;
    };
    if (definition?.kind !== 'command' || driver.kinds.length !== 1 || driver.kinds[0] !== 'command' ||
        Object.getOwnPropertyDescriptor(driver,'managedPlanDefinition')?.value !== definition ||
        Object.getOwnPropertyDescriptor(driver,'managedPlanConstruction')?.value !== construction ||
        Object.getOwnPropertyDescriptor(driver,'managedPlanProvider')?.value !== provider) {
      fail('InvalidInstalledEffectDriverConstruction');
    }
    const fields = own(construction,['write','check','metadataTextUnits']);
    const write = own(fields.write.value,['operation','maxRequestBytes','maxResponseBytes']);
    if (fields.check.value !== undefined || write.operation.value !== definition!.rowOperations[0].operation ||
        ![write.maxRequestBytes.value,write.maxResponseBytes.value].every(value =>
          Number.isSafeInteger(value) && value > 0 && value <= 2147483647) ||
        !Number.isSafeInteger(fields.metadataTextUnits.value) || fields.metadataTextUnits.value < 0) {
      fail('InvalidInstalledEffectDriverConstruction');
    }
    return construction as CommandConstruction;
  }

  // An installed provider may implement several existing write kinds. Each
  // immutable recipe retains that kind's actual operation strings/extents; a
  // create, update and upsert never borrow one another's credential occurrence.
  // Selection below uses the checked member kind, not provider DATA or a label.
  function captureManagedPlanRecipes(recipes: unknown, driver: Pick<DefinitionDriver, 'kinds'>,
      maxOperations: number): CapturedRecipes | undefined {
    if (recipes === undefined) return undefined;
    if (recipes === null || typeof recipes !== 'object' || nodeTypes.isProxy(recipes) ||
        !Object.isFrozen(recipes)) reject('InvalidInstalledEffectPlanRecipe');
    const fields = Object.getOwnPropertyDescriptors(recipes);
    const supportedKinds = driver.kinds;
    if (Reflect.ownKeys(fields).length !== supportedKinds.length || supportedKinds.some(kind =>
      !Object.hasOwn(fields[kind] ?? {}, 'value') || fields[kind].value === undefined)) {
      reject('InvalidInstalledEffectPlanRecipe');
    }
    return Object.freeze(Object.fromEntries(supportedKinds.map(kind => {
      const recipe = captureInstalledEffectPlanRecipe(fields[kind].value, maxOperations);
      if (kind !== 'upsert' && recipe?.credentialOperations?.some(entry =>
        entry.phase === 'write' && entry.slot !== undefined)) reject('InvalidInstalledEffectPlanRecipe');
      return [kind, recipe];
    })));
  }

  // The installer calls this while its original Source constructor still holds
  // the table and normalization workspace. Capture both control variants now
  // so a later single or composed stage only borrows the selected recipe.
  function prepareInstalledTargetPlanRecipes(mappings: unknown, recipes: unknown, cidPattern: RegExp,
      localContractLimits: Readonly<{maxNodes: number}>,
      managedTargetPlanOriginals: WeakMap<PreparedTargetRecipes, readonly unknown[]>): PreparedTargetRecipes {
    if (recipes === null || typeof recipes !== 'object' || nodeTypes.isProxy(recipes) ||
        !Object.isFrozen(recipes) || !Array.isArray(mappings) || nodeTypes.isProxy(mappings) ||
        !Object.isFrozen(mappings) || mappings.length === 0) {
      reject('InvalidInstalledEffectPlanRecipe');
    }
    const fields = Object.getOwnPropertyDescriptors(recipes),
      retained: Partial<Record<string, TargetRecipe>> = Object.create(null);
    if (Reflect.ownKeys(fields).length !== mappings.length) reject('InvalidInstalledEffectPlanRecipe');
    let maxEntryBytes = 0, maxResponseBytes = 0;
    for (const mapping of mappings) {
      if (mapping === null || typeof mapping !== 'object' || nodeTypes.isProxy(mapping) ||
          !Object.isFrozen(mapping)) reject('InvalidInstalledEffectPlanRecipe');
      const identity = Object.getOwnPropertyDescriptor(mapping, 'mappingCid');
      const mappingCid: unknown = identity?.value;
      if (!text(mappingCid) || !cidPattern.test(mappingCid)) reject('InvalidInstalledEffectPlanRecipe');
      const value = Object.hasOwn(fields[mappingCid] ?? {}, 'value') ? fields[mappingCid].value : undefined;
      if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
          !Object.isFrozen(value) || Object.hasOwn(retained, mappingCid)) {
        reject('InvalidInstalledEffectPlanRecipe');
      }
      const entry = Object.getOwnPropertyDescriptors(value);
      const read = entry.targetReadOperation, operation: unknown = read?.value;
      if (Reflect.ownKeys(entry).length !== 2 || !Object.hasOwn(read ?? {}, 'value') ||
          (operation !== undefined && (!text(operation) || !operation.isWellFormed())) ||
          !Object.hasOwn(entry.recipe ?? {}, 'value')) reject('InvalidInstalledEffectPlanRecipe');
      const recipe = captureInstalledEffectPlanRecipe(entry.recipe.value, localContractLimits.maxNodes);
      if (recipe === undefined || recipe.physicalWrite === undefined) reject('InvalidInstalledEffectPlanRecipe');
      const writeOperation = recipe.rowOperations[recipe.physicalWrite.operationIndex]?.operation;
      const reads = recipe.ownedReadOperations;
      if (!text(writeOperation) || (operation === undefined ? reads !== undefined :
          reads?.length !== 3 || reads.some(read =>
            recipe.rowOperations[read.operationIndex].operation !== operation + '.' + read.phase))) {
        reject('InvalidInstalledEffectPlanRecipe');
      }
      const entryLimit = recipe.savedControlCodec?.maxEntryBytes ?? effectLedgerImplementationBounds.maxEntryBytes;
      const responseLimit = recipe.savedControlCodec?.maxResponseBytes ?? effectLedgerImplementationBounds.maxResponseBytes;
      const fallback = installedEffectRecipeForControlEntryLimit(recipe,
        effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes);
      maxEntryBytes = Math.max(maxEntryBytes, entryLimit);
      maxResponseBytes = Math.max(maxResponseBytes, responseLimit);
      retained[mappingCid] = Object.freeze({recipe, fallback, entryLimit, responseLimit,
        writeOperation, targetReadOperation: operation});
    }
    const prepared = Object.freeze({byMapping: Object.freeze(retained), maxEntryBytes, maxResponseBytes});
    managedTargetPlanOriginals.set(prepared, mappings);
    return prepared;
  }

  return {captureManagedPlanDefinition, captureManagedDriverConstruction, captureManagedPlanRecipes,
    prepareInstalledTargetPlanRecipes};
}
