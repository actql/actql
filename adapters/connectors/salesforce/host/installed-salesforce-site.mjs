// Host-owned Salesforce Site installation. The Host profile fixes the org, the
// credential authority and the secret reference; the Host's account gate is
// installed once for all its Sites. Programs and callers supply none of them.
// Credential grants are issued only for a protected decision that installed
// gate returned as dispatch.
import {createHash, createPrivateKey, createPublicKey} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {createLocalAuthorizationGate} from
  '../../../host-node/local-account-config.mjs';
import {openSqliteCredentialJournal} from
  '../../../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  '../../../site-node/remote-credential-signature.mjs';
import {createSalesforceCliSecretResolver} from
  '../site/salesforce-cli-secret.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {syncSalesforceCatalog} from '../site/salesforce-catalog-sync.mjs';
import {readSalesforceQuery} from '../site/salesforce-query-read.mjs';
import {describeSalesforceResources, recoverNamedSalesforceObservation} from
  '../site/salesforce-named-describe.mjs';

export const INSTALLED_SALESFORCE_SITE_VERSION =
  'actql-installed-salesforce-site/0.1';
const requiredKeys = Object.freeze([
  'apiVersion', 'cliAlias', 'cliUsername',
  'connectionRevision', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'instanceOrigin', 'journalRoot',
  'orgId', 'siteGeneration', 'siteKey', 'tenant', 'version',
]);
const optionalKeys = Object.freeze(['caPath']);
// Record operations and the account boundary and operation class whose
// dispatch decision they require. Catalog metadata is the Site's own sync.
const recordOperations = Object.freeze(new Map([
  ['salesforce:record:observe', ['acquisition', 'read']],
  ['salesforce:query:read', ['acquisition', 'read']],
  ['salesforce:record:create', ['effect_commit', 'effect']],
  ['salesforce:record:update', ['effect_commit', 'effect']],
  ['salesforce:record:upsert', ['effect_commit', 'effect']],
]));
const catalogOperations = Object.freeze(new Set([
  'salesforce:catalog:list', 'salesforce:catalog:describe',
]));
// The list budget admits `maxResources` listed objects: a Salesforce listing
// entry carries its flags and URLs, about 1.2 KB and 33 JSON nodes each (a
// Developer org lists about 1,600 objects in about 1.9 MB).
export const DEFAULT_SALESFORCE_CATALOG_LIMITS = Object.freeze({
  list: Object.freeze({maxBytes: 4_000_000, maxNodes: 100_000, maxDepth: 32,
    maxResources: 2000, maxSelected: 200, maxNameUnits: 100_000}),
  describe: Object.freeze({maxBytes: 4_000_000, maxNodes: 400_000,
    maxDepth: 32, maxFields: 1000, maxNameUnits: 200_000}),
  maxObservationBytes: 8_000_000,
});

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;

