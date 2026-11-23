import {checked} from '../../../host-common/runtime-result.mjs';
import {checkedSalesforceCatalogPreparation} from
  './salesforce-effect-preparation-result.mjs';
import {ownInvocationAuthorization} from
  '../../../host-common/owned-invocation-context.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';

import type {SalesforceRequestScope, SalesforceWriteScope} from './salesforce-single-write.mjs';

import type {remoteCredentialControl} from '../../../host-common/remote-credential-control.mjs';
import type {withHttpsCredentialRunResponseOriginal} from '../../../site-node/https-credential-resource.mjs';

type Runtime = Readonly<{
  salesforceCatalogObservationJson(observation: unknown): string;
  salesforceSingleWriteRequestOrgId(request: unknown): string;
  salesforceSingleWriteRequestGrantOperation(request: unknown): string;
  salesforceSingleWriteRequestScopeMatches(request: unknown, ...scope: SalesforceRequestScope): boolean;
  salesforceCheckExecutionSingleWrite(mapping: unknown, request: unknown): unknown;
  salesforcePrepareWriteCapability(request: unknown, runtimeBundleCid: string, collection: boolean, bytes: number): unknown;
  salesforceCheckWriteCapabilityRequest(evidence: unknown, request: unknown, runtimeBundleCid: string): unknown;
  salesforceRecheckWriteCapability(evidence: unknown, current: unknown): unknown;
  salesforceWriteCapabilityIdentity(evidence: unknown): string;
  salesforceWriteCapabilityBody(evidence: unknown): string;
  salesforceWriteCapabilityRoute(evidence: unknown): number;
}>;
type CredentialOrg = NonNullable<Parameters<typeof matchesSalesforceCredentialOrg>[0]>;
type RunOriginal = Parameters<typeof withHttpsCredentialRunResponseOriginal>;
type GrantControl = ReturnType<typeof remoteCredentialControl>;
type GrantScope = Parameters<GrantControl['prepare']>[0];
type Credential = CredentialOrg & Readonly<{
  control: GrantControl;
  journal: Pick<RunOriginal[2], 'checkGrant'>;
  now?: () => number | bigint;
}>;
type Authority = Readonly<{scope: object}>;
type Current = () => string;
type Authorization = ReturnType<typeof ownInvocationAuthorization>;
type Capability = Readonly<{identity: string; wire: string}>;
type Owner = {
  moon: Runtime; maxRows: number; attested: Current | undefined;
  credential: Credential & Readonly<{now(): number | bigint}>;
  authorization: Authorization; evidence?: unknown;
};
type Issue = Readonly<{
  moon: Runtime; requests: readonly unknown[]; currentObservation: unknown;
  authorization?: Readonly<{grant?: unknown; scope: object}>; authority?: Authority;
  credential: Credential; mapping: unknown; collection?: boolean; maxRows: number; maxBytes: number;
}>;
type Recheck = Readonly<{currentObservation?: unknown; collection?: boolean}>;

const owners = new WeakMap<Capability, Readonly<Owner>>();
// Site attestations of its installed runtime and connection for one Effect
// dispatch, mapped to the Site's current check. Only these stand in for a
// signed grant; a copied or constructed object cannot.
const attestations = new WeakMap<Authority, Current>();
const fail: () => never = () => {
  throw Object.assign(new Error('InvalidSalesforceEffectCapability'), {
    code: 'InvalidSalesforceEffectCapability',
  });
};

// Register an installed Site's attestation for one Effect dispatch: the
// grant scope a write of that dispatch would carry, and `current`, which
// returns the Site's runtime bundle while it is installed as attested and
// throws otherwise. It grants no credential use; a write still needs its own
// grant for an approved commit decision.
export function attestSalesforceEffectCapabilityAuthority({scope, current}: Authority & Readonly<{current: Current}>) {
  if (scope === null || typeof scope !== 'object' ||
      typeof current !== 'function') fail();
  const authority = Object.freeze({scope: Object.freeze({...scope})});
  attestations.set(authority, current);
  return authority;
}

function currentGrant(owner: Readonly<Owner>) {
  const {credential, authorization, attested} = owner;
  if (attested !== undefined) return attested();
  const {control, journal, now} = credential;
  const grant = journal.checkGrant(control.identity(authorization.grant),
    BigInt(now()), authorization.scope as GrantScope, control);
  return control.projection(grant)[7] as string;
}

