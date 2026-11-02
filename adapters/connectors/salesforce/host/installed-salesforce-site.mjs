// Host-owned Salesforce Site installation. The Host profile fixes the org, the
// credential authority and the secret reference; the Host's account gate is
// installed once for all its Sites. Programs and callers supply none of them.
// Credential grants are issued only for a protected decision that installed
// gate returned as dispatch.
import {createHash} from 'node:crypto';
import {readSourceProfileJson,captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledCredentialSiteCleanup, releaseInstalledCredentialSite} from
  '../../../host-node/installed-host-cleanup.mjs';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {invocationBindingsMatch} from '../../../host-common/owned-invocation-context.mjs';
import {canonicalJson as canonicalValueJson} from '../../../../packages/sdk/host-port.mjs';
import {contentCid} from
  '../../../host-node/local-account-config.mjs';
import {installRowSourceAuthorization, loadRowSourceCredentialCustody} from
  '../../../host-node/installed-row-source.mjs';
import {createSalesforceCliSecretResolver} from
  '../site/salesforce-cli-secret.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {syncSalesforceCatalog} from '../site/salesforce-catalog-sync.mjs';
import {readSalesforceQuery} from '../site/salesforce-query-read.mjs';
import {checkpointApprovalFacts} from
  '../../../host-common/checkpoint-approval.mjs';
import {assertAuthorizationAccountCurrent, authorizationDispatchFacts} from
  '../../../host-common/authorization-gate.mjs';
import {describeSalesforceResources, recoverNamedSalesforceObservation,
  withSalesforceNamedDescribeOriginals} from
  '../site/salesforce-named-describe.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {attestSalesforceEffectCapabilityAuthority} from
  '../site/salesforce-effect-capability.mjs';

export const INSTALLED_SALESFORCE_SITE_VERSION =
  'actql-installed-salesforce-site/0.1';
const requiredKeys = Object.freeze([
  'apiVersion', 'cliAlias', 'cliUsername',
  'connectionRevision', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'instanceOrigin', 'journalRoot',
  'orgId', 'siteGeneration', 'siteKey', 'namespaceId', 'version',
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
  const failure = Object.assign(new Error(code, {cause}), {code});
  if (cause?.cleanupHandle !== undefined) {
    Object.assign(failure, {cleanupHandle: cause.cleanupHandle,
      cleanupPending: cause.cleanupPending});
  }
  throw failure;
};
const text = value => typeof value === 'string' && value.length > 0;
const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;

// Equal static Catalogs are not enough to co-install two roles for one
// connector. The Host compares this non-secret Site binding before it admits
// either role; read and commit decisions still remain separate.
export function installedSalesforceSiteBinding(site, connectorId) {
  if (!text(connectorId) || !text(site?.context?.contextCid)) {
    fail('InvalidSalesforceSiteBinding');
  }
  return Object.freeze({connectorId, bindingCid: contentCid({
    version: 'actql-installed-salesforce-site-binding/0.1',
    contextCid: site.context.contextCid,
    namespace_id: site.namespaceId, principal: site.principal,
    environment: site.environment, connection: site.connection,
    connectionRevision: site.connectionRevision, orgId: site.orgId,
    instanceOrigin: site.instanceOrigin, siteKey: site.siteKey,
    siteGeneration: site.siteGeneration, apiVersion: site.apiVersion,
    cliAlias: site.cliAlias, cliUsername: site.cliUsername,
    credentialAuthorityId: site.credentialAuthorityId,
    credentialKeyId: site.credentialKeyId,
    credentialPrivateKeyPath: site.credentialPrivateKeyPath,
    caPath: site.caPath,
  })});
}

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
// Only this existing installer can register a live Site receiver. A copied Site
// or a restored declaration cannot acquire a live physical observation.
const publicationSites = new WeakMap();

export async function observeInstalledSalesforcePublicationCurrent(site, declared) {
  const receiver = publicationSites.get(site);
  if (receiver === undefined) fail('SalesforcePublicationOriginalUnavailable');
  await receiver.observe(declared);
}

export function withInstalledSalesforceDeclarationOriginals(site, declared, consume) {
  const receiver = publicationSites.get(site);
  if (receiver === undefined) fail('SalesforcePublicationOriginalUnavailable');
  return receiver.withOriginals(declared, consume);
}


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
  const {issued, ...gate} = await installRowSourceAuthorization({
    accountConfiguration, principalId, root, connectorRegistration: 'salesforce',
    originalContext: context, gateOptions});
  // Preserve the compatibility entry's original surface and its private
  // installation provenance. Decision issuance belongs to the shared issuer;
  // a caller-supplied object with an `issued` method is never an installation.
  const authorization = Object.freeze(gate);
  installedDecisions.set(authorization, issued);
  return authorization;
}

