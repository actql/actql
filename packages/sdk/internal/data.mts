// Shared immutable data capture and comparison, without observation custody.
export const utf8 = new TextEncoder();

export const freezeInput = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freezeInput(child);
    Object.freeze(value);
  }
  return value;
};

export const structuralKey = value => value !== null && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(structuralKey).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + structuralKey(value[key])).join(',') + '}'
  : JSON.stringify(value);

// Observe each enumerable response field once, before admission or branching.
// This is a data capture, not request JSON serialization: no toJSON/coercion,
// borrowed array methods, or repeated reads of shared nested response objects.
export const captureResponse = (value, captured = new Map()) => {
  if (['function', 'symbol', 'bigint'].includes(typeof value)) {
    throw new TypeError('InvalidHostResponseData');
  }
  if (value === null || typeof value !== 'object') return value;
  if (captured.has(value)) return captured.get(value);
  const copy = Array.isArray(value) ? new Array(value.length) : {};
  captured.set(value, copy);
  for (const key of Object.keys(value)) Object.defineProperty(copy, key, {
    value: captureResponse(value[key], captured),
    enumerable: true, writable: true, configurable: true,
  });
  return copy;
};

export const positive = value => Number.isSafeInteger(value) && value > 0;
