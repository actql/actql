// Vendor request/response projection on the original accounted RowRun. The
// generic Host owns finish, capture and root cleanup; this driver owns no Run.
import {checked} from '../../../host-common/runtime-result.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {ownInvocationAuthorization, ownInvocationLimits, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource, openHttpsCredentialBinding,
  closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';

export type KintoneResourceCall = typeof callHttpsCredentialResource;
export type KintoneResourceInput = Parameters<KintoneResourceCall>[0];
export type KintoneResponse = Awaited<ReturnType<KintoneResourceCall>>;
export type KintoneObservationCause = Readonly<{code?: unknown; message?: string;
  observation?: KintoneResponse}> | null | undefined;
export type KintoneScope = Readonly<{connectorRegistration?: unknown; operation?: unknown;
  runInvocationCid?: unknown; dispatchRequestCid?: unknown}>;
export type KintoneInvocation<Limits, Callbacks> = Omit<ReturnType<typeof import(
  '../../../host-common/owned-invocation-context.mjs').ownInvocationContext>, 'limits' | 'callbacks' | 'scope'> &
  Readonly<{limits: Limits; callbacks: Callbacks; scope: KintoneScope}>;
export type KintoneFormAndPageRuntime = Readonly<{
  clientProgramKintoneFormLimits(bytes: number, nodes: number, depth: number, fields: number, names: number): unknown;
  clientProgramKintonePageLimits(bytes: number, nodes: number, depth: number, rows: number,
    columns: number, cells: number, tableRows: number): unknown;
}>;
type Native = KintoneFormAndPageRuntime & Readonly<{
  clientProgramKintoneValueLimits(columns: number, names: number, nodes: number, depth: number, textBytes: number): unknown;
  clientProgramKintoneReadAcquisition(prepared: unknown): unknown;
  clientProgramKintoneBorrowRead(prepared: unknown, run: unknown, page: unknown, values: unknown, pairs: number): unknown;
  clientProgramKintoneBindReadCleanup(read: unknown, stopped: () => boolean): unknown;
  clientProgramKintoneRecheckReadForm(read: unknown, body: Uint8Array, form: unknown): unknown;
  clientProgramKintoneAcceptReadPage(read: unknown, body: Uint8Array): unknown;
  clientProgramKintoneRetireRead(read: unknown): unknown;
  clientProgramKintoneFormRequestBody(prepared: unknown, bytes: number): unknown;
  clientProgramKintonePageRequestBody(prepared: unknown, cursor: string[], perPage: number, bytes: number): unknown;
  clientProgramKintonePageNextCursor(read: unknown, prior: string[], perPage: number): unknown;
}>;
type Limits = Readonly<Record<'maxResponseBytes' | 'maxNodes' | 'maxDepth' | 'maxFields' |
  'maxNameUnits' | 'maxColumns' | 'maxCells' | 'maxTableRows' | 'maxValueNodes' |
  'maxValueDepth' | 'maxValueTextBytes' | 'maxContractPairs' | 'maxRequestBytes' |
  'maxRequests' | 'maxPages' | 'perPage' | 'maxSecretBytes', number>>;
type PhysicalRead = Readonly<{
  moon: Native; prepared: unknown; limits: Limits; guestSpaceId?: string;
  rowRun: Readonly<{acquisition: unknown; run: unknown; requestId: string;
    runInvocationCid: string; dispatchRequestCid: string}>;
  credential: Omit<Parameters<typeof openHttpsCredentialBinding>[0], 'scope' | 'maxSecretBytes' | 'secretPresentation'> &
    Readonly<{binding?: unknown}>;
  authorizationFor(input: Readonly<{operation: string; index: number}>): unknown;
  current(operation: string): unknown; chargeResponse(body: Uint8Array): unknown;
  consumeObservation(charge: unknown): unknown; signal?: AbortSignal; callResource?: KintoneResourceCall;
}>;

export const KINTONE_FORM_READ_OPERATION = 'kintone:form:read';
export const KINTONE_RECORD_READ_OPERATION = 'kintone:records:read';
const fail: (code: string, cause?: unknown) => never = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;

