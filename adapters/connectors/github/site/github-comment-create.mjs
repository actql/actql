// GitHub's Issue comment creation at the Site, addressed by the Issue's
// global node ID. Fixed GraphQL documents pass through the typed exchange
// and credential resource: subject check, `addComment`, then confirmation
// of its original Created node. The provider MoonBit decides every meaning.
//
// Comment creation has no idempotency key and notifies watchers, so the
// common Effect owner's durable claim (one `execute` per claimed row, never
// again after the claim) is the only send-once guarantee. This module never
// resends, never infers success from content, and never reads a comment back
// to decide an unknown send. The subject check refuses a pull request,
// another repository or an unreadable node before the send; it does not
// exclude a move between the check and the send.
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {refusedEffectPreparation} from
  '../../../host-common/effect-preparation-result.mjs';
import {GITHUB_GRAPHQL_PATH, GITHUB_GRAPHQL_READ_OPERATION} from
  './github-issue-graphql-read.mjs';

export const GITHUB_COMMENT_CREATE_OPERATION = 'github:issues:comment:create';
const REQUEST_VERSION = 'actql-github-comment-create-request/0.1';

// Preview binds this recipe and the logical body. The Host supplies the SAME
// Core-issued DispatchKey CID text only after that exact Preview is fixed.
export const GITHUB_COMMENT_STAMP_RECIPE = Object.freeze({
  separator: '\n\n', prefix: '<!-- actql:effect:', suffix: ' -->',
});

const fail = (code, details = {}) => {
  throw Object.assign(new Error(code), {code, ...details});
};
const count = value => Number.isSafeInteger(value) && value > 0;
const pairs = headers => [headers.map(entry => entry[0]),
  headers.map(entry => entry[1])];

// Refusals of a subject check and the stop each one is.
const subjectRefusals = Object.freeze({
  WrongType: 'GitHubCommentSubjectNotIssue',
  SubjectUnavailable: 'GitHubCommentSubjectUnavailable',
  ForeignSubject: 'GitHubCommentSubjectChanged',
  ForeignRepository: 'GitHubCommentForeignRepository',
  IdRepresentationChanged: 'GitHubRepositoryRepublishRequired',
  BindingChanged: 'GitHubRepositoryBindingChanged',
  RateLimited: 'GitHubRateLimited',
});

function checkLimits(limits) {
  if (!limits || !count(limits.maxRequestBytes) ||
      !count(limits.maxResponseBytes) || !count(limits.maxNodes) ||
      !count(limits.maxDepth)) {
    fail('InvalidGitHubCommentLimits');
  }
  return limits;
}

// The exact request one comment row sends, and the identity of its exact
// bytes for the Effect Ledger claim. Nothing in it is secret.
export function prepareGitHubCommentRequest({moon, origin, subjectId, body}) {
  if (!moon || typeof moon.githubAddCommentRequestJson !== 'function' ||
      typeof origin !== 'string' || !origin.startsWith('https://') ||
      typeof subjectId !== 'string' || typeof body !== 'string') {
    fail('InvalidGitHubCommentRequest');
  }
  const prepared = JSON.parse(moon.githubAddCommentRequestJson(subjectId,
    body));
  if (prepared.refused !== undefined) {
    fail('InvalidGitHubCommentRequest', {refusal: prepared.refused});
  }
  const path = GITHUB_GRAPHQL_PATH;
  return Object.freeze({version: REQUEST_VERSION, origin, method: 'POST',
    path, subjectId, body: prepared.body,
    requestCid: exactRequestCid([REQUEST_VERSION, origin, 'POST', path,
      prepared.body])});
}

// Logical DATA only: no physical request or request CID exists at this phase.
// In particular an empty logical body remains distinct from an absent body;
// the provider's physical body limits apply after the marker is inserted.
export function prepareGitHubCommentLogicalRequest({origin, subjectId, body}) {
  if (typeof origin !== 'string' || !origin.startsWith('https://') ||
      !origin.isWellFormed() || typeof subjectId !== 'string' ||
      subjectId.length === 0 || !subjectId.isWellFormed() ||
      typeof body !== 'string' || !body.isWellFormed()) {
    fail('InvalidGitHubCommentRequest');
  }
  return Object.freeze({version: REQUEST_VERSION, origin, method: 'POST',
    path: GITHUB_GRAPHQL_PATH, subjectId, logicalBody: body});
}

