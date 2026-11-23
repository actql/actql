// GitHub's Issue listing driver at the Site. The provider MoonBit (through
// the `connectors/github/host_node` bridge) decides every meaning: the fixed
// request headers, page projection, the next page and failure classes. This
// driver only sequences exchanges through the common typed exchange and the
// credential resource, and re-checks before every request that the locator
// stays on the read's Resource path and that the read is still authorized.
//
// Completion is never inferred: a refused page, a refused link, a rate limit
// or a page ceiling ends the read as stopped, with the accepted pages and the
// unfetched locator kept for the owner's stop and cleanup. Raw header values
// are not retained; only the parsed rate-limit basis is.
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';

type Response = Awaited<ReturnType<typeof callHttpsCredentialResource>>;
type Transport = Parameters<typeof invokeScopedCredentialOperation>[0];
type Row = Readonly<Record<string, unknown>>;
type Page = Readonly<{rows: readonly Row[]; excludedPullRequests: number; providerItems: number}>;
type AcceptedPage = Readonly<{page: number; useCid: string; rows: number; excludedPullRequests: number; providerItems: number}>;
type Query = readonly (readonly [string, string])[];
type Locator = Readonly<{path: string; query: Query; page: number}>;
type Limits = Readonly<{maxPages: number; maxRows: number; maxBytes: number; maxNodes: number;
  maxDepth: number; maxLocatorUnits: number; perPage: number}>;
type Component = string | null | undefined;
type Codec = Readonly<{
  githubRequestHeadersJson(): string; githubResponseHeadersJson(): string;
  githubClassifyFailureJson(status: number, names: string[], values: string[]): string;
  githubIssuePageJson(body: Uint8Array, maxBytes: number, maxNodes: number, maxDepth: number, maxRows: number): string;
  githubNextPageJson(present: boolean, link: string, origin: string, path: string, page: number, maxLocatorUnits: number): string;
  githubRateLimitBasisJson(names: string[], values: string[]): string;
}>;
type Basis = Readonly<{remaining?: number}>;
type Failure = Readonly<{kind: string; basis?: Basis}>;
type PageReply = Readonly<{page: Page; refused?: undefined}> | Readonly<{refused: string}>;
type LocatorReply = Readonly<{next?: Locator | null; refused?: string}>;
type Cause = Readonly<{code?: string}> | null | undefined;
type Options = Readonly<{
  moon: Codec; origin: string; owner: Component; repo: Component; filters?: Query;
  credential: Transport['credential']; callResource?: Transport['callResource']; signal?: AbortSignal; limits: Limits;
  authorizationFor(index: number): unknown; consumePage?(rows: readonly Row[], page: number): unknown;
}>;

export const GITHUB_ISSUE_LIST_OPERATION = 'github:issues:list';

const fail: (code: string, details?: object) => never = (code, details = {}) => {
  throw Object.assign(new Error(code), {code, ...details});
};
const count = (value: number) => Number.isSafeInteger(value) && value > 0;
const segment = /^[A-Za-z0-9._-]{1,100}$/u;

// The Issue listing path of one repository, from its access owner/repo.
export function githubIssueListPath(owner: Component, repo: Component) {
  if (!segment.test(owner ?? '') || !segment.test(repo ?? '') ||
      owner === '.' || owner === '..' || repo === '.' || repo === '..') {
    fail('InvalidGitHubRepository');
  }
  return `/repos/${owner}/${repo}/issues`;
}

function checkLimits(limits: Limits) {
  if (!limits || !count(limits.maxPages) || !count(limits.maxRows) ||
      !count(limits.maxBytes) || !count(limits.maxNodes) ||
      !count(limits.maxDepth) || !count(limits.maxLocatorUnits) ||
      !count(limits.perPage) || limits.perPage > 100) {
    fail('InvalidGitHubReadLimits');
  }
  return Object.freeze({...limits});
}

const pairs = (headers: Response['headers']) => [headers.map(entry => entry[0]),
  headers.map(entry => entry[1])] as const;

