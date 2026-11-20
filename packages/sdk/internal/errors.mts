// SDK-owned error classification. Borrowed exceptions do not acquire it.
export class ClientError extends Error {
  constructor(code, details = {}) {
    super(code, details.cause === undefined ? undefined : {cause: details.cause});
    this.code = code;
    Object.assign(this, details);
  }
}

// A durably held request is not an unknown submission or a retry instruction.
// Keep the public class original available without loading execution modules.
export class RequestHeld extends ClientError {
  constructor(held, lookupContext) {
    super('RequestHeld', {requestId: held.requestId, held, lookupContext});
  }
}

const ownedClientFailures = new WeakMap();

export const readRefusalCodes = new Set(['ResultAccessDenied', 'ClientAuthenticationDenied']);

export const ownedClientFailure = (code, details) => {
  const error = new ClientError(code, details);
  ownedClientFailures.set(error, code);
  return error;
};

export const fail = code => { throw ownedClientFailure(code); };

export const requestCancellationCause = cause => {
  // Preserve only already public Client metadata, not borrowed source or
  // credential messages, nested causes, locators or cleanup handles.
  const code = cause instanceof ClientError ? cause.code : 'ClientTransportUnknown';
  const status = cause instanceof ClientError ? cause.status : undefined;
  return new ClientError(code,
    Number.isInteger(status) && status >= 100 && status <= 599 ? {status} : {});
};

export const isOwnedClientFailure = error => ownedClientFailures.has(error);
export const ownedFailureCode = error => ownedClientFailures.get(error);
export const markOwnedFailure = (error, code) => ownedClientFailures.set(error, code);
