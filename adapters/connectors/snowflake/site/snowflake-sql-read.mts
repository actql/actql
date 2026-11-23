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

type LimitName = 'maxBytes' | 'maxNodes' | 'maxDepth' | 'maxColumns' | 'maxNameUnits' |
  'maxHandleUnits' | 'maxPartitions' | 'maxRows' | 'maxTotalRows' | 'maxRequests' |
  'maxRequestBytes' | 'maxContractPairs' | 'timeoutSeconds' | 'maxSecretBytes' | 'pollDelayMs';
type ReadLimits = Readonly<Record<LimitName, number>>;
type Runtime = Readonly<{
  clientProgramSnowflakeResponseLimits(bytes: number, nodes: number, depth: number, columns: number,
    nameUnits: number, handleUnits: number, partitions: number, rows: number, totalRows: bigint): unknown;
  clientProgramSnowflakeReadAcquisition(prepared: unknown): object;
  clientProgramSnowflakeBorrowRead(prepared: unknown, run: unknown, limits: unknown, contractPairs: number): unknown;
  clientProgramSnowflakeBindReadTransport(read: unknown, stop: () => boolean): unknown;
  clientProgramSnowflakePrepareStatement(read: unknown, requestId: string, warehouse: string,
    role: string, timeout: number, requests: number, requestBytes: number): unknown;
  clientProgramSnowflakeNextRequest(statement: unknown): unknown;
  clientProgramSnowflakeRequestMaterial(request: unknown): unknown;
  clientProgramSnowflakeAttemptRequest(statement: unknown, request: unknown): unknown;
  clientProgramSnowflakeRecordResponseLoss(statement: unknown, request: unknown): unknown;
  clientProgramSnowflakeChargeResponse(statement: unknown, request: unknown, status: number, body: Uint8Array): unknown;
  clientProgramSnowflakeRecordDecoderRefusal(statement: unknown, ticket: unknown): unknown;
  clientProgramSnowflakeAcceptResponse(statement: unknown, ticket: unknown, decoded: Uint8Array): unknown;
  clientProgramSnowflakeStatementComplete(statement: unknown): boolean;
  clientProgramSnowflakeReadUsage(read: unknown): unknown;
  clientProgramSnowflakeStatementOriginal(statement: unknown): unknown;
  clientProgramSnowflakeInterruptRead(read: unknown): void;
  clientProgramSnowflakeRetireReadBorrow(read: unknown): unknown;
}>;
type Frame = Readonly<{
  run: unknown; acquisition: object; requestId: string; runInvocationCid: string; dispatchRequestCid: string;
}>;
type OwnedAuthorization = ReturnType<typeof ownInvocationAuthorization>;
type InvocationScope = OwnedAuthorization['scope'] & Readonly<{
  operation?: string; connectorRegistration?: string; runInvocationCid?: string; dispatchRequestCid?: string;
}>;
type BindingOptions = Parameters<typeof openHttpsCredentialBinding>[0];
type Binding = ReturnType<typeof openHttpsCredentialBinding>;
type Credential = Omit<BindingOptions, 'scope' | 'maxSecretBytes'> & Readonly<{binding?: unknown}>;
type ResourceResponse = Awaited<ReturnType<typeof callHttpsCredentialResource>>;
type Exchange = Readonly<{sequence: number; method: string; path: string; statusCode: ResourceResponse['statusCode'];
  useCid: string; wireSha256: string; decodedSha256: string}>;
type ReadResult = Readonly<{requestId: string; statementHandle: string | undefined; pages: number; rows: bigint;
  exchanges: number; wireBytes: bigint; decodedBytes: bigint; lastExchange?: Exchange}>;
type ReadOptions = Readonly<{
  moon: Runtime; prepared: unknown; rowRun: Frame; limits: ReadLimits; warehouse: string;
  role: string; authenticationType?: 'OAUTH' | 'KEYPAIR_JWT'; authorizationFor(sequence: number): unknown;
  credential: Credential; verifyRead(): unknown; signal?: AbortSignal;
  callResource?: typeof callHttpsCredentialResource;
}>;

