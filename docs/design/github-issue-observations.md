# GitHub Issue observations

The `pull_requests` relation uses the same repository-bound acquisition and
nested-field state machine with a distinct opaque native PullRequest page.
Its original `baseRefName` and `headRefName` are read values, including when
the corresponding Ref objects were deleted. Native OPEN, CLOSED and MERGED
remain distinct `open`, `closed` and `merged` Source states. Issue-only
`state_reason` is SQL NULL on an admitted PullRequest because it is inapplicable;
this is not a missing-field fallback for an Issue or a write-state mapping.
MERGEABLE, CONFLICTING and UNKNOWN map respectively to true, false and SQL NULL.
Missing required fields, other native enum values and foreign native types
refuse admission. Mergeability and a review decision do not grant merge authority.

Adding the view changes the enclosing Catalog identity. The existing Issue
carrier body and identity remain unchanged; an old publication is not silently
upgraded to the new declaration. The additional Source fields do not change
close-with-reason or other mutation contracts.

The `issue_comments` Source enumerates native Issue and PullRequest subjects
under the published repository node, then reads each subject's own comments
connection. Every dependent page checks the same native subject ID, number,
observed update time and repository correspondence. These checks do not assert
an atomic provider snapshot. A changed observation refuses completion instead
of following another subject, repository name or replacement Node ID.

A comment's public `id` is its original `fullDatabaseId` admitted into the
existing Signed64 carrier. GitHub serializes this BigInt as decimal text; no
binary64 round-trip, deprecated `databaseId` fallback or opaque Node-ID decoding
supplies it. Missing, malformed or unrepresentable keys refuse the row. The
separate opaque comment ID remains acquisition metadata and is not an extra
public column or automatic mutation key. Explicit null author and empty body
remain distinct original values.

One opaque decoder sequences subject enumeration, dependent comment pages and
both native families under shared request, subject and row ceilings. It rejects
revisited cursors and repeated keys; a refused decoder cannot resume after the
body is restored. Completed logical pages and enumeration observations consume
their respective original RowRun charges before another physical response.
The existing Credential Owner retains and checks the entire response/request/
use prefix. Projecting a page or retiring decoder aliases neither releases that
prefix nor acknowledges its transport or resource lifetime. Comment predicates
remain on the Host unless the existing owner proves an exact pushdown.

The `issues` relation keeps the published repository binding and the provider's
fifteen Issue columns. Repository node ID, database ID and access name are
independently checked on every outer and dependent response. Issue `number` is
a repository-scoped candidate key; it is not a global identifier or authority.
The original node ID and observed `updatedAt` also bind dependent field reads.
A transfer, replacement, changed observation or incomplete response refuses
completion; this does not assert a provider transaction or snapshot guarantee.

The provider decoder reads integer tokens from their retained UTF-8 spans.
`number` and `comments` cross the existing Signed64 Relation boundary as exact
canonical decimal strings under `int64` Contracts. They are never first rounded
through binary64, relabelled as Number or treated as a String contract. The
GraphQL fields retain their narrower native `Int` domain at provider admission.
The nullable native `stateReason` enum has an explicit lowercase correspondence.
The browser `url`, milestone title, assignee logins and label names remain DATA,
not selectors, stable account identity or permission.

GitHub's [connection pagination](https://docs.github.com/en/graphql/guides/using-pagination-in-the-graphql-api)
limits each requested connection page. The initial `assignees` and `labels`
arrays therefore cannot establish completeness while `hasNextPage` is true.
One opaque codec state retains the original row and each pending field cursor,
count and cursor history. Fixed repository-scoped Issue queries fetch those
continuations; callers cannot supply query text. Exact total counts, identities,
version observations and cursor progress are checked before appending values.
Provider order, duplicates, empty strings, whitespace and Unicode spelling are
preserved. A refused codec state remains refused, including after restored bytes.

All requests use the existing declared read operation, original acquisition,
Credential grant and per-use authorization. The current read decision and stop
signal are checked for every send. Outer and dependent requests share the same
request ceiling; nested pages do not gain an additional allowance. Every actual
response is charged before decoding, including malformed or refused responses.

The existing RowRun permits one pending response charge. Before receiving a
continuation, the preceding actual charge is consumed as an observation while
the codec retains its incomplete row graph. The private read also retains every
exact Credential-issued response and its original request, grant, use, scope,
control and Journal. The Credential Owner rechecks its own response membership
and bytes before and after awaited accounting consumers and before final return.
A copied response, another read's use, changed prefix bytes or an observed
failure followed by restored bytes cannot supply that original prefix. Exactly the final actual response
ticket accompanies the complete logical page, following the existing dependent
row-read rule. Canonical output is never fabricated as received transfer bytes,
and incomplete rows are never delivered. A lost reply retains its original
Credential Unknown; this reader neither retries nor reconciles it by resending.

Observation-ticket consumption and codec retirement do not release retained
backings or acknowledge transport cleanup. Original raw/decode graphs, partial
arrays, cursor history, request/response wires, completed output and callback
aliases overlap until their original owners retire them. The existing resource
supplier must cover that full lifetime independently of parser or request bounds.
The saved Relation schema changes its Catalog identity; an old publication is
not silently admitted under the new schema or reissued as a live observation.
