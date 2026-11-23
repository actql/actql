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
import {httpsCredentialResponseHeaderByteLimit} from '../../../site-node/https-credential-resource.mjs';
import {installedJsonSourceReaderLimitNames} from '../../../host-node/installed-credential-source-reader.mjs';
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
import {GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION,
  prepareGitHubSourceReadSequence} from '../site/github-issue-graphql-read.mjs';
import type {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import type {createInstalledCredentialSourceReader} from '../../../host-node/installed-credential-source-reader.mjs';
import type {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';

type Sequence = Parameters<typeof prepareGitHubSourceReadSequence>[0];
type HttpResponse = Awaited<ReturnType<typeof callHttpsCredentialResource>>;
type SiteOptions = Parameters<typeof openRowSourceCredentialSite>[0];
type Reader = ReturnType<typeof createInstalledCredentialSourceReader>;
type Configuration = ReturnType<typeof captureConfigurationReaders> &
  Readonly<{readOriginalText?: (path: URL) => unknown; readOriginalBytes?: (path: string) => unknown}>;
type Read = (path: string, options: Readonly<{maxBytes: number}>) => unknown;
type ReadText = (path: URL) => string | PromiseLike<string>;
type Profile = Readonly<{accountConfigurationWire: string; connectorId: string; publicationPath: string; siteProfilePath: string}>;
type SourceProfile = Profile & Readonly<{version: typeof INSTALLED_GITHUB_SOURCE_VERSION}>;
type SiteInput = Readonly<{
  version: typeof INSTALLED_GITHUB_SITE_VERSION; caPath?: string;
  apiOrigin: string; credentialAuthorityId: string; credentialKeyId: string; credentialPrivateKeyPath: string;
  environment: string; journalRoot: string; namespaceId: string; owner: string; repo: string;
  siteGeneration: number; siteKey: string; tokenEnvironment: string;
}>;
type Site = SiteInput & Readonly<{ca: SiteOptions['ca']}>;
type Repository = Readonly<{id: number; node_id: string}>;
type Publication = Readonly<{
  version: typeof PUBLICATION_VERSION; apiOrigin: string; owner: string; repo: string; repository: Repository;
  catalogCid: string; connectorId: string;
}>;
type Declared = Parameters<typeof rowSourceCheckEnvironment>[1] & Readonly<{catalog_cid: string}>;
type Prepared = Readonly<{declaration: unknown; declared: Declared}>;
type Common = Readonly<{
  clientProgramRowSourceRestoreRelationDeclaration(connector: string, registration: string,
    revision: string, views: string, expectedCatalogCid: string | undefined): unknown;
  clientProgramRowSourceDeclarationJson(declaration: unknown): string;
}>;
type RepositoryCodec = Readonly<{githubRepositoryAccessValid(owner: string, repo: string): boolean}>;
type PublishCodec = RepositoryCodec & Readonly<{
  githubRequestHeadersJson(): string;
  githubRepositoryRequest(owner: string, repo: string): string;
  githubRepositoryResponseJson(body: Buffer, maxBytes: number): string;
}>;
type RepositoryReply = Readonly<{refused?: Readonly<{kind: string}>;
  repository: Readonly<{node_id: string; database_id: number; name_with_owner: string}>}>;
type CleanupCause = Readonly<{cleanupHandle?: unknown; cleanupPending?: unknown; code?: string}> | null | undefined;
type Binding = Readonly<{version?: unknown; api_origin?: unknown; repository_id?: unknown; repository_node_id?: unknown;
  owner?: unknown; repo?: unknown; catalog_cid?: unknown; resource?: unknown; fields?: unknown}> | null | undefined;
type ActualSite = Extract<Awaited<ReturnType<typeof openRowSourceCredentialSite>>, {issueReadGrant: (...args: never[]) => unknown}>;
type SiteAuthorization = Awaited<ReturnType<typeof installRowSourceAuthorization>>;
type Opened = Readonly<{site: ActualSite; authorization: SiteAuthorization; connection: string}>;
type Installation = Readonly<{responseHeaders?: readonly string[]}>;
type OpenOptions = Readonly<{root?: string; principalId: SiteOptions['principalId']; moon: Common;
  runtimeBundleCid: string; resolveSecret?: SiteOptions['resolveSecret']; publication?: Publication;
  installation?: Installation; sourceInitialization?: object}>;
type PublishOptions = Omit<OpenOptions, 'publication' | 'sourceInitialization'> &
  Readonly<{providerMoon: PublishCodec; signal?: AbortSignal}>;
type CredentialLimits = NonNullable<SiteOptions['runAcquisitionLimits']>;
type ReaderLimits = Readonly<Record<typeof installedJsonSourceReaderLimitNames[number] | 'maxSecretBytes', number>>;
type Implementation = Readonly<{runAcquisitionLimits: CredentialLimits; capacity: unknown}>;
type ConstructedSource = Readonly<{
  readOperation: string; physicalTarget(resource: string, fields: readonly string[]): object;
  bindingCid: string; limits: typeof rowLimits; providerReader: Reader;
  prepareRead(input: Sequence['preparedRead']): Promise<Sequence['preparedRead']>;
}>;
type Construction = Readonly<{
  configurationReader: Readonly<{readJson: Read; readOriginalText: ReadText}>;
  prepareDeclaration(views: string, catalogCid: string): unknown;
  openRowSite(input: Readonly<{accountConfiguration: string; connection: string; runAcquisitionLimits: CredentialLimits;
    profile: Site & Readonly<{resourceOrigin: string}>; resolveSecret: SiteOptions['resolveSecret'];
    ca: SiteOptions['ca']; responseHeaders: readonly string[];
    admitsApprovalTarget(binding: Binding, resource: string): boolean}>): PromiseLike<Readonly<{
      site: Sequence['site']; authorization: Pick<SiteAuthorization, 'context'>;
    }>>;
  sourceReaderImplementation(input: Readonly<{limits: ReaderLimits; columnCount: number;
    readSequenceConstruction: Readonly<{capacity: unknown; originalLimits: typeof readLimits; maxRequestBytes: number;
      sequence: Readonly<{operation: string; maxUses: number; children: readonly object[]}>}>}>): Implementation;
  createSourceReader(input: Readonly<{implementation: Implementation;
    prepareReadSequence(input: Pick<Sequence, 'preparedRead' | 'originalAuthorization'>,
      retireProjection: Sequence['retireProjection']): ReturnType<typeof prepareGitHubSourceReadSequence>}>): Reader;
  createRowSource(input: ConstructedSource): unknown;
}>;
type InstallOptions = Omit<PublishOptions, 'providerMoon'> & Readonly<{
  providerMoon: RepositoryCodec & Sequence['moon']; baseEnvironmentWire?: string; construction?: Construction;
}>;

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

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  const failure = Object.assign(new Error(code, {cause}), {code});
  if ((cause as CleanupCause)?.cleanupHandle !== undefined) {
    Object.assign(failure, {cleanupHandle: (cause as NonNullable<CleanupCause>).cleanupHandle,
      cleanupPending: (cause as NonNullable<CleanupCause>).cleanupPending});
  }
  throw failure;
};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const absolute = (value: unknown): value is string => text(value) && isAbsolute(value);
const sameKeys = (value: unknown, keys: readonly string[]): value is Record<string, unknown> => value !== null && typeof value === 'object' &&
  !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

export function checkInstalledGitHubSourceProfile(profile: unknown): SourceProfile {
  if (!sameKeys(profile, profileKeys) ||
      profile.version !== INSTALLED_GITHUB_SOURCE_VERSION ||
      !absolute(profile.siteProfilePath) || !absolute(profile.publicationPath) ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire)) {
    fail('InvalidInstalledSourceProfile');
  }
  return Object.freeze({...profile}) as SourceProfile;
}

