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

## Comment request construction

The existing comment constructor bounds the subject in UTF-16 units and the
body in Unicode scalar characters. Its native JSON request String and the
separate JSON String export coexist. Escaping a control character can therefore
require six units in the inner request and seven in the outer export before
the Host applies the HTTP request-byte limit. That later refusal cannot fund
these earlier allocations or reduce the constructor's original input domain.

The native constructor inventory retains both builders, their transient String
values, the fixed JSON object/iterator controls and their Array/Map backing.
Original subject/body text and the fixed documents remain borrowed. The common
representation policy prices these units; the provider adds no byte tariff or
capacity grant. Subject checks have a separate constructor inventory.

Fixed controls use the existing common constructor envelope per actual
stringify call over the whole co-held closed document forest. The two calls
remain two occurrences for each row; their controls are not moved into a
single Host fee. Only the original String bounds and literal geometry belong
to this provider. It does not duplicate builtin iterator/closure/header prices.

The Host must reserve the original Plan's composed extent before calling the
constructor. It separately accounts for quotation controls, decoded input,
JavaScript mapping/parsing/hash and saved request bodies, credentials, HTTP
request/response storage, returned provider observations and failed-child
overlap. Returning constructor DATA or a request String does not retire those
owners, consume a physical attempt, authorize a write or acknowledge cleanup.

The standard comment subject check declares its fixed HTTP request to the same
Host as the write. Its provider hooks only construct the original subject body
and interpret the already-accounted status, body and declared headers. The
transport's original `accepted` value is forwarded as DATA, including false;
it is never synthesized from a successful await or HTTP status. Repository and
Issue correspondence, documented semantic refusals, rate-limit uncertainty and
unclassified failures keep their existing provider meanings. The direct Site
helper composes these same pure hooks for its existing callers; the standard
installed path does not retain a second Provider-owned HTTP callback. Neither
projection nor a returned subject retires the physical read or its failed child.

## Installed native Source Reader

The installed loader selects the existing shared Reader before constructing the
Row Source. The original GitHub protocol runs inside that Reader, with one
ordered occurrence declaration for all outer and dependent GraphQL reads.
The same RowRun grant, scope, request packet and use ordinal reach the checked
child authorization; the packet itself is its occurrence original. An operation
name, equal scope DATA or a request byte bound cannot replace that original.
POST uses the unchanged native body and the original installed request bound.

The native quantity retains protocol rows, subjects, continuations, cursor
histories and the response-prefix aliases, plus current parser/index and output
construction. Fixed request quantities derive from the same Catalog documents
and fragments used by the original builders. HTTP rejection bounds do not fund
those earlier native stringify calls. Native finish JSON, Host parsing and
row serialization can overlap; the unchanged later row-wire limit does not
bound an allocation that already occurred before that refusal.

Initial request/control construction is selected before any read callback.
After each actual response is retained and charged, the same RowRun grows its
original allowance from the largest owned response extent and the number of
actual retained responses before native projection. Equal-sized replies still
add original prefix occurrences. The quantity also retains the next request
while keeping future, unreceived rows out of the current constructor inventory.
Every completed native row or subject contains the original `id` and `updatedAt`
text members; their disjoint encoded objects bound row geometry, with an extra
partial current row retained on failure. This narrows constructor geometry only; parser, page, subject,
row and total-response rejection limits keep their original values. The shared
native Reader composes its response/binding/credential inventory with that
original provider quantity; neither quantity issues permission or a new budget.

The fixed native exports have ASCII member names and at most five container
levels. Their Host `JSON.parse` tree uses the preserving construction inventory;
it does not normalize a hypothetical body-sized key. Raw provider parsing keeps
its original NFC/depth contract, and the RowRun separately owns row admission.
Native label/assignee strings come from disjoint complete name/login objects,
which bound emitted array-item counts before construction. An invalid partial
element remains covered by the current raw parser/index workspace.

A complete page consumes the original response charge once. A dependent reply
without a complete page consumes that same charge as an observation before the
next receive. The native codec still decides completeness and provider meaning.
The protocol never calls a second charge function or constructs a replacement
ticket. Codec close cuts decoder aliases, while the shared Reader retains the
original response/failed-child duties. Only its existing stopped-binding and
pending-callback checks permit protocol-prefix retirement; an awaited read or
codec close alone is no physical cleanup acknowledgement.

Managed decoder originals close through the same Reader's retirement duty,
using the original synchronous projector supplied to its constructor. This
projector retains invalid asynchronous results without imposing a read-current
fence on cleanup. A rejected/stopped read therefore keeps its original failure;
a failed decoder close keeps that same original page for retirement retry.
Read projections still enforce their unchanged current/stop fences. Closing
a decoder returns Unit, never a physical acknowledgement or new permission.

## Original comment confirmation

Comment CREATE first retains its logical input. The same fixed Preview supplies
the original DispatchKey for the physical marked request before the existing
durable claim. Recovery validates those saved bytes against that Preview and
key; it neither encodes another mutation nor creates a replacement request tag.

A Created mutation reply remains provider evidence. The common Row Effect uses
a distinct initial or restored confirmation occurrence, with its own current
read decision and credential grant under the same Request and Ledger. The
provider checks that exact returned comment node, original Issue/repository,
logical body and request marker before the existing receipt/CAS can record
`applied`. An absent, foreign, refused or interrupted confirmation cannot make
the mutation successful. A lost mutation reply supplies no node for this read;
the original uncertain send is never retried or searched by matching content.

The whole native seven-role construction profile reaches the existing Host
composer unchanged. Logical construction, marked-request finalization and both
physical confirmation occurrences have separate original operation slots.
Returned request/reply material and control work remain charged to their
existing owners; stopped or pending reads retire through the same physical
child. A settled Promise or a validated response is not a cleanup acknowledgement.
