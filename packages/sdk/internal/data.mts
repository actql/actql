// Shared immutable data capture and comparison, without observation custody.
export const utf8 = new TextEncoder();

export const freezeInput = <const T,>(value: T): T => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value as Record<string, unknown>)) freezeInput(child);
    Object.freeze(value);
  }
  return value;
};

export const structuralKey = (value: unknown): string | undefined => value !== null && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(structuralKey).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + structuralKey((value as Record<string, unknown>)[key])).join(',') + '}'
  : JSON.stringify(value);

// Observe each enumerable response field once, before admission or branching.
// This is a data capture, not request JSON serialization: no toJSON/coercion,
// borrowed array methods, or repeated reads of shared nested response objects.
export type ResponsePrimitive = null | undefined | boolean | number | string;
export type ResponseData = ResponsePrimitive | ResponseData[] | {[key: string]: ResponseData};

export const captureResponse = (value: unknown,
  captured = new Map<object, ResponseData>()): ResponseData => {
  if (['function', 'symbol', 'bigint'].includes(typeof value)) {
    throw new TypeError('InvalidHostResponseData');
  }
  if (value === null || typeof value !== 'object') return value as ResponsePrimitive;
  if (captured.has(value)) return captured.get(value);
  const copy: ResponseData[] | {[key: string]: ResponseData} =
    Array.isArray(value) ? new Array<ResponseData>(value.length) : {};
  captured.set(value, copy);
  for (const key of Object.keys(value)) Object.defineProperty(copy, key, {
    value: captureResponse((value as Record<string, unknown>)[key], captured),
    enumerable: true, writable: true, configurable: true,
  });
  return copy;
};

export const positive = (value: unknown): boolean => Number.isSafeInteger(value) && (value as number) > 0;
