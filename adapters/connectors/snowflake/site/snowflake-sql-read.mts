// Physical SQL API transport for the original same-runtime Core Read. Common
// still owns row admission/finish/capture/cleanup; this driver owns no Run.
import {gunzipSync} from 'node:zlib';
import {setTimeout as delay} from 'node:timers/promises';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';

type Runtime = Readonly<{
  clientProgramSnowflakeAdoptManagedRead(description: unknown, borrow: unknown,
    response: unknown, descriptionLimits: unknown, contractPairs: number): unknown;
  clientProgramSnowflakePrepareStatement(read: unknown, requestId: string, warehouse: string,
    role: string, timeout: number, requests: number, requestBytes: number): unknown;
  clientProgramSnowflakeNextRequest(statement: unknown): unknown;
  clientProgramSnowflakeRequestMaterial(request: unknown): unknown;
  clientProgramSnowflakeAttemptRequest(statement: unknown, request: unknown): unknown;
  clientProgramSnowflakeRecordResponseLoss(statement: unknown, request: unknown): unknown;
  clientProgramSnowflakeAdoptManagedResponse(statement: unknown, request: unknown, status: number, charge: unknown): unknown;
  clientProgramSnowflakeRecordDecoderRefusal(statement: unknown, ticket: unknown): unknown;
  clientProgramSnowflakeAcceptResponse(statement: unknown, ticket: unknown, decoded: Uint8Array): unknown;
  clientProgramSnowflakeStatementComplete(statement: unknown): boolean;
  clientProgramSnowflakeReadUsage(read: unknown): unknown;
  clientProgramSnowflakeStatementOriginal(statement: unknown): unknown;
  clientProgramSnowflakeRetireManagedRead(read: unknown): boolean;
}>;
type Input = Readonly<{responseBorrow: unknown; preparedRead: string}>;
type Limits = Readonly<{maxContractPairs: number; timeoutSeconds: number; maxRequests: number;
  maxRequestBytes: number; maxBytes: number; pollDelayMs: number}>;
type Options = {moon: Runtime; description: unknown; descriptionLimits: unknown; input: Input | undefined;
  limits: Limits; warehouse: string; role: string; authenticationType: 'OAUTH' | 'KEYPAIR_JWT'; responseBound: unknown};
type Response = Readonly<{body: Uint8Array; statusCode: number; headers?: readonly (readonly [string, string])[]}>;
type Child = Readonly<{operation: string; prepare(): Readonly<{original: unknown; request: Readonly<{
  method: unknown; path: unknown; body?: unknown; headers: readonly (readonly [string, string])[];
  responseHeaders: readonly string[]}>; project(response: Response): Response}>}>;
type ReadContext = Readonly<{signal: AbortSignal;
  project(method: Runtime['clientProgramSnowflakeNextRequest'], receiver: Runtime, args: readonly unknown[]): unknown;
  readChild(options: Child): Promise<Response>;
  consumeChargedResponse(project: (charge: unknown) => number): Promise<unknown>}>;
type StatementFailure = AcquisitionOpenError & {
  originalStatement?: Readonly<{requestId: unknown; statementHandle: unknown}>;
};

export const SNOWFLAKE_SQL_READ_OPERATION = 'snowflake:sql:read';
const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
function decodeResponse(response: Response, maxBytes: number) {
  const encoding = response.headers?.find(pair => pair[0] === 'content-encoding')?.[1];
  if (encoding === undefined || encoding.toLowerCase() === 'identity') return response.body;
  if (encoding.toLowerCase() !== 'gzip') fail('UnsupportedSnowflakeResponseEncoding');
  // This is a decoder output bound, not permission to enlarge the original
  // transfer/retention/workspace. The wire ticket was charged before this call.
  return gunzipSync(response.body, {maxOutputLength: maxBytes});
}

