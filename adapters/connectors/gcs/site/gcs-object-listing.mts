// Ordinary object rows share the installed Source/Credential/RowRun owners.
// This transport does not grant a read, complete LIST_FILES, issue references
// from metadata, or turn an incomplete provider scan into a captured Result.
import type {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {setImmediate as yieldTurn} from 'node:timers/promises';
import {checked} from '../../../host-common/runtime-result.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization} from '../../../host-common/owned-invocation-context.mjs';
import {GCS_FILE_LIST_OPERATION} from './gcs-file-listing.mjs';

type ObjectLimits = Readonly<{maxPageBytes: number; maxPageItems: number; maxRequestBytes: number;
  maxTimeMs: number; maxPages: number; maxRows: number}>;
type ObjectRuntime = Readonly<{
  gcsObjectFailureCode(issue: unknown): string;
  gcsObjectListingPrefix(prefix: string, request: Buffer, bytes: number, nodes: number, depth: number): unknown;
  gcsObjectMetadataPage(body: Buffer, bucket: string, prefix: string, maximum: number,
    bytes: number, nodes: number, depth: number, metadataBytes: number): unknown;
  gcsObjectMetadataPageCount(page: unknown): number;
  gcsObjectMetadataPageNextToken(page: unknown): string | undefined;
  gcsObjectMetadataPageRowJson(page: unknown, position: number, bytes: number, nodes: number, depth: number): unknown;
}>;
type Invocation = ReturnType<typeof ownInvocationAuthorization>;
type Scope = Readonly<{operation?: string; resourceOrigin?: string; siteGeneration?: number}>;
type Response = Pick<Awaited<ReturnType<typeof callHttpsCredentialResource>>,
  'accepted' | 'statusCode' | 'headers' | 'body'>;
type Row = Readonly<{name: string; version: string; metadata: unknown}> & Readonly<Record<string, unknown>>;
type ListingOptions = Readonly<{
  moon: ObjectRuntime; target: Readonly<{bucket: string; prefix: string}>; limits: ObjectLimits; credential: unknown;
  authorizationFor(index: number): unknown; chargePage(body: Buffer): unknown;
  consumePage(rows: readonly (Row & Readonly<{resource: object}>)[], original: Readonly<{charge: unknown}>): unknown;
  resourceFor(target: Readonly<{bucket: string; objectName: string}>): unknown;
  callResource: (...args: never[]) => unknown;
  verifyRead(): unknown; requestWire: string; signal?: AbortSignal;
}>;

const origin = 'https://storage.googleapis.com';
const positive = (value: number) => Number.isInteger(value) && value > 0 && value <= 2147483647;
const exact = (value: unknown, maximum: number, empty = false): value is string => typeof value === 'string' &&
  (empty || value.length > 0) && value.isWellFormed() && Buffer.byteLength(value) <= maximum;
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const encode = (value: string) => encodeURIComponent(value).replace(/[!'()*]/gu,
  character => `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
function result(moon: Pick<ObjectRuntime, 'gcsObjectFailureCode'>, value: unknown) {
  try { return checked(value); }
  catch (error) {
    if ((error as {code?: unknown} | null)?.code !== 'MoonBitHostFailure') throw error;
    const code = moon.gcsObjectFailureCode((error as Error).cause);
    throw Object.assign(new Error(code, {cause: (error as Error).cause}), {code});
  }
}

export async function readGcsObjects({moon, target, limits, credential,
  authorizationFor, chargePage, consumePage, resourceFor, callResource,
  verifyRead, requestWire, signal: parentSignal}: ListingOptions) {
  if (!exact(target?.bucket, 222) || !exact(target?.prefix, 1024, true) ||
      !(['maxPageBytes', 'maxPageItems', 'maxRequestBytes', 'maxTimeMs', 'maxPages', 'maxRows'] as const)
        .every(name => positive(limits?.[name])) || limits.maxPageItems > 1000 ||
      typeof requestWire !== 'string' || !requestWire.isWellFormed() ||
      Buffer.byteLength(requestWire) > limits.maxPageBytes ||
      [authorizationFor, chargePage, consumePage, resourceFor, callResource, verifyRead]
        .some(value => typeof value !== 'function') ||
      [moon?.gcsObjectMetadataPage, moon?.gcsObjectMetadataPageCount,
        moon?.gcsObjectMetadataPageNextToken, moon?.gcsObjectMetadataPageRowJson,
        moon?.gcsObjectFailureCode, moon?.gcsObjectListingPrefix]
        .some(value => typeof value !== 'function')) {
    fail('InvalidGcsObjectListing');
  }
  // Snapshot only finite Host-selected clamps, not a new capacity/grant. For
  // this flat provider shape every node/metadata entry consumes input bytes;
  // the byte clamp is also a conservative parser node/entry ceiling.
  const bound = Object.freeze({...limits});
  const prefix = result(moon, moon.gcsObjectListingPrefix(target.prefix,
    Buffer.from(requestWire), bound.maxPageBytes, bound.maxPageBytes, 64)) as string;
  const scope = Object.freeze({bucket: target.bucket, prefix});
  const signal = AbortSignal.any([AbortSignal.timeout(bound.maxTimeMs),
    ...(parentSignal === undefined ? [] : [parentSignal])]);
  const tokens = new Set<string>();
  let next: string | undefined, originalScope: Scope | undefined, count = 0;
  for (let index = 0; ; index++) {
    signal.throwIfAborted();
    if (index >= bound.maxPages || count >= bound.maxRows) fail('GcsObjectListingLimit');
    await verifyRead();
    signal.throwIfAborted();
    const authorization = ownInvocationAuthorization(await authorizationFor(index)) as Invocation & Readonly<{scope: Scope}>;
    if (!authorization.grant || authorization.scope.resourceOrigin !== origin ||
        authorization.scope.operation !== GCS_FILE_LIST_OPERATION ||
        !Number.isSafeInteger(authorization.scope.siteGeneration) ||
        (authorization.scope.siteGeneration as number) < 0 || (originalScope !== undefined &&
          !invocationBindingsMatch(authorization.scope, originalScope))) {
      fail('InvalidGcsObjectListingAuthorization');
    }
    originalScope ??= authorization.scope;
    signal.throwIfAborted();
    const maximum = Math.min(bound.maxPageItems, bound.maxRows - count);
    const response = await invokeScopedCredentialOperation({authorization, credential,
      callResource, operation: GCS_FILE_LIST_OPERATION, method: 'GET',
      path: `/storage/v1/b/${encode(scope.bucket)}/o`,
      query: [['prefix', scope.prefix], ['maxResults', String(maximum)], ['projection', 'noAcl'],
        ...(next === undefined ? [] : [['pageToken', next]])],
      headers: [['accept-encoding', 'identity']], responseHeaders: ['content-encoding'],
      maxRequestBytes: bound.maxRequestBytes, maxResponseBytes: bound.maxPageBytes, signal}) as Response;
    if (!Buffer.isBuffer(response.body)) fail('InvalidGcsObjectListingPage');
    const charge = await chargePage(response.body);
    signal.throwIfAborted();
    if (charge === undefined || charge === null) fail('GcsObjectListingChargeMissing');
    if (response.body.length > bound.maxPageBytes) fail('GcsObjectListingPageBytesExceeded');
    if (!response.accepted || response.statusCode !== 200) fail('GcsObjectListingRejected');
    if (!Array.isArray(response.headers) || response.headers.length > 1 ||
        response.headers.some(pair => !Array.isArray(pair) || pair.length !== 2 ||
          pair[0] !== 'content-encoding' || pair[1] !== 'identity')) {
      fail('GcsObjectListingRepresentationUnsupported');
    }
    const page = result(moon, moon.gcsObjectMetadataPage(response.body, scope.bucket,
      scope.prefix, maximum, bound.maxPageBytes, bound.maxPageBytes, 64, bound.maxPageBytes));
    const size = moon.gcsObjectMetadataPageCount(page);
    const rows = [];
    for (let position = 0; position < size; position++) {
      signal.throwIfAborted();
      const row = JSON.parse(result(moon, moon.gcsObjectMetadataPageRowJson(page,
        position, bound.maxPageBytes, bound.maxPageBytes, 64)) as string) as Row;
      const resource = resourceFor(Object.freeze({bucket: scope.bucket, objectName: row.name}));
      if (resource === null || typeof resource !== 'object') fail('GcsObjectListingResourceUnavailable');
      rows.push({resource, ...row});
      if ((position + 1) % 64 === 0) await yieldTurn(undefined, {signal});
    }
    await consumePage(rows, {charge});
    signal.throwIfAborted();
    count += size;
    next = moon.gcsObjectMetadataPageNextToken(page);
    if (next === undefined) return;
    if (tokens.has(next)) fail('GcsObjectListingRepeatedToken');
    tokens.add(next);
    // Empty pages still consume an original request and retain continuation.
    // Neither an output limit nor a successful callback proves completion.
  }
}
