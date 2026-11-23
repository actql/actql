// Public Resource discovery over installed Salesforce Sites. Each Site answers
// from the observation of its published declaration (explicitly published,
// or restored from the published generation); discovery never syncs or
// describes the provider itself. Listing and inspection check current read
// disclosure per Resource; a preview needs its own read dispatch. The caller
// must be the principal the Site was installed for.
import {createHash} from 'node:crypto';
import {installSalesforceResourceDiscovery} from
  './salesforce-resource-discovery.mjs';

import type {DiscoveryRuntime} from './salesforce-resource-discovery.mjs';
import type {ResourceAuthorization, ResourceBinding, ResourceCatalog} from './salesforce-resource-resolver.mjs';

type InstalledCatalog = ResourceCatalog & Readonly<{observationJson: string}>;
type Target = Readonly<{resource: string; maxBytes: number; signal?: AbortSignal}>;
type Peek = Target & Readonly<{fields: readonly string[]; maxRows: number}>;
type Decision = Awaited<ReturnType<ResourceAuthorization['authorize']>>;
type Preview = Readonly<{observationCid: string; fields: readonly string[]; rows: unknown; limited: boolean}>;
type Site = Readonly<{
  connection: string; namespaceId: string; principal: string; environment: string; orgId: string;
  siteKey: string; siteGeneration: number; connectionRevision: string; instanceOrigin: string;
  connectorRegistration: string; connectorRevision: string; authorization: ResourceAuthorization;
  ownsDeclaration(declaration: unknown): boolean;
  peek(input: Peek & Readonly<{decision: Decision}>): Preview | PromiseLike<Preview>;
}>;
type Scope = Readonly<{principalId: string; resourceConnection: string}>;
type List = Scope & Readonly<{query?: string; limit?: number; signal?: AbortSignal}>;
type Declared = Readonly<{declaration: unknown; observed: InstalledCatalog}>;
type Held = Readonly<{catalog: InstalledCatalog; discovery: ReturnType<typeof installSalesforceResourceDiscovery>}>;
type ServiceError = Readonly<{code?: unknown}> | null | undefined;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const cid = (value: unknown) => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const utf8Bytes = (text: string) => Buffer.byteLength(text, 'utf8');
// Denials and malformed Resource names keep their public meaning; nothing is
// revealed about why a Resource is not visible.
const denied: (code: string, error: unknown) => never = (code, error) => {
  if ((error as ServiceError)?.code === 'ExecutionAuthorizationDenied' ||
      (error as ServiceError)?.code === 'SalesforcePeekNotAuthorized') fail(code, error);
  if ((error as ServiceError)?.code === 'InvalidSalesforceResourceDiscovery' ||
      (error as ServiceError)?.code === 'InvalidSalesforcePeek') fail('InvalidClientRequest', error);
  throw error;
};

