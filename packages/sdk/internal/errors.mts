import type {ClientError as PublicClientError, HeldRequest} from '../index.d.ts';

export interface ClientError extends PublicClientError {}

export type ClientErrorDetails = {cause?: unknown; [key: string]: unknown};

// SDK-owned error classification. Borrowed exceptions do not acquire it.
export class ClientError extends Error {
  declare readonly code: string;

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

  constructor(held: HeldRequest, lookupContext: PublicClientError['lookupContext']) {
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