export const SNOWFLAKE_SQL_READ_OPERATION = 'snowflake:sql:read';
const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const count = (value: number) => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const sha = (value: Uint8Array) => createHash('sha256').update(value).digest('hex');

function responseLimits(moon: Runtime, limits: ReadLimits) {
  for (const key of ['maxBytes', 'maxNodes', 'maxDepth', 'maxColumns',
    'maxNameUnits', 'maxHandleUnits', 'maxPartitions', 'maxRows',
    'maxTotalRows', 'maxRequests', 'maxRequestBytes', 'maxContractPairs',
    'timeoutSeconds', 'maxSecretBytes', 'pollDelayMs'] as const) {
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

function authorizationForRead(value: unknown, original: InvocationScope | undefined, frame: Frame) {
  const owned = ownInvocationAuthorization(value) as OwnedAuthorization & Readonly<{scope: InvocationScope}>;
  if (owned.scope.operation !== SNOWFLAKE_SQL_READ_OPERATION ||
      owned.scope.connectorRegistration !== 'snowflake' ||
      owned.scope.runInvocationCid !== frame.runInvocationCid ||
      owned.scope.dispatchRequestCid !== frame.dispatchRequestCid ||
      (original !== undefined && !invocationBindingsMatch(owned.scope, original))) {
    fail('ForeignSnowflakeReadAuthorization');
  }
  return owned;
}

function decodeResponse(response: ResourceResponse, maxBytes: number) {
  const encoding = response.headers?.find(pair => pair[0] === 'content-encoding')?.[1];
  if (encoding === undefined || encoding.toLowerCase() === 'identity') return response.body;
  if (encoding.toLowerCase() !== 'gzip') fail('UnsupportedSnowflakeResponseEncoding');
  // This is a decoder output bound, not permission to enlarge the original
  // transfer/retention/workspace. The wire ticket was charged before this call.
  return gunzipSync(response.body, {maxOutputLength: maxBytes});
}

export async function readSnowflakeSqlApi({moon, prepared, rowRun, limits,
  warehouse, role, authenticationType, authorizationFor, credential,
  verifyRead, signal, callResource = callHttpsCredentialResource}: ReadOptions) {
  // Own caller-selected primitives/functions before the first await. The
  // opaque preparation, run, grant and journal keep their original identity.
  const bounds = ownInvocationLimits(limits) as ReadLimits;
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
  let read: unknown, statement: unknown, binding: Binding | undefined, bound = false, attempted = 0, exchanges = 0;
  let wireBytes = 0n, decodedBytes = 0n, lastStatus: number | undefined, lastExchange: Exchange | undefined;
  let transportLost = false, result: ReadResult | undefined, failure: unknown,
    lastObservation: ResourceResponse | undefined, recordingFailure: unknown;
  // JavaScript rejection reasons may be undefined; presence is independent
  // of the original reason and of secondary recording/cleanup failures.
  let failed = false, recordingFailed = false, cleanupFailed = false, cleanupFailure: unknown;
  let processingOriginal = true;
  let remoteStatementUnconfirmed = false;
  try {
    signal?.throwIfAborted();
    await verifyRead();
    signal?.throwIfAborted();
    const initial = authorizationForRead(await authorizationFor(0), undefined, frame);
    signal?.throwIfAborted();
    binding = openHttpsCredentialBinding({...physicalCredential,
      scope: initial.scope, maxSecretBytes: bounds.maxSecretBytes} as BindingOptions);
    const scopedCredential = Object.freeze({...physicalCredential, binding,
      currentBeforeSend: verifyRead});
    read = checked(moon.clientProgramSnowflakeBorrowRead(prepared, frame.run,
      admittedLimits, bounds.maxContractPairs));
    checked(moon.clientProgramSnowflakeBindReadTransport(read, () => {
      const transportStopped = closeHttpsCredentialBinding(binding!) === 'closed';
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
      const method = runtimeField(material, 0) as string, path = runtimeField(material, 1) as string;
      const body = runtimeField(material, 2), sequence = runtimeField(material, 3) as number;
      const authorization = sequence === 0 ? initial : authorizationForRead(
        await authorizationFor(sequence), initial.scope, frame);
      signal?.throwIfAborted();
      await verifyRead();
      signal?.throwIfAborted();
      checked(moon.clientProgramSnowflakeAttemptRequest(statement, request));
      attempted++;
      let response: ResourceResponse;
      try {
        response = await invokeScopedCredentialOperation({authorization,
          credential: scopedCredential, callResource,
          operation: SNOWFLAKE_SQL_READ_OPERATION, method, path,
          ...(body === undefined || body === null ? {} : {body}),
          headers: [['user-agent', 'actql-snowflake/0.1'],
            ...(authenticationType === undefined ? [] : [
              ['x-snowflake-authorization-token-type', authenticationType]])],
          responseHeaders: ['content-encoding'], maxRequestBytes: bounds.maxRequestBytes,
          maxResponseBytes: bounds.maxBytes, signal}) as ResourceResponse;
      } catch (error) {
        transportLost = true;
        // Unit records only this original response loss; it is not an ACK,
        // retry permission or a successful Source observation.
        try { checked(moon.clientProgramSnowflakeRecordResponseLoss(statement, request)); }
        catch (secondary) { recordingFailed = true; recordingFailure = secondary; }
        throw error;
      }
      lastObservation = response;
      lastStatus = response.statusCode;
      // A later refusal to read status cannot end the statement accepted by
      // this original 202. Local socket retirement is a separate observation.
      if (response.statusCode === 202) remoteStatementUnconfirmed = true;
      const ticket = checked(moon.clientProgramSnowflakeChargeResponse(statement,
        request, response.statusCode!, response.body));
      wireBytes += BigInt(response.body.byteLength);
      exchanges++;
      await verifyRead();
      signal?.throwIfAborted();
      let decoded;
      try { decoded = decodeResponse(response, bounds.maxBytes); }
      catch (error) {
        try { checked(moon.clientProgramSnowflakeRecordDecoderRefusal(statement, ticket)); }
        catch (secondary) { recordingFailed = true; recordingFailure = secondary; }
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
    remoteStatementUnconfirmed = false;
    const usage = moon.clientProgramSnowflakeReadUsage(read);
    const original = moon.clientProgramSnowflakeStatementOriginal(statement);
    result = Object.freeze({requestId: runtimeField(original, 0) as string,
      statementHandle: runtimeField(original, 1) as string | undefined, pages: runtimeField(usage, 0) as number,
      rows: runtimeField(usage, 1) as bigint, exchanges, wireBytes, decodedBytes, lastExchange});
  } catch (error) {
    failed = true;
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
    cleanupFailed = true;
    cleanupFailure = cleanupError;
    if (!failed) {
      failed = true;
      failure = Object.assign(new Error('SnowflakeReadCleanupPending',
        {cause: cleanupError}), {code: 'SnowflakeReadCleanupPending'});
    }
  }
  if (!stopped && !failed) {
    failed = true;
    failure = Object.assign(new Error('SnowflakeReadCleanupPending'), {code: 'SnowflakeReadCleanupPending'});
  }
  if (failed) {
    const original = statement === undefined ? undefined :
      moon.clientProgramSnowflakeStatementOriginal(statement);
    const outcome = !stopped || transportLost || remoteStatementUnconfirmed || lastStatus === 202 ||
      lastStatus === 408 || lastStatus! >= 500 ? 'unknown'
      : attempted === 0 ? 'not_started' : 'stopped';
    const error = new AcquisitionOpenError(failure, outcome);
    // Retain this one bounded original observation privately on refusal. It
    // does not grant disclosure or turn an HTTP reply into Source evidence.
    if (lastObservation !== undefined) Object.defineProperty(error, 'observation',
      {value: lastObservation});
    if (recordingFailed) Object.defineProperty(error, 'recordingFailure',
      {value: recordingFailure});
    if (cleanupFailed) Object.defineProperty(error, 'cleanupFailure',
      {value: cleanupFailure});
    (error as AcquisitionOpenError & {originalStatement: unknown}).originalStatement = Object.freeze({requestId: frame.requestId,
      statementHandle: original === undefined ? undefined : runtimeField(original, 1)});
    // Pending physical cleanup is already retained by this same Core root's
    // original observer. The Host carries that original root's recovery.
    throw error;
  }
  return result!;
}
