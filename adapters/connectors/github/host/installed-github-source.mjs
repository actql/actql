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
import {canonicalJson, contentCid} from
  '../../../host-node/local-account-config.mjs';
import {createInstalledRowSource, installRowSourceAuthorization,
  openRowSourceCredentialSite, rowSourceCheckEnvironment} from
  '../../../host-node/installed-row-source.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';
import {githubIssueListPath} from '../site/github-issue-read.mjs';
import {GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION,
  readGitHubIssuesByNode} from '../site/github-issue-graphql-read.mjs';

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
  maxRequestBytes: 16_384});
const rowLimits = Object.freeze({maxPages: readLimits.maxPages,
  maxPageBytes: 4_000_000, maxPageRows: 100, maxCaptureRows: 100});

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
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

async function readJson(path, code) {
  try {
    const bytes = await readFile(path);
    if (bytes.byteLength > 1024 * 1024) fail(code);
    return JSON.parse(bytes.toString('utf8'));
  } catch (cause) {
    if (cause?.code === code) throw cause;
    fail(code, cause);
  }
}

async function readSite(path) {
  const site = await readJson(path, 'InvalidInstalledGitHubSite');
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
  return Object.freeze({...site,
    ca: caPath === undefined ? undefined : await readFile(caPath)});
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
    await read(checkedProfile.siteProfilePath),
    await read(checkedProfile.publicationPath),
  ];
}

async function restore(moon, connectorId, expectedCatalogCid) {
  const views = await readFile(viewsUrl, 'utf8');
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    connectorId, registration, revision, views, expectedCatalogCid));
  const declared = JSON.parse(
    moon.clientProgramRowSourceDeclarationJson(declaration));
  if (declared === null) fail('InvalidGitHubDeclaration');
  return {declaration, declared};
}

async function openSite(checkedProfile, site, {root, principalId, moon,
  runtimeBundleCid, resolveSecret, publication}) {
  // The authorization tuple names the access target (API host and
  // owner/repo); the stable repository id is pinned by the physical binding
  // an approval covers and by the installation identity.
  const connection = `github:${new URL(site.apiOrigin).host}/${site.owner}/${site.repo}`;
  const authorization = await installRowSourceAuthorization({
    accountConfiguration: checkedProfile.accountConfigurationWire,
    principalId, root, connectorRegistration: registration});
  const credentialSite = await openRowSourceCredentialSite({
    profile: {...site, resourceOrigin: site.apiOrigin}, principalId,
    authorization, connection, connectorRegistration: registration,
    connectorRevision: revision, runtimeBundleCid, commonMoon: moon,
    resolveSecret: resolveSecret ?? environmentSecret(site.tokenEnvironment),
    ca: site.ca,
    admitsApprovalTarget: (binding, resource) => publication !== undefined &&
      binding?.version === TARGET_VERSION &&
      binding.api_origin === site.apiOrigin &&
      binding.repository_id === publication.repository.id &&
      binding.repository_node_id === publication.repository.node_id &&
      binding.owner === site.owner && binding.repo === site.repo &&
      binding.catalog_cid === publication.catalogCid &&
      binding.resource === resource && Array.isArray(binding.fields)});
  return {authorization, site: credentialSite, connection};
}

// The explicit publication step: observe the repository's stable identity
// under the installed read decision and the credential resource, and record
// it with the declaration's Catalog CID. A Host start never runs it.
export async function publishInstalledGitHubSource(profile, {root,
  principalId, moon, providerMoon, runtimeBundleCid, resolveSecret, signal}) {
  const checkedProfile = checkInstalledGitHubSourceProfile(profile);
  const site = await readSite(checkedProfile.siteProfilePath);
  const {declared} = await restore(moon, checkedProfile.connectorId, undefined);
  const opened = await openSite(checkedProfile, site, {root, principalId,
    moon, runtimeBundleCid, resolveSecret});
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
      callResource: callHttpsCredentialResource,
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
  } finally {
    opened.site.close();
  }
}

// Load one installed GitHub source: restore its declaration and repository
// binding without provider I/O.
export async function loadInstalledGitHubSource(profile, {root, principalId,
  moon, providerMoon, baseEnvironmentWire, runtimeBundleCid, resolveSecret}) {
  const checkedProfile = checkInstalledGitHubSourceProfile(profile);
  const site = await readSite(checkedProfile.siteProfilePath);
  let publication;
  try {
    publication = JSON.parse(await readFile(checkedProfile.publicationPath,
      'utf8'));
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
  const {declaration, declared} = await restore(moon,
    checkedProfile.connectorId, publication.catalogCid);
  const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
  const opened = await openSite(checkedProfile, site, {root, principalId,
    moon, runtimeBundleCid, resolveSecret, publication});
  const physicalTarget = (resource, fields) => Object.freeze({
    version: TARGET_VERSION, api_origin: site.apiOrigin,
    repository_id: publication.repository.id,
    repository_node_id: publication.repository.node_id,
    owner: site.owner, repo: site.repo,
    catalog_cid: publication.catalogCid, resource,
    fields: Object.freeze([...fields])});
  return createInstalledRowSource({moon, declaration, declared,
    environmentWire: environment.wire,
    connectorId: checkedProfile.connectorId,
    connectorRegistration: registration, connectorRevision: revision,
    site: opened.site, authorization: opened.authorization,
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
    readPages: async ({resource, authorizationFor, consumePage, signal}) => {
      if (resource !== 'issues') fail('UndeclaredGitHubResource');
      return readGitHubIssuesByNode({moon: providerMoon,
        repository: {nodeId: publication.repository.node_id,
          databaseId: publication.repository.id,
          nameWithOwner: `${site.owner}/${site.repo}`},
        filters: {state: 'all', labels: []},
        credential: opened.site.credential,
        callResource: callHttpsCredentialResource, authorizationFor,
        limits: readLimits, consumePage, signal});
    }});
}
