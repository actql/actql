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
import {syncSalesforceCatalog} from '../site/salesforce-catalog-sync.mjs';

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
const defaultCatalogLimits = Object.freeze({
  list: Object.freeze({maxBytes: 1_000_000, maxNodes: 100_000, maxDepth: 32,
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
  now = () => Date.now()} = {}) {
  if (typeof path !== 'string' || !isAbsolute(path)) {
    fail('InvalidInstalledSalesforceSiteProfilePath');
  }
  const issuedDecisions = installedDecisions.get(authorization);
  if (issuedDecisions === undefined ||
      !cidPattern.test(runtimeBundleCid ?? '') ||
      commonMoon === undefined || salesforceMoon === undefined ||
      typeof now !== 'function' ||
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
  const credential = Object.freeze({orgId: profile.orgId, control, journal,
    resolveSecret: secret, ca, now});
  const grantLifetimeMs = 15 * 60 * 1000;

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
        decision.tuple?.operation !== required[1]) {
      fail('SalesforceCredentialGrantNotAuthorized');
    }
    return sign({operation, runInvocationCid, taskAttempt,
      dispatchRequestCid, maxUses});
  }

  let syncSequence = 0;
  // One bounded Catalog observation under this Site's own metadata grants.
  async function refreshCatalog({occurrence, retainResponses = false,
    maxRetainedBytes = 0, limits = defaultCatalogLimits, signal} = {}) {
    const sequence = syncSequence++;
    const syncOccurrence = occurrence ?? `catalog-sync-${now()}-${sequence}`;
    const runInvocationCid = cid({version: 'actql-salesforce-catalog-sync/0.1',
      siteKey: profile.siteKey, siteGeneration: profile.siteGeneration,
      syncOccurrence});
    const dispatchRequestCid = cid({version:
      'actql-salesforce-catalog-dispatch/0.1', runInvocationCid});
    const grant = operation => {
      if (!catalogOperations.has(operation)) {
        fail('InvalidSalesforceCredentialGrantRequest');
      }
      return sign({operation, runInvocationCid, taskAttempt: 1,
        dispatchRequestCid, maxUses: operation === 'salesforce:catalog:list'
          ? 1 : limits.list.maxSelected});
    };
    const list = grant('salesforce:catalog:list');
    const describe = grant('salesforce:catalog:describe');
    return await syncSalesforceCatalog({
      moon: salesforceMoon, apiVersion: profile.apiVersion,
      connectionRevision: profile.connectionRevision, orgId: profile.orgId,
      syncOccurrence, maxObservationBytes: limits.maxObservationBytes,
      retainResponses, maxRetainedBytes,
      listAuthorization: {...list, useId: `${syncOccurrence}-list`},
      authorizationForDescribe: async name => ({...describe,
        useId: `${syncOccurrence}-describe-${name}`}),
      credential, listLimits: limits.list, describeLimits: limits.describe,
      signal,
    });
  }

  return Object.freeze({
    orgId: profile.orgId, connection, apiVersion: profile.apiVersion,
    instanceOrigin: profile.instanceOrigin, siteKey: profile.siteKey,
    siteGeneration: profile.siteGeneration, tenant: profile.tenant,
    environment: profile.environment,
    connectionRevision: profile.connectionRevision,
    principal: principalId, context, authorization, credential,
    issueGrant, refreshCatalog,
    close() { journal.close(); },
  });
}
