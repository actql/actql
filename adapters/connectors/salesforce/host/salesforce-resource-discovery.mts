import {requireAuthorizedDispatch} from
  '../../../host-common/authorization-gate.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {catalogRequiredReason, resolveSalesforceResource} from
  './salesforce-resource-resolver.mjs';

import type {CatalogBindingArguments, CatalogResourceArguments, ResourceAuthorization, ResourceBinding,
  ResourceCatalog, ResolveResource, ResourceResolutionRuntime} from './salesforce-resource-resolver.mjs';

export type DiscoveryRuntime = ResourceResolutionRuntime & Readonly<{
  salesforceCatalogObservationMatchesBinding(observation: unknown, ...binding: CatalogBindingArguments): boolean;
  salesforceCatalogObservationIsComplete(observation: unknown): boolean;
  salesforceCatalogResourceSummaryJson(...input: [...resource: CatalogResourceArguments, bytes: number]): unknown;
}>;
type DiscoveryOptions = Readonly<{moon: DiscoveryRuntime; catalog: ResourceCatalog;
  binding: ResourceBinding; authorization: ResourceAuthorization; connection: string}>;
type List = Readonly<{query?: string; maxResults?: number; signal?: AbortSignal}>;
type Inspect = Readonly<{resource?: string; maxSummaryBytes?: number; signal?: AbortSignal}>;
type Entry = Readonly<{name: string; outcome: string}>;
type Projection = Readonly<{version: unknown; listed_resources: readonly Entry[];
  truncated: boolean; listing_use_cid: unknown}>;
type DiscoveryError = Readonly<{code?: unknown}> | null | undefined;

const bindingFields = Object.freeze([
  'namespace_id', 'principal', 'environment', 'connection_revision', 'org_id',
  'site_key', 'site_generation', 'connector_registration',
  'connector_revision', 'resource_origin', 'run_invocation_cid',
  'dispatch_request_cid', 'sync_occurrence',
] as const);
const fail: () => never = () => {
  throw Object.assign(new Error('InvalidSalesforceResourceDiscovery'), {
    code: 'InvalidSalesforceResourceDiscovery',
  });
};
const resourceName = /^[A-Za-z_][A-Za-z0-9_]{0,254}$/u;


// An installed view of one exact observation. The view owns its binding;
// current metadata disclosure is checked for each returned Resource. It does
// not refresh a provider, grant read/write use, or turn partial metadata into
// evidence that a Resource is absent.
export function installSalesforceResourceDiscovery({moon, catalog, binding,
  authorization, connection}: DiscoveryOptions) {
  if (!moon || !catalog?.observation || !binding || !authorization ||
      typeof authorization.authorize !== 'function' ||
      typeof connection !== 'string') fail();
  const ownedBinding = Object.freeze(Object.fromEntries(bindingFields.map(
    name => [name, binding[name]]))) as ResourceBinding;
  if (bindingFields.some(name => name === 'site_generation'
    ? !Number.isSafeInteger(ownedBinding[name]) || ownedBinding[name] < 0
    : typeof ownedBinding[name] !== 'string' ||
      ownedBinding[name].length === 0) ||
      authorization.principal !== ownedBinding.principal ||
      connection !== `salesforce:${ownedBinding.org_id}` ||
      moon.salesforceCatalogObservationMatchesBinding(
        catalog.observation, ...(bindingFields.map(name => ownedBinding[name]) as CatalogBindingArguments))
        !== true) fail();
  const observationCid = moon.salesforceCatalogObservationCid(
    catalog.observation);
  const body = moon.salesforceCatalogObservationJson(catalog.observation);
  if (catalog.observationCid !== observationCid ||
      catalog.observationJson !== body) fail();
  const ownedCatalog = Object.freeze({observation: catalog.observation,
    observationCid, observationJson: body});
  const projection = JSON.parse(body) as Projection;
  if (projection.version !== 'actql-salesforce-catalog-observation/0.1' ||
      !Array.isArray(projection.listed_resources) ||
      typeof projection.truncated !== 'boolean') fail();
  const entries = Object.freeze(projection.listed_resources.map(entry => {
    if (typeof entry?.name !== 'string' || !resourceName.test(entry.name) ||
        typeof entry?.outcome !== 'string') fail();
    return Object.freeze({name: entry.name, outcome: entry.outcome});
  }));
  // A named observation carries no provider listing.
  const named = projection.listing_use_cid === null;
  const snapshotComplete = moon.salesforceCatalogObservationIsComplete(
    ownedCatalog.observation);
  const authorize = (resource: string, signal?: AbortSignal) => requireAuthorizedDispatch(
    authorization, 'acquisition', {connection, resource, operation: 'read'},
    {subjectCid: observationCid, signal});
  async function list({query = '', maxResults = 100, signal}: List = {}) {
    if (typeof query !== 'string' || query.length > 255 ||
        !Number.isSafeInteger(maxResults) || maxResults < 1 ||
        maxResults > 1000) fail();
    const match = query.toLowerCase();
    const visible = [];
    let resultTruncated = false;
    for (const entry of entries) {
      signal?.throwIfAborted();
      try {
        await authorize(entry.name, signal);
      } catch (error) {
        if ((error as DiscoveryError)?.code === 'ExecutionAuthorizationDenied') continue;
        throw error;
      }
      signal?.throwIfAborted();
      if (!entry.name.toLowerCase().includes(match)) continue;
      if (visible.length === maxResults) {
        resultTruncated = true;
        continue;
      }
      visible.push(entry);
    }
    return Object.freeze({observationCid,
      resources: Object.freeze(visible),
      snapshotTruncated: projection.truncated, snapshotComplete,
      resultTruncated});
  }
  async function inspect({resource, maxSummaryBytes = 100000, signal}: Inspect = {}) {
    if (typeof resource !== 'string' || !resourceName.test(resource) ||
        !Number.isSafeInteger(maxSummaryBytes) || maxSummaryBytes < 1 ||
        maxSummaryBytes > 1_000_000) fail();
    await authorize(resource, signal);
    signal?.throwIfAborted();
    const arguments_ = [ownedCatalog.observation, ...bindingFields.map(name =>
      ownedBinding[name]), resource] as CatalogResourceArguments;
    const state = checked(moon.salesforceCatalogObservedResourceState(
      ...arguments_));
    if (state !== 1) {
      return Object.freeze({status: 'catalog_required', observationCid,
        reason: catalogRequiredReason(state, named)});
    }
    const summary = JSON.parse(checked(moon.salesforceCatalogResourceSummaryJson(
      ...arguments_, maxSummaryBytes)) as string) as unknown;
    return Object.freeze({status: 'ready' as const, observationCid, summary});
  }
  return Object.freeze({
    list: (options?: List) => list(options),
    search: (query: string, options?: Omit<List, 'query'>) => list({...options, query}),
    inspect: (options?: Inspect) => inspect(options),
    resolve: (options: ResolveResource) => resolveSalesforceResource({...options, moon,
      catalog: ownedCatalog,
      binding: ownedBinding, authorization, connection}),
  });
}