// The Host retains and validates the original logical carrier/key association.
// CID syntax here is DATA validation, not DispatchKey issuance or permission.
// This performs no send, claim, readback, retry or cold request preparation.
export function finalizeGitHubCommentRequest({moon, request, requestTag}) {
  const names = ['version', 'origin', 'method', 'path', 'subjectId', 'logicalBody'];
  if (request === null || typeof request !== 'object' || types.isProxy(request) ||
      typeof requestTag !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(requestTag)) {
    fail('InvalidGitHubCommentRequest');
  }
  const fields = Object.getOwnPropertyDescriptors(request);
  if (Reflect.ownKeys(fields).length !== names.length || names.some(name =>
    !Object.hasOwn(fields[name] ?? {}, 'value') || !fields[name].enumerable ||
    typeof fields[name].value !== 'string' || !fields[name].value.isWellFormed())) {
    fail('InvalidGitHubCommentRequest');
  }
  const original = Object.fromEntries(names.map(name => [name, fields[name].value]));
  if (original.version !== REQUEST_VERSION || original.method !== 'POST' ||
      original.path !== GITHUB_GRAPHQL_PATH || !original.origin.startsWith('https://') ||
      original.subjectId.length === 0) fail('InvalidGitHubCommentRequest');
  const body = original.logicalBody + GITHUB_COMMENT_STAMP_RECIPE.separator +
    GITHUB_COMMENT_STAMP_RECIPE.prefix + requestTag + GITHUB_COMMENT_STAMP_RECIPE.suffix;
  const physical = prepareGitHubCommentRequest({moon, origin: original.origin,
    subjectId: original.subjectId, body});
  return Object.freeze({...physical, logicalBody: original.logicalBody, requestTag});
}

function ownCommentLogicalRequest(request, code) {
  const names = ['version', 'origin', 'method', 'path', 'subjectId', 'logicalBody'];
  if (request === null || typeof request !== 'object' || types.isProxy(request)) {
    fail(code);
  }
  const fields = Object.getOwnPropertyDescriptors(request);
  if (Reflect.ownKeys(fields).length !== names.length || names.some(name =>
    !Object.hasOwn(fields[name] ?? {}, 'value') || !fields[name].enumerable ||
    typeof fields[name].value !== 'string' || !fields[name].value.isWellFormed())) {
    fail(code);
  }
  const original = Object.fromEntries(names.map(name => [name, fields[name].value]));
  if (original.version !== REQUEST_VERSION || original.method !== 'POST' ||
      original.path !== GITHUB_GRAPHQL_PATH || !original.origin.startsWith('https://') ||
      original.subjectId.length === 0) fail(code);
  return original;
}

// Restore the original physical wire only after independent original logical
// fields and DispatchKey tag have been selected. No mutation encoder, request
// preparation, replacement tag, credential or send is available here.
export function restoreGitHubCommentRequest({moon, request, logical, requestTag, limits}) {
  const names = ['version', 'origin', 'method', 'path', 'subjectId', 'body',
    'requestCid', 'logicalBody', 'requestTag'];
  if (request === null || typeof request !== 'object' || types.isProxy(request)) {
    fail('InvalidGitHubOriginalCommentRequest');
  }
  const fields = Object.getOwnPropertyDescriptors(request);
  if (Reflect.ownKeys(fields).length !== names.length || names.some(name =>
    !Object.hasOwn(fields[name] ?? {}, 'value') || !fields[name].enumerable ||
    typeof fields[name].value !== 'string' || !fields[name].value.isWellFormed())) {
    fail('InvalidGitHubOriginalCommentRequest');
  }
  const original = Object.fromEntries(names.map(name => [name, fields[name].value]));
  const expected = ownCommentLogicalRequest(logical, 'InvalidGitHubOriginalCommentRequest');
  if (original.version !== expected.version || original.origin !== expected.origin ||
      original.method !== expected.method || original.path !== expected.path ||
      original.subjectId !== expected.subjectId || original.logicalBody !== expected.logicalBody ||
      typeof requestTag !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(requestTag) ||
      original.requestTag !== requestTag || typeof moon?.githubOriginalMarkedCommentRequestJson !== 'function') {
    fail('InvalidGitHubOriginalCommentRequest');
  }
  const owned = checkLimits(limits);
  if (Buffer.byteLength(original.body) > owned.maxRequestBytes ||
      original.requestCid !== exactRequestCid([REQUEST_VERSION, original.origin,
        original.method, original.path, original.body])) {
    fail('InvalidGitHubOriginalCommentRequest');
  }
  const admitted = JSON.parse(moon.githubOriginalMarkedCommentRequestJson(
    Buffer.from(original.body, 'utf8'), owned.maxRequestBytes,
    owned.maxNodes, owned.maxDepth, expected.subjectId, expected.logicalBody, requestTag));
  if (admitted.refused !== undefined || admitted.original?.subject_id !== expected.subjectId) {
    fail('InvalidGitHubOriginalCommentRequest');
  }
  return Object.freeze(request);
}