async function readJson(path: string, code: string, read: Read = readSourceProfileJson) {
  try {
    return await read(path, {maxBytes: 1024 * 1024});
  } catch (cause) {
    if ((cause as CleanupCause)?.code === code) throw cause;
    fail(code, cause);
  }
}

async function readSite(path: string, configurationReader: unknown, providerMoon: RepositoryCodec): Promise<Site> {
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => fail('InstalledGitHubConfigurationReaderUnavailable')) as Configuration;
  const site = await readJson(path, 'InvalidInstalledGitHubSite', readers.readJson as Read) as SiteInput | null | undefined;
  const {version, caPath, ...rest} = (site ?? {}) as SiteInput;
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
  // Admit Text before the typed, allocation-free Catalog predicate. The old
  // REST helper's RegExp coercion is not a configuration or provider contract.
  if (typeof rest.owner !== 'string' || typeof rest.repo !== 'string') {
    fail('InvalidGitHubRepository');
  }
  if (typeof providerMoon?.githubRepositoryAccessValid !== 'function') {
    fail('InstalledGitHubRepositoryValidationUnavailable');
  }
  const valid = providerMoon.githubRepositoryAccessValid(rest.owner, rest.repo);
  if (valid !== true) {
    if (valid !== false) fail('InstalledGitHubRepositoryValidationUnavailable');
    fail('InvalidGitHubRepository');
  }
  if (caPath !== undefined && configurationReader !== undefined && readers.readOriginalBytes === undefined) {
    fail('InstalledGitHubConfigurationReaderUnavailable');
  }
  return Object.freeze({...site,
    ca: caPath === undefined ? undefined : await (configurationReader === undefined
      ? readFile(caPath) : readers.readOriginalBytes!(caPath)) as SiteOptions['ca']}) as Site;
}

