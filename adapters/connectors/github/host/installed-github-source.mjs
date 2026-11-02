// GitHub's source installation for the standard installed Host, entered in
// the installed connector table by `src/connectors/github/host-bundle.json`.
// Everything common (declaration, Check Environment, read decisions,
// credential grants, acquisition, capture, Source Evidence) is the Host's
// provider-neutral row source; this module supplies GitHub's view
// specification, its repository binding and its Issue listing driver.
//
// Physical identity: the API origin, the repository's stable database id and
// global node ID (observed by the explicit publication step through the same
// GraphQL API the reads use, never during Check or load) and the owner/repo
// used for access are kept apart. Every read page resolves the repository by
// that node ID, so a different repository under the same name is never read.
// A rename or transfer is not followed: a publication whose owner/repo no
// longer matches the Site profile, or a page whose repository is now named
// differently, is refused, and a new explicit publication re-binds it; so is
// a node ID whose representation changed.
import {createHash, randomUUID} from 'node:crypto';
import {mkdir, readFile, rename, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute} from 'node:path';
import {checked} from '../../../host-common/runtime-result.mjs';
import {retainInstalledHostInitializationFailure} from
  '../../../host-node/installed-host-cleanup.mjs';
import {readSourceProfileJson, captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {canonicalJson, contentCid} from
  '../../../host-node/local-account-config.mjs';
import {installRowSourceAuthorization,
  openRowSourceCredentialSite} from
  '../../../host-node/installed-row-source.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {githubIssueListPath} from '../site/github-issue-read.mjs';
import {GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION,
  readGitHubIssuesByNode, readGitHubPullRequestsByNode, readGitHubIssueCommentsByNode} from '../site/github-issue-graphql-read.mjs';

export const INSTALLED_GITHUB_SOURCE_VERSION =
  'actql-installed-github-source/0.1';
export const INSTALLED_GITHUB_SITE_VERSION = 'actql-installed-github-site/0.1';
const PUBLICATION_VERSION = 'actql-github-publication/0.1';
const TARGET_VERSION = 'actql-installed-github-target/0.1';
const registration = 'github';
const revision = 'github/0.1';
const viewsUrl = new URL('../../../../src/connectors/github/source-views.json',
  import.meta.url);
const profileKeys = ['accountConfigurationWire', 'connectorId',
  'publicationPath', 'siteProfilePath', 'version'];
const siteKeys = ['apiOrigin', 'credentialAuthorityId', 'credentialKeyId',
  'credentialPrivateKeyPath', 'environment', 'journalRoot', 'namespaceId',
  'owner', 'repo', 'siteGeneration', 'siteKey', 'tokenEnvironment'];
const readLimits = Object.freeze({maxPages: 10, maxRows: 100,
  maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 32, perPage: 100,
  maxRequestBytes: 16_384, maxSubjects: 100});
const rowLimits = Object.freeze({maxPages: readLimits.maxPages,
  maxPageBytes: 4_000_000, maxPageRows: 100, maxCaptureRows: 100});

const fail = (code, cause) => {
  const failure = Object.assign(new Error(code, {cause}), {code});
  if (cause?.cleanupHandle !== undefined) {
    Object.assign(failure, {cleanupHandle: cause.cleanupHandle,
      cleanupPending: cause.cleanupPending});
  }
  throw failure;
};
const text = value => typeof value === 'string' && value.length > 0;
const absolute = value => text(value) && isAbsolute(value);
const sameKeys = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

export function checkInstalledGitHubSourceProfile(profile) {
  if (!sameKeys(profile, profileKeys) ||
      profile.version !== INSTALLED_GITHUB_SOURCE_VERSION ||
      !absolute(profile.siteProfilePath) || !absolute(profile.publicationPath) ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire)) {
    fail('InvalidInstalledSourceProfile');
  }
  return Object.freeze({...profile});
}

async function readJson(path, code, read = readSourceProfileJson) {
  try {
    return await read(path, {maxBytes: 1024 * 1024});
  } catch (cause) {
    if (cause?.code === code) throw cause;
    fail(code, cause);
  }
}

