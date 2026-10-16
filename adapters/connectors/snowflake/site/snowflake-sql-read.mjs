// Physical SQL API transport for the original same-runtime Core Read. Common
// still owns row admission/finish/capture/cleanup; this driver owns no Run.
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

export const SNOWFLAKE_SQL_READ_OPERATION = 'snowflake:sql:read';
const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const count = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const sha = value => createHash('sha256').update(value).digest('hex');

function responseLimits(moon, limits) {
  for (const key of ['maxBytes', 'maxNodes', 'maxDepth', 'maxColumns',
    'maxNameUnits', 'maxHandleUnits', 'maxPartitions', 'maxRows',
    'maxTotalRows', 'maxRequests', 'maxRequestBytes', 'maxContractPairs',
    'timeoutSeconds', 'maxSecretBytes', 'pollDelayMs']) {
    if (!count(limits[key]) || (limits[key] === 0 &&
        !['maxRows', 'maxTotalRows', 'pollDelayMs'].includes(key))) {
      fail('InvalidSnowflakeReadLimits');
    }
  }
  return moon.clientProgramSnowflakeResponseLimits(limits.maxBytes,
    limits.maxNodes, limits.maxDepth, limits.maxColumns, limits.maxNameUnits,
    limits.maxHandleUnits, limits.maxPartitions, limits.maxRows,
    BigInt(limits.maxTotalRows));
}

function authorizationForRead(value, original, frame) {
  const owned = ownInvocationAuthorization(value);
  if (owned.scope.operation !== SNOWFLAKE_SQL_READ_OPERATION ||
      owned.scope.connectorRegistration !== 'snowflake' ||
      owned.scope.runInvocationCid !== frame.runInvocationCid ||
      owned.scope.dispatchRequestCid !== frame.dispatchRequestCid ||
      (original !== undefined && !invocationBindingsMatch(owned.scope, original))) {
    fail('ForeignSnowflakeReadAuthorization');
  }
  return owned;
}

function decodeResponse(response, maxBytes) {
  const encoding = response.headers?.find(pair => pair[0] === 'content-encoding')?.[1];
  if (encoding === undefined || encoding.toLowerCase() === 'identity') return response.body;
  if (encoding.toLowerCase() !== 'gzip') fail('UnsupportedSnowflakeResponseEncoding');
  // This is a decoder output bound, not permission to enlarge the original
  // transfer/retention/workspace. The wire ticket was charged before this call.
  return gunzipSync(response.body, {maxOutputLength: maxBytes});
}