export function installSalesforceResourceService({salesforceMoon, sites}: Readonly<{salesforceMoon: DiscoveryRuntime; sites: readonly Site[]}>) {
  if (salesforceMoon === undefined || !Array.isArray(sites) ||
      sites.length === 0) {
    fail('InvalidSalesforceResourceService');
  }
  const byConnection = new Map<string, Site>(sites.map((site: Site) => [site.connection, site]));
  if (byConnection.size !== sites.length) {
    fail('InvalidSalesforceResourceService');
  }
  const current = new Map<string, Held>();
  // An observation answers current discovery only when it was observed for
  // this Site as installed now. A snapshot of another namespace, principal,
  // environment, org, Site generation, connection revision, origin or
  // connector revision is refused and the current view is kept.
  const install = (site: Site, catalog: InstalledCatalog) => {
    const binding = JSON.parse(catalog.observationJson).binding as ResourceBinding;
    const expected = {namespace_id: site.namespaceId, principal: site.principal,
      environment: site.environment, org_id: site.orgId,
      site_key: site.siteKey, site_generation: site.siteGeneration,
      connection_revision: site.connectionRevision,
      resource_origin: site.instanceOrigin,
      connector_registration: site.connectorRegistration,
      connector_revision: site.connectorRevision};
    const mismatch = Object.keys(expected).filter(name =>
      binding?.[name as keyof typeof expected] !== expected[name as keyof typeof expected]);
    if (mismatch.length !== 0) {
      throw Object.assign(new Error('ResourceCatalogBindingMismatch'),
        {code: 'ResourceCatalogBindingMismatch', fields: mismatch});
    }
    const discovery = installSalesforceResourceDiscovery({
      moon: salesforceMoon, catalog, binding,
      authorization: site.authorization, connection: site.connection});
    const held = Object.freeze({catalog, discovery});
    current.set(site.connection, held);
    return held;
  };
  const siteFor = (principalId: string, resourceConnection: string) => {
    const site = byConnection.get(resourceConnection);
    if (site === undefined) fail('ResourceConnectionNotFound');
    if (principalId !== site.principal) fail('ResourceDiscoveryDenied');
    return site;
  };

  // Answer discovery for one Site from its published declaration: one the
  // Site itself generated or restored for its current installation.
  function installPublished(resourceConnection: string, declared: Declared) {
    const site = byConnection.get(resourceConnection);
    if (site === undefined) fail('ResourceConnectionNotFound');
    if (!site.ownsDeclaration(declared?.declaration) ||
        declared.observed?.observation === undefined) {
      fail('ForeignSalesforceDeclaration');
    }
    install(site, declared.observed);
    return declared.observed.observationCid;
  }

  async function discoveryFor(principalId: string, resourceConnection: string) {
    const site = siteFor(principalId, resourceConnection);
    const held = current.get(resourceConnection);
    // Nothing is published for this Site: discovery never syncs it.
    if (held === undefined) fail('ResourceCatalogUnavailable');
    return {site, discovery: held.discovery};
  }

  return Object.freeze({
    installPublished,
    // Public `resources`: one bounded page of visible Resource names.
    async resources({principalId, resourceConnection, query, limit, signal}: List) {
      const {discovery} = await discoveryFor(principalId, resourceConnection);
      let listing;
      try {
        listing = await discovery.list({query, maxResults: limit, signal});
      } catch (error) { denied('ResourceDiscoveryDenied', error); }
      return Object.freeze({resourceConnection, ...listing});
    },
    // Public `resource-inspect`: typed metadata or the Catalog reason.
    async inspectResource({principalId, resourceConnection, resource,
      maxBytes, signal}: Scope & Target) {
      const {discovery} = await discoveryFor(principalId, resourceConnection);
      let inspected;
      try {
        inspected = await discovery.inspect({resource,
          maxSummaryBytes: maxBytes, signal});
      } catch (error) { denied('ResourceDiscoveryDenied', error); }
      if (inspected.status !== 'ready') {
        return Object.freeze({resourceConnection, resource,
          observationCid: inspected.observationCid,
          status: inspected.status, reason: inspected.reason});
      }
      const summaryJson = JSON.stringify(inspected.summary);
      if (utf8Bytes(summaryJson) > maxBytes) fail('ResourceInspectionTooLarge');
      return Object.freeze({resourceConnection, resource,
        observationCid: inspected.observationCid, status: 'ready',
        summaryJson});
    },
    // Public `resource-peek`: a separately authorized bounded prefix.
    async peekResource({principalId, resourceConnection, resource, fields,
      maxRows, maxBytes, signal}: Scope & Peek) {
      const site = siteFor(principalId, resourceConnection);
      const decision = await site.authorization.authorize('acquisition', {
        connection: site.connection, resource, operation: 'read'}, {
        subjectCid: cid({version: 'actql-resource-peek-request/0.1',
          principalId, resourceConnection, resource, fields, maxRows}),
        signal});
      if (decision.action !== 'dispatch') fail('ResourcePeekDenied');
      let preview;
      try {
        preview = await site.peek({decision, resource, fields, maxRows,
          maxBytes, signal});
      } catch (error) { denied('ResourcePeekDenied', error); }
      const rowsJson = JSON.stringify(preview.rows);
      if (utf8Bytes(rowsJson) > maxBytes) fail('ResourcePeekTooLarge');
      return Object.freeze({resourceConnection, resource,
        observationCid: preview.observationCid,
        fields: preview.fields, rowsJson, limited: preview.limited});
    },
  });
}
