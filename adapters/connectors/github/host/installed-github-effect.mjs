// GitHub's Effect installation for the standard installed Host, entered in
// the installed connector table by `src/connectors/github/host-bundle.json`
// (`effect`). Everything common (the Mapping generated from
// `src/connectors/github/writes.json`, the Check Environment, capture, the
// Preview, approval, the Effect Ledger, apply, recovery and publication) is
// the Host's provider-neutral installed row Effect; this module supplies
// GitHub's comment driver over the same Site, repository publication and
// declaration as the GitHub source.
//
// A comment row names its Issue by global node ID. Before the Preview and
// again before the approved Set is applied, every row's subject must be an
// Issue of the published repository under a current read decision; a pull
// request, another repository's Issue or an unresolvable node is refused
// before any comment is sent. That check does not exclude a move between it
// and the send. A send is never repeated: a lost or unclassified reply stays
// unknown.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {retainInstalledHostInitializationFailure} from
  '../../../host-node/installed-host-cleanup.mjs';
import {createInstalledRowEffect} from
  '../../../host-node/installed-row-effect.mjs';
import {captureInstalledStandardCreateLimits} from
  '../../../host-node/installed-effect-plan.mjs';
import {rowSourceCheckEnvironment, rowSourceMapping} from
  '../../../host-node/installed-row-source.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {GITHUB_COMMENT_CREATE_OPERATION, prepareGitHubCommentSubjectRequest,
  projectGitHubCommentSubjectResponse, prepareGitHubCommentLogicalRequest,
  GITHUB_COMMENT_STAMP_RECIPE, finalizeGitHubCommentRequest, restoreGitHubCommentRequest,
  prepareGitHubCommentConfirmationRequest, projectGitHubCommentConfirmation,
  projectGitHubCommentObservation} from '../site/github-comment-create.mjs';
import {GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION} from
  '../site/github-issue-graphql-read.mjs';
import {openGitHubSite, publishGitHubRepository, readGitHubPublication,
  readGitHubSite, restoreGitHubDeclaration} from
  './installed-github-source.mjs';

export const INSTALLED_GITHUB_EFFECT_VERSION =
  'actql-installed-github-effect/0.1';
const registration = 'github';
const revision = 'github/0.1';
const writesUrl = new URL('../../../../src/connectors/github/writes.json',
  import.meta.url);
const profileKeys = ['accountConfigurationWire', 'connectorId',
  'publicationPath', 'siteProfilePath', 'version', 'writes'];

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const absolute = value => text(value) && isAbsolute(value);
const sameKeys = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const cid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;

function checkWrite(write) {
  if (!sameKeys(write, ['resource', 'sources']) || !text(write.resource) ||
      !Array.isArray(write.sources) || write.sources.length === 0 ||
      write.sources.length > 16 ||
      !write.sources.every(source => sameKeys(source,
        ['field', 'null_behavior', 'target']) && text(source.target) &&
        text(source.field) && text(source.null_behavior))) {
    fail('InvalidInstalledEffectProfile');
  }
  return Object.freeze({resource: write.resource,
    sources: Object.freeze(write.sources.map(source =>
      Object.freeze({...source})))});
}

// Check the Host profile's shape before anything is read or installed. It
// holds no secret value: the Site profile names the token's environment
// variable.
export function checkInstalledGitHubEffectProfile(profile) {
  if (!sameKeys(profile, profileKeys) ||
      profile.version !== INSTALLED_GITHUB_EFFECT_VERSION ||
      !absolute(profile.siteProfilePath) || !absolute(profile.publicationPath) ||
      !text(profile.connectorId) || !text(profile.accountConfigurationWire) ||
      !Array.isArray(profile.writes) || profile.writes.length === 0 ||
      profile.writes.length > 16) {
    fail('InvalidInstalledEffectProfile');
  }
  const writes = profile.writes.map(checkWrite);
  if (new Set(writes.map(write => canonicalJson(write))).size !==
      writes.length) {
    fail('InvalidInstalledEffectProfile');
  }
  return Object.freeze({...profile, writes: Object.freeze(writes)});
}

// The parts of this installation's identity: the Host profile with its
// account configuration as a document, the Site profile and the publication.
export async function installedGitHubEffectIdentityParts(profile, read) {
  const checked = checkInstalledGitHubEffectProfile(profile);
  return [
    {...profile, accountConfigurationWire: JSON.parse(
      profile.accountConfigurationWire)},
    await read(checked.siteProfilePath, {maxBytes: 1024 * 1024}),
    await read(checked.publicationPath, {maxBytes: 1024 * 1024}),
  ];
}

