import type {StandardSchemaV1} from './standard-schema.d.ts';

type SchemaErrorConstructor = new(code: string) => Error;
interface UncheckedStandard {version?: unknown; vendor?: unknown; validate?: unknown}
export interface CapturedResultRead {
  readonly options: unknown;
  readonly validate?: (value: unknown) => unknown;
}
export type ValidationOutcome =
  | {kind: 'invalid_result'}
  | {kind: 'issues'; issues: readonly StandardSchemaV1.Issue[]}
  | {kind?: never; value: unknown};

// Read options and the selected validation method belong to the invocation,
// including a query shortcut that waits for credentials or Run observation.
export function captureReadOptions(options: unknown): unknown {
  if (options === null || typeof options !== 'object' &&
      typeof options !== 'function' || Array.isArray(options)) return options;
  // Ordinary property access preserves class, inherited and hidden ceilings.
  return Object.freeze(Object.fromEntries(['signal', 'maxWireBytes',
    'maxRowWireBytes', 'maxRowRetainedValueBytes', 'maxRows',
    'maxRetainedValueBytes', 'maxBatchRows', 'maxBatchRetainedValueBytes']
    .map(name => [name, (options as Record<string, unknown>)[name]])));
}

export function captureResultRead(ClientError: SchemaErrorConstructor, schemaOrOptions: unknown,
  options?: unknown): CapturedResultRead {
  const object = schemaOrOptions !== null &&
    ['object', 'function'].includes(typeof schemaOrOptions);
  let typed;
  try { typed = options !== undefined || object && '~standard' in (schemaOrOptions as object); }
  catch { throw new ClientError('InvalidResultSchema'); }
  if (!typed) {
    return Object.freeze({options: captureReadOptions(
      schemaOrOptions === undefined ? {} : schemaOrOptions)});
  }
  let standard: UncheckedStandard | null | undefined, validate: unknown;
  try {
    standard = (schemaOrOptions as Record<string, unknown> | null | undefined)?.['~standard'] as UncheckedStandard | null | undefined;
    validate = standard?.validate;
    if (standard?.version !== 1 || typeof standard.vendor !== 'string' ||
        typeof validate !== 'function') throw new Error('Invalid standard');
  } catch {
    throw new ClientError('InvalidResultSchema');
  }
  return Object.freeze({options: captureReadOptions(options === undefined ? {} : options),
    validate: (value: unknown) => Reflect.apply(validate as (value: unknown) => unknown, standard, [value])});
}

// Aborting the wait releases the reader owner even if application code returns
// a never-settling Promise. It cannot stop arbitrary JavaScript or its effects.
export function awaitValidation<T>(value: T | PromiseLike<T>, signal: AbortSignal): Promise<Awaited<T>> {
  return new Promise<Awaited<T>>((resolve, reject) => {
    const abort = () => { signal.removeEventListener('abort', abort); reject(signal.reason); };
    signal.addEventListener('abort', abort, {once: true});
    if (signal.aborted) abort();
    Promise.resolve(value).then(result => {
      signal.removeEventListener('abort', abort);
      resolve(result);
    }, cause => {
      signal.removeEventListener('abort', abort);
      reject(cause);
    });
  });
}

export function validationOutcome(result: unknown): ValidationOutcome {
  if (result === null || typeof result !== 'object' || Array.isArray(result)) {
    return {kind: 'invalid_result'};
  }
  const issues = (result as {issues?: unknown}).issues;
  if (issues !== undefined) {
    // Empty issues is still a failure under Standard Schema. Validate the
    // diagnostic shape, but do not serialize outputs, paths or thrown values.
    if (!Array.isArray(issues) || !issues.every((issue: unknown) => issue !== null &&
        typeof issue === 'object' && typeof (issue as {message?: unknown}).message === 'string' &&
        ((issue as {path?: readonly unknown[]}).path === undefined || Array.isArray((issue as {path?: readonly unknown[]}).path) &&
          (issue as {path: readonly unknown[]}).path.every((part: unknown) => ['string', 'number', 'symbol'].includes(typeof part) ||
            part !== null && typeof part === 'object' &&
            ['string', 'number', 'symbol'].includes(typeof (part as {key?: unknown}).key))))) {
      return {kind: 'invalid_result'};
    }
    return {kind: 'issues', issues} as ValidationOutcome;
  }
  if (!('value' in result)) return {kind: 'invalid_result'};
  // Keep any output, even a Promise/thenable, boxed through async plumbing.
  return {value: (result as {value: unknown}).value};
}
