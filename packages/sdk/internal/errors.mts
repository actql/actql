import type {CancellationReference, Execution, HeldRequest, ResultReference, RunReference, RunState, SignedCheckpointAnswer,
  StandardSchemaV1} from '../index.mjs';
import type {WireOperationAttemptRef} from '@actql/client-wire';

export type ClientErrorDetails = {cause?: unknown; [key: string]: unknown};

// SDK-owned error classification. Borrowed exceptions do not acquire it.
export class ClientError extends Error {
  declare readonly code: string;
  declare readonly hint?: string;
  declare readonly requestId?: string;
  declare readonly attemptId?: string;
  /** Present only after a Run was admitted; never fabricated for RequestHeld. */
  declare readonly execution?: Execution;
  declare readonly executionRef?: RunReference;
  /** Exact owner observation on a short query failure; omitted from JSON. */
  declare readonly observation?: RunState;
  /** Original immutable cancellation target on uncertainty or refusal. */
  declare readonly cancelRef?: Readonly<CancellationReference>;
  declare readonly attemptRef?: Readonly<WireOperationAttemptRef>;
  /** Complete rows returned by the failed call; aggregate calls return none. */
  declare readonly rowsYielded?: number;
  /** Local schema validation failure; the Run itself is unchanged. */
  declare readonly validationKind?: 'issues' | 'exception' | 'invalid_result';
  /** Zero-based index of the raw row that failed validation. */
  declare readonly rowIndex?: number;
  declare readonly resultRef?: ResultReference;
  /** Explicit schema diagnostics, omitted from default JSON serialization. */
  declare readonly issues?: readonly StandardSchemaV1.Issue[];
  declare readonly cleanupError?: unknown;
  /** Client cleanup has not confirmed release; retry await client.close(). */
  declare readonly cleanupPending?: boolean;
  declare readonly lookupContext?: Readonly<{endpoint: string; scopeRef: string}>;
  declare readonly status?: number;
  // ResolutionUnknown: the exact signed answers to resend unchanged.
  declare readonly signed?: readonly SignedCheckpointAnswer[];

  constructor(code: string, details: ClientErrorDetails = {}) {
    super(code, details.cause === undefined ? undefined : {cause: details.cause});
    this.code = code;
    Object.assign(this, details);
  }
}

// A durably held request is not an unknown submission or a retry instruction.
// Keep the public class original available without loading execution modules.
export class RequestHeld extends ClientError {
  declare readonly code: 'RequestHeld';
  declare readonly requestId: string;
  declare readonly held: HeldRequest;

  constructor(held: HeldRequest, lookupContext: ClientError['lookupContext']) {
    super('RequestHeld', {requestId: held.requestId, held, lookupContext});
  }
}

const ownedClientFailures = new WeakMap<object, string>();

export const readRefusalCodes = new Set(['ResultAccessDenied', 'ClientAuthenticationDenied']);

export const ownedClientFailure = (code: string, details?: ClientErrorDetails) => {
  const error = new ClientError(code, details);
  ownedClientFailures.set(error, code);
  return error;
};

export const fail: (code: string) => never = code => { throw ownedClientFailure(code); };

export const requestCancellationCause = (cause: unknown): ClientError => {
  // Preserve only already public Client metadata, not borrowed source or
  // credential messages, nested causes, locators or cleanup handles.
  const code = cause instanceof ClientError ? cause.code : 'ClientTransportUnknown';
  const status = cause instanceof ClientError ? cause.status : undefined;
  return new ClientError(code,
    Number.isInteger(status) && (status as number) >= 100 && (status as number) <= 599 ? {status} : {});
};

export const isOwnedClientFailure = (error: unknown): boolean => ownedClientFailures.has(error as object);
export const ownedFailureCode = (error: unknown): string | undefined => ownedClientFailures.get(error as object);
export const markOwnedFailure = (error: object, code: string) => ownedClientFailures.set(error, code);