// The installed writes' Mappings, generated by the common runtime from the
// declaration and GitHub's declared writes.
async function mappingsOf(moon, declaration, writes, sourceInitialization,
  readOriginalText = path => readFile(path, 'utf8')) {
  const constructor = sourceInitialization === undefined ? undefined
    : Object.getOwnPropertyDescriptor(sourceInitialization, 'prepareMappings');
  if (sourceInitialization !== undefined && (!constructor || !Object.hasOwn(constructor, 'value') ||
      typeof constructor.value !== 'function')) fail('InstalledGitHubInitializationUnavailable');
  const writesJson = await readOriginalText(writesUrl);
  if (constructor !== undefined) return Reflect.apply(constructor.value, sourceInitialization, [writesJson, writes]);
  return {mappings: writes.map(write => {
    const mapping = rowSourceMapping(moon, declaration, writesJson, write.resource, write.sources);
    return Object.freeze({...mapping, resource: mapping.target.split('/').at(-1)});
  })};
}

// The explicit publication step: bind the repository exactly as the GitHub
// source does, and report the Mappings a Program targets.
export async function publishInstalledGitHubEffect(profile, options) {
  const checked = checkInstalledGitHubEffectProfile(profile);
  const publication = await publishGitHubRepository(checked, options);
  const {declaration} = await restoreGitHubDeclaration(options.moon,
    checked.connectorId, publication.catalogCid);
  const {mappings} = await mappingsOf(options.moon, declaration,
    checked.writes);
  return Object.freeze({...publication,
    mappings: Object.freeze(mappings.map(mapping => Object.freeze({
      resource: mapping.target.split('/').at(-1), kind: 'create',
      target: mapping.target, mappingRef: mapping.mappingRef,
      mappingCid: mapping.mappingCid})))});
}

// The comment value of one row: exactly the Issue node ID and the body.
function commentValue(resource, value) {
  if (resource !== 'issue_comments' ||
      !sameKeys(value, ['body', 'subject_id']) ||
      typeof value.subject_id !== 'string' || typeof value.body !== 'string') {
    fail('GitHubCommentValueRefused');
  }
  return value;
}

// A Created response is provider evidence pending actual scoped confirmation,
// not a terminal Effect outcome or an asynchronous OperationRef.
function commentOutcome(projected) {
  if (projected.kind === 'typed-success-response') {
    return Object.freeze({kind: 'provider-response', observation: projected.observation,
      providerEvidence: Object.freeze({kind: 'CreatedComment',
        comment_id: projected.result.commentId, node_id: projected.result.nodeId})});
  }
  if (projected.kind === 'typed-failure-response') {
    return {kind: projected.kind, outcome: {state: 'failed', error: {
      code: projected.errorType === undefined ? 'GitHubCommentRefused'
        : 'GitHubCommentRejected',
      message: 'GitHub did not create the comment',
      details: {http_status: projected.status,
        ...(projected.errorType === undefined ? {}
          : {type: projected.errorType})}}}};
  }
  return {kind: projected.kind};
}