async function readSite(path, configurationReader) {
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => fail('InstalledGitHubConfigurationReaderUnavailable'));
  const site = await readJson(path, 'InvalidInstalledGitHubSite', readers.readJson);
  const {version, caPath, ...rest} = site ?? {};
  let origin;
  try { origin = new URL(rest.apiOrigin); } catch { origin = undefined; }
  if (version !== INSTALLED_GITHUB_SITE_VERSION || !sameKeys(rest, siteKeys) ||
      origin?.protocol !== 'https:' || origin.origin !== rest.apiOrigin ||
      !Number.isSafeInteger(rest.siteGeneration) ||
      !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(rest.tokenEnvironment) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !absolute(rest.credentialPrivateKeyPath) || !absolute(rest.journalRoot)) {
    fail('InvalidInstalledGitHubSite');
  }
  // The owner/repo of access; the path builder refuses anything else.
  githubIssueListPath(rest.owner, rest.repo);
  if (caPath !== undefined && configurationReader !== undefined && readers.readOriginalBytes === undefined) {
    fail('InstalledGitHubConfigurationReaderUnavailable');
  }
  return Object.freeze({...site,
    ca: caPath === undefined ? undefined : await (configurationReader === undefined
      ? readFile(caPath) : readers.readOriginalBytes(caPath))});
}

// The token is read from the environment variable the Site profile names;
// the profile never holds a token value.
const environmentSecret = name => async () => {
  const value = process.env[name];
  if (!text(value)) fail('RemoteCredentialSecretUnavailable');
  return value;
};

// The parts of this installation's identity: the Host profile with its
// account configuration as a document, the Site profile and the publication.
export async function installedGitHubSourceIdentityParts(profile,
  providerProfile, read) {
  const checkedProfile = checkInstalledGitHubSourceProfile(providerProfile);
  return [
    {...profile, accountConfigurationWire: JSON.parse(
      profile.accountConfigurationWire)},
    await read(checkedProfile.siteProfilePath, {maxBytes: 1024 * 1024}),
    await read(checkedProfile.publicationPath, {maxBytes: 1024 * 1024}),
  ];
}

// The published repository binding of a checked profile, without provider
// I/O. A publication for another connector or another owner/repo is refused.
export async function readGitHubPublication(checkedProfile, site, read = readSourceProfileJson) {
  let publication;
  try {
    publication = await read(checkedProfile.publicationPath,
      {maxBytes: 1024 * 1024});
  } catch (cause) {
    fail('GitHubPublicationMissing', cause);
  }
  if (publication?.version !== PUBLICATION_VERSION ||
      publication.connectorId !== checkedProfile.connectorId) {
    fail('InvalidGitHubPublication');
  }
  if (publication.apiOrigin !== site.apiOrigin ||
      publication.owner !== site.owner || publication.repo !== site.repo) {
    fail('GitHubRepositoryBindingChanged');
  }
  return publication;
}

// The Site, its opening and the declaration are shared with the GitHub
// Effect installation; there is no second copy of any of them.
export {readSite as readGitHubSite, openSite as openGitHubSite,
  restore as restoreGitHubDeclaration};

async function restore(moon, connectorId, expectedCatalogCid, sourceInitialization,
  readOriginalText = path => readFile(path, 'utf8')) {
  const constructor = sourceInitialization === undefined ? undefined
    : Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareDeclaration');
  if (sourceInitialization !== undefined && (!constructor || !Object.hasOwn(constructor, 'value') ||
      typeof constructor.value !== 'function')) fail('InstalledGitHubInitializationUnavailable');
  const views = await readOriginalText(viewsUrl);
  if (constructor !== undefined) return Reflect.apply(constructor.value, sourceInitialization, [views, expectedCatalogCid]);
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    connectorId, registration, revision, views, expectedCatalogCid));
  const declared = JSON.parse(
    moon.clientProgramRowSourceDeclarationJson(declaration));
  if (declared === null) fail('InvalidGitHubDeclaration');
  return {declaration, declared};
}

