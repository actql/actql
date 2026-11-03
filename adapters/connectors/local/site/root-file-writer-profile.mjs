// Capture inert implementation DATA once from the selected native image. This
// supplies no path handle, physical attempt, permission or caller allowance.
import {types as nodeTypes} from 'node:util';
const fail = () => {throw Object.assign(new Error('LocalFileWriteConstructionUnavailable'),
  {code: 'LocalFileWriteConstructionUnavailable'});};
const names = ['nativeOriginalBytes', 'maxRootBytes', 'maxNameBytes', 'maxDepth', 'writeQuantumBytes'];

export function captureLocalFileWriteConstructionProfile(native) {
  if (native === null || typeof native !== 'object' || nodeTypes.isProxy(native)) fail();
  const field = Object.getOwnPropertyDescriptor(native, 'localFileWriteConstructionProfile');
  const method = field && Object.hasOwn(field, 'value') ? field.value : undefined;
  if (typeof method !== 'function' || nodeTypes.isProxy(method) || nodeTypes.isAsyncFunction(method)) fail();
  const original = Reflect.apply(method, native, []);
  if (original === null || typeof original !== 'object' || nodeTypes.isProxy(original) ||
      !Object.isFrozen(original)) fail();
  const fields = Object.getOwnPropertyDescriptors(original);
  if (Reflect.ownKeys(fields).length !== names.length) fail();
  const profile = {};
  for (const name of names) {
    const value = fields[name]?.value;
    if (!Object.hasOwn(fields[name] ?? {}, 'value') ||
        !Number.isSafeInteger(value) || value < 1 || value > 2147483647) fail();
    profile[name] = value;
  }
  return Object.freeze(profile);
}