// The bound reader owns transport, the original response charge, currency,
// and cleanup. Snowflake supplies the same statement and typed result codec.
export function prepareSnowflakeManagedRead({moon, description, descriptionLimits,
  input, limits, warehouse, role, authenticationType, responseBound}: Options) {
  let read = checked(moon.clientProgramSnowflakeAdoptManagedRead(description,
    input!.responseBorrow, responseBound, descriptionLimits, limits.maxContractPairs));
  let statement: unknown, started = false, attempted = false, pendingStatement = false;
  let lastResponse: Response | undefined, recordingFailure: unknown, recordingFailed = false;
  return Object.freeze({
    async read(context: ReadContext) {
      if (started || read === undefined) fail('ForeignSnowflakeReadPreparation');
      started = true;
      statement = checked(moon.clientProgramSnowflakePrepareStatement(read,
        input!.preparedRead, warehouse, role, limits.timeoutSeconds,
        limits.maxRequests, limits.maxRequestBytes));
      while (true) {
        const request = checked(context.project(moon.clientProgramSnowflakeNextRequest,
          moon, [statement]));
        if (request === undefined || request === null) break;
        let response: Response, requestAttempted = false;
        try {
          response = await context.readChild({operation: SNOWFLAKE_SQL_READ_OPERATION, prepare() {
            const material = moon.clientProgramSnowflakeRequestMaterial(request);
            const method = runtimeField(material, 0), path = runtimeField(material, 1);
            const body = runtimeField(material, 2);
            checked(moon.clientProgramSnowflakeAttemptRequest(statement, request));
            attempted = requestAttempted = true;
            return Object.freeze<ReturnType<Child['prepare']>>({original: request, request: Object.freeze({method, path,
              ...(body === undefined || body === null ? {} : {body}),
              headers: [['user-agent', 'actql-snowflake/0.1'],
                ['x-snowflake-authorization-token-type', authenticationType]],
              responseHeaders: ['content-encoding']}),
              project(observed) {return observed;}});
          }});
        } catch (cause) {
          // Preserve the original Host/transport refusal. A failed request
          // does not create a second submit or resolve the first statement.
          if (requestAttempted) {
            try {checked(moon.clientProgramSnowflakeRecordResponseLoss(statement, request));}
            catch (error) {recordingFailure = error; recordingFailed = true;}
          }
          throw cause;
        }
        lastResponse = response;
        if (response.statusCode === 202) pendingStatement = true;
        await context.consumeChargedResponse(charge => {
          const ticket = checked(moon.clientProgramSnowflakeAdoptManagedResponse(
            statement, request, response.statusCode, charge));
          let body;
          try {body = decodeResponse(response, limits.maxBytes);}
          catch (cause) {
            try {checked(moon.clientProgramSnowflakeRecordDecoderRefusal(statement, ticket));}
            catch (error) {recordingFailure = error; recordingFailed = true;}
            throw cause;
          }
          const before = runtimeField(moon.clientProgramSnowflakeReadUsage(read), 1) as bigint;
          checked(moon.clientProgramSnowflakeAcceptResponse(statement, ticket, body));
          return Number((runtimeField(moon.clientProgramSnowflakeReadUsage(read), 1) as bigint) - before);
        });
        if (response.statusCode === 202 && limits.pollDelayMs !== 0) {
          await delay(limits.pollDelayMs, undefined, {signal: context.signal});
        }
      }
      if (!moon.clientProgramSnowflakeStatementComplete(statement)) fail('SnowflakeReadIncomplete');
      pendingStatement = false;
    },
    onError(cause: unknown, retained: Response | undefined, confirmTransportStop: () => boolean) {
      const observation = retained?.body === lastResponse?.body ? lastResponse : retained;
      const status = observation?.statusCode;
      let outcome = attempted ? 'unknown' : 'not_started';
      let cleanupFailure, cleanupFailed = false;
      if (attempted && !pendingStatement && Number.isInteger(status) &&
          status !== 202 && status !== 408 && status! < 500 &&
          observation === lastResponse) {
        try {if (confirmTransportStop() === true) outcome = 'stopped';}
        catch (error) {cleanupFailure = error; cleanupFailed = true;}
      }
      const failure: StatementFailure = new AcquisitionOpenError(cause, outcome);
      if (observation !== undefined) Object.defineProperty(failure, 'observation', {value: observation});
      if (cleanupFailed) Object.defineProperty(failure, 'cleanupFailure', {value: cleanupFailure});
      if (recordingFailed) Object.defineProperty(failure, 'recordingFailure', {value: recordingFailure});
      if (statement !== undefined) {
        const original = moon.clientProgramSnowflakeStatementOriginal(statement);
        failure.originalStatement = Object.freeze({requestId: runtimeField(original, 0),
          statementHandle: runtimeField(original, 1) ?? undefined});
      }
      return failure;
    },
    retire() {
      if (read === undefined) return true;
      if (moon.clientProgramSnowflakeRetireManagedRead(read) !== true) return false;
      read = statement = input = description = lastResponse = recordingFailure = undefined;
      return true;
    },
  });
}
