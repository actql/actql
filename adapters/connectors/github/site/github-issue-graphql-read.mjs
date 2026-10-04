// GitHub's Issue read at the Site, bound to the published repository's
// global node ID. Every page is one POST of the provider's fixed read-only
// GraphQL document with typed variables; this driver never sends query text
// of its own and has no name-addressed fallback. The provider MoonBit decides
// every meaning (projection, identity, cursor, failure class); this driver
// sequences exchanges, takes the current read decision before every request,
// and stops on anything but a complete, exact page.
//
// Completion is never inferred: GraphQL `errors` (including a rate limit in
// an HTTP 200), incomplete data, a missing, repeated or non-advancing cursor,
// a page or row ceiling, a revoked decision or a transport failure stops the
// read with its accepted pages and the unfetched cursor kept. Raw header
// values are not retained. Nothing is retried.
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';

export const GITHUB_GRAPHQL_READ_OPERATION = 'github:graphql:read';
export const GITHUB_GRAPHQL_PATH = '/graphql';

const fail = (code, details = {}) => {
  throw Object.assign(new Error(code), {code, ...details});
};
const count = value => Number.isSafeInteger(value) && value > 0;
const pairs = headers => [headers.map(entry => entry[0]),
  headers.map(entry => entry[1])];

// Refusal kinds of a 200 response and the stop each one is.
const refusalCodes = Object.freeze({
  RateLimited: 'GitHubRateLimited',
  RepositoryUnavailable: 'GitHubRepositoryUnavailable',
  ForeignRepository: 'GitHubRepositoryIdentityChanged',
  IdRepresentationChanged: 'GitHubRepositoryRepublishRequired',
  BindingChanged: 'GitHubRepositoryBindingChanged',
});

function checkLimits(limits) {
  if (!limits || !count(limits.maxPages) || !count(limits.maxRows) ||
      !count(limits.maxBytes) || !count(limits.maxNodes) ||
      !count(limits.maxDepth) || !count(limits.perPage) ||
      limits.perPage > 100 || !count(limits.maxRequestBytes)) {
    fail('InvalidGitHubReadLimits');
  }
  return Object.freeze({...limits});
}

// Read the published repository's Issues. `repository` is the publication's
// `{nodeId, databaseId, nameWithOwner}`; `authorizationFor(index)` returns
// the credential authorization of the next request after rechecking the
// current read decision; `consumePage(rows, page)` receives each accepted
// page before the next request.
export async function readGitHubIssuesByNode({moon, repository,
  filters = {state: 'all', labels: []}, credential, callResource,
  authorizationFor, limits, consumePage, signal}) {
  if (!moon || typeof moon.githubIssuesRequestJson !== 'function' ||
      typeof authorizationFor !== 'function' || !credential ||
      typeof callResource !== 'function' ||
      typeof repository?.nodeId !== 'string' ||
      !Number.isSafeInteger(repository.databaseId) ||
      typeof repository.nameWithOwner !== 'string') {
    fail('InvalidGitHubRead');
  }
  const owned = checkLimits(limits);
  const labels = filters.labels ?? [];
  if (!['open', 'closed', 'all'].includes(filters.state) ||
      !Array.isArray(labels) ||
      labels.some(label => typeof label !== 'string') ||
      (filters.since !== undefined && typeof filters.since !== 'string')) {
    fail('InvalidGitHubReadFilters');
  }
  const headers = JSON.parse(moon.githubRequestHeadersJson());
  const responseHeaders = JSON.parse(moon.githubResponseHeadersJson());
  const accepted = [];
  const rows = [];
  const cursors = new Set();
  let after;
  let page = 1;
  let pending = true;
  const stopped = (code, details) => fail(code, {stopped: true,
    acceptedPages: Object.freeze([...accepted]),
    unfetched: pending ? Object.freeze({after, page}) : undefined,
    ...details});
  while (pending) {
    signal?.throwIfAborted();
    if (accepted.length >= owned.maxPages) stopped('GitHubReadPageLimit');
    const request = JSON.parse(moon.githubIssuesRequestJson(repository.nodeId,
      owned.perPage, after !== undefined, after ?? '', filters.state, labels,
      filters.since !== undefined, filters.since ?? ''));
    if (request.refused) stopped('InvalidGitHubReadRequest',
      {refusal: request.refused});
    let response;
    try {
      const authorization = await authorizationFor(accepted.length);
      signal?.throwIfAborted();
      response = await invokeScopedCredentialOperation({
        authorization, credential, callResource,
        operation: GITHUB_GRAPHQL_READ_OPERATION, method: 'POST',
        path: GITHUB_GRAPHQL_PATH, headers, body: request.body,
        responseHeaders, maxRequestBytes: owned.maxRequestBytes,
        maxResponseBytes: owned.maxBytes, signal,
      });
    } catch (cause) {
      stopped(cause?.code ?? 'GitHubReadInterrupted', {cause});
    }
    const [names, values] = pairs(response.headers);
    const basis = JSON.parse(moon.githubRateLimitBasisJson(names, values));
    if (!response.accepted || response.statusCode !== 200) {
      const failure = JSON.parse(moon.githubClassifyFailureJson(
        response.statusCode, names, values));
      if (failure.kind === 'RateLimited') {
        stopped('GitHubRateLimited', {basis: failure.basis});
      }
      stopped('GitHubReadRejected', {failure});
    }
    const projected = JSON.parse(moon.githubIssuesPageJson(response.body,
      owned.maxBytes, owned.maxNodes, owned.maxDepth, owned.perPage,
      repository.nodeId, repository.databaseId, repository.nameWithOwner));
    if (projected.refused) {
      stopped(refusalCodes[projected.refused.kind] ?? 'GitHubGraphQLRefused',
        {refusal: projected.refused,
          ...(projected.refused.kind === 'RateLimited' ? {basis} : {})});
    }
    const current = projected.page;
    if (rows.length + current.rows.length > owned.maxRows) {
      stopped('GitHubReadRowLimit');
    }
    if (consumePage !== undefined) {
      try { await consumePage(current.rows, page); }
      catch (cause) {
        stopped(cause?.code ?? 'GitHubPageNotAdmitted', {cause});
      }
    }
    rows.push(...current.rows);
    accepted.push(Object.freeze({page, useCid: response.useCid,
      rows: current.rows.length}));
    if (!current.hasNextPage) {
      pending = false;
      break;
    }
    // A cursor seen before (including the one just sent) never advances the
    // read: the provider would return a page already accepted.
    if (current.endCursor === after || cursors.has(current.endCursor)) {
      stopped('GitHubCursorCycle');
    }
    cursors.add(current.endCursor);
    after = current.endCursor;
    page += 1;
    // An accepted page with no remaining quota is kept; the read stops
    // before the next request instead of spending one it cannot make.
    if (basis.remaining === 0) stopped('GitHubRateLimited', {basis});
  }
  return Object.freeze({rows: Object.freeze(rows),
    pages: Object.freeze(accepted), complete: true});
}
