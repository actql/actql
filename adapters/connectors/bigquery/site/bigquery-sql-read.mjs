// Physical transport of one original accounted Common Job. The installed
// Journal supplies the original-operation callback; this driver cannot issue it.
import {createHash} from 'node:crypto';
import {gunzipSync} from 'node:zlib';
import {setTimeout as delay} from 'node:timers/promises';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {ownInvocationAuthorization, ownInvocationLimits, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource, openHttpsCredentialBinding,
  closeHttpsCredentialBinding} from '../../../site-node/https-credential-resource.mjs';

export const BIGQUERY_SQL_READ_OPERATION = 'bigquery:sql:read';
const fail = code => { throw Object.assign(new Error(code), {code}); };
const count = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

function queryLimits(moon, limits) {
  for (const name of ['maxBytes', 'maxNodes', 'maxDepth', 'maxFields',
    'maxNameBytes', 'maxSchemaBytes', 'maxRows', 'maxValueNodes',
    'maxValueTextBytes', 'maxJobBytes', 'maxPageTokenBytes', 'maxPages',
    'maxResults', 'timeoutMs', 'maxRequests', 'maxRequestBytes', 'maxSecretBytes',
    'pollDelayMs']) {
    if (!count(limits[name]) || limits[name] === 0 &&
        !['maxRows', 'timeoutMs', 'pollDelayMs'].includes(name)) {
      fail('InvalidBigQueryReadLimits');
    }
  }
  if (typeof limits.maxTotalRows !== 'bigint' || limits.maxTotalRows < 0n ||
      limits.maxTotalRows > 9223372036854775807n ||
      typeof limits.maximumBytesBilled !== 'bigint' || limits.maximumBytesBilled <= 0n ||
      limits.maximumBytesBilled > 9223372036854775807n) fail('InvalidBigQueryReadLimits');
  return moon.clientProgramBigQueryQueryLimits(
    moon.clientProgramBigQueryDescriptionLimits(limits.maxBytes, limits.maxNodes,
      limits.maxDepth, limits.maxFields, limits.maxNameBytes, limits.maxSchemaBytes),
    limits.maxRows, limits.maxTotalRows, limits.maxValueNodes,
    limits.maxValueTextBytes, limits.maxJobBytes, limits.maxPageTokenBytes);
}

function authorizeRead(value, frame, original) {
  const owned = ownInvocationAuthorization(value);
  if (owned.scope.operation !== BIGQUERY_SQL_READ_OPERATION ||
      owned.scope.connectorRegistration !== 'bigquery' ||
      owned.scope.runInvocationCid !== frame.runInvocationCid ||
      owned.scope.dispatchRequestCid !== frame.dispatchRequestCid ||
      original !== undefined && !invocationBindingsMatch(owned.scope, original)) {
    fail('ForeignBigQueryReadAuthorization');
  }
  return owned;
}

function decodeResponse(response, limit) {
  const encoding = response.headers?.find(pair => pair[0] === 'content-encoding')?.[1];
  if (encoding === undefined || encoding.toLowerCase() === 'identity') return response.body;
  if (encoding.toLowerCase() !== 'gzip') fail('UnsupportedBigQueryResponseEncoding');
  return gunzipSync(response.body, {maxOutputLength: limit});
}