// The token is read from the environment variable the Site profile names;
// the profile never holds a token value.
const environmentSecret = (name: string) => async () => {
  const value = process.env[name];
  if (!text(value)) fail('RemoteCredentialSecretUnavailable');
  return value;
};

// The parts of this installation's identity: the Host profile with its
// account configuration as a document, the Site profile and the publication.
export async function installedGitHubSourceIdentityParts(profile: Readonly<{accountConfigurationWire: string}>,
  providerProfile: unknown, read: Read) {
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
export async function readGitHubPublication(checkedProfile: Profile, site: Site, read: Read = readSourceProfileJson): Promise<Publication> {
  let publication: Publication | undefined;
  try {
    publication = await read(checkedProfile.publicationPath,
      {maxBytes: 1024 * 1024}) as Publication;
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

async function restore(moon: Common, connectorId: string, expectedCatalogCid: string | undefined,
  sourceInitialization?: object, readOriginalText: ReadText = path => readFile(path, 'utf8')): Promise<Prepared> {
  const constructor = sourceInitialization === undefined ? undefined
    : Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareDeclaration');
  if (sourceInitialization !== undefined && (!constructor || !Object.hasOwn(constructor, 'value') ||
      typeof constructor.value !== 'function')) fail('InstalledGitHubInitializationUnavailable');
  const views = await readOriginalText(viewsUrl);
  if (constructor !== undefined) return Reflect.apply(constructor.value, sourceInitialization, [views, expectedCatalogCid]) as Prepared;
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    connectorId, registration, revision, views, expectedCatalogCid));
  const declared = JSON.parse(
    moon.clientProgramRowSourceDeclarationJson(declaration)) as Declared | null;
  if (declared === null) fail('InvalidGitHubDeclaration');
  return {declaration, declared};
}

async function openSite(checkedProfile: Profile, site: Site, {root, principalId, moon,
  runtimeBundleCid, resolveSecret, publication, installation, sourceInitialization}: OpenOptions,
  installationServices?: object): Promise<Opened> {
  // The authorization tuple names the access target (API host and
  // owner/repo); the stable repository id is pinned by the physical binding
  // an approval covers and by the installation identity.
  const connection = `github:${new URL(site.apiOrigin).host}/${site.owner}/${site.repo}`;
  const configuration = {
    profile: Object.freeze({...site, resourceOrigin: site.apiOrigin}),
    resolveSecret: resolveSecret ?? environmentSecret(site.tokenEnvironment),
    ca: site.ca, responseHeaders: installation?.responseHeaders ?? [],
    admitsApprovalTarget: ((binding: Binding, resource: string) => publication !== undefined &&
      binding?.version === TARGET_VERSION &&
      binding.api_origin === site.apiOrigin &&
      binding.repository_id === publication.repository.id &&
      binding.repository_node_id === publication.repository.node_id &&
      binding.owner === site.owner && binding.repo === site.repo &&
      binding.catalog_cid === publication.catalogCid &&
      binding.resource === resource && Array.isArray(binding.fields)) as NonNullable<SiteOptions['admitsApprovalTarget']>};
  if (installationServices !== undefined) {
    const open = Object.getOwnPropertyDescriptor(installationServices, 'openRowSite');
    if (!open || !Object.hasOwn(open, 'value') || typeof open.value !== 'function') {
      fail('InvalidInstalledEffectSiteServices');
    }
    const opened = await Reflect.apply(open.value, installationServices, [{
      installation, accountConfiguration: checkedProfile.accountConfigurationWire,
      ...(sourceInitialization === undefined ? {} : {sourceInitialization}),
      connection, ...configuration}]) as Omit<Opened, 'connection'>;
    return {...opened, connection};
  }
  const authorization = await installRowSourceAuthorization({
    accountConfiguration: checkedProfile.accountConfigurationWire,
    principalId, root, connectorRegistration: registration});
  const credentialSite = await openRowSourceCredentialSite({
    ...configuration, principalId, authorization, connection,
    connectorRegistration: registration, connectorRevision: revision,
    runtimeBundleCid, commonMoon: moon}) as ActualSite;
  return {authorization, site: credentialSite, connection};
}

// The explicit publication step: observe the repository's stable identity
// under the installed read decision and the credential resource, and record
// it with the declaration's Catalog CID. A Host start never runs it.
export async function publishInstalledGitHubSource(profile: unknown, options: PublishOptions) {
  return publishGitHubRepository(checkInstalledGitHubSourceProfile(profile),
    options);
}

// The publication step of a checked GitHub source or Effect profile: both
// bind the same repository the same way.
export async function publishGitHubRepository(checkedProfile: Profile, {root,
  principalId, moon, providerMoon, runtimeBundleCid, resolveSecret, signal,
  installation}: PublishOptions): Promise<Publication> {
  const site = await readSite(checkedProfile.siteProfilePath, undefined, providerMoon);
  const {declared} = await restore(moon, checkedProfile.connectorId, undefined);
  const opened = await openSite(checkedProfile, site, {root, principalId,
    moon, runtimeBundleCid, resolveSecret, installation});
  let primaryFailure: unknown;
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
      maxRequestBytes: 16_384, maxResponseBytes: 1_000_000, signal}) as HttpResponse;
    if (!response.accepted || response.statusCode !== 200) {
      fail('GitHubRepositoryUnavailable');
    }
    const observed = JSON.parse(providerMoon.githubRepositoryResponseJson(
      response.body, 1_000_000)) as RepositoryReply;
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
    const publication: Publication = {version: PUBLICATION_VERSION,
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
export async function loadInstalledGitHubSource(profile: unknown, {root, principalId,
  moon, providerMoon, baseEnvironmentWire, runtimeBundleCid, resolveSecret,
  installation, construction}: InstallOptions) {
  if (typeof construction?.prepareDeclaration !== 'function' ||
      typeof construction.openRowSite !== 'function' ||
      typeof construction.createRowSource !== 'function' ||
      typeof construction.sourceReaderImplementation !== 'function' ||
      typeof construction.createSourceReader !== 'function' ||
      typeof construction.configurationReader?.readOriginalText !== 'function') {
    fail('InstalledGitHubConstructionUnavailable');
  }
  const readers = construction.configurationReader;
  const checkedProfile = checkInstalledGitHubSourceProfile(profile);
  const site = await readSite(checkedProfile.siteProfilePath, readers, providerMoon);
  const publication = await readGitHubPublication(checkedProfile, site, readers.readJson);
  const viewInput = await readers.readOriginalText(viewsUrl);
  construction.prepareDeclaration(viewInput, publication.catalogCid);
  const connection = `github:${new URL(site.apiOrigin).host}/${site.owner}/${site.repo}`;
  {
    const physicalTarget = (resource: string, fields: readonly string[]) => Object.freeze({
      version: TARGET_VERSION, api_origin: site.apiOrigin,
      repository_id: publication.repository.id,
      repository_node_id: publication.repository.node_id,
      owner: site.owner, repo: site.repo,
      catalog_cid: publication.catalogCid, resource,
      fields: Object.freeze([...fields])});
    const policyMethod = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledSourceReaderPolicy')?.value;
    if (typeof policyMethod !== 'function') fail('InstalledSourceReaderRuntimeUnavailable');
    const policy = Reflect.apply(policyMethod,moon,[]);
    if (!Array.isArray(policy) || policy.length !== 3 || policy.some(value =>
      !Number.isSafeInteger(value) || value < 1 || value > 2147483647)) fail('InstalledSourceReaderPolicyUnavailable');
    // Original binding/target strings, not observed rows or a capacity grant.
    const bindingUnits = site.apiOrigin.length + site.owner.length + site.repo.length +
      publication.repository.node_id.length + String(publication.repository.id).length +
      publication.catalogCid.length + TARGET_VERSION.length;
    const readerLimits = Object.freeze({maxResponseBytes:readLimits.maxBytes,
      maxTotalResponseBytes:readLimits.maxPages * readLimits.maxBytes,
      maxNodes:readLimits.maxNodes,maxDepth:readLimits.maxDepth,
      maxRows:readLimits.maxRows,maxTotalRows:readLimits.maxRows,
      maxPages:readLimits.maxPages,pageSize:readLimits.perPage,
      maxCursorBytes:3 * 1024,maxIdentityBytes:readLimits.maxBytes,
      maxTargetBytes:1024 + 6 * (bindingUnits + viewInput.length),
      maxValueNodes:readLimits.maxNodes,maxValueTextBytes:readLimits.maxBytes,
      maxRowsWireBytes:rowLimits.maxPageBytes,maxRowsWireNodes:readLimits.maxNodes,
      maxRowsWireDepth:readLimits.maxDepth,maxSecretBytes:policy[0]});
    const nativeCapacity = Object.getOwnPropertyDescriptor(providerMoon, 'githubSourceReadPrefixConstructionCapacity')?.value;
    const readerCapacity = Object.getOwnPropertyDescriptor(moon, 'clientProgramInstalledNativeSourceReaderCapacity')?.value;
    if (typeof nativeCapacity !== 'function' || typeof readerCapacity !== 'function') {
      fail('InstalledSourceReaderRuntimeUnavailable');
    }
    const originalBounds = Object.freeze((['maxBytes','maxNodes','maxDepth','maxRows','maxPages','maxSubjects'] as const)
      .map(name => readLimits[name]));
    const readerBounds = Object.freeze(installedJsonSourceReaderLimitNames.map(name => readerLimits[name]));
    const responseCapacity = (bytes: number, responses = 0) => {
      const domain = Reflect.apply(nativeCapacity,providerMoon,[...originalBounds,bytes,httpsCredentialResponseHeaderByteLimit,responses]);
      const capacity = Reflect.apply(readerCapacity,moon,[readerBounds,policy[2],policy[0],domain]);
      if (capacity === undefined || capacity === null) fail('InstalledSourceReaderCapacityUnavailable');
      return capacity;
    };
    const implementation = construction.sourceReaderImplementation({limits:readerLimits,columnCount:policy[2],
      readSequenceConstruction:Object.freeze({capacity:responseCapacity(0),originalLimits:readLimits,
        maxRequestBytes:readLimits.maxRequestBytes,
        sequence:Object.freeze({operation:GITHUB_GRAPHQL_READ_OPERATION,maxUses:readLimits.maxPages,
          children:Object.freeze([])})})});
    // The same credential issuer captures this implementation's limits when
    // its Site is constructed; later registration cannot retrofit that owner.
    const opened = await construction.openRowSite({
      accountConfiguration: checkedProfile.accountConfigurationWire, connection,
      runAcquisitionLimits: implementation.runAcquisitionLimits,
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
    const repository = Object.freeze({nodeId:publication.repository.node_id,
      databaseId:publication.repository.id,nameWithOwner:`${site.owner}/${site.repo}`});
    const providerReader = construction.createSourceReader({implementation,
      prepareReadSequence(input,retireProjection) {
        return prepareGitHubSourceReadSequence({moon:providerMoon,site:opened.site,repository,
          preparedRead:input.preparedRead,originalAuthorization:input.originalAuthorization,
          limits:readLimits,responseCapacity,retireProjection});
      }});
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
      providerReader,
      prepareRead: async ({resource,nonce,runInvocationCid,dispatchRequestCid,signal}) => {
        if (!['issues','pull_requests','issue_comments'].includes(resource)) fail('UndeclaredGitHubResource');
        return Object.freeze({resource,nonce,runInvocationCid,dispatchRequestCid,signal});
      }});
  }
}
