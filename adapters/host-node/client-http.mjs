// Client-Host HTTP ingress. Authentication and connection consent are installed
// by the Host; Run meaning and read admission stay with the existing services.
import {inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {deliverAuthorizedResult,
  inspectAuthorizedDeliveryAttempt} from './result-access.mjs';

const operations = new Set(['connect', 'submit', 'attach',
  'lookup-request', 'status', 'wait', 'cancel', 'reconcile',
  'read', 'delivery-attempt']);
const cid = /^sha256:[0-9a-f]{64}$/u;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
  [...keys].sort().join('\0');
const boundedText = (value, maximum = 256) => typeof value === 'string' &&
  value.length > 0 && value.length <= maximum &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const refs = value => Array.isArray(value) &&
  value.every(item => boundedText(item)) &&
  new Set(value).size === value.length;
const runRef = value => exact(value, [
  'tenantId', 'authorityScopeCid', 'runDefinitionCid',
]) && boundedText(value.tenantId) && cid.test(value.authorityScopeCid) &&
  cid.test(value.runDefinitionCid);

function validConnection(value) {
  if (value === null || typeof value !== 'object' ||
      Array.isArray(value)) return false;
  const required = ['mode', 'owner', 'consentRefs', 'runners'];
  const allowed = new Set([...required, 'durability', 'movementPolicyRef']);
  if (required.some(key => !Object.hasOwn(value, key)) ||
      Object.keys(value).some(key => !allowed.has(key)) ||
      !(value.mode === 'remote' && value.owner === 'remote' ||
        value.mode === 'local' && value.owner === 'local' ||
        value.mode === 'hybrid' && ['local', 'cloud'].includes(value.owner)) ||
      !refs(value.consentRefs) || !refs(value.runners) ||
      value.durability !== undefined &&
        !['volatile', 'durable'].includes(value.durability)) return false;
  return value.mode === 'hybrid'
    ? boundedText(value.movementPolicyRef)
    : value.movementPolicyRef === undefined && value.runners.length === 0;
}

function validBody(operation, body) {
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
  if (!exact(body, bodyKeys) || !validConnection(body.connection)) {
    return false;
  }
  if (operation === 'connect') return true;
  if (operation === 'submit') {
    return boundedText(body.requestId) &&
      (body.kind === 'aql' && exact(body.input, ['text', 'format']) &&
        typeof body.input.text === 'string' &&
        body.input.text.length > 0 && body.input.text.length <= 65536 &&
        !body.input.text.includes('\u0000') &&
        ['json', 'yaml'].includes(body.input.format) ||
        body.kind === 'program' && body.input !== null &&
        typeof body.input === 'object' && !Array.isArray(body.input));
  }
  if (operation === 'lookup-request') return boundedText(body.requestId);
  if (!runRef(body.ref)) return false;
  if (operation === 'read') return boundedText(body.resultName) &&
    boundedText(body.attemptId) &&
    ['json', 'jsonl', 'csv'].includes(body.format);
  if (operation === 'delivery-attempt') return boundedText(body.resultName) &&
    boundedText(body.attemptId);
  if (operation === 'wait') return body.until === null ||
    boundedText(body.until, 128);
  return true;
}

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
      if (!validBody(operation, body)) invalid('InvalidClientRequest');
      const connection = Object.freeze({...body.connection,
        consentRefs: Object.freeze([...body.connection.consentRefs]),
        runners: Object.freeze([...body.connection.runners])});
      const ref = body.ref === undefined ? undefined :
        Object.freeze({...body.ref});
      let authorized;
      try {
        authorized = await authorizeConnection(Object.freeze({
          principalId: principal,
          connection, ref,
          operation,
        }));
      } catch { authorized = false; }
      if (authorized !== true) invalid('ClientConnectionDenied');
      const invoke = async (handler, name) => {
        if (typeof handler !== 'function') invalid('ClientOperationUnavailable');
        return handler(Object.freeze({
          principalId: principal,
          connection,
          ...Object.fromEntries(Object.entries(body)
            .filter(([key]) => key !== 'connection' && key !== 'ref')),
          ...(ref === undefined ? {} : {ref}),
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
