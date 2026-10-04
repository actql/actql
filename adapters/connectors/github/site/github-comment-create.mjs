// GitHub's Issue comment creation at the Site, addressed by the Issue's
// global node ID. Two fixed GraphQL documents are sent through the typed
// exchange and the credential resource: a read-only subject check, then the
// `addComment` mutation. The provider MoonBit decides every meaning.
//
// Comment creation has no idempotency key and notifies watchers, so the
// common Effect owner's durable claim (one `execute` per claimed row, never
// again after the claim) is the only send-once guarantee. This module never
// resends, never infers success from content, and never reads a comment back
// to decide an unknown send. The subject check refuses a pull request,
// another repository or an unreadable node before the send; it does not
// exclude a move between the check and the send.
import {createHash} from 'node:crypto';
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

// Check, under a read authorization, that the subject is an Issue of the
// published repository `{nodeId, databaseId, nameWithOwner}`. Returns the
// Issue's `{nodeId, number}` or throws a coded refusal; nothing is sent.
export async function checkGitHubCommentSubject({moon, subjectId, repository,
  authorization, credential, limits,
  callResource = callHttpsCredentialResource, signal}) {
  if (!moon || typeof moon.githubCommentSubjectJson !== 'function' ||
      typeof repository?.nodeId !== 'string' ||
      !Number.isSafeInteger(repository.databaseId) ||
      typeof repository.nameWithOwner !== 'string') {
    fail('InvalidGitHubCommentSubjectCheck');
  }
  const owned = checkLimits(limits);
  const request = JSON.parse(moon.githubCommentSubjectRequestJson(subjectId));
  if (request.refused !== undefined) {
    fail('InvalidGitHubCommentRequest', {refusal: request.refused});
  }
  signal?.throwIfAborted();
  const response = await exchange({moon, authorization, credential,
    callResource, operation: GITHUB_GRAPHQL_READ_OPERATION,
    body: request.body, limits: owned, signal});
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
    owned.maxResponseBytes, owned.maxNodes, owned.maxDepth, subjectId,
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
