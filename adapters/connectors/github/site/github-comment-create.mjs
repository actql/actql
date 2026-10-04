// GitHub's Issue comment creation at the Site: one POST through the typed
// exchange and the credential resource, and the provider's classification of
// its observed reply. Comment creation has no idempotency key and notifies
// watchers, so the common Effect owner's durable claim (one `execute` per
// claimed row, never again after the claim) is the only send-once guarantee.
// This module never resends, never infers success from content, and never
// reads a comment back to decide an unknown send.
import {createHash} from 'node:crypto';
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {githubIssueListPath} from './github-issue-read.mjs';

export const GITHUB_COMMENT_CREATE_OPERATION = 'github:issues:comment:create';
const REQUEST_VERSION = 'actql-github-comment-create-request/0.1';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};
const count = value => Number.isSafeInteger(value) && value > 0;

// The exact request one comment row sends, and the identity of its exact
// bytes for the Effect Ledger claim. Nothing in it is secret.
export function prepareGitHubCommentRequest({origin, owner, repo,
  issueNumber, body, maxBodyBytes = 65_536}) {
  if (typeof origin !== 'string' || !origin.startsWith('https://') ||
      !count(issueNumber) || typeof body !== 'string' || body.length === 0 ||
      Buffer.byteLength(body) > maxBodyBytes) {
    fail('InvalidGitHubCommentRequest');
  }
  const path = `${githubIssueListPath(owner, repo)}/${issueNumber}/comments`;
  const wire = JSON.stringify({body});
  return Object.freeze({version: REQUEST_VERSION, origin, method: 'POST',
    path, body: wire,
    requestCid: exactRequestCid([REQUEST_VERSION, origin, 'POST', path, wire])});
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

// Send exactly once. The caller is the common Effect owner's `execute`; it
// must not call this outside a fresh durable claim.
export async function sendGitHubIssueComment({moon, request, authorization,
  credential, limits, callResource = callHttpsCredentialResource, signal}) {
  if (!moon || typeof moon.githubCommentOutcomeJson !== 'function' ||
      !request?.requestCid || !limits || !count(limits.maxRequestBytes) ||
      !count(limits.maxResponseBytes) ||
      authorization?.scope?.resourceOrigin !== request.origin) {
    fail('InvalidGitHubCommentSend');
  }
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({
    authorization, credential, callResource,
    operation: GITHUB_COMMENT_CREATE_OPERATION, method: 'POST',
    path: request.path, body: request.body,
    headers: JSON.parse(moon.githubRequestHeadersJson()),
    responseHeaders: JSON.parse(moon.githubResponseHeadersJson()),
    maxRequestBytes: limits.maxRequestBytes,
    maxResponseBytes: limits.maxResponseBytes, signal,
  });
  return Object.freeze({
    observation: Object.freeze({useCid: response.useCid,
      statusCode: response.statusCode, body: response.body}),
    headers: response.headers,
  });
}

// Classify one observed reply. `headers` is the live declared observation;
// a reply recovered from the Ledger has only its status and bytes, so its
// headers are absent and a 403 cannot be told apart from a rate limit: it
// stays unknown rather than becoming a refusal.
export function projectGitHubCommentObservation({moon, observation, headers,
  maxResponseBytes}) {
  if (!moon || !observation || !Number.isSafeInteger(observation.statusCode) ||
      !(observation.body instanceof Uint8Array) || !count(maxResponseBytes)) {
    fail('InvalidGitHubCommentObservation');
  }
  if (headers === undefined && observation.statusCode === 403) {
    return Object.freeze({kind: 'provider-response', observation});
  }
  const pairs = headers ?? [];
  const outcome = JSON.parse(moon.githubCommentOutcomeJson(
    observation.statusCode, pairs.map(entry => entry[0]),
    pairs.map(entry => entry[1]), observation.body, maxResponseBytes));
  if (outcome.outcome === 'Created') {
    return Object.freeze({kind: 'typed-success-response', observation,
      result: Object.freeze({commentId: outcome.id, nodeId: outcome.nodeId})});
  }
  if (outcome.outcome === 'Refused') {
    return Object.freeze({kind: 'typed-failure-response', observation,
      status: outcome.status});
  }
  return Object.freeze({kind: observation.statusCode >= 200 &&
    observation.statusCode < 300 ? 'unclassified-response'
    : 'provider-response', observation});
}
