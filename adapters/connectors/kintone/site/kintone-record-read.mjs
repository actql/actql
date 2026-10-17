// Vendor request/response projection on the original accounted RowRun. The
// generic Host owns finish, capture and root cleanup; this driver owns no Run.
import {checked} from '../../../host-common/runtime-result.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {ownInvocationAuthorization, ownInvocationLimits, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource, openHttpsCredentialBinding,
  closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';

export const KINTONE_FORM_READ_OPERATION = 'kintone:form:read';
export const KINTONE_RECORD_READ_OPERATION = 'kintone:records:read';
const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;

function readBounds(moon, limits) {
  for (const key of ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxFields',
    'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes',
    'maxValueDepth', 'maxValueTextBytes', 'maxContractPairs', 'maxRequestBytes',
    'maxRequests', 'maxPages', 'perPage', 'maxSecretBytes']) {
    if (!positive(limits[key])) fail('InvalidKintoneReadLimits');
  }
  if (limits.perPage > 500 || limits.maxPages > limits.maxRequests) fail('InvalidKintoneReadLimits');
  return Object.freeze({
    form: moon.clientProgramKintoneFormLimits(limits.maxResponseBytes, limits.maxNodes,
      limits.maxDepth, limits.maxFields, limits.maxNameUnits),
    page: moon.clientProgramKintonePageLimits(limits.maxResponseBytes, limits.maxNodes,
      limits.maxDepth, limits.perPage, limits.maxColumns, limits.maxCells, limits.maxTableRows),
    values: moon.clientProgramKintoneValueLimits(limits.maxColumns, limits.maxNameUnits,
      limits.maxValueNodes, limits.maxValueDepth, limits.maxValueTextBytes),
  });
}

export async function readKintoneRecords({moon, prepared, rowRun, limits,
  guestSpaceId, authorizationFor, credential, current, chargeResponse,
  consumeObservation, signal, callResource = callHttpsCredentialResource}) {
  const bounds = ownInvocationLimits(limits), frame = Object.freeze({...rowRun});
  const physicalCredential = Object.freeze({...credential});
  if (!moon || !prepared || !frame.acquisition || !frame.run ||
      typeof frame.requestId !== 'string' || typeof frame.runInvocationCid !== 'string' ||
      typeof frame.dispatchRequestCid !== 'string' ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') || physicalCredential.binding !== undefined ||
      (guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId))) {
    fail('InvalidKintonePhysicalRead');
  }
  if (moon.clientProgramKintoneReadAcquisition(prepared) !== frame.acquisition) {
    fail('ForeignKintoneReadPreparation');
  }
  const admitted = readBounds(moon, bounds);
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  let read, binding, bound = false, processing = true, attempted = 0, pages = 0, rows = 0;
  let originalScope, failure, responseLost = false, lastStatus;
  try {
    // Bind the same Core cleanup observer before any fallible secret or I/O
    // acquisition. A failed open still leaves the original Root reachable.
    read = checked(moon.clientProgramKintoneBorrowRead(prepared, frame.run,
      admitted.page, admitted.values, bounds.maxContractPairs));
    checked(moon.clientProgramKintoneBindReadCleanup(read, () =>
      (binding === undefined || closeHttpsCredentialBinding(binding) === 'closed') && !processing));
    bound = true;
    const exchange = async (operation, path, body) => {
      signal?.throwIfAborted();
      if (attempted >= bounds.maxRequests) fail('KintoneReadRequestLimit');
      await current(operation);
      const authorization = ownInvocationAuthorization(await authorizationFor({operation, index: attempted}));
      if (authorization.scope.connectorRegistration !== 'kintone' ||
          authorization.scope.operation !== operation ||
          authorization.scope.runInvocationCid !== frame.runInvocationCid ||
          authorization.scope.dispatchRequestCid !== frame.dispatchRequestCid ||
          (originalScope !== undefined && !invocationBindingsMatch(authorization.scope, originalScope))) {
        fail('ForeignKintoneReadAuthorization');
      }
      if (originalScope === undefined) {
        originalScope = authorization.scope;
        binding = openHttpsCredentialBinding({...physicalCredential, scope: originalScope,
          maxSecretBytes: bounds.maxSecretBytes, secretPresentation: 'kintone-api-token'});
      }
      await current(operation);
      signal?.throwIfAborted();
      attempted++;
      let response;
      try {
        response = await invokeScopedCredentialOperation({authorization,
          credential: {...physicalCredential, binding,
            currentBeforeSend: () => current(operation)}, callResource, operation,
          // Official method override, fixed by this vendor driver. It grants
          // only the selected read operation, never an arbitrary POST target.
          method: 'POST', path: prefix + path, body,
          headers: [['x-http-method-override', 'GET']], responseHeaders: [],
          maxRequestBytes: bounds.maxRequestBytes, maxResponseBytes: bounds.maxResponseBytes, signal});
      } catch (cause) {
        responseLost = true;
        throw cause;
      }
      lastStatus = response.statusCode;
      // Charge/admit synchronously before another awaited current check can
      // refuse. No rows become a public capture before the Host's final fence.
      if (response.statusCode !== 200) {
        consumeObservation(chargeResponse(response.body));
        await current(operation);
        fail('KintoneReadHttpRejected');
      }
      if (operation === KINTONE_FORM_READ_OPERATION) {
        checked(moon.clientProgramKintoneRecheckReadForm(read, response.body, admitted.form));
      } else {
        rows += checked(moon.clientProgramKintoneAcceptReadPage(read, response.body));
      }
      await current(operation);
      signal?.throwIfAborted();
    };
    const form = () => exchange(KINTONE_FORM_READ_OPERATION, 'app/form/fields.json',
      checked(moon.clientProgramKintoneFormRequestBody(prepared, bounds.maxRequestBytes)));
    let cursor = [];
    await form();
    while (true) {
      if (pages >= bounds.maxPages) fail('KintoneReadPageLimit');
      const body = checked(moon.clientProgramKintonePageRequestBody(prepared, cursor,
        bounds.perPage, bounds.maxRequestBytes));
      await exchange(KINTONE_RECORD_READ_OPERATION, 'records.json', body);
      pages++;
      const next = checked(moon.clientProgramKintonePageNextCursor(read, cursor, bounds.perPage));
      // Recheck after every page, including the final one. Metadata drift
      // cannot be repaired by a replacement declaration or another lookup.
      await form();
      if (next.length === 0) break;
      cursor = next;
    }
  } catch (cause) {failure = cause;}
  // All response decoding/current callbacks have left the original frame.
  // A pending socket close remains with the same Core borrow and root.
  processing = false;
  let stopped = false;
  try {
    if (bound) checked(moon.clientProgramKintoneRetireRead(read));
    else if (binding !== undefined && closeHttpsCredentialBinding(binding) !== 'closed') {
      fail('KintoneReadCleanupPending');
    }
    stopped = true;
  } catch (cleanupFailure) {
    failure = Object.assign(new Error(failure?.code ?? 'KintoneReadCleanupPending',
      {cause: failure ?? cleanupFailure}), {code: failure?.code ?? 'KintoneReadCleanupPending', cleanupFailure});
  }
  if (failure !== undefined) {
    const outcome = !stopped || responseLost || lastStatus === 408 || lastStatus >= 500
      ? 'unknown' : attempted === 0 ? 'not_started' : 'stopped';
    throw new AcquisitionOpenError(failure, outcome);
  }
  return Object.freeze({pages, requests: attempted, rows});
}