// Confirmation is an independently authorized read of the exact Created node,
// never another addComment or a repository-history search. The enclosing
// Effect owner retains the original claim, response and physical read child.
export function prepareGitHubCommentConfirmationRequest({moon, providerEvidence}) {
  if (providerEvidence?.kind !== 'CreatedComment' ||
      !Number.isSafeInteger(providerEvidence.comment_id) ||
      typeof providerEvidence.node_id !== 'string' ||
      typeof moon?.githubCommentConfirmationRequestJson !== 'function') {
    fail('InvalidGitHubCommentConfirmation');
  }
  const request = JSON.parse(moon.githubCommentConfirmationRequestJson(providerEvidence.node_id));
  if (request.refused !== undefined || typeof request.body !== 'string') {
    fail('InvalidGitHubCommentConfirmation');
  }
  return request.body;
}

// No successful mutation outcome follows from absence, a failed confirmation
// read or a copied marker. The provider codec must compare the complete
// original object/Issue/repository/logical body/tag before returning DATA.
export function projectGitHubCommentConfirmation({moon, request, providerEvidence,
  repository, limits, accepted, observation}) {
  const owned = checkLimits(limits);
  if (!accepted || observation?.statusCode !== 200) return undefined;
  if (!(observation.body instanceof Uint8Array) ||
      providerEvidence?.kind !== 'CreatedComment' ||
      typeof moon?.githubCommentConfirmationJson !== 'function') {
    fail('InvalidGitHubCommentConfirmation');
  }
  const projected = JSON.parse(moon.githubCommentConfirmationJson(observation.body,
    owned.maxResponseBytes, owned.maxNodes, owned.maxDepth,
    providerEvidence.comment_id, providerEvidence.node_id, request.subjectId,
    repository.nodeId, repository.databaseId, repository.nameWithOwner,
    request.logicalBody, request.requestTag));
  if (projected.refused !== undefined) return undefined;
  const comment = projected.comment;
  if (comment?.id !== providerEvidence.comment_id ||
      comment.node_id !== providerEvidence.node_id || comment.subject_id !== request.subjectId) {
    fail('ForeignGitHubCommentConfirmation');
  }
  return Object.freeze({kind: 'typed-success-response',
    outcome: Object.freeze({state: 'applied', action: 'created',
      result: Object.freeze({id: String(comment.id), node_id: comment.node_id})})});
}

// The identity of the exact request: each part's exact UTF-8 bytes, length
// prefixed, with no logical canonicalization. Two requests whose sent bytes
// differ in any way (NFC/NFD, CRLF/LF, escaping) never share a CID.
function exactRequestCid(parts) {
  const hash = createHash('sha256');
  for (const part of parts) {
    const bytes = Buffer.from(part, 'utf8');
    hash.update(`${bytes.byteLength}:`);
    hash.update(bytes);
  }
  return `sha256:${hash.digest('hex')}`;
}

async function exchange({moon, authorization, credential, callResource,
  operation, body, limits, signal}) {
  return invokeScopedCredentialOperation({
    authorization, credential, callResource, operation, method: 'POST',
    path: GITHUB_GRAPHQL_PATH, body,
    headers: JSON.parse(moon.githubRequestHeadersJson()),
    responseHeaders: JSON.parse(moon.githubResponseHeadersJson()),
    maxRequestBytes: limits.maxRequestBytes,
    maxResponseBytes: limits.maxResponseBytes, signal,
  });
}

// Pure standard declaration hooks. The body hook validates the SAME original
// repository/limits before native construction; the projection hook interprets
// only its already-accounted reply. Neither hook acquires a credential, sends,
// claims a write, creates a cleanup owner or returns an authorization result.
export function prepareGitHubCommentSubjectRequest({moon, subjectId, repository, limits}) {
  if (!moon || typeof moon.githubCommentSubjectJson !== 'function' ||
      typeof repository?.nodeId !== 'string' ||
      !Number.isSafeInteger(repository.databaseId) ||
      typeof repository.nameWithOwner !== 'string') {
    fail('InvalidGitHubCommentSubjectCheck');
  }
  checkLimits(limits);
  const request = JSON.parse(moon.githubCommentSubjectRequestJson(subjectId));
  if (request.refused !== undefined) {
    fail('InvalidGitHubCommentRequest', {refusal: request.refused});
  }
  return request.body;
}