function readBounds(moon: Native, limits: Limits) {
  for (const key of ['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxFields',
    'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes',
    'maxValueDepth', 'maxValueTextBytes', 'maxContractPairs', 'maxRequestBytes',
    'maxRequests', 'maxPages', 'perPage', 'maxSecretBytes'] as const) {
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
  consumeObservation, signal, callResource = callHttpsCredentialResource}: PhysicalRead) {
  const bounds = ownInvocationLimits(limits) as Limits, frame = Object.freeze({...rowRun});
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
  let read: unknown, binding: ReturnType<typeof openHttpsCredentialBinding> | undefined, bound = false, processing = true, attempted = 0, pages = 0, rows = 0;
  let originalScope: KintoneScope | undefined, failure: unknown, responseLost = false, lastStatus: number | undefined;
  try {
    // Bind the same Core cleanup observer before any fallible secret or I/O
    // acquisition. A failed open still leaves the original Root reachable.
    read = checked(moon.clientProgramKintoneBorrowRead(prepared, frame.run,
      admitted.page, admitted.values, bounds.maxContractPairs));
    checked(moon.clientProgramKintoneBindReadCleanup(read, () =>
      (binding === undefined || closeHttpsCredentialBinding(binding) === 'closed') && !processing));
    bound = true;
    const exchange = async (operation: string, path: string, body: string) => {
      signal?.throwIfAborted();
      if (attempted >= bounds.maxRequests) fail('KintoneReadRequestLimit');
      await current(operation);
      const authorization = ownInvocationAuthorization(await authorizationFor({operation, index: attempted})) as
        ReturnType<typeof ownInvocationAuthorization> & {scope: KintoneScope};
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
          maxSecretBytes: bounds.maxSecretBytes, secretPresentation: 'kintone-api-token'} as
          Parameters<typeof openHttpsCredentialBinding>[0]);
      }
      await current(operation);
      signal?.throwIfAborted();
      attempted++;
      let response: KintoneResponse;
      try {
        response = await invokeScopedCredentialOperation({authorization,
          credential: {...physicalCredential, binding,
            currentBeforeSend: () => current(operation)}, callResource, operation,
          // Official method override, fixed by this vendor driver. It grants
          // only the selected read operation, never an arbitrary POST target.
          method: 'POST', path: prefix + path, body,
          headers: [['x-http-method-override', 'GET']], responseHeaders: [],
          maxRequestBytes: bounds.maxRequestBytes, maxResponseBytes: bounds.maxResponseBytes, signal}) as KintoneResponse;
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
        rows += checked(moon.clientProgramKintoneAcceptReadPage(read, response.body)) as number;
      }
      await current(operation);
      signal?.throwIfAborted();
    };
    const form = () => exchange(KINTONE_FORM_READ_OPERATION, 'app/form/fields.json',
      checked(moon.clientProgramKintoneFormRequestBody(prepared, bounds.maxRequestBytes)) as string);
    let cursor: string[] = [];
    await form();
    while (true) {
      if (pages >= bounds.maxPages) fail('KintoneReadPageLimit');
      const body = checked(moon.clientProgramKintonePageRequestBody(prepared, cursor,
        bounds.perPage, bounds.maxRequestBytes)) as string;
      await exchange(KINTONE_RECORD_READ_OPERATION, 'records.json', body);
      pages++;
      const next = checked(moon.clientProgramKintonePageNextCursor(read, cursor, bounds.perPage)) as string[];
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
    failure = Object.assign(new Error(((failure as KintoneObservationCause)?.code ?? 'KintoneReadCleanupPending') as string,
      {cause: failure ?? cleanupFailure}), {code: (failure as KintoneObservationCause)?.code ?? 'KintoneReadCleanupPending', cleanupFailure});
  }
  if (failure !== undefined) {
    const outcome = !stopped || responseLost || lastStatus === 408 || (lastStatus as number) >= 500
      ? 'unknown' : attempted === 0 ? 'not_started' : 'stopped';
    throw new AcquisitionOpenError(failure, outcome);
  }
  return Object.freeze({pages, requests: attempted, rows});
}
