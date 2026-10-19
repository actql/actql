import {setImmediate as yieldTurn} from 'node:timers/promises';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationLimits} from
  '../../../host-common/owned-invocation-context.mjs';

export const GCS_FILE_LIST_OPERATION = 'gcs:file:list';
const origin = 'https://storage.googleapis.com';
const fail = code => { throw Object.assign(new Error(code), {code}); };
const positive = value => Number.isSafeInteger(value) && value > 0;
const text = (value, max, empty = false) => typeof value === 'string' &&
  (empty || value.length > 0) && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value) && Buffer.byteLength(value) <= max;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const encode = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  char => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);

function setup(options) {
  const {moon, target, limits, listing, credential, authorizationFor, chargePage,
    resourceFor, callResource = callHttpsCredentialResource} = options;
  if ((moon !== undefined && typeof moon?.gcsObjectTimestamp !== 'function') ||
      !object(target) || !text(target.bucket, 222) ||
      typeof target.prefix !== 'string' || !target.prefix.isWellFormed() ||
      Buffer.byteLength(target.prefix) > 1024 || !object(credential) ||
      !object(limits) || !positive(limits.maxPageBytes) ||
      !positive(limits.maxPageItems) || limits.maxPageItems > 1000 ||
      !positive(limits.maxRequestBytes) || !positive(limits.maxTimeMs) ||
      limits.maxTimeMs > 2_147_483_647 ||
      [listing?.beginRequest, listing?.consumePage, authorizationFor,
        chargePage, resourceFor, callResource].some(value => typeof value !== 'function')) {
    fail('InvalidGcsFileListing');
  }
  return Object.freeze({moon, target: Object.freeze({...target}),
    limits: ownInvocationLimits(limits), credential: Object.freeze({...credential}),
    callbacks: Object.freeze({beginRequest: listing.beginRequest,
      consumePage: listing.consumePage, authorizationFor, chargePage,
      resourceFor, callResource})});
}

function authorization(value, original) {
  const owned = ownInvocationAuthorization(value);
  if (!owned.grant || owned.scope.operation !== GCS_FILE_LIST_OPERATION ||
      owned.scope.resourceOrigin !== origin ||
      !Number.isSafeInteger(owned.scope.siteGeneration) || owned.scope.siteGeneration < 0 ||
      (original && !invocationBindingsMatch(owned.scope, original))) {
    fail('InvalidGcsFileListingAuthorization');
  }
  return owned;
}

function page(body, target, maximum, moon) {
  let parsed;
  try { parsed = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(body)); }
  catch { fail('InvalidGcsFileListingPage'); }
  if (!object(parsed) || parsed.kind !== 'storage#objects' ||
      (parsed.prefixes !== undefined &&
        (!Array.isArray(parsed.prefixes) || parsed.prefixes.length !== 0)) ||
      (parsed.items !== undefined && !Array.isArray(parsed.items)) ||
      (parsed.nextPageToken !== undefined && !text(parsed.nextPageToken, 8192))) {
    fail('InvalidGcsFileListingPage');
  }
  const items = parsed.items ?? [];
  if (items.length > maximum) fail('GcsFileListingPageItemsExceeded');
  // No delimiter, matchGlob, soft-deleted objects or all-version listing is
  // requested. Selection and duplicate/conflicting Resource facts belong to
  // the common listing owner, not this provider transport.
  const timestamps = [];
  for (const item of items) {
    if (!object(item) || item.bucket !== target.bucket ||
        // Keep the original JSON object name, including legal controls.
        // XML/CLI compatibility advice is not a listing naming restriction.
        typeof item.name !== 'string' || item.name.length === 0 ||
        !item.name.isWellFormed() || /[\r\n]/u.test(item.name) ||
        Buffer.byteLength(item.name) > 1024 || !item.name.startsWith(target.prefix) ||
        typeof item.generation !== 'string' || !/^[1-9][0-9]{0,19}$/u.test(item.generation) ||
        typeof item.size !== 'string' || !/^(0|[1-9][0-9]{0,19})$/u.test(item.size) ||
        BigInt(item.size) > BigInt(Number.MAX_SAFE_INTEGER) ||
        (item.contentType !== undefined && !text(item.contentType, 1024)) ||
        (item.updated !== undefined && (!text(item.updated, 128) ||
          !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/u.test(item.updated)))) {
      fail('GcsFileListingMetadataMismatch');
    }
    // Retain the original report separately from the logical Timestamp.
    // The ordinary provider uses the same exact Common projection as its
    // object table; the explicit historical source-only ABI is unchanged.
    let timestamp = item.updated;
    if (timestamp !== undefined && moon !== undefined) {
      timestamp = moon.gcsObjectTimestamp(timestamp);
      if (typeof timestamp !== 'string' || Buffer.byteLength(timestamp) > 30) {
        fail('GcsFileListingMetadataMismatch');
      }
    }
    timestamps.push(timestamp);
  }
  return {items, timestamps, nextToken: parsed.nextPageToken};
}