async function openSite(checkedProfile, site, {root, principalId, moon,
  runtimeBundleCid, resolveSecret, publication, installation, sourceInitialization}, installationServices) {
  // The authorization tuple names the access target (API host and
  // owner/repo); the stable repository id is pinned by the physical binding
  // an approval covers and by the installation identity.
  const connection = `github:${new URL(site.apiOrigin).host}/${site.owner}/${site.repo}`;
  const configuration = {
    profile: Object.freeze({...site, resourceOrigin: site.apiOrigin}),
    resolveSecret: resolveSecret ?? environmentSecret(site.tokenEnvironment),
    ca: site.ca, responseHeaders: installation?.responseHeaders ?? [],
    admitsApprovalTarget: (binding, resource) => publication !== undefined &&
      binding?.version === TARGET_VERSION &&
      binding.api_origin === site.apiOrigin &&
      binding.repository_id === publication.repository.id &&
      binding.repository_node_id === publication.repository.node_id &&
      binding.owner === site.owner && binding.repo === site.repo &&
      binding.catalog_cid === publication.catalogCid &&
      binding.resource === resource && Array.isArray(binding.fields)};
  if (installationServices !== undefined) {
    const open = Object.getOwnPropertyDescriptor(installationServices, 'openRowSite');
    if (!open || !Object.hasOwn(open, 'value') || typeof open.value !== 'function') {
      fail('InvalidInstalledEffectSiteServices');
    }
    const opened = await Reflect.apply(open.value, installationServices, [{
      installation, accountConfiguration: checkedProfile.accountConfigurationWire,
      ...(sourceInitialization === undefined ? {} : {sourceInitialization}),
      connection, ...configuration}]);
    return {...opened, connection};
  }
  const authorization = await installRowSourceAuthorization({
    accountConfiguration: checkedProfile.accountConfigurationWire,
    principalId, root, connectorRegistration: registration});
  const credentialSite = await openRowSourceCredentialSite({
    ...configuration, principalId, authorization, connection,
    connectorRegistration: registration, connectorRevision: revision,
    runtimeBundleCid, commonMoon: moon});
  return {authorization, site: credentialSite, connection};
}

// The explicit publication step: observe the repository's stable identity
// under the installed read decision and the credential resource, and record
// it with the declaration's Catalog CID. A Host start never runs it.
export async function publishInstalledGitHubSource(profile, options) {
  return publishGitHubRepository(checkInstalledGitHubSourceProfile(profile),
    options);
}

// The publication step of a checked GitHub source or Effect profile: both
// bind the same repository the same way.
export async function publishGitHubRepository(checkedProfile, {root,
  principalId, moon, providerMoon, runtimeBundleCid, resolveSecret, signal,
  installation}) {
  const site = await readSite(checkedProfile.siteProfilePath);
  const {declared} = await restore(moon, checkedProfile.connectorId, undefined);
  const opened = await openSite(checkedProfile, site, {root, principalId,
    moon, runtimeBundleCid, resolveSecret, installation});
  let primaryFailure;
  try {
    const decision = await opened.authorization.authorize('acquisition',
      {connection: opened.connection, resource: 'issues', operation: 'read'},
      {subjectCid: contentCid({version: 'actql-github-publication-read/0.1',
        owner: site.owner, repo: site.repo}), signal});
    if (decision?.action !== 'dispatch') {
      fail('ExecutionAuthorizationDenied');
    }
    const nonce = randomUUID();
    const runInvocationCid = `sha256:${createHash('sha256')
      .update(`github-publication:${nonce}`).digest('hex')}`;
    const grant = opened.site.issueReadGrant({
      operation: GITHUB_GRAPHQL_READ_OPERATION, decision, resource: 'issues',
      runInvocationCid, dispatchRequestCid: runInvocationCid, maxUses: 1});
    // The fixed repository lookup, so the stored node ID has the same
    // representation every read compares exactly.
    const response = await invokeScopedCredentialOperation({
      authorization: {...grant, useId: `${nonce}-repository`},
      credential: opened.site.credential,
      callResource: opened.site.callResource,
      operation: GITHUB_GRAPHQL_READ_OPERATION, method: 'POST',
      path: GITHUB_GRAPHQL_PATH,
      headers: JSON.parse(providerMoon.githubRequestHeadersJson()),
      body: providerMoon.githubRepositoryRequest(site.owner, site.repo),
      maxRequestBytes: 16_384, maxResponseBytes: 1_000_000, signal});
    if (!response.accepted || response.statusCode !== 200) {
      fail('GitHubRepositoryUnavailable');
    }
    const observed = JSON.parse(providerMoon.githubRepositoryResponseJson(
      response.body, 1_000_000));
    if (observed.refused) {
      fail(observed.refused.kind === 'RepositoryUnavailable'
        ? 'GitHubRepositoryUnavailable' : 'GitHubRepositoryUnverified');
    }
    const repository = observed.repository;
    // The access owner/repo must be the repository's current names: a
    // redirect or rename is not followed silently.
    if (repository.name_with_owner !== `${site.owner}/${site.repo}`) {
      fail('GitHubRepositoryBindingChanged');
    }
    const publication = {version: PUBLICATION_VERSION,
      apiOrigin: site.apiOrigin, owner: site.owner, repo: site.repo,
      repository: {id: repository.database_id,
        node_id: repository.node_id},
      catalogCid: declared.catalog_cid,
      connectorId: checkedProfile.connectorId};
    await mkdir(dirname(checkedProfile.publicationPath), {recursive: true});
    const temporary = `${checkedProfile.publicationPath}.${nonce}`;
    await writeFile(temporary, canonicalJson(publication), {mode: 0o600});
    await rename(temporary, checkedProfile.publicationPath);
    return Object.freeze({...publication});
  } catch (cause) {
    primaryFailure = cause;
    throw cause;
  } finally {
    try { await opened.site.close(); }
    catch (cause) {
      // Publication may already be durable. Retain only the original Site's
      // cleanup, never repeat discovery or replace its original refusal.
      throw await retainInstalledHostInitializationFailure(primaryFailure ?? cause,
        {sourceProfile: opened.site});
    }
  }
}