export function projectGitHubCommentSubjectResponse({moon, subjectId, repository,
  response, limits}) {
  // A refusal decided from an observed reply is definitive for the row; a
  // rate limit or an unclassified failure is not.
  const refuse = (code, details) => {
    const error = Object.assign(new Error(code), {code, ...details});
    throw ['GitHubRateLimited', 'GitHubCommentSubjectRefused']
      .includes(code) ? error : refusedEffectPreparation(error);
  };
  if (!response.accepted || response.statusCode !== 200) {
    const [names, values] = pairs(response.headers);
    const failure = JSON.parse(moon.githubClassifyFailureJson(
      response.statusCode, names, values));
    if (failure.kind === 'RateLimited') {
      fail('GitHubRateLimited', {failure});
    }
    // Only a documented refusal (permission, not found, gone) is decided.
    if (!['PermissionDenied', 'NotFound', 'Gone'].includes(failure.kind)) {
      fail('GitHubCommentSubjectUnverified', {failure});
    }
    refuse('GitHubCommentSubjectRejected', {failure});
  }
  const projected = JSON.parse(moon.githubCommentSubjectJson(response.body,
    limits.maxResponseBytes, limits.maxNodes, limits.maxDepth, subjectId,
    repository.nodeId, repository.databaseId, repository.nameWithOwner));
  if (projected.refused !== undefined) {
    const {kind, type} = projected.refused;
    // A typed GraphQL NOT_FOUND or FORBIDDEN is an observed answer that the
    // node is not readable here; other error types are not decided.
    refuse(kind === 'Errors' && ['NOT_FOUND', 'FORBIDDEN'].includes(type)
      ? 'GitHubCommentSubjectUnavailable'
      : subjectRefusals[kind] ?? 'GitHubCommentSubjectRefused',
    {refusal: projected.refused});
  }
  return Object.freeze({nodeId: projected.subject.node_id,
    number: projected.subject.number});
}

// Compatibility for the existing direct Site caller. Normal installed CREATE
// uses the SAME pure hooks with its original shared Host HTTP child instead.
export async function checkGitHubCommentSubject({moon, subjectId, repository,
  authorization, credential, limits,
  callResource = callHttpsCredentialResource, signal}) {
  const body = prepareGitHubCommentSubjectRequest({moon, subjectId, repository, limits});
  signal?.throwIfAborted();
  const response = await exchange({moon, authorization, credential,
    callResource, operation: GITHUB_GRAPHQL_READ_OPERATION, body, limits, signal});
  return projectGitHubCommentSubjectResponse({moon, subjectId, repository, response, limits});
}

// Send exactly once. The caller is the common Effect owner's `execute`; it
// must not call this outside a fresh durable claim.
export async function sendGitHubIssueComment({moon, request, authorization,
  credential, limits, callResource = callHttpsCredentialResource, signal}) {
  if (!moon || typeof moon.githubCommentOutcomeJson !== 'function' ||
      !request?.requestCid || request.path !== GITHUB_GRAPHQL_PATH ||
      authorization?.scope?.resourceOrigin !== request.origin) {
    fail('InvalidGitHubCommentSend');
  }
  const owned = checkLimits(limits);
  signal?.throwIfAborted();
  const response = await exchange({moon, authorization, credential,
    callResource, operation: GITHUB_COMMENT_CREATE_OPERATION,
    body: request.body, limits: owned, signal});
  return Object.freeze({
    observation: Object.freeze({useCid: response.useCid,
      statusCode: response.statusCode, body: response.body}),
    headers: response.headers,
  });
}

// Classify one observed reply for the row's subject. `headers` is the live
// declared observation; a reply recovered from the Ledger has only its status
// and bytes, so its headers are absent and a 403 cannot be told apart from a
// rate limit: it stays unknown rather than becoming a refusal.
export function projectGitHubCommentObservation({moon, observation, headers,
  limits, subjectId}) {
  if (!moon || !observation || !Number.isSafeInteger(observation.statusCode) ||
      !(observation.body instanceof Uint8Array) ||
      typeof subjectId !== 'string') {
    fail('InvalidGitHubCommentObservation');
  }
  const owned = checkLimits(limits);
  if (headers === undefined && observation.statusCode === 403) {
    return Object.freeze({kind: 'provider-response', observation});
  }
  const [names, values] = pairs(headers ?? []);
  const outcome = JSON.parse(moon.githubCommentOutcomeJson(
    observation.statusCode, names, values, observation.body,
    owned.maxResponseBytes, owned.maxNodes, owned.maxDepth, subjectId));
  if (outcome.outcome === 'Created') {
    return Object.freeze({kind: 'typed-success-response', observation,
      result: Object.freeze({commentId: outcome.id, nodeId: outcome.nodeId})});
  }
  if (outcome.outcome === 'Refused') {
    return Object.freeze({kind: 'typed-failure-response', observation,
      status: outcome.status});
  }
  if (outcome.outcome === 'Rejected') {
    return Object.freeze({kind: 'typed-failure-response', observation,
      status: observation.statusCode, errorType: outcome.type});
  }
  return Object.freeze({kind: observation.statusCode >= 200 &&
    observation.statusCode < 300 ? 'unclassified-response'
    : 'provider-response', observation});
}
