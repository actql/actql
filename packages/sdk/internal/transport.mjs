// One bounded Host transport. Dispatch tracking distinguishes local no-send
// from uncertain delivery; neither transport errors nor HTTP codes authorize retries.
import {boundedHostJson, controlValue} from './transport-response.mjs';
import {validConnectionStringCredential} from '../connection-string.mjs';
import {connectionFailure} from './connection-options.mjs';
import {ClientError, fail, ownedClientFailure, readRefusalCodes} from './errors.mjs';
import {retainCancellationExplanation} from './run-observation.mjs';
import {submissionNotSent, submissionUnknown} from './submission-observation.mjs';

export async function createTransport(selected, port, isClosed) {
  let directLoopback;
  if (selected.directLoopbackHttp) {
    try { ({requestLoopbackClient: directLoopback} = await import('#loopback-http')); }
    catch { fail('LoopbackHttpUnavailable'); }
    if (typeof directLoopback !== 'function') fail('LoopbackHttpUnavailable');
  }
  const dispatchedCancellations = new WeakSet();
  const dispatchedSubmissions = new WeakSet();
  const exchange = async (operation, body = {}, signal, submitContext, cancellationContext) => {
    if (isClosed()) fail('ClientClosed');
    if (port !== undefined) {
      let request;
      try { request = structuredClone({connection: selected.wire, ...body}); }
      catch { fail('InvalidClientPayload'); }
      try {
        if (cancellationContext !== undefined) {
          signal?.throwIfAborted();
          dispatchedCancellations.add(cancellationContext);
        }
        if ((operation === 'submit-intent' || operation === 'restart-intent')) {
          signal?.throwIfAborted();
          dispatchedSubmissions.add(submitContext);
        }
        const value = await port.perform(operation, request, signal);
        if (value instanceof Response) {
          throw retainCancellationExplanation(new ClientError('InvalidLocalHostPortResponse'),
            cancellationContext, 'outcome_unknown');
        }
        return value;
      }
      catch (cause) {
        if ((operation === 'submit-intent' || operation === 'restart-intent')) {
          if (!dispatchedSubmissions.has(submitContext)) {
            throw submissionNotSent(submitContext, cause);
          }
          throw submissionUnknown(submitContext, cause);
        }
        if (cause instanceof ClientError) {
          throw cause;
        }
        throw retainCancellationExplanation(ownedClientFailure('ClientTransportUnknown', {cause}),
          cancellationContext, 'outcome_unknown');
      }
    }
    let payload;
    try { payload = JSON.stringify({connection: selected.wire, ...body}); }
    catch { fail('InvalidClientPayload'); }
    if (typeof payload !== 'string') fail('InvalidClientPayload');
    let credential;
    try {
      credential = typeof selected.token === 'function'
        ? await selected.token() : selected.token;
    } catch (cause) {
      if (selected.redactCredentialErrors || operation === 'connect') {
        connectionFailure('ClientCredentialUnavailable',
          'The token provider could not supply a credential. Check the provider without logging its result or exception.');
      }
      throw cause;
    }
    if (selected.redactCredentialErrors ? !validConnectionStringCredential(credential)
      : typeof credential !== 'string' || !credential ||
        /[\r\n]/u.test(credential)) fail('InvalidConnectionToken');
    let response;
    if (cancellationContext !== undefined) {
      signal?.throwIfAborted();
      dispatchedCancellations.add(cancellationContext);
    }
    if ((operation === 'submit-intent' || operation === 'restart-intent')) {
      signal?.throwIfAborted();
      dispatchedSubmissions.add(submitContext);
    }
    try {
      let traceparent;
      try {
        // Correlation only: no baggage, tracestate, arbitrary header injection
        // or changed authorization/semantic request identity.
        const parent = selected.traceContext?.();
        const {traceId, spanId, traceFlags} = parent ?? {};
        if (typeof traceId === 'string' && /^[a-f0-9]{32}$/u.test(traceId) &&
            !/^0+$/u.test(traceId) && typeof spanId === 'string' && /^[a-f0-9]{16}$/u.test(spanId) &&
            !/^0+$/u.test(spanId) && Number.isInteger(traceFlags) &&
            traceFlags >= 0 && traceFlags <= 255) {
          traceparent = `00-${traceId}-${spanId}-${(traceFlags & 1)
            .toString(16).padStart(2, '0')}`;
        }
      } catch { /* Optional correlation cannot reject the request. */ }
      response = await (directLoopback ?? fetch)(new URL(
        `actql/client/0.1/${operation}`, selected.endpoint,
      ), {
        method: 'POST',
        headers: {authorization: `Bearer ${credential}`,
          ...(traceparent === undefined ? {} : {traceparent}),
          'content-type': 'application/json'},
        body: payload,
        signal,
        redirect: 'error',
      });
    } catch (cause) {
      if ((operation === 'submit-intent' || operation === 'restart-intent')) {
        throw submissionUnknown(submitContext,
          selected.redactCredentialErrors ? undefined : cause);
      }
      throw retainCancellationExplanation(ownedClientFailure('ClientTransportUnknown',
        selected.redactCredentialErrors || operation === 'connect' ? {} : {cause}),
          cancellationContext, 'outcome_unknown');
    }
    if (!response.ok) {
      let error;
      try { error = await boundedHostJson(response); } catch {}
      const code = typeof error?.code === 'string' &&
        /^[A-Za-z][A-Za-z0-9_]{0,79}$/u.test(error.code)
        ? error.code : `HostHTTP${response.status}`;
      if ((operation === 'submit-intent' || operation === 'restart-intent')) {
        throw submissionUnknown(submitContext, new ClientError(code));
      }
      if (operation === 'read' && readRefusalCodes.has(code)) {
        throw ownedClientFailure(code, {status: response.status});
      }
      throw new ClientError(code, {status: response.status});
    }
    return response;
  };
  const responseValue = async (response, maxWireBytes) => {
    try { return await controlValue(response, maxWireBytes); }
    catch (cause) {
      if (selected.redactCredentialErrors) throw new Error('InvalidHostControlResponse');
      throw cause;
    }
  };
  return {exchange, responseValue, typedRows: port !== undefined,
    wasSubmissionDispatched: context => dispatchedSubmissions.has(context),
    wasCancellationDispatched: context => dispatchedCancellations.has(context)};
}