// Load one installed Salesforce Site. `resolveSecret` replaces only the
// provider secret source (the profile's sf CLI connection by default); it
// never replaces the account gate, the credential authority or the org.
// `openCredentialJournal` replaces only the credential journal's physical
// opener (the SQLite journal by default); tests use it to inject close
// failures.
export async function loadInstalledSalesforceSite(path, {commonMoon,
  salesforceMoon, authorization, runtimeBundleCid, resolveSecret,configurationReader,
  now = () => Date.now(), grantLifetimeMs = 15 * 60 * 1000,
  openCredentialJournal, runAcquisitionLimits} = {}) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    fail('InvalidInstalledSalesforceSiteProfilePath');
  }
  const issuedDecisions = installedDecisions.get(authorization);
  if (issuedDecisions === undefined ||
      !cidPattern.test(runtimeBundleCid ?? '') ||
      commonMoon === undefined || salesforceMoon === undefined ||
      typeof now !== 'function' || !Number.isSafeInteger(grantLifetimeMs) ||
      grantLifetimeMs < 1 || grantLifetimeMs > 24 * 60 * 60 * 1000 ||
      (resolveSecret !== undefined && typeof resolveSecret !== 'function') ||
      (openCredentialJournal !== undefined && typeof openCredentialJournal !== 'function')) {
    fail('InvalidInstalledSalesforceSiteOptions');
  }
  const principalId = authorization.context.principal;
  const context = authorization.context;
  const readers=captureConfigurationReaders(configurationReader,undefined,()=>fail('InvalidInstalledSalesforceSiteOptions'));
  let profile;
  // Match the existing Host identity/configuration ceiling; Salesforce's
  // publication uses its separate original 16,000,000-byte text boundary.
  try { profile = await readers.readJson(path, {maxBytes: 8 * 1024 * 1024}); }
  catch (error) { fail('InvalidInstalledSalesforceSiteProfile', error); }
  if (!validProfile(profile)) fail('InvalidInstalledSalesforceSiteProfile');
  const connection = `salesforce:${profile.orgId}`;
  // Keep the original Salesforce origin, task attempt and diagnostic names;
  // credential journal/signing/retirement are the shared Row Site's one path.
  const custody = await loadRowSourceCredentialCustody({
    profile: Object.freeze({...profile, resourceOrigin: profile.instanceOrigin}),
    principalId, connectorRegistration: 'salesforce',
    connectorRevision: 'salesforce/0.1', runtimeBundleCid, commonMoon,
    now, grantLifetimeMs,
    openCredentialJournal, runAcquisitionLimits,configurationReader,
    credentialFacts: Object.freeze({orgId: profile.orgId}),
    closedCode: 'SalesforceSiteClosed',
    grantCode: 'InvalidSalesforceCredentialGrantRequest'}, {
    caPath: profile.caPath, invalidCode: 'InvalidInstalledSalesforceSiteCredential',
    prepareResolver: () => resolveSecret ?? createSalesforceCliSecretResolver({
      connection: {alias: profile.cliAlias, orgId: profile.orgId,
        username: profile.cliUsername, instanceOrigin: profile.instanceOrigin},
      principal: principalId, namespaceId: profile.namespaceId,
      environment: profile.environment, siteKey: profile.siteKey,
      siteGeneration: profile.siteGeneration,
    })});
  const {credential, ensureOpen, sign} = custody;
  const liveDeclarations = new WeakMap();
  const liveDescribes = new WeakMap();
  const profileWire = JSON.stringify(profile);
  const recordAuthorizations = runAcquisitionLimits === undefined ? undefined : new WeakMap();

  function signRecord(fields, resource, assertDecisionCurrent, decision) {
    const issued = sign({...fields, ...(fields.operation === 'salesforce:query:read'
      ? {issuerPurpose: Object.freeze({kind: 'read', resource, decision})} : {})});
    recordAuthorizations?.set(issued, Object.freeze({resource, assertDecisionCurrent}));
    return issued;
  }

  // Issue one credential grant for a record operation on `resource`. The
  // decision must be the installed gate's dispatch for the same connection,
  // resource and operation class at the operation's boundary. A record write
  // is granted only for the Effect commit decision of `subjectCid`, the
  // sealed Effect Set it approves.
  function issueGrant({operation, decision, resource, runInvocationCid,
    taskAttempt = 1, dispatchRequestCid, maxUses = 1, subjectCid}) {
    ensureOpen();
    const required = recordOperations.get(operation);
    if (required === undefined || !text(resource) ||
        (required[0] === 'effect_commit' && !cidPattern.test(subjectCid ?? ''))) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    // A read approval admitted from the Host's Checkpoint grants only the
    // query read of its own Resource.
    const approved = approvedReads.get(decision);
    if (approved !== undefined) {
      if (operation !== (approved.kind === 'effect_target'
          ? 'salesforce:record:observe' : 'salesforce:query:read') ||
          approved.resource !== resource) {
        fail('SalesforceCredentialGrantNotAuthorized');
      }
      approved.assertCurrent?.();
      approved.enter?.();
      return signRecord({operation, runInvocationCid, taskAttempt,
        dispatchRequestCid, maxUses}, resource, approved.assertCurrent, decision);
    }
    // An Effect commit dispatch another gate of the Host (its Checkpoint
    // commit gate) decided counts as this gate's only when that gate decided
    // it for this principal under this exact admitted account configuration.
    // Operation, Resource and sealed Set are checked below as for any
    // decision; the gate owns its approval's currency.
    const commitFacts = required[0] === 'effect_commit'
      ? authorizationDispatchFacts(decision) : undefined;
    const hostCommit = commitFacts !== undefined &&
      commitFacts.principal === principalId &&
      commitFacts.configurationCid === authorization.configurationCid;
    if (!(issuedDecisions(decision) || hostCommit) ||
        decision.action !== 'dispatch' ||
        decision.boundary !== required[0] ||
        (!hostCommit && decision.contextCid !== context.contextCid) ||
        decision.tuple?.connection !== connection ||
        decision.tuple?.resource !== resource ||
        decision.tuple?.operation !== required[1] ||
        (required[0] === 'effect_commit' &&
          decision.subjectCid !== subjectCid) ||
        metadataDecisions.has(decision)) {
      fail('SalesforceCredentialGrantNotAuthorized');
    }
    // Revisit the exact issuing scope after all earlier awaits. Matching
    // provenance survives closure and cannot by itself authorize a new grant.
    assertAuthorizationAccountCurrent(decision);
    return signRecord({operation, runInvocationCid, taskAttempt,
      dispatchRequestCid, maxUses}, resource,
    () => assertAuthorizationAccountCurrent(decision), decision);
  }

  // Retain the original Site-issued read/write authorization, not a grant
  // reconstructed from a CID. The same binding's material may serve another
  // separately issued operation only under the same original acquisition.
  function bindRecordAcquisition(originalAuthorization, originalCurrent) {
    ensureOpen();
    if (recordAuthorizations === undefined) fail('SalesforceRecordAcquisitionUnavailable');
    const first = recordAuthorizations.get(originalAuthorization);
    if (first === undefined) fail('ForeignSalesforceRecordAcquisitionAuthorization');
    const state = {retiring: false, failure: undefined};
    const assertOpen = () => {
      ensureOpen();
      if (state.failure !== undefined) throw state.failure;
      if (state.retiring) fail('SalesforceRecordAcquisitionRetiring');
    };
    const captureCurrent = value => {
      if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) {
        fail('InvalidSalesforceRecordAcquisitionCurrent');
      }
      const fields = Object.getOwnPropertyDescriptors(value);
      if (Reflect.ownKeys(fields).length !== 2 || ['assertCurrent', 'observeCurrent'].some(name =>
        !fields[name] || !Object.hasOwn(fields[name], 'value') || typeof fields[name].value !== 'function')) {
        fail('InvalidSalesforceRecordAcquisitionCurrent');
      }
      return Object.freeze({assertCurrent: fields.assertCurrent.value,
        observeCurrent: fields.observeCurrent.value});
    };
    const currentFor = (record, methods) => {
      if (typeof record.assertDecisionCurrent !== 'function') {
        fail('SalesforceRecordAcquisitionCurrentUnavailable');
      }
      const assertOriginal = method => {
        const result = Reflect.apply(method, undefined, []);
        if (result !== undefined) {
          if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
          fail('InvalidSalesforceRecordAcquisitionCurrent');
        }
      };
      const assertCurrent = () => {
        try {
          assertOpen();
          assertOriginal(record.assertDecisionCurrent);
          assertOriginal(methods.assertCurrent);
          assertOriginal(record.assertDecisionCurrent);
          assertOpen();
        } catch (cause) { state.failure ??= cause; throw cause; }
      };
      const observeCurrent = async () => {
        try {
          assertCurrent();
          await Reflect.apply(methods.observeCurrent, undefined, []);
          assertCurrent();
          const current = await readSourceProfileJson(path, {maxBytes: 8 * 1024 * 1024});
          assertCurrent();
          if (JSON.stringify(current) !== profileWire) fail('SalesforceRecordAcquisitionProfileChanged');
        } catch (cause) { state.failure ??= cause; throw cause; }
      };
      return Object.freeze({assertCurrent, observeCurrent});
    };
    const firstCurrent = currentFor(first, captureCurrent(originalCurrent));
    const original = custody.bindRunAcquisition(originalAuthorization, firstCurrent);
    const credentialFor = callbacks => Object.freeze({...original.credential,
      currentBeforeSend: callbacks.observeCurrent});
    return Object.freeze({authorization: originalAuthorization,
      credential: credentialFor(firstCurrent),
      forAuthorization(authorization, current) {
        assertOpen();
        const record = recordAuthorizations.get(authorization);
        if (record === undefined || record.resource !== first.resource ||
            !invocationBindingsMatch(authorization.scope, originalAuthorization.scope,
              credential.control)) fail('ForeignSalesforceRecordAcquisitionAuthorization');
        const callbacks = currentFor(record, captureCurrent(current));
        callbacks.assertCurrent();
        return Object.freeze({authorization, credential: credentialFor(callbacks)});
      },
      close() {
        state.retiring = true;
        return original.close();
      }});
  }

  // This Site's attestation of its installed runtime and connection for one
  // Effect dispatch: the capability evidence of a Preview, issued before any
  // commit is decided. It signs no grant and consumes no credential use; it
  // stops attesting once the Site is closed.
  function attestEffectCapability({operation, runInvocationCid,
    dispatchRequestCid, taskAttempt = 1}) {
    ensureOpen();
    if (recordOperations.get(operation)?.[0] !== 'effect_commit' ||
        !cidPattern.test(runInvocationCid ?? '') ||
        !cidPattern.test(dispatchRequestCid ?? '') ||
        !Number.isSafeInteger(taskAttempt) || taskAttempt < 1) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    return attestSalesforceEffectCapabilityAuthority({
      scope: {issuerAuthority: profile.credentialAuthorityId,
        principal: principalId, namespaceId: profile.namespaceId,
        environment: profile.environment, siteKey: profile.siteKey,
        siteGeneration: profile.siteGeneration, runtimeBundleCid,
        connectorRegistration: 'salesforce',
        connectorRevision: 'salesforce/0.1',
        resourceOrigin: profile.instanceOrigin, operation, runInvocationCid,
        taskAttempt, dispatchRequestCid},
      current() {
        ensureOpen();
        return runtimeBundleCid;
      }});
  }

  // Read approvals admitted from the Host's Checkpoint for this installation:
  // the approval object the Site returns, mapped to what it covers.
  const approvedReads = new WeakMap();
  // Admit a read approval the Host's Checkpoint returned for one dispatch.
  // Only a decision the Checkpoint owner recorded is considered, and only
  // when the approved read is this installation's: the requesting principal,
  // org, connection revision, Site key and generation, origin and Resource.
  // The approval authorizes that Resource's data query (`issueGrant`) and,
  // for the same read, its metadata describe (`describeForAcquisition`);
  // nothing else. It is decided current by the Checkpoint when returned.
  function admitCheckpointReadApproval(decision) {
    ensureOpen();
    const facts = checkpointApprovalFacts(decision);
    const binding = facts?.physicalBinding;
    const assertCurrent = facts?.assertCurrent;
    const enter = facts?.enter;
    const scoped = assertCurrent !== undefined || enter !== undefined;
    if (facts === undefined || decision.action !== 'dispatch' ||
        decision.basis !== 'resumed_approval' ||
        decision.boundary !== 'acquisition' ||
        decision.tuple?.connection !== connection ||
        decision.tuple?.operation !== 'read' ||
        facts.principalId !== principalId ||
        facts.readTuple?.connection !== connection ||
        facts.readTuple?.operation !== 'read' ||
        facts.readTuple?.resource !== decision.tuple.resource ||
        binding?.version !== 'actql-installed-salesforce-target/0.1' ||
        binding.org_id !== profile.orgId ||
        binding.instance_origin !== profile.instanceOrigin ||
        binding.site_key !== profile.siteKey ||
        binding.site_generation !== profile.siteGeneration ||
        binding.connection_revision !== profile.connectionRevision ||
        binding.resource !== decision.tuple.resource ||
        !Array.isArray(binding.fields) || !text(binding.catalog_cid) ||
        scoped && (typeof assertCurrent !== 'function' || typeof enter !== 'function')) {
      fail('SalesforceReadApprovalNotAdmitted');
    }
    // The original Source continuation owns these fences. Preserve them on
    // its physical read token rather than reducing it to historical facts.
    assertCurrent?.();
    const approval = Object.freeze({resource: binding.resource,
      fields: Object.freeze([...binding.fields]),
      catalogCid: binding.catalog_cid, checkpointCid: facts.checkpointCid,
      ...(scoped ? {assertCurrent, enter} : {})});
    approvedReads.set(approval, approval);
    return approval;
  }

  // The provider supplies its independently resolved member binding. The
  // common target owner must have approved that exact binding and tuple;
  // this token covers record observation and its Catalog, never query or write.
  function admitCheckpointEffectTargetRead(decision, physicalBinding) {
    ensureOpen();
    const facts = checkpointApprovalFacts(decision);
    if (facts?.kind !== 'effect_target' || decision.action !== 'dispatch' ||
        decision.boundary !== 'acquisition' || facts.principalId !== principalId ||
        facts.configurationCid !== authorization.configurationCid ||
        facts.contextCid !== context.contextCid ||
        decision.tuple?.connection !== connection ||
        decision.tuple?.operation !== 'read' ||
        facts.readTuple?.connection !== connection || facts.readTuple?.operation !== 'read' ||
        facts.readTuple?.resource !== decision.tuple.resource ||
        physicalBinding?.version !== 'actql-installed-salesforce-effect-target-read/0.1' ||
        physicalBinding.site_binding_cid !==
          installedSalesforceSiteBinding(siteFacts, 'salesforce').bindingCid ||
        physicalBinding.resource !== decision.tuple.resource ||
        !Array.isArray(facts.physicalBindings) ||
        !facts.physicalBindings.some(binding =>
          canonicalValueJson(binding) === canonicalValueJson(physicalBinding)) ||
        typeof facts.assertCurrent !== 'function' || typeof facts.enter !== 'function') {
      fail('SalesforceEffectTargetReadApprovalNotAdmitted');
    }
    facts.assertCurrent();
    const approval = Object.freeze({kind: 'effect_target',
      resource: physicalBinding.resource, checkpointCid: facts.checkpointCid,
      assertCurrent: facts.assertCurrent, enter: facts.enter});
    approvedReads.set(approval, approval);
    return approval;
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
    if (!issuedDecisions(decision) || decision.action !== 'dispatch' ||
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
    approval, signal, retainPublicationOriginals = false, readChild}) {
    ensureOpen();
    if (!Array.isArray(resources) || resources.length === 0 ||
        !resources.every(text) || !text(occurrence) ||
        (runCid === undefined) !== (dispatchCid === undefined) ||
        readChild !== undefined && typeof readChild !== 'function') {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    const decided = new Map();
    // An admitted read approval covers the describe of its own Resource in
    // its dispatch; every other describe needs its metadata decision.
    const covered = approval === undefined ? undefined
      : approvedReads.get(approval);
    if (approval !== undefined && covered === undefined) {
      fail('SalesforceCatalogDescribeNotAuthorized');
    }
    for (const resource of resources) {
      if (covered?.resource !== resource) {
        decided.set(resource, await authorizeDescribe(resource, {occurrence, signal}));
      } else decided.set(resource, undefined);
    }
    const runInvocationCid = runCid ?? cid({version:
      'actql-salesforce-catalog-sync/0.1', siteKey: profile.siteKey,
      siteGeneration: profile.siteGeneration, syncOccurrence: occurrence});
    const dispatchRequestCid = dispatchCid ?? cid({version:
      'actql-salesforce-catalog-dispatch/0.1', runInvocationCid});
    const originals = readChild === undefined ? undefined : new Map();
    const result = await describeSalesforceResources({moon: salesforceMoon,
      apiVersion: profile.apiVersion,
      connectionRevision: profile.connectionRevision, orgId: profile.orgId,
      syncOccurrence: occurrence,
      maxObservationBytes: limits.maxObservationBytes,
      resources: [...resources], credential,
      describeLimits: limits.describe, retainEvidence, retainPublicationOriginals, maxRetainedBytes,
      ...(readChild === undefined ? {} : {callResource(input) {
        const original = originals.get(input.grant);
        if (original === undefined) fail('ForeignSalesforceSourceReadChild');
        return readChild(original, input);
      }}),
      authorizationForDescribe: async name => {
        if (!decided.has(name)) fail('SalesforceCatalogDescribeNotAuthorized');
        const original = decided.get(name);
        if (original !== undefined) assertAuthorizationAccountCurrent(original);
        covered?.assertCurrent?.();
        covered?.enter?.();
        const issued = sign({operation: 'salesforce:catalog:describe',
          runInvocationCid, taskAttempt: 1, dispatchRequestCid, maxUses: 1,
          issuerPurpose: Object.freeze({kind: 'read', resource: name, decision: original ?? approval})});
        originals?.set(issued.grant, issued);
        return {...issued,
        useId: `${occurrence}-describe-${name}`};
      }, signal});
    if (retainPublicationOriginals) liveDescribes.set(result, () => {
      ensureOpen();
      signal?.throwIfAborted();
      for (const decision of decided.values()) {
        if (decision !== undefined) assertAuthorizationAccountCurrent(decision);
      }
      covered?.assertCurrent?.();
      ensureOpen();
    });
    return result;
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
    ensureOpen();
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
    ensureOpen();
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
  const siteBinding = () => ({namespace_id: profile.namespaceId, principal: principalId,
    environment: profile.environment, org_id: profile.orgId,
    site_key: profile.siteKey, site_generation: profile.siteGeneration,
    connection_revision: profile.connectionRevision,
    resource_origin: profile.instanceOrigin,
    connector_registration: 'salesforce',
    connector_revision: 'salesforce/0.1'});
  // The declaration covers the targets the describe observed; a target the
  // org did not find or did not answer stays in the observation only.
  const describedTargets = (resources, evidence) => {
    const described = resources.filter(name =>
      evidence.outcomes[evidence.names.indexOf(name)] === 1);
    if (described.length === 0) fail('SalesforceDeclarationUnavailable');
    return described;
  };
  const generate = (observation, connectorId, resources, limits) => {
    const binding = JSON.parse(
      salesforceMoon.salesforceCatalogObservationJson(observation)).binding;
    const declaration = checked(
      salesforceMoon.salesforceGenerateStaticDeclaration(observation,
        binding.namespace_id, binding.principal, binding.environment,
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
    retainPublicationOriginals = false,
    maxEvidenceBytes = DEFAULT_SALESFORCE_CATALOG_LIMITS.maxObservationBytes,
    limits = {maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 64}} = {}) {
    ensureOpen();
    if (!Array.isArray(resources) || resources.length === 0 ||
        !resources.every(text) || !text(connectorId) ||
        typeof retainPublicationOriginals !== 'boolean' ||
        !declarationLimits(limits) ||
        !Number.isSafeInteger(maxEvidenceBytes) || maxEvidenceBytes < 1) {
      fail('InvalidSalesforceDeclaration');
    }
    const selected = [...new Set(resources)];
    const catalog = await describeNamed({resources: selected,
      occurrence: `declare-${now()}-${declareSequence++}`,
      retainEvidence: true, retainPublicationOriginals,
      maxRetainedBytes: maxEvidenceBytes, signal});
    if (catalog.status === 'interrupted') {
      fail(catalog.interruptionCode === 'SalesforceCatalogCancelled'
        ? 'SalesforceCatalogCancelled' : 'SalesforceCatalogRefreshInterrupted');
    }
    const declared = Object.freeze({...generate(catalog.observation, connectorId,
      describedTargets(selected, catalog.evidence), limits), observationCid: catalog.observationCid,
    evidence: catalog.evidence, observed: Object.freeze({
      observation: catalog.observation,
      observationCid: catalog.observationCid,
      observationJson: catalog.observationJson})});
    if (retainPublicationOriginals) {
      const assertCurrent = liveDescribes.get(catalog);
      assertCurrent();
      const declarationWire = checked(salesforceMoon.salesforceStaticDeclarationJson(
        declared.declaration, limits.maxBytes, limits.maxNodes, limits.maxDepth));
      liveDeclarations.set(declared, {catalog, assertCurrent, declarationWire,
        observed: false, pending: false, failure: undefined});
    }
    return declared;
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
    ensureOpen();
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
      describedTargets([...new Set(resources)], evidence), limits);
    if (restored.catalog_cid !== catalogCid) {
      fail('ForeignSalesforceDeclaration');
    }
    return Object.freeze({...restored, observationCid, evidence,
      observed: Object.freeze({observation, observationCid,
        observationJson: evidence.observationJson})});
  }

  // A describe of exactly `resource` for one acquisition dispatch, under its
  // own metadata read decision. The describe responses are retained so the
  // runtime that owns the acquisition reprojects the observation itself.
  async function describeForAcquisition({resource, runInvocationCid,
    dispatchRequestCid, occurrence, approval, signal, readChild} = {}) {
    ensureOpen();
    if (!text(resource) || !text(occurrence) ||
        !cidPattern.test(runInvocationCid ?? '') ||
        !cidPattern.test(dispatchRequestCid ?? '')) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    const catalog = await describeNamed({resources: [resource], occurrence,
      runInvocationCid, dispatchRequestCid, retainEvidence: true,
      maxRetainedBytes: DEFAULT_SALESFORCE_CATALOG_LIMITS.maxObservationBytes,
      approval, signal, readChild});
    if (catalog.status === 'interrupted') {
      fail(catalog.interruptionCode === 'SalesforceCatalogCancelled'
        ? 'SalesforceCatalogCancelled' : 'SalesforceCatalogRefreshInterrupted');
    }
    return Object.freeze({observationCid: catalog.observationCid,
      evidence: catalog.evidence});
  }

  // A describe of exactly `resources` for one Effect dispatch, under their
  // own metadata read decisions: the Catalog observation its writes are
  // projected from and rechecked against, with the retained describe
  // evidence that restores it after a restart.
  async function describeEffectCatalog({resources, runInvocationCid,
    dispatchRequestCid, occurrence, approval, signal} = {}) {
    ensureOpen();
    if (!Array.isArray(resources) || resources.length === 0 ||
        !cidPattern.test(runInvocationCid ?? '') ||
        !cidPattern.test(dispatchRequestCid ?? '') || !text(occurrence)) {
      fail('InvalidSalesforceCredentialGrantRequest');
    }
    const catalog = await describeNamed({resources, occurrence,
      runInvocationCid, dispatchRequestCid, retainEvidence: true,
      maxRetainedBytes: DEFAULT_SALESFORCE_CATALOG_LIMITS.maxObservationBytes,
      approval, signal});
    if (catalog.status === 'interrupted') {
      fail(catalog.interruptionCode === 'SalesforceCatalogCancelled'
        ? 'SalesforceCatalogCancelled' : 'SalesforceCatalogRefreshInterrupted');
    }
    return Object.freeze({observation: catalog.observation,
      observationCid: catalog.observationCid, evidence: catalog.evidence});
  }

  const writeKinds = Object.freeze({create: 0, createFromResult: 1,
    update: 2, upsert: 3});
  // The executable Mapping of one Effect, from a declaration this Site
  // generated. It names the declaration's own manifest entry.
  function prepareExecutionMapping({declaration, resource, write,
    limits = {maxBytes: 400_000, maxNodes: 40_000, maxDepth: 64}} = {}) {
    ensureOpen();
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
    ensureOpen();
    if (!issuedDecisions(decision) || decision.action !== 'dispatch' ||
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
        catalog.observation, binding.namespace_id, binding.principal,
        binding.environment, binding.connection_revision, binding.org_id,
        binding.site_key, binding.site_generation,
        binding.connector_registration, binding.connector_revision,
        binding.resource_origin, binding.run_invocation_cid,
        binding.dispatch_request_cid, binding.sync_occurrence, resource,
        fields, 4096)))), maxRows));
    const query = issueGrant({operation: 'salesforce:query:read', decision,
      resource, runInvocationCid, taskAttempt: 1, dispatchRequestCid, maxUses: 1});
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

  const siteFacts = Object.freeze({
    orgId: profile.orgId, connection, apiVersion: profile.apiVersion,
    instanceOrigin: profile.instanceOrigin, siteKey: profile.siteKey,
    siteGeneration: profile.siteGeneration, namespaceId: profile.namespaceId,
    environment: profile.environment,
    connectionRevision: profile.connectionRevision,
    cliAlias: profile.cliAlias, cliUsername: profile.cliUsername,
    credentialAuthorityId: profile.credentialAuthorityId,
    credentialKeyId: profile.credentialKeyId,
    credentialPrivateKeyPath: profile.credentialPrivateKeyPath,
    caPath: profile.caPath,
    connectorRegistration: 'salesforce', connectorRevision: 'salesforce/0.1',
    principal: principalId, context,
  });
  const site = Object.freeze({...siteFacts, authorization, credential, callResource: callHttpsCredentialResource,
    issueGrant, bindRecordAcquisition, attestEffectCapability, refreshCatalog, declareCatalog,
    restoreDeclaration, describeForAcquisition, describeEffectCatalog,
    admitCheckpointReadApproval,
    admitCheckpointEffectTargetRead,
    prepareExecutionMapping, peek,
    // Whether this Site generated `declaration`.
    ownsDeclaration: declaration => declarations.has(declaration),
    // Stop new operations, then release the credential journal. Returns
    // once released; a failed release throws and stays retryable.
    close: custody.closeOnce,
    // Whether this Site was closed but its journal is not yet released.
    cleanupPending: custody.cleanupPending,
  });
  const originalDeclaration = declared => {
    const original = liveDeclarations.get(declared);
    if (original === undefined) fail('SalesforcePublicationOriginalUnavailable');
    if (original.failure !== undefined) throw original.failure;
    original.assertCurrent();
    return original;
  };
  publicationSites.set(site, Object.freeze({
    async observe(declared) {
      const original = originalDeclaration(declared);
      if (original.pending) fail('SalesforcePublicationObservationPending');
      original.pending = true;
      original.observed = false;
      try {
        const current = await readSourceProfileJson(path, {maxBytes: 8 * 1024 * 1024});
        original.assertCurrent();
        if (JSON.stringify(current) !== profileWire) fail('SalesforcePublicationSiteChanged');
        original.observed = true;
      } catch (cause) { original.failure = cause; throw cause; }
      finally { original.pending = false; }
    },
    withOriginals(declared, consume) {
      const original = originalDeclaration(declared);
      if (original.pending || !original.observed) fail('SalesforcePublicationCurrentUnobserved');
      if (typeof consume !== 'function') fail('InvalidSalesforcePublicationConsumer');
      const value = withSalesforceNamedDescribeOriginals(original.catalog, credential,
        facts => {
          original.assertCurrent();
          return consume(Object.freeze({site, declared,
            declaration: declared.declaration, declarationWire: original.declarationWire,
            control: credential.control, journal: credential.journal,
            ...facts}));
        });
      original.assertCurrent();
      return value;
    },
  }));
  return custody.retainOperationSite === undefined ? site : custody.retainOperationSite(site);
}

// Compatibility entries delegate the same Site and primary failure to the
// shared Host lifecycle owner. Keep Salesforce's original fallback code and
// synchronous first close; this does not prepare or retry provider work.
export function retainSalesforceSiteCleanup(site, primary) {
  return retainInstalledCredentialSiteCleanup(site, primary,
    'SalesforceSiteOwnerFailed');
}

export function releaseSalesforceSite(site) {
  return releaseInstalledCredentialSite(site, 'SalesforceSiteOwnerFailed');
}
