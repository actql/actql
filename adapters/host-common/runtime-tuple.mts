import {runtimeField} from './compiler-binding.generated.mjs';

// Preserve an existing JS tuple array, or read the two compiler fields.
export const tuplePair = (value: unknown): readonly unknown[] | undefined => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [runtimeField(value, 0), runtimeField(value, 1)]
    : undefined;
