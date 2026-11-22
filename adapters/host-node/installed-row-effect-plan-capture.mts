import {types as nodeTypes} from 'node:util';

type Operation<Role extends string> = Readonly<{role: Role; operation: string}>;
type ManagedPlanDefinition = Readonly<{memberOperations: readonly []}> & (
  Readonly<{kind: 'update'; rowOperations: readonly [Operation<'target-read'>, Operation<'write'>]}> |
  Readonly<{kind: 'command'; rowOperations: readonly [Operation<'write'>]}>
);
type DefinitionDriver = Readonly<{kinds: readonly string[]; targetRead?: Readonly<{operation: string}>}>;
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

  return {captureManagedPlanDefinition, captureManagedDriverConstruction};
}
