// One real identity request in an already authorized acquisition. The Host
// supplies its original portal observation and the same Credential binding;
// this adapter neither grants identity access nor creates the binding.
import {ownInvocationContext, invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';

export const HUBSPOT_ACCOUNT_DETAILS_OPERATION = 'hubspot:account:details';
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const fail = code => { throw Object.assign(new Error(code), {code}); };

// Original bounded response custody survives a later projection, current or
// accounting failure. It is private input for the original caller's cleanup
// and persistence; no new public error payload, ACK or retry classification.
export class HubSpotAccountObservationFailure extends Error {
  constructor(cause, observation) {
    super(typeof cause?.message === 'string' ? cause.message :
      'HubSpotAccountObservationFailed', {cause});
    this.name = typeof cause?.name === 'string' ? cause.name : 'Error';
    this.code = cause?.code ?? 'HubSpotAccountObservationFailed';
    Object.defineProperty(this, 'observation', {value: observation});
  }
}

// Same Native identity decoder for Source and installed Effect reads. HTTP
// acceptance, original current/accounting and response custody stay with the
// invoking physical owner; this pure projection grants no access.
export function projectHubSpotAccountIdentity({moon, body, originalPortalId, limits}) {
  const projected = JSON.parse(moon.hubspotRecheckAccountIdentityJson(body, originalPortalId,
    limits.maxResponseBytes, limits.maxNodes, limits.maxDepth));
  if (projected.refused !== undefined) {
    throw Object.assign(new Error('HubSpotAccountIdentityRefused'), {
      code: 'HubSpotAccountIdentityRefused', refusal: projected.refused});
  }
  if (projected.account === null || typeof projected.account !== 'object' ||
      Object.keys(projected.account).sort().join(',') !== 'portalId,responseSha256' ||
      projected.account.portalId !== originalPortalId ||
      !/^[0-9a-f]{64}$/u.test(projected.account.responseSha256 ?? '')) {
    fail('InvalidHubSpotAccountProjection');
  }
  return Object.freeze(projected.account);
}

export async function observeHubSpotAccount({moon, originalPortalId,
  authorization, credential, limits, current, chargeResponse, consumeObservation,
  signal, callResource = callHttpsCredentialResource}) {
  if (typeof moon?.hubspotRecheckAccountIdentityJson !== 'function' ||
      typeof originalPortalId !== 'string' || originalPortalId.length === 0 ||
      originalPortalId.length > 11 ||
      credential?.binding === null || typeof credential?.binding !== 'object' ||
      !['maxResponseBytes', 'maxNodes', 'maxDepth'].every(key => positive(limits?.[key])) ||
      [current, chargeResponse, consumeObservation, callResource].some(value =>
        typeof value !== 'function')) fail('InvalidHubSpotAccountObservation');
  const project = moon.hubspotRecheckAccountIdentityJson;
  const context = ownInvocationContext({authorization, credential, limits,
    callbacks: {current, chargeResponse, consumeObservation, callResource}});
  if (context.scope.operation !== HUBSPOT_ACCOUNT_DETAILS_OPERATION) {
    fail('ForeignHubSpotAccountOperation');
  }
  signal?.throwIfAborted();
  await context.callbacks.current();
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({
    authorization: context.authorization, credential: context.credential,
    callResource: function accountResource(options) {
      return context.callbacks.callResource({...options,
        currentBeforeSend: context.callbacks.current});
    },
    operation: HUBSPOT_ACCOUNT_DETAILS_OPERATION, method: 'GET',
    path: '/account-info/v3/details', query: [], headers: [['accept', 'application/json']],
    responseHeaders: [], maxResponseBytes: context.limits.maxResponseBytes, signal,
  });
  try {
    // Keep the received HTTP outcome before accounting/current callbacks can
    // await. Later mutation cannot upgrade that original provider rejection.
    const accepted = response.accepted && response.statusCode === 200;
    // Received bytes remain real usage even if authority was revoked while
    // awaiting them. No provider decoding precedes the original Ledger charge.
    const charge = await context.callbacks.chargeResponse(response.body);
    await context.callbacks.current();
    signal?.throwIfAborted();
    if (!accepted) {
      fail('HubSpotAccountObservationRejected');
    }
    const identity = projectHubSpotAccountIdentity({moon: {hubspotRecheckAccountIdentityJson: project},
      body: response.body, originalPortalId, limits: context.limits});
    await context.callbacks.consumeObservation(charge);
    await context.callbacks.current();
    signal?.throwIfAborted();
    return Object.freeze({identity, response});
  } catch (cause) {
    throw new HubSpotAccountObservationFailure(cause, response);
  }
}