// Read one repository's Issues. `authorizationFor(index)` returns the
// credential authorization of the next request after rechecking the current
// read decision; it is called immediately before every request.
// `consumePage(rows, page)`, when given, receives each accepted page's rows
// before the next request; a throw stops the read like any other stop.
export async function readGitHubIssues({moon, origin, owner, repo,
  filters = [], credential, authorizationFor, limits, consumePage,
  callResource = callHttpsCredentialResource, signal}: Options) {
  if (!moon || typeof moon.githubIssuePageJson !== 'function' ||
      typeof authorizationFor !== 'function' || !credential ||
      typeof origin !== 'string') {
    fail('InvalidGitHubRead');
  }
  const owned = checkLimits(limits);
  const path = githubIssueListPath(owner, repo);
  const allowed = new Set(['state', 'since', 'labels', 'sort', 'direction']);
  if (!Array.isArray(filters) || filters.some(pair => !Array.isArray(pair) ||
      pair.length !== 2 || !allowed.has(pair[0]) ||
      typeof pair[1] !== 'string')) {
    fail('InvalidGitHubReadFilters');
  }
  const headers = JSON.parse(moon.githubRequestHeadersJson());
  const responseHeaders = JSON.parse(moon.githubResponseHeadersJson());
  const accepted: AcceptedPage[] = [];
  const rows: Row[] = [];
  let next: Locator | undefined = {path, query: [...filters, ['per_page', String(owned.perPage)]],
    page: 1};
  const stopped: (code: string, details?: object) => never = (code, details) => fail(code, {stopped: true,
    acceptedPages: Object.freeze([...accepted]),
    unfetched: next === undefined ? undefined
      : Object.freeze({path: next.path, query: next.query, page: next.page}),
    ...details});
  while (next !== undefined) {
    signal?.throwIfAborted();
    if (accepted.length >= owned.maxPages) stopped('GitHubReadPageLimit');
    // The locator must stay on this read's Resource; the credential
    // resource separately pins the origin to the grant.
    if (next.path !== path) stopped('ForeignGitHubLocator');
    let response: Response;
    try {
      const authorization = await authorizationFor(accepted.length);
      signal?.throwIfAborted();
      response = await invokeScopedCredentialOperation({
        authorization, credential, callResource,
        operation: GITHUB_ISSUE_LIST_OPERATION, method: 'GET',
        path: next.path, query: next.query, headers, responseHeaders,
        maxResponseBytes: owned.maxBytes, signal,
      }) as Response;
    } catch (cause) {
      // A revoked decision, cancellation or transport failure keeps its
      // own code; the pages already accepted stay with the owner.
      stopped((cause as Cause)?.code ?? 'GitHubReadInterrupted', {cause});
    }
    const [names, values] = pairs(response.headers);
    if (!response.accepted || response.statusCode !== 200) {
      const failure = JSON.parse(moon.githubClassifyFailureJson(
        response.statusCode!, names, values)) as Failure;
      if (failure.kind === 'RateLimited') {
        stopped('GitHubRateLimited', {basis: failure.basis});
      }
      stopped('GitHubReadRejected', {failure});
    }
    const projected = JSON.parse(moon.githubIssuePageJson(response.body,
      owned.maxBytes, owned.maxNodes, owned.maxDepth, owned.perPage)) as PageReply;
    if (projected.refused) stopped('GitHubIssuePageRefused',
      {refusal: projected.refused});
    const {page} = projected as {page: Page};
    if (rows.length + page.rows.length > owned.maxRows) {
      stopped('GitHubReadRowLimit');
    }
    if (consumePage !== undefined) {
      try { await consumePage(page.rows, next.page); }
      catch (cause) {
        stopped((cause as Cause)?.code ?? 'GitHubPageNotAdmitted', {cause});
      }
    }
    rows.push(...page.rows);
    accepted.push(Object.freeze({page: next.page, useCid: response.useCid,
      rows: page.rows.length, excludedPullRequests: page.excludedPullRequests,
      providerItems: page.providerItems}));
    const linkIndex = names.indexOf('link');
    const decided = JSON.parse(moon.githubNextPageJson(linkIndex >= 0,
      linkIndex >= 0 ? values[linkIndex] : '', origin, path, next.page,
      owned.maxLocatorUnits)) as LocatorReply;
    if (decided.refused) {
      next = undefined;
      stopped('GitHubLinkRefused', {refusal: decided.refused});
    }
    next = decided.next ?? undefined;
    // An accepted page with no remaining quota is kept; the read stops
    // before the next request instead of spending a request it cannot make.
    const basis = JSON.parse(moon.githubRateLimitBasisJson(names, values)) as Basis;
    if (next !== undefined && basis.remaining === 0) {
      stopped('GitHubRateLimited', {basis});
    }
  }
  return Object.freeze({rows: Object.freeze(rows),
    pages: Object.freeze(accepted), complete: true});
}
