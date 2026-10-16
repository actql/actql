// Ordinary object rows share the installed Source/Credential/RowRun owners.
// This transport does not grant a read, complete LIST_FILES, issue references
// from metadata, or turn an incomplete provider scan into a captured Result.
import {setImmediate as yieldTurn} from 'node:timers/promises';
import {checked} from '../../../host-common/runtime-result.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization} from '../../../host-common/owned-invocation-context.mjs';
import {GCS_FILE_LIST_OPERATION} from './gcs-file-listing.mjs';

const origin = 'https://storage.googleapis.com';
const positive = value => Number.isInteger(value) && value > 0 && value <= 2147483647;
const exact = (value, maximum, empty = false) => typeof value === 'string' &&
  (empty || value.length > 0) && value.isWellFormed() && Buffer.byteLength(value) <= maximum;
const fail = code => { throw Object.assign(new Error(code), {code}); };
const encode = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  character => `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
function result(moon, value) {
  try { return checked(value); }
  catch (error) {
    if (error?.code !== 'MoonBitHostFailure') throw error;
    const code = moon.gcsObjectFailureCode(error.cause);
    throw Object.assign(new Error(code, {cause: error.cause}), {code});
  }
}

export async function readGcsObjects({moon, target, limits, credential,
  authorizationFor, chargePage, consumePage, resourceFor, callResource,
  verifyRead, requestWire, signal: parentSignal}) {
  if (!exact(target?.bucket, 222) || !exact(target?.prefix, 1024, true) ||
      !['maxPageBytes', 'maxPageItems', 'maxRequestBytes', 'maxTimeMs', 'maxPages', 'maxRows']
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
    Buffer.from(requestWire), bound.maxPageBytes, bound.maxPageBytes, 64));
  const scope = Object.freeze({bucket: target.bucket, prefix});
  const signal = AbortSignal.any([AbortSignal.timeout(bound.maxTimeMs),
    ...(parentSignal === undefined ? [] : [parentSignal])]);
  const tokens = new Set();
  let next, originalScope, count = 0;
  for (let index = 0; ; index++) {
    signal.throwIfAborted();
    if (index >= bound.maxPages || count >= bound.maxRows) fail('GcsObjectListingLimit');
    await verifyRead();
    signal.throwIfAborted();
    const authorization = ownInvocationAuthorization(await authorizationFor(index));
    if (!authorization.grant || authorization.scope.resourceOrigin !== origin ||
        authorization.scope.operation !== GCS_FILE_LIST_OPERATION ||
        !Number.isSafeInteger(authorization.scope.siteGeneration) ||
        authorization.scope.siteGeneration < 0 || (originalScope !== undefined &&
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
      maxRequestBytes: bound.maxRequestBytes, maxResponseBytes: bound.maxPageBytes, signal});
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
        position, bound.maxPageBytes, bound.maxPageBytes, 64)));
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