export async function readSnowflakeSqlApi({moon, prepared, rowRun, limits,
  warehouse, role, authenticationType, authorizationFor, credential,
  verifyRead, signal, callResource = callHttpsCredentialResource}) {
  // Own caller-selected primitives/functions before the first await. The
  // opaque preparation, run, grant and journal keep their original identity.
  const bounds = ownInvocationLimits(limits);
  const frame = Object.freeze({...rowRun});
  const physicalCredential = Object.freeze({...credential});
  if (!moon || !prepared || !frame.run || !frame.acquisition ||
      typeof frame.requestId !== 'string' ||
      typeof frame.runInvocationCid !== 'string' ||
      typeof frame.dispatchRequestCid !== 'string' ||
      typeof authorizationFor !== 'function' || typeof verifyRead !== 'function' ||
      typeof callResource !== 'function' || physicalCredential.binding !== undefined ||
      (authenticationType !== undefined &&
        !['OAUTH', 'KEYPAIR_JWT'].includes(authenticationType))) {
    fail('InvalidSnowflakePhysicalRead');
  }
  if (moon.clientProgramSnowflakeReadAcquisition(prepared) !== frame.acquisition) {
    fail('ForeignSnowflakeReadPreparation');
  }
  const admittedLimits = responseLimits(moon, bounds);
  let read, statement, binding, bound = false, attempted = 0, exchanges = 0;
  let wireBytes = 0n, decodedBytes = 0n, lastStatus, lastExchange;
  let transportLost = false, result, failure, lastObservation, recordingFailure;
  let processingOriginal = true;
  try {
    signal?.throwIfAborted();
    await verifyRead();
    signal?.throwIfAborted();
    const initial = authorizationForRead(await authorizationFor(0), undefined, frame);
    signal?.throwIfAborted();
    binding = openHttpsCredentialBinding({...physicalCredential,
      scope: initial.scope, maxSecretBytes: bounds.maxSecretBytes});
    const scopedCredential = Object.freeze({...physicalCredential, binding,
      currentBeforeSend: verifyRead});
    read = checked(moon.clientProgramSnowflakeBorrowRead(prepared, frame.run,
      admittedLimits, bounds.maxContractPairs));
    checked(moon.clientProgramSnowflakeBindReadTransport(read, () => {
      const transportStopped = closeHttpsCredentialBinding(binding) === 'closed';
      // Socket stop does not retire this driver's in-flight use of the same
      // response/workspace. Parent close keeps the same Root until finally.
      return transportStopped && !processingOriginal;
    }));
    bound = true;
    statement = checked(moon.clientProgramSnowflakePrepareStatement(read,
      frame.requestId, warehouse, role, bounds.timeoutSeconds,
      bounds.maxRequests, bounds.maxRequestBytes));
    while (true) {
      const request = checked(moon.clientProgramSnowflakeNextRequest(statement));
      if (request === undefined || request === null) break;
      const material = moon.clientProgramSnowflakeRequestMaterial(request);
      const method = runtimeField(material, 0), path = runtimeField(material, 1);
      const body = runtimeField(material, 2), sequence = runtimeField(material, 3);
      const authorization = sequence === 0 ? initial : authorizationForRead(
        await authorizationFor(sequence), initial.scope, frame);
      signal?.throwIfAborted();
      await verifyRead();
      signal?.throwIfAborted();
      checked(moon.clientProgramSnowflakeAttemptRequest(statement, request));
      attempted++;
      let response;
      try {
        response = await invokeScopedCredentialOperation({authorization,
          credential: scopedCredential, callResource,
          operation: SNOWFLAKE_SQL_READ_OPERATION, method, path,
          ...(body === undefined || body === null ? {} : {body}),
          headers: [['user-agent', 'actql-snowflake/0.1'],
            ...(authenticationType === undefined ? [] : [
              ['x-snowflake-authorization-token-type', authenticationType]])],
          responseHeaders: ['content-encoding'], maxRequestBytes: bounds.maxRequestBytes,
          maxResponseBytes: bounds.maxBytes, signal});
      } catch (error) {
        transportLost = true;
        // Unit records only this original response loss; it is not an ACK,
        // retry permission or a successful Source observation.
        try { checked(moon.clientProgramSnowflakeRecordResponseLoss(statement, request)); }
        catch (secondary) { recordingFailure = secondary; }
        throw error;
      }
      lastObservation = response;
      lastStatus = response.statusCode;
      const ticket = checked(moon.clientProgramSnowflakeChargeResponse(statement,
        request, response.statusCode, response.body));
      wireBytes += BigInt(response.body.byteLength);
      exchanges++;
      await verifyRead();
      signal?.throwIfAborted();
      let decoded;
      try { decoded = decodeResponse(response, bounds.maxBytes); }
      catch (error) {
        try { checked(moon.clientProgramSnowflakeRecordDecoderRefusal(statement, ticket)); }
        catch (secondary) { recordingFailure = secondary; }
        throw error;
      }
      decodedBytes += BigInt(decoded.byteLength);
      await verifyRead();
      signal?.throwIfAborted();
      checked(moon.clientProgramSnowflakeAcceptResponse(statement, ticket, decoded));
      // Bounded last-exchange material only. The original credential journal
      // retains every use; this is not another unbounded response inventory.
      lastExchange = Object.freeze({sequence, method, path, statusCode: response.statusCode,
        useCid: response.useCid, wireSha256: sha(response.body), decodedSha256: sha(decoded)});
      if (response.statusCode === 202 && bounds.pollDelayMs !== 0) {
        await delay(bounds.pollDelayMs, undefined, {signal});
      }
    }
    if (!moon.clientProgramSnowflakeStatementComplete(statement)) fail('SnowflakeReadIncomplete');
    const usage = moon.clientProgramSnowflakeReadUsage(read);
    const original = moon.clientProgramSnowflakeStatementOriginal(statement);
    result = Object.freeze({requestId: runtimeField(original, 0),
      statementHandle: runtimeField(original, 1), pages: runtimeField(usage, 0),
      rows: runtimeField(usage, 1), exchanges, wireBytes, decodedBytes, lastExchange});
  } catch (error) {
    failure = error;
    if (read !== undefined) moon.clientProgramSnowflakeInterruptRead(read);
  }
  // No more physical request, decoder, current callback or response admission
  // can use this original scope after this point. The same stop observer may
  // now acknowledge retirement; no parent/root is reconstructed.
  processingOriginal = false;
  let stopped = binding === undefined;
  try {
    if (bound) {
      checked(moon.clientProgramSnowflakeRetireReadBorrow(read));
      stopped = true;
    } else {
      if (binding !== undefined) stopped = closeHttpsCredentialBinding(binding) === 'closed';
      if (read !== undefined) checked(moon.clientProgramSnowflakeRetireReadBorrow(read));
    }
  } catch (cleanupError) {
    failure = Object.assign(new Error(failure?.code ?? 'SnowflakeReadCleanupPending',
      {cause: failure ?? cleanupError}), {code: failure?.code ?? 'SnowflakeReadCleanupPending',
      cleanupFailure: cleanupError});
  }
  if (!stopped && failure === undefined) {
    failure = Object.assign(new Error('SnowflakeReadCleanupPending'), {code: 'SnowflakeReadCleanupPending'});
  }
  if (failure !== undefined) {
    const original = statement === undefined ? undefined :
      moon.clientProgramSnowflakeStatementOriginal(statement);
    const outcome = !stopped || transportLost || lastStatus === 202 ||
      lastStatus === 408 || lastStatus >= 500 ? 'unknown'
      : attempted === 0 ? 'not_started' : 'stopped';
    const error = new AcquisitionOpenError(failure, outcome);
    // Retain this one bounded original observation privately on refusal. It
    // does not grant disclosure or turn an HTTP reply into Source evidence.
    if (lastObservation !== undefined) Object.defineProperty(error, 'observation',
      {value: lastObservation});
    if (recordingFailure !== undefined) Object.defineProperty(error, 'recordingFailure',
      {value: recordingFailure});
    error.originalStatement = Object.freeze({requestId: frame.requestId,
      statementHandle: original === undefined ? undefined : runtimeField(original, 1)});
    // Pending physical cleanup is already retained by this same Core root's
    // original observer. The Host carries that original root's recovery.
    throw error;
  }
  return result;
}
