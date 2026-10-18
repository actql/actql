# GitHub Issue observations

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
the codec retains its incomplete row graph. Exactly the final actual response
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