// Load one installed GitHub source: restore its declaration and repository
// binding without provider I/O.
export async function loadInstalledGitHubSource(profile, {root, principalId,
  moon, providerMoon, baseEnvironmentWire, runtimeBundleCid, resolveSecret,
  installation, construction}) {
  if (typeof construction?.prepareDeclaration !== 'function' ||
      typeof construction.openRowSite !== 'function' ||
      typeof construction.createRowSource !== 'function' ||
      typeof construction.configurationReader?.readOriginalText !== 'function') {
    fail('InstalledGitHubConstructionUnavailable');
  }
  const readers = construction.configurationReader;
  const checkedProfile = checkInstalledGitHubSourceProfile(profile);
  const site = await readSite(checkedProfile.siteProfilePath, readers);
  const publication = await readGitHubPublication(checkedProfile, site, readers.readJson);
  construction.prepareDeclaration(await readers.readOriginalText(viewsUrl), publication.catalogCid);
  const connection = `github:${new URL(site.apiOrigin).host}/${site.owner}/${site.repo}`;
  const opened = await construction.openRowSite({
    accountConfiguration: checkedProfile.accountConfigurationWire, connection,
    profile: Object.freeze({...site, resourceOrigin: site.apiOrigin}),
    resolveSecret: resolveSecret ?? environmentSecret(site.tokenEnvironment),
    ca: site.ca, responseHeaders: installation?.responseHeaders ?? [],
    admitsApprovalTarget: (binding, resource) =>
      binding?.version === TARGET_VERSION &&
      binding.api_origin === site.apiOrigin &&
      binding.repository_id === publication.repository.id &&
      binding.repository_node_id === publication.repository.node_id &&
      binding.owner === site.owner && binding.repo === site.repo &&
      binding.catalog_cid === publication.catalogCid &&
      binding.resource === resource && Array.isArray(binding.fields)});
  {
    const physicalTarget = (resource, fields) => Object.freeze({
      version: TARGET_VERSION, api_origin: site.apiOrigin,
      repository_id: publication.repository.id,
      repository_node_id: publication.repository.node_id,
      owner: site.owner, repo: site.repo,
      catalog_cid: publication.catalogCid, resource,
      fields: Object.freeze([...fields])});
    return await construction.createRowSource({
      readOperation: GITHUB_GRAPHQL_READ_OPERATION, physicalTarget,
      bindingCid: contentCid({version: 'actql-installed-github-binding/0.1',
        contextCid: opened.authorization.context.contextCid,
        apiOrigin: site.apiOrigin, repository: publication.repository,
        owner: site.owner, repo: site.repo, siteKey: site.siteKey,
        siteGeneration: site.siteGeneration, namespaceId: site.namespaceId,
        environment: site.environment,
        credentialAuthorityId: site.credentialAuthorityId,
        credentialKeyId: site.credentialKeyId}),
      limits: rowLimits,
      readPages: async ({resource, authorizationFor, chargePage, consumeObservation, consumePage,
        signal}) => {
        const read = resource === 'issues' ? readGitHubIssuesByNode
          : resource === 'pull_requests' ? readGitHubPullRequestsByNode
          : resource === 'issue_comments' ? readGitHubIssueCommentsByNode : undefined;
        if (read === undefined) fail('UndeclaredGitHubResource');
        return read({moon: providerMoon,
          repository: {nodeId: publication.repository.node_id,
            databaseId: publication.repository.id,
            nameWithOwner: `${site.owner}/${site.repo}`},
          filters: {state: 'all', labels: []},
          credential: opened.site.credential,
          callResource: opened.site.callResource, authorizationFor,
          limits: readLimits, chargePage, consumeObservation,
          consumePage: (rows, _page, admission) => consumePage(rows, admission),
          signal});
      }});
  }
}