export async function readBigQuerySqlApi({moon, prepared, rowRun, job, limits,
  authorizationFor, credential, verifyRead, withOriginalJob, signal,
  callResource = callHttpsCredentialResource}) {
  // This private trusted assembly port must bind the same accepted Run/task,
  // Store epoch and actual prepared occurrence. It confirms the original CAS
  // before invoking sendOriginal once. A record, function or equal CID cannot
  // supply a missing production issuer, credential or current authorization.
  if (typeof withOriginalJob !== 'function') fail('BigQueryOriginalOperationUnavailable');
  const bounds = ownInvocationLimits(limits);
  const frame = Object.freeze({...rowRun});
  const physicalCredential = Object.freeze({...credential});
  if (!moon || !prepared || !job || !frame.run || !frame.acquisition ||
      typeof frame.requestId !== 'string' || typeof frame.runInvocationCid !== 'string' ||
      typeof frame.dispatchRequestCid !== 'string' || typeof verifyRead !== 'function' ||
      typeof authorizationFor !== 'function' || typeof callResource !== 'function' ||
      physicalCredential.binding !== undefined) fail('InvalidBigQueryPhysicalRead');
  if (moon.clientProgramBigQueryReadAcquisition(prepared) !== frame.acquisition) {
    fail('ForeignBigQueryReadPreparation');
  }
  const admitted = queryLimits(moon, bounds);
  let read, jobRead, binding, originalScope, bound = false, processing = true;
  let attempted = 0, exchanges = 0, wireBytes = 0n, decodedBytes = 0n;
  let firstOperationEntered = false, firstOperationOpen = false, firstSendEntered = false;
  let firstSendPromise;
  let transportLost = false, recordingFailure, lastObservation, lastExchange, failure, result;
  try {
    signal?.throwIfAborted();
    await verifyRead();
    signal?.throwIfAborted();
    read = checked(moon.clientProgramBigQueryBorrowRead(prepared, frame.run, job,
      admitted, bounds.maxPages));
    jobRead = checked(moon.clientProgramBigQueryPrepareJob(read, bounds.maximumBytesBilled,
      bounds.maxResults, bounds.timeoutMs, bounds.maxRequests, bounds.maxRequestBytes));
    const recordLimits = moon.clientProgramBigQueryJobRecordLimits(bounds.maxRequestBytes,
      bounds.maxNodes, bounds.maxDepth, bounds.maxJobBytes, bounds.maxRequestBytes);
    const record = checked(moon.clientProgramBigQueryJobOriginalRecord(jobRead, recordLimits));
    const wire = moon.clientProgramBigQueryJobOriginalRecordWire(record);
    const send = async request => {
      const material = moon.clientProgramBigQueryRequestMaterial(request);
      const method = runtimeField(material, 0), path = runtimeField(material, 1);
      const body = runtimeField(material, 2), sequence = runtimeField(material, 3);
      const authorization = authorizeRead(await authorizationFor(sequence), frame, originalScope);
      signal?.throwIfAborted();
      await verifyRead();
      signal?.throwIfAborted();
      if (binding === undefined) {
        originalScope = authorization.scope;
        binding = openHttpsCredentialBinding({...physicalCredential,
          scope: originalScope, maxSecretBytes: bounds.maxSecretBytes});
        checked(moon.clientProgramBigQueryBindReadTransport(read, () =>
          closeHttpsCredentialBinding(binding) === 'closed' && !processing));
        bound = true;
      }
      checked(moon.clientProgramBigQueryAttemptRequest(jobRead, request));
      attempted++;
      let response;
      try {
        response = await invokeScopedCredentialOperation({authorization,
          credential: Object.freeze({...physicalCredential, binding, currentBeforeSend: verifyRead}),
          callResource, operation: BIGQUERY_SQL_READ_OPERATION, method, path,
          ...(body === undefined || body === null ? {} : {body}),
          headers: [['user-agent', 'actql-bigquery/0.1']], responseHeaders: ['content-encoding'],
          maxRequestBytes: bounds.maxRequestBytes, maxResponseBytes: bounds.maxBytes, signal});
      } catch (error) {
        transportLost = true;
        try { checked(moon.clientProgramBigQueryRecordResponseLoss(jobRead, request)); }
        catch (secondary) { recordingFailure = secondary; }
        throw error;
      }
      lastObservation = response;
      const ticket = checked(moon.clientProgramBigQueryChargeResponse(jobRead, request,
        response.statusCode, response.body));
      exchanges++;
      wireBytes += BigInt(response.body.byteLength);
      await verifyRead();
      signal?.throwIfAborted();
      let decoded;
      try { decoded = decodeResponse(response, bounds.maxBytes); }
      catch (error) {
        try { checked(moon.clientProgramBigQueryRecordDecoderRefusal(jobRead, ticket)); }
        catch (secondary) { recordingFailure = secondary; }
        throw error;
      }
      decodedBytes += BigInt(decoded.byteLength);
      await verifyRead();
      signal?.throwIfAborted();
      checked(moon.clientProgramBigQueryAcceptResponse(jobRead, ticket, decoded));
      lastExchange = Object.freeze({sequence, method, path, statusCode: response.statusCode,
        useCid: response.useCid, wireSha256: sha(response.body), decodedSha256: sha(decoded)});
    };
    while (true) {
      const request = checked(moon.clientProgramBigQueryNextRequest(jobRead));
      if (request === undefined || request === null) break;
      const sequence = runtimeField(moon.clientProgramBigQueryRequestMaterial(request), 3);
      if (sequence === 0) {
        if (!moon.clientProgramBigQueryJobOriginalRecordMatchesRequest(jobRead, request, record)) {
          fail('ForeignBigQueryOriginalJob');
        }
        firstOperationEntered = firstOperationOpen = true;
        let originalOperationFailure;
        try {
          await withOriginalJob(Object.freeze({jobRead, request, record, wire, frame}), () => {
            if (!firstOperationOpen || firstSendEntered) fail('BigQueryOriginalJobAlreadyAttempted');
            firstSendEntered = true;
            // The original callback cannot move dispatch past a failed await
            // or return. Recheck the same live material before physical use.
            if (!moon.clientProgramBigQueryJobOriginalRecordMatchesRequest(jobRead, request, record)) {
              fail('ForeignBigQueryOriginalJob');
            }
            firstSendPromise = send(request);
            // Retain and observe the original send even if a trusted caller
            // returns or throws without awaiting the supplied operation.
            void firstSendPromise.catch(() => {});
            return firstSendPromise;
          });
        } catch (error) { originalOperationFailure = error; }
        finally { firstOperationOpen = false; }
        if (firstSendPromise !== undefined) {
          try { await firstSendPromise; }
          catch (error) { originalOperationFailure ??= error; }
        }
        if (originalOperationFailure !== undefined) throw originalOperationFailure;
        if (!firstSendEntered) fail('BigQueryOriginalJobUnresolved');
      } else {
        await send(request);
        if (bounds.pollDelayMs !== 0) await delay(bounds.pollDelayMs, undefined, {signal});
      }
    }
    if (!moon.clientProgramBigQueryJobComplete(jobRead)) fail('BigQueryReadIncomplete');
    const original = moon.clientProgramBigQueryJobOriginal(jobRead);
    const usage = moon.clientProgramBigQueryReadUsage(read);
    result = Object.freeze({project: runtimeField(original, 0), jobId: runtimeField(original, 1),
      location: runtimeField(original, 2), pages: runtimeField(usage, 0), rows: runtimeField(usage, 1),
      exchanges, wireBytes, decodedBytes, lastExchange});
  } catch (error) {
    failure = error;
    if (read !== undefined) moon.clientProgramBigQueryInterruptRead(read);
  }
  processing = false;
  let stopped = binding === undefined;
  try {
    if (bound) {
      checked(moon.clientProgramBigQueryRetireReadBorrow(read));
      stopped = true;
    } else {
      if (binding !== undefined) stopped = closeHttpsCredentialBinding(binding) === 'closed';
      if (read !== undefined) checked(moon.clientProgramBigQueryRetireReadBorrow(read));
    }
  } catch (cleanupFailure) {
    failure = Object.assign(new Error(failure?.code ?? 'BigQueryReadCleanupPending',
      {cause: failure ?? cleanupFailure}), {code: failure?.code ?? 'BigQueryReadCleanupPending', cleanupFailure});
  }
  if (!stopped && failure === undefined) {
    failure = Object.assign(new Error('BigQueryReadCleanupPending'), {code: 'BigQueryReadCleanupPending'});
  }
  if (failure !== undefined) {
    const remoteDone = jobRead !== undefined && moon.clientProgramBigQueryJobRemoteDone(jobRead);
    const outcome = !stopped || transportLost || firstOperationEntered && !firstSendEntered ||
      attempted !== 0 && !remoteDone ? 'unknown' : attempted === 0 ? 'not_started' : 'stopped';
    const error = new AcquisitionOpenError(failure, outcome);
    if (lastObservation !== undefined) Object.defineProperty(error, 'observation', {value: lastObservation});
    if (recordingFailure !== undefined) Object.defineProperty(error, 'recordingFailure', {value: recordingFailure});
    if (jobRead !== undefined) {
      const original = moon.clientProgramBigQueryJobOriginal(jobRead);
      error.originalJob = Object.freeze({project: runtimeField(original, 0),
        jobId: runtimeField(original, 1), location: runtimeField(original, 2)});
    }
    throw error;
  }
  return result;
}
