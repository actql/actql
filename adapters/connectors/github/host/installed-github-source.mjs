// GitHub's source installation for the standard installed Host, entered in
// the installed connector table by `src/connectors/github/host-bundle.json`.
// Everything common (declaration, Check Environment, read decisions,
// credential grants, acquisition, capture, Source Evidence) is the Host's
// provider-neutral row source; this module supplies GitHub's view
// specification, its repository binding and its Issue listing driver.
//
// Physical identity: the API origin, the repository's stable id and node id
// (observed by the explicit publication step, never during Check or load)
// and the owner/repo used for access are kept apart. A rename or transfer is
// not followed: a publication whose owner/repo no longer matches the Site
// profile is refused, and a new explicit publication re-binds it.
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
import {GITHUB_ISSUE_LIST_OPERATION, githubIssueListPath, readGitHubIssues}
  from '../site/github-issue-read.mjs';

export const INSTALLED_GITHUB_SOURCE_VERSION =
  'actql-installed-github-source/0.1';
export const INSTALLED_GITHUB_SITE_VERSION = 'actql-installed-github-site/0.1';
const PUBLICATION_VERSION = 'actql-github-publication/0.1';
const TARGET_VERSION = 'actql-installed-github-target/0.1';
const REPOSITORY_OPERATION = 'github:repository:read';
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
  maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 32,
  maxLocatorUnits: 2048, perPage: 100});
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
    const grant = opened.site.issueReadGrant({operation: REPOSITORY_OPERATION,
      decision, resource: 'issues', runInvocationCid,
      dispatchRequestCid: runInvocationCid, maxUses: 1});
    const response = await invokeScopedCredentialOperation({
      authorization: {...grant, useId: `${nonce}-repository`},
      credential: opened.site.credential,
      callResource: callHttpsCredentialResource,
      operation: REPOSITORY_OPERATION, method: 'GET',
      path: `/repos/${site.owner}/${site.repo}`,
      headers: JSON.parse(providerMoon.githubRequestHeadersJson()),
      maxResponseBytes: 1_000_000, signal});
    if (!response.accepted || response.statusCode !== 200) {
      fail('GitHubRepositoryUnavailable');
    }
    const repository = JSON.parse(providerMoon.githubRepositoryJson(
      response.body, 1_000_000));
    // The access owner/repo must be the repository's current names: a
    // redirect or rename is not followed silently.
    if (repository === null || repository.owner !== site.owner ||
        repository.name !== site.repo) {
      fail('GitHubRepositoryBindingChanged');
    }
    const publication = {version: PUBLICATION_VERSION,
      apiOrigin: site.apiOrigin, owner: site.owner, repo: site.repo,
      repository: {id: repository.id, node_id: repository.node_id},
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
    readOperation: GITHUB_ISSUE_LIST_OPERATION, physicalTarget,
    bindingCid: contentCid({version: 'actql-installed-github-binding/0.1',
      contextCid: opened.authorization.context.contextCid,
      apiOrigin: site.apiOrigin, repository: publication.repository,
      owner: site.owner, repo: site.repo, siteKey: site.siteKey,
      siteGeneration: site.siteGeneration, namespaceId: site.namespaceId,
      environment: site.environment,
      credentialAuthorityId: site.credentialAuthorityId,
      credentialKeyId: site.credentialKeyId}),
    limits: rowLimits,
    targetOperations: [REPOSITORY_OPERATION],
    // GitHub's documented Issue listing is addressed by owner/repo and its
    // rows carry no repository id. The read is bound to the published
    // repository by checking, under the current read decision, that the
    // access name resolves to the published id and node id immediately
    // before the first page and again after the last; any difference, or an
    // unverifiable check, stops the acquisition before capture, so no Result
    // or Source Evidence is issued under the old binding. A replacement that
    // is reversed entirely within the read window is not observable through
    // name-addressed listing and is not claimed to be detected.
    readPages: async ({resource, authorizationFor, targetAuthorizationFor,
      consumePage, signal}) => {
      if (resource !== 'issues') fail('UndeclaredGitHubResource');
      const verify = async label => {
        const response = await invokeScopedCredentialOperation({
          authorization: await targetAuthorizationFor(REPOSITORY_OPERATION,
            label),
          credential: opened.site.credential,
          callResource: callHttpsCredentialResource,
          operation: REPOSITORY_OPERATION, method: 'GET',
          path: `/repos/${site.owner}/${site.repo}`,
          headers: JSON.parse(providerMoon.githubRequestHeadersJson()),
          maxResponseBytes: 1_000_000, signal});
        const observed = response.accepted && response.statusCode === 200
          ? JSON.parse(providerMoon.githubRepositoryJson(response.body,
            1_000_000)) : null;
        if (observed === null) fail('GitHubRepositoryUnverified');
        if (observed.id !== publication.repository.id ||
            observed.node_id !== publication.repository.node_id ||
            observed.owner !== site.owner || observed.name !== site.repo) {
          fail('GitHubRepositoryIdentityChanged');
        }
      };
      await verify('before');
      const read = await readGitHubIssues({moon: providerMoon,
        origin: site.apiOrigin, owner: site.owner, repo: site.repo,
        filters: [['state', 'all']], credential: opened.site.credential,
        authorizationFor, limits: readLimits, consumePage, signal});
      await verify('after');
      return read;
    }});
}