function validProfile(profile) {
  if (profile === null || typeof profile !== 'object' ||
      Array.isArray(profile)) return false;
  const keys = Object.keys(profile);
  if (!requiredKeys.every(key => keys.includes(key)) ||
      !keys.every(key => requiredKeys.includes(key) ||
        optionalKeys.includes(key))) return false;
  let origin;
  try { origin = new URL(profile.instanceOrigin); }
  catch { return false; }
  return profile.version === INSTALLED_SALESFORCE_SITE_VERSION &&
    requiredKeys.filter(key => key !== 'siteGeneration')
      .every(key => text(profile[key])) &&
    Number.isSafeInteger(profile.siteGeneration) &&
    profile.siteGeneration >= 0 &&
    origin.protocol === 'https:' && origin.origin === profile.instanceOrigin &&
    /^v[1-9][0-9]*\.[0-9]+$/u.test(profile.apiVersion) &&
    /^00D[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?$/u.test(profile.orgId) &&
    isAbsolute(profile.journalRoot) &&
    isAbsolute(profile.credentialPrivateKeyPath) &&
    (profile.caPath === undefined ||
      (text(profile.caPath) && isAbsolute(profile.caPath)));
}

// The decisions each installed authorization returned. Only these can
// authorize a credential grant; a copied or constructed object cannot.
const installedDecisions = new WeakMap();

// Install the Host's account gate for its Salesforce Sites from the exact
// configuration text the Host was given. An unreadable or rejected
// configuration fails installation; it never degrades to allow.
export async function installSalesforceAuthorization({accountConfiguration,
  principalId, root, gateOptions = {}} = {}) {
  if (!text(accountConfiguration) || !text(principalId) || !text(root)) {
    fail('InvalidSalesforceAuthorizationInstallation');
  }
  const context = Object.freeze({principal: principalId,
    contextCid: cid({version: 'actql-installed-salesforce-context/0.1',
      root, principalId})});
  const gate = await createLocalAuthorizationGate({...gateOptions,
    accountConfiguration, principal: principalId, context});
  const issued = new WeakSet();
  const own = decision => {
    if (decision !== null && typeof decision === 'object') issued.add(decision);
    return decision;
  };
  const authorization = Object.freeze({...gate, context,
    authorize: async (...args) => own(await gate.authorize(...args)),
    resume: async (...args) => own(await gate.resume(...args))});
  installedDecisions.set(authorization, issued);
  return authorization;
}

// Load one installed Salesforce Site. `resolveSecret` replaces only the
// provider secret source (the profile's sf CLI connection by default); it
// never replaces the account gate, the credential authority or the org.
export async function loadInstalledSalesforceSite(path, {commonMoon,
  salesforceMoon, authorization, runtimeBundleCid, resolveSecret,
  now = () => Date.now(), grantLifetimeMs = 15 * 60 * 1000} = {}) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    fail('InvalidInstalledSalesforceSiteProfilePath');
  }
  const issuedDecisions = installedDecisions.get(authorization);
  if (issuedDecisions === undefined ||
      !cidPattern.test(runtimeBundleCid ?? '') ||
      commonMoon === undefined || salesforceMoon === undefined ||
      typeof now !== 'function' || !Number.isSafeInteger(grantLifetimeMs) ||
      grantLifetimeMs < 1 || grantLifetimeMs > 24 * 60 * 60 * 1000 ||
      (resolveSecret !== undefined && typeof resolveSecret !== 'function')) {
    fail('InvalidInstalledSalesforceSiteOptions');
  }
  const principalId = authorization.context.principal;
  const context = authorization.context;
  let profile;
  try { profile = JSON.parse(await readFile(path, 'utf8')); }
  catch (error) { fail('InvalidInstalledSalesforceSiteProfile', error); }
  if (!validProfile(profile)) fail('InvalidInstalledSalesforceSiteProfile');
  let privateKey;
  let ca;
  try {
    privateKey = createPrivateKey(await readFile(
      profile.credentialPrivateKeyPath, 'utf8'));
    if (profile.caPath !== undefined) ca = await readFile(profile.caPath);
  } catch (error) {
    fail('InvalidInstalledSalesforceSiteCredential', error);
  }
  if (privateKey.asymmetricKeyType !== 'ed25519') {
    fail('InvalidInstalledSalesforceSiteCredential');
  }
  const connection = `salesforce:${profile.orgId}`;
  const secret = resolveSecret ?? createSalesforceCliSecretResolver({
    connection: {alias: profile.cliAlias, orgId: profile.orgId,
      username: profile.cliUsername, instanceOrigin: profile.instanceOrigin},
    principal: principalId, tenant: profile.tenant,
    environment: profile.environment, siteKey: profile.siteKey,
    siteGeneration: profile.siteGeneration,
  });
  const control = runtimeCore(commonMoon).remoteCredentialControl;
  const journal = openSqliteCredentialJournal(profile.journalRoot, {
    credentialAuthorities: new Map([[profile.credentialAuthorityId,
      new Map([[profile.credentialKeyId, createPublicKey(privateKey)]])]]),
  });
  let closed = false;
  const credential = Object.freeze({orgId: profile.orgId, control, journal,
    resolveSecret: secret, ca, now});

  function sign({operation, runInvocationCid, taskAttempt,
    dispatchRequestCid, maxUses}) {
    if (!cidPattern.test(runInvocationCid ?? '') ||
        !cidPattern.test(dispatchRequestCid ?? '') ||
        !Number.isSafeInteger(taskAttempt) || taskAttempt < 1 ||
        !Number.isSafeInteger(maxUses) || maxUses < 1 || maxUses > 10_000) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    const scope = Object.freeze({
      issuerAuthority: profile.credentialAuthorityId,
      principal: principalId, tenant: profile.tenant,
      environment: profile.environment, siteKey: profile.siteKey,
      siteGeneration: profile.siteGeneration, runtimeBundleCid,
      connectorRegistration: 'salesforce',
      connectorRevision: 'salesforce/0.1',
      resourceOrigin: profile.instanceOrigin, operation, runInvocationCid,
      taskAttempt, dispatchRequestCid,
      expiresUnixMilliseconds: BigInt(now() + grantLifetimeMs), maxUses,
    });
    const grant = control.prepare(scope);
    journal.acceptGrant(signRemoteCredentialGrant(grant, control, {
      keyId: profile.credentialKeyId, privateKey}), control);
    return Object.freeze({grant, scope});
  }

  // Issue one credential grant for a record operation on `resource`. The
  // decision must be the installed gate's dispatch for the same connection,
  // resource and operation class at the operation's boundary.
  function issueGrant({operation, decision, resource, runInvocationCid,
    taskAttempt = 1, dispatchRequestCid, maxUses = 1}) {
    const required = recordOperations.get(operation);
    if (required === undefined || !text(resource)) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    if (!issuedDecisions.has(decision) || decision.action !== 'dispatch' ||
        decision.boundary !== required[0] ||
        decision.contextCid !== context.contextCid ||
        decision.tuple?.connection !== connection ||
        decision.tuple?.resource !== resource ||
        decision.tuple?.operation !== required[1] ||
        metadataDecisions.has(decision)) {
      fail('SalesforceCredentialGrantNotAuthorized');
    }
    return sign({operation, runInvocationCid, taskAttempt,
      dispatchRequestCid, maxUses});
  }

  // Metadata read decisions: the installed gate's `read` dispatch at the
  // acquisition boundary for one Resource, under a describe subject (the
  // boundary kind is the subject, not the operation). They authorize only
  // that Resource's describe grant and never a query or record grant.
  const metadataDecisions = new WeakSet();
  async function authorizeDescribe(resource, {occurrence, signal}) {
    const decision = await authorization.authorize('acquisition', {
      connection, resource, operation: 'read'}, {
      subjectCid: cid({version: 'actql-salesforce-catalog-describe/0.1',
        contextCid: context.contextCid, siteKey: profile.siteKey,
        siteGeneration: profile.siteGeneration,
        connectionRevision: profile.connectionRevision, resource,
        occurrence}), signal});
    if (!issuedDecisions.has(decision) || decision.action !== 'dispatch' ||
        decision.boundary !== 'acquisition' ||
        decision.contextCid !== context.contextCid ||
        decision.tuple?.connection !== connection ||
        decision.tuple?.resource !== resource ||
        decision.tuple?.operation !== 'read') {
      throw Object.assign(new Error('SalesforceCatalogDescribeNotAuthorized'),
        {code: 'SalesforceCatalogDescribeNotAuthorized', resource,
          action: decision?.action});
    }
    metadataDecisions.add(decision);
    return decision;
  }

  // Describe exactly `resources`, without the provider's sObject listing.
  // Every Resource's metadata read is decided before any provider I/O; one
  // denial refuses the whole observation. Each describe uses its own
  // one-use grant.
  async function describeNamed({resources, occurrence, runInvocationCid:
    runCid, dispatchRequestCid: dispatchCid, retainEvidence = false,
    maxRetainedBytes = 0, limits = DEFAULT_SALESFORCE_CATALOG_LIMITS,
    signal}) {
    if (!Array.isArray(resources) || resources.length === 0 ||
        !resources.every(text) || !text(occurrence) ||
        (runCid === undefined) !== (dispatchCid === undefined)) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    const decided = new Set();
    for (const resource of resources) {
      await authorizeDescribe(resource, {occurrence, signal});
      decided.add(resource);
    }
    const runInvocationCid = runCid ?? cid({version:
      'actql-salesforce-catalog-sync/0.1', siteKey: profile.siteKey,
      siteGeneration: profile.siteGeneration, syncOccurrence: occurrence});
    const dispatchRequestCid = dispatchCid ?? cid({version:
      'actql-salesforce-catalog-dispatch/0.1', runInvocationCid});
    return await describeSalesforceResources({moon: salesforceMoon,
      apiVersion: profile.apiVersion,
      connectionRevision: profile.connectionRevision, orgId: profile.orgId,
      syncOccurrence: occurrence,
      maxObservationBytes: limits.maxObservationBytes,
      resources: [...resources], credential,
      describeLimits: limits.describe, retainEvidence, maxRetainedBytes,
      authorizationForDescribe: async name => {
        if (!decided.has(name)) fail('SalesforceCatalogDescribeNotAuthorized');
        return {...sign({operation: 'salesforce:catalog:describe',
          runInvocationCid, taskAttempt: 1, dispatchRequestCid, maxUses: 1}),
        useId: `${occurrence}-describe-${name}`};
      }, signal});
  }

  let syncSequence = 0;
  // The request for one bounded Catalog observation under this Site's own
  // metadata grants. A Run's current Catalog is bound to its dispatch
  // (`runInvocationCid`, `dispatchRequestCid`, `taskAttempt`); otherwise the
  // sync is the Site's own.
  function catalogSyncRequest({occurrence, retainResponses = false,
    maxRetainedBytes = 0, limits = DEFAULT_SALESFORCE_CATALOG_LIMITS,
    runInvocationCid: runCid, dispatchRequestCid: dispatchCid,
    taskAttempt = 1, grantUses, resources} = {}) {
    const sequence = syncSequence++;
    const syncOccurrence = occurrence ?? `catalog-sync-${now()}-${sequence}`;
    if ((runCid === undefined) !== (dispatchCid === undefined)) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    const runInvocationCid = runCid ?? cid({version:
      'actql-salesforce-catalog-sync/0.1', siteKey: profile.siteKey,
      siteGeneration: profile.siteGeneration, syncOccurrence});
    const dispatchRequestCid = dispatchCid ?? cid({version:
      'actql-salesforce-catalog-dispatch/0.1', runInvocationCid});
    const grant = operation => {
      if (!catalogOperations.has(operation)) {
        fail('InvalidSalesforceCredentialGrantRequest');
      }
      return sign({operation, runInvocationCid, taskAttempt,
        dispatchRequestCid, maxUses: grantUses ??
          (operation === 'salesforce:catalog:list'
            ? 1 : limits.list.maxSelected)});
    };
    const list = grant('salesforce:catalog:list');
    const describe = grant('salesforce:catalog:describe');
    const request = Object.freeze({
      apiVersion: profile.apiVersion,
      connectionRevision: profile.connectionRevision, orgId: profile.orgId,
      syncOccurrence, maxObservationBytes: limits.maxObservationBytes,
      retainResponses, maxRetainedBytes,
      listAuthorization: {...list, useId: `${syncOccurrence}-list`},
      authorizationForDescribe: async name => ({...describe,
        useId: `${syncOccurrence}-describe-${name}`}),
      listLimits: limits.list, describeLimits: limits.describe,
      ...(resources === undefined ? {} : {resources: [...resources]}),
    });
    return Object.freeze({request, grants: Object.freeze({list, describe})});
  }

  // One bounded Catalog observation under this Site's own metadata grants.
  async function refreshCatalog({signal, ...options} = {}) {
    const {request, grants} = catalogSyncRequest(options);
    const catalog = await syncSalesforceCatalog({...request,
      moon: salesforceMoon, credential, signal});
    // The metadata grants stay with the observation for its recovery.
    return Object.freeze({...catalog, grants});
  }

  // Declarations this Site generated. Only these can gate its own reads and
  // writes; a copied or constructed object cannot.
  const declarations = new WeakSet();
  let declareSequence = 0;
  const declarationLimits = limits =>
    Number.isSafeInteger(limits?.maxBytes) && limits.maxBytes >= 1 &&
    Number.isSafeInteger(limits?.maxNodes) && limits.maxNodes >= 1 &&
    Number.isSafeInteger(limits?.maxDepth) && limits.maxDepth >= 1;
  // The binding an observation must carry to belong to this Site as
  // installed now.
  const siteBinding = () => ({tenant: profile.tenant, principal: principalId,
    environment: profile.environment, org_id: profile.orgId,
    site_key: profile.siteKey, site_generation: profile.siteGeneration,
    connection_revision: profile.connectionRevision,
    resource_origin: profile.instanceOrigin,
    connector_registration: 'salesforce',
    connector_revision: 'salesforce/0.1'});
  const generate = (observation, connectorId, resources, limits) => {
    const binding = JSON.parse(
      salesforceMoon.salesforceCatalogObservationJson(observation)).binding;
    const declaration = checked(
      salesforceMoon.salesforceGenerateStaticDeclaration(observation,
        binding.tenant, binding.principal, binding.environment,
        binding.connection_revision, binding.org_id, binding.site_key,
        binding.site_generation, binding.connector_registration,
        binding.connector_revision, binding.resource_origin,
        binding.run_invocation_cid, binding.dispatch_request_cid,
        binding.sync_occurrence,
        checked(salesforceMoon.salesforceImplementation(
          'salesforce/0.1')), connectorId, [...resources],
        limits.maxBytes, limits.maxNodes, limits.maxDepth));
    declarations.add(declaration);
    const summary = JSON.parse(checked(
      salesforceMoon.salesforceStaticDeclarationJson(declaration,
        limits.maxBytes, limits.maxNodes, limits.maxDepth)));
    return {...summary, declaration};
  };
  // Generate the static declaration (Catalog and Mappings) for the selected
  // Resources from a describe of exactly those Resources, each under its own
  // metadata read decision; the provider's full listing is not read. The
  // result, with the retained describe evidence, is the explicit publication
  // input to Check; it is not current authority and issues no grant.
  async function declareCatalog({connectorId, resources, signal,
    maxEvidenceBytes = DEFAULT_SALESFORCE_CATALOG_LIMITS.maxObservationBytes,
    limits = {maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 64}} = {}) {
    if (!Array.isArray(resources) || resources.length === 0 ||
        !resources.every(text) || !text(connectorId) ||
        !declarationLimits(limits) ||
        !Number.isSafeInteger(maxEvidenceBytes) || maxEvidenceBytes < 1) {
      fail('InvalidSalesforceDeclaration');
    }
    const selected = [...new Set(resources)];
    const catalog = await describeNamed({resources: selected,
      occurrence: `declare-${now()}-${declareSequence++}`,
      retainEvidence: true, maxRetainedBytes: maxEvidenceBytes, signal});
    if (catalog.status === 'interrupted') {
      fail(catalog.interruptionCode === 'SalesforceCatalogCancelled'
        ? 'SalesforceCatalogCancelled' : 'SalesforceCatalogRefreshInterrupted');
    }
    return Object.freeze({...generate(catalog.observation, connectorId,
      selected, limits), observationCid: catalog.observationCid,
    evidence: catalog.evidence});
  }

  // Restore a declaration this Site published from its retained describe
  // evidence, without credential or provider I/O. The evidence must be
  // bound to this Site as installed now (principal, org, connection
  // revision, Site generation, origin and connector) and must regenerate
  // the exact published Catalog. Restoring is not current authority: every
  // read still needs its own dispatch.
  function restoreDeclaration({connectorId, resources, evidence,
    observationCid, catalogCid,
    limits = {maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 64}} = {}) {
    if (!Array.isArray(resources) || resources.length === 0 ||
        !resources.every(text) || !text(connectorId) ||
        !declarationLimits(limits) || !cidPattern.test(observationCid ?? '') ||
        !cidPattern.test(catalogCid ?? '') ||
        typeof evidence?.observationJson !== 'string') {
      fail('InvalidSalesforceDeclaration');
    }
    let binding;
    try { binding = JSON.parse(evidence.observationJson).binding; }
    catch (error) { fail('InvalidSalesforceDeclaration', error); }
    const expected = siteBinding();
    const mismatch = Object.keys(expected).filter(name =>
      binding?.[name] !== expected[name]);
    if (mismatch.length !== 0) {
      throw Object.assign(new Error('ForeignSalesforceDeclaration'),
        {code: 'ForeignSalesforceDeclaration', fields: mismatch});
    }
    const observation = recoverNamedSalesforceObservation({
      moon: salesforceMoon, evidence, expectedObservationCid: observationCid});
    const restored = generate(observation, connectorId,
      [...new Set(resources)], limits);
    if (restored.catalog_cid !== catalogCid) {
      fail('ForeignSalesforceDeclaration');
    }
    return Object.freeze({...restored, observationCid, evidence});
  }

  const writeKinds = Object.freeze({create: 0, createFromResult: 1,
    update: 2, upsert: 3});
  // The executable Mapping of one Effect, from a declaration this Site
  // generated. It names the declaration's own manifest entry.
  function prepareExecutionMapping({declaration, resource, write,
    limits = {maxBytes: 400_000, maxNodes: 40_000, maxDepth: 64}} = {}) {
    if (!declarations.has(declaration) || !text(resource) ||
        writeKinds[write?.kind] === undefined ||
        !Array.isArray(write.fields ?? []) ||
        !Array.isArray(write.sources ?? [])) {
      fail('InvalidSalesforceExecutionMapping');
    }
    const sources = write.sources ?? [];
    const mapping = checked(salesforceMoon.salesforcePrepareExecutionMapping(
      declaration, resource, writeKinds[write.kind], [...(write.fields ?? [])],
      write.key ?? '', sources.map(source => source.target),
      sources.map(source => source.field),
      sources.map(source => source.nullBehavior),
      limits.maxBytes, limits.maxNodes,
      limits.maxDepth));
    return Object.freeze({mapping,
      mappingRef: salesforceMoon.salesforceExecutionMappingRef(mapping),
      mappingCid: salesforceMoon.salesforceExecutionMappingCid(mapping),
      body: salesforceMoon.salesforceExecutionMappingBody(mapping)});
  }

  let peekSequence = 0;
  // One authorized preview of at most `maxRows` rows of `resource`. The
  // decision must be the installed gate's read dispatch for this exact
  // Resource. The preview syncs its own current Catalog, reads one page
  // under a one-use query grant, and returns a prefix for display only:
  // never complete-read evidence or a Result. `limited` means the reply
  // reached `maxRows`, so more rows may exist; `order` is `id` when the
  // query fixed ascending Id order and `provider` otherwise.
  async function peek({decision, resource, fields, maxRows,
    maxBytes = 65536, maxNodes = 10000, signal} = {}) {
    if (!issuedDecisions.has(decision) || decision.action !== 'dispatch' ||
        decision.boundary !== 'acquisition' ||
        decision.contextCid !== context.contextCid ||
        decision.tuple?.connection !== connection ||
        decision.tuple?.resource !== resource ||
        decision.tuple?.operation !== 'read') {
      fail('SalesforcePeekNotAuthorized');
    }
    if (!Array.isArray(fields) || fields.length === 0 || fields.length > 100 ||
        !fields.every(text) || new Set(fields).size !== fields.length ||
        !Number.isSafeInteger(maxRows) || maxRows < 1 || maxRows > 200 ||
        !Number.isSafeInteger(maxBytes) || maxBytes < 1 ||
        maxBytes > 4_000_000 || !Number.isSafeInteger(maxNodes) ||
        maxNodes < 1 || maxNodes > 1_000_000) {
      fail('InvalidSalesforcePeek');
    }
    const occurrence = `peek-${now()}-${peekSequence++}`;
    const runInvocationCid = cid({version: 'actql-salesforce-peek/0.1',
      subjectCid: decision.subjectCid, resource, fields, maxRows,
      occurrence});
    const dispatchRequestCid = cid({version:
      'actql-salesforce-peek-dispatch/0.1', runInvocationCid});
    // The first describe plans the query; the query read rechecks it once
    // under its own occurrence and the same dispatch. Each describes only
    // the previewed Resource, under its own metadata read decision; the
    // provider's sObject listing is never read.
    const describe = suffix => describeNamed({resources: [resource],
      occurrence: `${occurrence}-${suffix}`, runInvocationCid,
      dispatchRequestCid, signal});
    const catalog = await describe('plan');
    if (catalog.status === 'interrupted') {
      fail('SalesforceCatalogRefreshInterrupted');
    }
    const binding = JSON.parse(catalog.observationJson).binding;
    // Ascending Id where the describe reports it sortable: the order of this
    // one reply, not a snapshot or a rerun guarantee.
    const plan = checked(salesforceMoon.salesforceReadProjectionWithRowLimit(
      checked(salesforceMoon.salesforceReadProjectionWithIdOrderIfSortable(
      checked(salesforceMoon.salesforcePrepareReadProjection(
        catalog.observation, binding.tenant, binding.principal,
        binding.environment, binding.connection_revision, binding.org_id,
        binding.site_key, binding.site_generation,
        binding.connector_registration, binding.connector_revision,
        binding.resource_origin, binding.run_invocation_cid,
        binding.dispatch_request_cid, binding.sync_occurrence, resource,
        fields, 4096)))), maxRows));
    const query = sign({operation: 'salesforce:query:read', runInvocationCid,
      taskAttempt: 1, dispatchRequestCid, maxUses: 1});
    const rows = [];
    const result = await readSalesforceQuery({moon: salesforceMoon, plan,
      apiVersion: profile.apiVersion,
      limits: {maxBytes, maxNodes, maxDepth: 16, maxRows,
        maxLocatorUnits: 2048, maxPages: 1, maxTotalRows: maxRows},
      initialAuthorization: {...query, useId: `${occurrence}-query`},
      authorizationForPage: async () => fail('SalesforcePeekPageLimit'),
      credential, refreshCatalog: () => describe('recheck'),
      consumePage: async page => {
        rows.push(...JSON.parse(checked(
          salesforceMoon.salesforceQueryPageRowsJson(page, maxBytes,
            maxNodes))));
      }, signal});
    return Object.freeze({
      observationCid: result.currentCatalog.observationCid, resource,
      fields: Object.freeze([...fields]), rows: Object.freeze(rows),
      limited: rows.length === maxRows,
      order: salesforceMoon.salesforceReadProjectionOrderedById(plan)
        ? 'id' : 'provider',
    });
  }

  return Object.freeze({
    orgId: profile.orgId, connection, apiVersion: profile.apiVersion,
    instanceOrigin: profile.instanceOrigin, siteKey: profile.siteKey,
    siteGeneration: profile.siteGeneration, tenant: profile.tenant,
    environment: profile.environment,
    connectionRevision: profile.connectionRevision,
    connectorRegistration: 'salesforce', connectorRevision: 'salesforce/0.1',
    principal: principalId, context, authorization, credential,
    issueGrant, refreshCatalog, declareCatalog, restoreDeclaration,
    prepareExecutionMapping, peek,
    // Whether this Site generated `declaration`.
    ownsDeclaration: declaration => declarations.has(declaration),
    close() {
      if (closed) return;
      closed = true;
      journal.close();
    },
  });
}
