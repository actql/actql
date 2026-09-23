// Client-Host HTTP ingress. Authentication and connection consent are installed
// by the Host; Run meaning and read admission stay with the existing services.
import {inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {deliverAuthorizedResult,
  inspectAuthorizedDeliveryAttempt} from './result-access.mjs';

const operations = new Set(['connect', 'submit', 'attach',
  'lookup-request', 'status', 'wait', 'cancel', 'reconcile',
  'read', 'delivery-attempt']);
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
  [...keys].sort().join('\0');

function invalid(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}

async function boundedJson(request, maxBytes) {
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.byteLength;
    if (size > maxBytes) invalid('ClientRequestTooLarge');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { invalid('InvalidClientRequest'); }
}

function responseCode(error) {
  if (error?.code === 'RunStateAccessDenied' ||
      error?.code === 'ResultAccessDenied' ||
      error?.code === 'ResultDeliveryDenied' ||
      error?.code === 'ClientAuthenticationDenied' ||
      error?.code === 'ClientConnectionDenied') return 403;
  if (error?.code === 'ResultUnavailable') return 410;
  if (error?.code === 'ClientRequestTooLarge') return 413;
  if (error?.code === 'InvalidClientRequest' ||
      error?.code === 'InvalidRunStateRequest' ||
      error?.code === 'InvalidResultAccessRequest') return 400;
  if (error?.code === 'UnknownClientOperation') return 404;
  if (error?.code === 'ClientOperationUnavailable') return 501;
  if (error?.code === 'ResultAttemptLookupUnavailable') return 501;
  return 500;
}

function sendError(response, error) {
  if (response.headersSent) {
    response.destroy(error);
    return;
  }
  const status = responseCode(error);
  response.writeHead(status, {'content-type': 'application/json'});
  response.end(JSON.stringify({
    code: status === 500 ? 'ClientHostFailure' : error.code,
  }));
}

function write(response, bytes) {
  return new Promise((resolve, reject) => {
    if (response.destroyed) {
      reject(new Error('ClientDisconnected'));
      return;
    }
    response.write(bytes, error => error ? reject(error) :
      resolve({confirmedBytes: bytes.byteLength}));
  });
}

function finish(response, format) {
  return new Promise((resolve, reject) => {
    if (response.destroyed) {
      reject(new Error('ClientDisconnected'));
      return;
    }
    // A raw record separator cannot occur unescaped in JSON. It marks normal
    // transport completion without altering the MoonBit-owned payload digest.
    response.end(format === 'jsonl' ? Buffer.from([0x1e]) : undefined,
      error => error ? reject(error) :
      resolve({confirmed: true}));
  });
}

export function createClientHttpHandler({
  authenticate, authorizeConnection, stateService, resultService,
  negotiate, submit, attach, lookupRequest, observeRun, wait, cancel,
  reconcile, deliveryAttempt,
  maxRequestBytes = 65536,
}) {
  if (typeof authenticate !== 'function' ||
      typeof authorizeConnection !== 'function' ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0) {
    throw new TypeError('InvalidClientHostInstallation');
  }
  return async (request, response) => {
    try {
      if (request.method !== 'POST' ||
          !request.url?.startsWith('/actql/client/0.1/')) {
        invalid('UnknownClientOperation');
      }
      const operation = request.url.slice('/actql/client/0.1/'.length);
      if (!operations.has(operation)) invalid('UnknownClientOperation');
      if (request.headers['content-type'] !== 'application/json') {
        invalid('InvalidClientRequest');
      }
      let principal;
      try { principal = await authenticate(request.headers.authorization); }
      catch { invalid('ClientAuthenticationDenied'); }
      if (typeof principal !== 'string' || principal.length === 0) {
        invalid('ClientAuthenticationDenied');
      }
      const body = await boundedJson(request, maxRequestBytes);
      const bodyKeys = {
        connect: ['connection'],
        submit: ['connection', 'requestId', 'kind', 'input', 'parameters'],
        attach: ['connection', 'ref'],
        'lookup-request': ['connection', 'requestId'],
        status: ['connection', 'ref'],
        wait: ['connection', 'ref', 'until'],
        cancel: ['connection', 'ref'],
        reconcile: ['connection', 'ref'],
        read: ['connection', 'ref', 'resultName', 'format', 'attemptId'],
        'delivery-attempt': ['connection', 'ref', 'resultName', 'attemptId'],
      }[operation];
      if (!exact(body, bodyKeys) ||
          typeof body.connection !== 'object' ||
          body.connection === null || Array.isArray(body.connection) ||
          typeof body.connection.mode !== 'string' ||
          typeof body.connection.owner !== 'string' ||
          !Array.isArray(body.connection.runners) ||
          !Array.isArray(body.connection.consentRefs)) {
        invalid('InvalidClientRequest');
      }
      let authorized;
      try {
        authorized = await authorizeConnection(Object.freeze({
          principalId: principal,
          connection: body.connection,
          ref: body.ref,
          operation,
        }));
      } catch { authorized = false; }
      if (authorized !== true) invalid('ClientConnectionDenied');
      const invoke = async (handler, name) => {
        if (typeof handler !== 'function') invalid('ClientOperationUnavailable');
        return handler(Object.freeze({
          principalId: principal,
          connection: body.connection,
          ...Object.fromEntries(Object.entries(body)
            .filter(([key]) => key !== 'connection')),
        }));
      };
      const sendJson = value => {
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify(value));
      };
      if (operation === 'connect') {
        sendJson(await invoke(negotiate));
      } else if (operation === 'submit') {
        sendJson(await invoke(submit));
      } else if (operation === 'attach') {
        sendJson(await invoke(attach));
      } else if (operation === 'lookup-request') {
        sendJson(await invoke(lookupRequest));
      } else if (operation === 'status') {
        const state = observeRun === undefined
          ? await inspectAuthorizedRunState(stateService, {
          indexKey: body.ref,
          principalId: principal,
          purpose: 'inspect',
        }) : await invoke(observeRun);
        sendJson(state);
      } else if (operation === 'wait') {
        sendJson(await invoke(wait));
      } else if (operation === 'cancel') {
        sendJson(await invoke(cancel));
      } else if (operation === 'reconcile') {
        sendJson(await invoke(reconcile));
      } else if (operation === 'delivery-attempt') {
        sendJson(deliveryAttempt === undefined
          ? await inspectAuthorizedDeliveryAttempt(resultService, {
            indexKey: body.ref,
            principalId: principal,
            purpose: 'download',
            resultName: body.resultName,
            attemptId: body.attemptId,
          }) : await invoke(deliveryAttempt));
      } else {
        if (!['json', 'jsonl', 'csv'].includes(body.format)) {
          invalid('InvalidClientRequest');
        }
        const contentType = {
          json: 'application/json',
          jsonl: 'application/x-ndjson',
          csv: 'text/csv',
        }[body.format];
        const begin = () => {
          if (!response.headersSent) {
            response.writeHead(200, {'content-type': contentType});
          }
        };
        const controller = new AbortController();
        response.once('close', () => {
          if (!response.writableEnded) controller.abort();
        });
        await deliverAuthorizedResult(resultService, {
          indexKey: body.ref,
          principalId: principal,
          purpose: 'download',
          resultName: body.resultName,
          format: body.format,
          attemptId: body.attemptId,
        }, {
          write: bytes => { begin(); return write(response, bytes); },
          finish: () => { begin(); return finish(response, body.format); },
        }, controller.signal);
      }
    } catch (error) {
      sendError(response, error);
    }
  };
}
