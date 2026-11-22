import {types as nodeTypes} from 'node:util';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

type PhysicalTarget = Readonly<{
  [key: string]: string | readonly string[];
  resource: string;
  fields: readonly string[];
}>;

const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;

// Private standard installation DATA, not a callback-currentness promise.
// Callback targets keep their original full revalidation below, even when a
// callback happens to return a frozen object. No public or restored wire can
// replace an original prepared target through this constructor input.
export function prepareImmutablePhysicalTargets(value: unknown) {
  if (typeof value === 'function') return undefined;
  const mismatch: () => never = () => fail('InstalledSourcePreparationMismatch');
  const arrayValues = (input: unknown): readonly unknown[] => {
    if (!Array.isArray(input) || nodeTypes.isProxy(input) || !Object.isFrozen(input) ||
        Object.getPrototypeOf(input) !== Array.prototype) mismatch();
    const length = Object.getOwnPropertyDescriptor(input, 'length')!.value as number;
    if (Reflect.ownKeys(input).length !== length + 1) mismatch();
    for (let index = 0; index < length; index++) {
      const property = Object.getOwnPropertyDescriptor(input, index);
      if (!property || !Object.hasOwn(property, 'value')) mismatch();
    }
    return input;
  };
  const resources = new Set<string>();
  const inventory = arrayValues(value) as readonly PhysicalTarget[];
  for (const input of inventory) {
    if (input === null || typeof input !== 'object' || nodeTypes.isProxy(input) ||
        !Object.isFrozen(input) || Object.getPrototypeOf(input) !== Object.prototype) mismatch();
    for (const key of Reflect.ownKeys(input)) {
      const property = Object.getOwnPropertyDescriptor(input, key)!;
      if (typeof key !== 'string' || !Object.hasOwn(property, 'value') ||
          !property.enumerable || key !== 'fields' && typeof property.value !== 'string') mismatch();
    }
    if (!text(input.resource) || resources.has(input.resource) || !Object.hasOwn(input, 'fields')) mismatch();
    const fields = arrayValues(input.fields);
    if (fields.some(field => !text(field)) || new Set(fields).size !== fields.length) mismatch();
    resources.add(input.resource);
  }
  if (inventory.length === 0) mismatch();
  resources.clear();
  // The existing Source constructor already retains these exact immutable
  // outputs. Do not allocate another inventory, target Map or field arrays.
  return Object.freeze({inventory, prepare(resource: string, fields: readonly string[]) {
    const target = inventory.find(target => target.resource === resource);
    if (target === undefined || !Array.isArray(fields) || new Set(fields).size !== fields.length ||
        fields.some(field => !target.fields.includes(field))) mismatch();
    return Object.freeze({...target, fields: Object.freeze([...fields])});
  }});
}
