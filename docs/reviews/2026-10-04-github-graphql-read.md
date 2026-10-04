# GitHub Issue read through the published node ID: field contract

This records the review decision on #319, Option A. The installed GitHub Issue source reads each page by `node(id: <published repository node ID>)` through GitHub's GraphQL API. The REST listing `/repos/{owner}/{repo}/issues` is no longer the read path. That REST path was addressed by name, and its rows did not prove which repository they belonged to.

## Identity

| Concern | Rule |
| --- | --- |
| Binding | Recorded by the explicit publication step: API origin, repository `databaseId`, repository global node `id`, and access owner/repo. |
| ID form | Publication uses the same GraphQL API as the reads (`repository(owner:, name:) { id databaseId nameWithOwner }`). The stored node ID therefore has the representation every read compares. |
| Each page | The page must resolve `node(id:)` to `__typename = Repository`. Its `databaseId` must equal the published id, or the page is refused (`GitHubRepositoryIdentityChanged`). Its `id` must equal the published node ID exactly, compared as an opaque string, or the page is refused (`GitHubRepositoryRepublishRequired`: a read never rewrites the binding). Its `nameWithOwner` must equal the access owner/repo, or the page is refused (`GitHubRepositoryBindingChanged`). |
| No fallback | A null node is refused (`GitHubRepositoryUnavailable`). So are GraphQL `errors` such as `NOT_FOUND`, and HTTP 401/403/404. There is never a lookup by name during a read. |
| Same name, other repository | Never read. The request always names the published node ID. |

## Request

- Two fixed read-only documents are compiled into the provider: `ActqlRepository`, used only for publication, and `ActqlIssues`.
- Callers supply typed variables only: `id`, `first` (1–100), `after`, `states`, `labels`, `since`. There is no entry for free-form query text or mutations.
- Each request is one POST to `/graphql` under the `github:graphql:read` grant and the current read decision. The same credential resource, journal, response-header allowlist and byte bounds apply as for every other exchange.

## Completion

- An HTTP 200 with `errors` is never a page. That includes `RATE_LIMITED`, which stops the read as `GitHubRateLimited` with its basis, and it includes `errors` alongside `data`.
- `hasNextPage` without an `endCursor` is refused as `MissingCursor`.
- A cursor equal to one already sent is refused as `GitHubCursorCycle`.
- Page and row ceilings, a revoked decision, cancellation and transport loss stop the read with the accepted pages and the unfetched cursor kept.
- Nothing is retried.

## Field map (the `issues` Resource is unchanged)

| Column | Type | REST source (before) | GraphQL source (now) | Contract note |
| --- | --- | --- | --- | --- |
| `number` | number, not null | `number` | `number` | Same. |
| `node_id` | string, not null | `node_id` | `id` | Opaque global ID. GitHub may state an older or newer representation for the same Issue, so values read before and after this change may differ in spelling. |
| `title` | string, not null | `title` | `title` | Same. |
| `state` | string, not null | `"open"` / `"closed"` | `OPEN` / `CLOSED` mapped to `"open"` / `"closed"` | Same values. |
| `body` | string, nullable | `body` (null when empty) | `body` (`""` when empty) mapped to null | Same: an empty body is null. |
| `author` | string, nullable | `user.login` | `author.login`, or null | **Changed:** an author whose account was deleted is null. REST stated GitHub's `ghost` user. |
| `comments` | number, not null | `comments` | `comments.totalCount` | Same count. |
| `created_at` / `updated_at` | timestamp, not null | `created_at` / `updated_at` | `createdAt` / `updatedAt` | Same instant, in ActQL spelling `...SS.000Z`. |
| `closed_at` | timestamp, nullable | `closed_at` | `closedAt` | Same. |
| Pull requests | — | Listed by REST and excluded by the provider | Not part of `Repository.issues` | Same result: never an Issue row. |
| Filter `state` | — | `state=open\|closed\|all` | `states: [OPEN] \| [CLOSED] \| null` | Same meaning. |
| Filter `labels` | — | comma-separated `labels` | `labels: [String!]` | Same meaning. A label containing a comma is now exact; REST would have split it. |
| Filter `since` | — | `since` (ISO 8601) | `filterBy: {since:}` | Same meaning. |
| Order | — | REST default (created, desc) | GraphQL default | Not part of the contract: Source Evidence states `ordering_evidence.stable = false`. |

## Rate limits

GraphQL rate limits arrive either as HTTP 403/429 with rate-limit headers or as an HTTP 200 with a `RATE_LIMITED` error. Both stop the read. The REST `Link` handling (#301) remains for REST exchanges, but this read does not use it.