function checkRequests(owner: Readonly<Owner>, requests: readonly unknown[], runtimeBundleCid: string) {
  if (!Array.isArray(requests) || requests.length === 0 ||
      requests.length > owner.maxRows) fail();
  const {moon, authorization, credential, evidence} = owner;
  const scope = authorization.scope as SalesforceWriteScope;
  for (const request of requests) {
    if (!matchesSalesforceCredentialOrg(credential,
        moon.salesforceSingleWriteRequestOrgId(request)) ||
        scope.operation !==
          moon.salesforceSingleWriteRequestGrantOperation(request) ||
        !moon.salesforceSingleWriteRequestScopeMatches(request,
          scope.namespaceId, scope.principal, scope.environment,
          scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
          scope.connectorRevision, scope.resourceOrigin,
          scope.runInvocationCid, scope.dispatchRequestCid)) fail();
    checked(moon.salesforceCheckWriteCapabilityRequest(evidence,
      request, runtimeBundleCid));
  }
}

// The loaded Connector defines the supported profile in MoonBit, and each
// request must be exactly the write of the Effect's execution Mapping. The
// Site
// authenticates the configured runtime and connection against its signed
// grant journal, or by its own attestation (`authority`) before any commit is
// decided; no secret is resolved and no credential use is consumed.
export function issueSalesforceEffectCapability({moon, requests,
  currentObservation, authorization, authority, credential, mapping,
  collection = false, maxRows, maxBytes}: Issue) {
  const attested = authority === undefined ? undefined
    : attestations.get(authority);
  if ((authority === undefined) === (authorization === undefined) ||
      (authority !== undefined && attested === undefined)) fail();
  if (!moon || !Array.isArray(requests) || !requests[0] || !mapping ||
      !currentObservation || typeof collection !== 'boolean' ||
      !Number.isSafeInteger(maxRows) || maxRows < 1 || maxRows > 100_000 ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 1_000_000 ||
      typeof credential?.journal?.checkGrant !== 'function' ||
      typeof credential.control?.projection !== 'function' ||
      (credential.now !== undefined && typeof credential.now !== 'function')) {
    fail();
  }
  const owner: Owner = {
    moon, maxRows, attested,
    credential: Object.freeze({...credential, now: credential.now ?? Date.now}),
    authorization: ownInvocationAuthorization({...(authority ?? authorization),
      useId: 'capability-admission'}),
  };
  // Each request must be exactly the write of this Effect's execution
  // Mapping (Resource, operation, fields, upsert key), for the declaring
  // Site, with every field meaning what was declared, before any grant or
  // credential check.
  for (const request of requests) {
    checked(moon.salesforceCheckExecutionSingleWrite(mapping, request));
  }
  const runtimeBundleCid = currentGrant(owner);
  owner.evidence = checked(moon.salesforcePrepareWriteCapability(
    requests[0], runtimeBundleCid, collection, maxBytes));
  checkRequests(owner, requests, runtimeBundleCid);
  checkedSalesforceCatalogPreparation(moon.salesforceRecheckWriteCapability(
    owner.evidence, currentObservation), moon, currentObservation);
  const result = Object.freeze({
    identity: moon.salesforceWriteCapabilityIdentity(owner.evidence),
    wire: moon.salesforceWriteCapabilityBody(owner.evidence),
  });
  owners.set(result, Object.freeze(owner));
  return result;
}

export function inspectSalesforceEffectCapability(capability: Capability, requests: readonly unknown[],
  {currentObservation, collection}: Recheck = {}) {
  const owner = owners.get(capability);
  if (!owner) fail();
  const runtimeBundleCid = currentGrant(owner);
  checkRequests(owner, requests, runtimeBundleCid);
  if (currentObservation !== undefined) {
    checkedSalesforceCatalogPreparation(owner.moon.salesforceRecheckWriteCapability(
      owner.evidence, currentObservation), owner.moon, currentObservation);
  }
  const route = owner.moon.salesforceWriteCapabilityRoute(owner.evidence);
  if (collection !== undefined && collection !== (route === 1)) fail();
  return Object.freeze({identity: capability.identity, route});
}