// Load the installed GitHub Effect: restore its declaration, Mappings and
// repository binding without provider I/O.
export async function loadInstalledGitHubEffect(profile, {root, principalId,
  moon, providerMoon, baseEnvironmentWire, runtimeBundleCid, resolveSecret,
  ledgerRoot, installation, installationServices, configurationReader, sourceInitialization}) {
  const checked = checkInstalledGitHubEffectProfile(profile);
  if (!text(baseEnvironmentWire) || !absolute(ledgerRoot)) {
    fail('InvalidInstalledEffectOptions');
  }
  const commentLimits = captureInstalledStandardCreateLimits(providerMoon);
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => fail('InstalledGitHubConfigurationReaderUnavailable'));
  if (configurationReader !== undefined && readers.readOriginalText === undefined) {
    fail('InstalledGitHubConfigurationReaderUnavailable');
  }
  const site = await readGitHubSite(checked.siteProfilePath, configurationReader);
  const publication = await readGitHubPublication(checked, site, readers.readJson);
  const {declaration, declared} = await restoreGitHubDeclaration(moon,
    checked.connectorId, publication.catalogCid, sourceInitialization, readers.readOriginalText);
  const prepared = await mappingsOf(moon, declaration, checked.writes, sourceInitialization, readers.readOriginalText);
  const {mappings} = prepared;
  const environment = sourceInitialization === undefined ? rowSourceCheckEnvironment(baseEnvironmentWire,
    declared, mappings.map(mapping => mapping.body)) : prepared.environment;
  const opened = await openGitHubSite(checked, site, {root, principalId,
    moon, runtimeBundleCid, resolveSecret, publication, installation, sourceInitialization}, installationServices);
  try {
    const repository = Object.freeze({nodeId: publication.repository.node_id,
      databaseId: publication.repository.id,
      nameWithOwner: `${site.owner}/${site.repo}`});
    const boundaryCid = cid({version: 'actql-github-comment-boundary/0.1',
      api_origin: site.apiOrigin, repository_id: publication.repository.id,
      repository_node_id: publication.repository.node_id});
    return await createInstalledRowEffect({moon, providerMoon,
      mappings, declaration, declared, environment, sourceInitialization,
      environmentWire: environment.wire, connectorId: checked.connectorId,
      connectorRegistration: registration, connectorRevision: revision,
      connection: opened.connection, site: opened.site,
      authorization: opened.authorization, runtimeBundleCid,
      bindingCid: cid({version: 'actql-installed-github-effect-binding/0.1',
        contextCid: opened.authorization.context.contextCid,
        apiOrigin: site.apiOrigin, repository: publication.repository,
        owner: site.owner, repo: site.repo, siteKey: site.siteKey,
        siteGeneration: site.siteGeneration, namespaceId: site.namespaceId,
        environment: site.environment,
        credentialAuthorityId: site.credentialAuthorityId,
        credentialKeyId: site.credentialKeyId}),
      ledgerRoot,
      installation,
      write: {
        kind: 'create', operation: GITHUB_COMMENT_CREATE_OPERATION,
        resourceKind: 'issue_comment', boundaryCid,
        http: {origin: site.apiOrigin, method: 'POST', path: GITHUB_GRAPHQL_PATH,
          headers: JSON.parse(providerMoon.githubRequestHeadersJson()),
          responseHeaders: JSON.parse(providerMoon.githubResponseHeadersJson()),
          maxRequestBytes: commentLimits.maxRequestBytes, maxResponseBytes: commentLimits.maxResponseBytes},
        request({resource, value}) {
          if (typeof providerMoon.githubCommentOutcomeJson !== 'function') fail('InvalidGitHubCommentSend');
          const comment = commentValue(resource, value);
          return prepareGitHubCommentLogicalRequest({
            origin: site.apiOrigin, subjectId: comment.subject_id,
            body: comment.body});
        },
        finalization: {recipe: GITHUB_COMMENT_STAMP_RECIPE,
          finalize: ({request, requestTag}) => finalizeGitHubCommentRequest({moon: providerMoon, request, requestTag}),
          restore: ({request, logical, requestTag}) => restoreGitHubCommentRequest({moon: providerMoon,
            request, logical, requestTag, limits: commentLimits})},
        confirmation: {resource: 'issue_comments', operation: GITHUB_GRAPHQL_READ_OPERATION,
          http: {origin: site.apiOrigin, method: 'POST', path: GITHUB_GRAPHQL_PATH,
            headers: JSON.parse(providerMoon.githubRequestHeadersJson()),
            responseHeaders: JSON.parse(providerMoon.githubResponseHeadersJson()),
            maxRequestBytes: commentLimits.maxRequestBytes, maxResponseBytes: commentLimits.maxResponseBytes},
          body: ({providerEvidence}) => prepareGitHubCommentConfirmationRequest({moon: providerMoon, providerEvidence}),
          project: ({request, providerEvidence, observation, accepted}) => projectGitHubCommentConfirmation({
            moon: providerMoon, request, providerEvidence, repository, limits: commentLimits, observation, accepted})},
        check: {resource: 'issues', operation: GITHUB_GRAPHQL_READ_OPERATION,
          http: {origin: site.apiOrigin, method: 'POST', path: GITHUB_GRAPHQL_PATH,
            headers: JSON.parse(providerMoon.githubRequestHeadersJson()),
            responseHeaders: JSON.parse(providerMoon.githubResponseHeadersJson()),
            maxRequestBytes: commentLimits.maxRequestBytes, maxResponseBytes: commentLimits.maxResponseBytes},
          body: ({request}) => prepareGitHubCommentSubjectRequest({moon: providerMoon,
            subjectId: request.subjectId, repository, limits: commentLimits}),
          project({request, observation, headers, accepted}) {
            projectGitHubCommentSubjectResponse({moon: providerMoon,
              subjectId: request.subjectId, repository, limits: commentLimits,
              response: {accepted, ...observation, headers}});
          }},
        classify: ({request, observation, headers}) => commentOutcome(
          projectGitHubCommentObservation({moon: providerMoon, observation,
            headers, limits: commentLimits, subjectId: request.subjectId})),
      }});
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause,
      {installedEffect: opened.site});
  }
}