// Site transport, not a second listing owner. The common owner checks the
// request cursor before every send and admits all observed Resources through
// its bounded selector, issuer and completion protocol. The Host supplies
// resourceFor; neither this transport nor a Program issues reference authority.
// The prefix is an installed scope, not a translation of the ActQL glob.
export async function readGcsFileListing(options) {
  const {moon, target, limits, credential, callbacks} = setup(options);
  const signal = AbortSignal.any([AbortSignal.timeout(limits.maxTimeMs),
    ...(options.signal === undefined ? [] : [options.signal])]);
  let nextToken, firstScope, index = 0;
  for (;;) {
    signal.throwIfAborted();
    // beginRequest enforces the cumulative page/attempt/time ceilings and
    // repeated-token prohibition before the physical operation is authorized.
    await callbacks.beginRequest(nextToken);
    const auth = authorization(await callbacks.authorizationFor(index++), firstScope);
    firstScope ??= auth.scope;
    signal.throwIfAborted();
    const response = await invokeScopedCredentialOperation({
      authorization: auth, credential, callResource: callbacks.callResource,
      operation: GCS_FILE_LIST_OPERATION, method: 'GET',
      path: `/storage/v1/b/${encode(target.bucket)}/o`,
      query: [['prefix', target.prefix], ['maxResults', String(limits.maxPageItems)],
        ['projection', 'noAcl'],
        ...(nextToken === undefined ? [] : [['pageToken', nextToken]])],
      headers: [['accept-encoding', 'identity']], responseHeaders: ['content-encoding'],
      maxRequestBytes: limits.maxRequestBytes, maxResponseBytes: limits.maxPageBytes, signal,
    });
    if (!Buffer.isBuffer(response.body)) fail('InvalidGcsFileListingPage');
    // Preserve the exact received-body charge even for an error response or
    // malformed page. Normalized envelope bytes never replace this charge.
    const charge = await callbacks.chargePage(response.body);
    signal.throwIfAborted();
    if (charge === undefined || charge === null) fail('GcsFileListingChargeMissing');
    if (response.body.length > limits.maxPageBytes) fail('GcsFileListingPageBytesExceeded');
    if (!response.accepted || response.statusCode !== 200) fail('GcsFileListingRejected');
    if (!Array.isArray(response.headers) || response.headers.length > 1 ||
        response.headers.some(pair => !Array.isArray(pair) || pair.length !== 2 ||
          pair[0] !== 'content-encoding' || pair[1] !== 'identity')) {
      fail('GcsFileListingRepresentationUnsupported');
    }
    const observed = page(response.body, target, limits.maxPageItems, moon);
    const items = [];
    for (const [position, item] of observed.items.entries()) {
      signal.throwIfAborted();
      const resource = callbacks.resourceFor(Object.freeze({bucket: target.bucket,
        objectName: item.name}));
      if (!object(resource)) fail('GcsFileListingResourceUnavailable');
      items.push({resource, name: item.name, path: item.name, version: item.generation,
        media_type: item.contentType ?? null, size_bytes: Number(item.size),
        modified_at: observed.timestamps[position] ?? null});
      if ((position + 1) % 64 === 0) await yieldTurn(undefined, {signal});
    }
    const envelope = Buffer.from(JSON.stringify({items,
      request_token: nextToken ?? null, next_token: observed.nextToken ?? null}));
    if (envelope.length > limits.maxPageBytes) fail('GcsFileListingEnvelopeBytesExceeded');
    await callbacks.consumePage(envelope, {charge});
    signal.throwIfAborted();
    nextToken = observed.nextToken;
    if (nextToken === undefined) return;
    // Even an empty page with a token remains incomplete. The common owner
    // observes every next token; no local output LIMIT can end this scan.
  }
}
