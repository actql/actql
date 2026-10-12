// Physical sequencing for the common checked keyed capture. Metadata and media
// are two actual responses in the same RowRun. A metadata-only empty page
// consumes its exact charge ticket without claiming a completed Source/key.
// Only the existing capture owner can return the issued ContentRef for the
// final row; this module has no issuer, completion receipt or cleanup ledger.
import {readGcsVersionedContent, gcsMetadataRequestWire} from './gcs-versioned-content.mjs';
import {ownInvocationLimits} from '../../../host-common/owned-invocation-context.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
export async function readGcsKeyedContent({requestWire, resolveResource,
  beginRequest, chargePage, consumePage, captureContent, chargeVerification, verifyRead,
  credential, limits, signal, callResource}) {
  if (typeof requestWire !== 'string' ||
      [resolveResource, beginRequest, chargePage, consumePage, captureContent,
        chargeVerification, verifyRead].some(callback => typeof callback !== 'function')) {
    fail('InvalidGcsKeyedContentRead');
  }
  let request;
  try { request = JSON.parse(requestWire); } catch { fail('InvalidGcsKeyedContentRead'); }
  if (request === null || typeof request !== 'object' || Array.isArray(request) ||
      Object.keys(request).sort().join(',') !== 'resource,version' ||
      request.resource === null || typeof request.resource !== 'object' ||
      Array.isArray(request.resource) || typeof request.version !== 'string' ||
      !/^[1-9][0-9]{0,19}$/u.test(request.version)) fail('InvalidGcsKeyedContentRead');
  // ResourceRef's admitted fields are primitive. Do not let a resolver mutate
  // the exact request identity that the final row must still correlate with.
  request.resource = Object.freeze(request.resource);
  Object.freeze(request);
  // The existing keyed/capture envelope must fund this bounded original-limits
  // view and its overlap with the physical invocation context before entry.
  // Resolve/request callbacks may await before that context is constructed;
  // neither callback may widen the originally admitted read bounds.
  limits = ownInvocationLimits(limits);
  // This resolver belongs to the installed Resource/Catalog observation, not
  // to the Program. It must validate the exact issued reference and scope.
  const locator = await resolveResource(request.resource, signal);
  signal?.throwIfAborted();
  if (locator === null || typeof locator !== 'object' || Array.isArray(locator) ||
      Object.keys(locator).sort().join(',') !== 'bucket,objectName,prefix') {
    fail('GcsKeyedResourceUnavailable');
  }
  const target = Object.freeze({...locator, generation: request.version});
  const initialAuthorization = await beginRequest(gcsMetadataRequestWire(target));
  signal?.throwIfAborted();
  let mediaCharge;
  const captured = await readGcsVersionedContent({target, limits, signal,
    credential, callResource, initialAuthorization,
    authorizationForRequest: ({requestWire: wire}) => beginRequest(wire),
    recheckAuthorization: async () => {
      await verifyRead();
      signal?.throwIfAborted();
      // This checks current authority through the original installed owner;
      // it does not mint a new grant or account a request that was not sent.
      return initialAuthorization;
    },
    chargeBody: async (body, observation) => {
      const ticket = await chargePage(body);
      if (observation.phase === 'metadata') await consumePage([], {charge: ticket});
      else mediaCharge = ticket;
      return ticket;
    },
    chargeVerification,
    receiveContent: (bytes, observation) => captureContent({bytes,
      mediaType: observation.metadata.mediaType,
      contentCid: observation.digests.contentCid,
      metadata: observation.metadata, observations: observation.observations}),
  });
  signal?.throwIfAborted();
  await consumePage([{resource: request.resource, version: request.version,
    content: captured.receipt}], {charge: mediaCharge});
  signal?.throwIfAborted();
}
