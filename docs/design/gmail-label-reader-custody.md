# Gmail label reader custody

## Responsibility

The Gmail Catalog owns `gmail.labels`' declared non-null `id`, `name`, `type`
strings and the `id` candidate key within that configured mailbox Source. The
physical caller owns the exact original mailbox and one registered GET to
`/gmail/v1/users/{userId}/labels`. Account, Credential/Site, RowRun and Ledger
owners retain original selection, authorization, current policy, original use,
charging, capture and cleanup. Neither a label name/type nor successful label
projection proves an account, mailbox identity, OAuth scope or permission.

The [vendor label-list endpoint](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/list)
is unpaged. The request selects every declared column even if the query later
projects `id` away. The complete bounded response is admitted before any row
escapes: duplicate decoded JSON fields, duplicate label IDs, missing/null cells,
unknown label types and row/value limits refuse the entire page. An omitted
empty `labels` array is accepted only in the empty endpoint response object;
foreign message/error or pagination envelopes are not empty mailboxes. Original
label order and exact string contents are retained, including an explicit empty
name. No rows are sorted, deduplicated, truncated or inferred from metadata.

## Original invocation and physical custody

The private caller requires an explicit original configured mailbox, rather
than selecting `me` or a token-derived mailbox as a default. The original Site
issuer must bind this mailbox/delegation and task request independently; a
String, query field or response digest is not an issuer. The path encodes that
mailbox as one component, fixes the label-list suffix and requests no body. The
same original invocation and per-operation authorization are retained across
awaits, with current checks before actual send and after response/delivery.

Every received body is retained and charged before status, current or Catalog
refusal. A returned result or failure retains the exact original Credential
response packet and raw body. A private reader handle retains its original
read/stop/observe methods and receiver and starts at most once. Stop cancels
only its original signal. A completed Promise, closed Credential, frozen array,
garbage collection or observed row capture is not reader retirement. Escaped
raw/result/error/charge/callback/Promise aliases keep cleanup unconfirmed.

The installer must bind the full simultaneous reader inventory to the original
prepared acquisition and existing RowRun/Ledger before I/O. Original response
chunks/body, strict source/decode trees, IDs, checked values, emitted row wire,
parsed rows, callbacks, provider/configuration and Credential/material controls
can overlap. Limits on wire bytes, rows, nodes, names and strings are independent
local ceilings, not a normal retained/workspace supply or a release ACK. Missing
normal inventory, placement or original physical retirement remains unavailable
or pending. The existing response-borrow/custody owner must retain reservations;
no fixed spare budget, second Ledger or mark-clean callback is introduced.

These private Catalog/transport boundaries do not by themselves register a
normally installed Gmail Source, supply service-account authentication, prove
live mailbox access or complete the other Gmail read/write/content operations.

## Original thread list and dependent metadata gets

The same Gmail Catalog owns the separate thread row projection. A list page
selects ordered original target IDs and opaque continuation; it contains no
logical message rows. `resultSizeEstimate` is an estimate, not a row count or
proof that a selected extent is complete. An empty page with a continuation
still requires its dependent next page. The nominal Connector protocol retains
each original page, rejects repeated tokens and cross-page duplicate IDs, and
issues one pending list or get occurrence at a time. Equal IDs, copied request
DATA or a different read control cannot consume that pending occurrence.
Malformed responses consume it without authorizing retry or a replacement.

Each selected target uses `threads.get` with `format=metadata`, Subject and Date
header selection, and the exact required message/thread identity, label IDs,
internalDate and top-level header name/value fields. Only that same original
selected response may interpret omitted `labelIds` or admitted payload
`headers` as empty repeated collections. Explicit null and malformed values
remain invalid. Generic projection, minimal/list responses and equal masks do
not supply that nominal extent. Missing payload or missing/null thread messages
are not repaired; only an explicitly complete empty message array establishes
an empty thread. Original response digests and bytes remain distinct even when
absent and explicit-empty collections project to equal logical values.

The declared row keeps exact non-null thread ID, exact non-null int64 message
count and non-null first-occurrence label-ID union. Subject is nullable and
comes only from the first original message; duplicate selected Subject headers
refuse instead of choosing a value. The nullable thread date maximizes all
public message Dates, irrespective of conversation order. The source RFC Date
parser uses the existing Value calendar/UTC conversion and preserves the
distinction between malformed input, an unsupported valid instant and exhausted
work. Only absent or genuinely malformed Date uses that message's exact int64
internalDate fallback. Leap-second or output-range refusal is not malformed,
and no host locale, Date object, binary64 conversion or current clock repairs it.

The physical receiver retains the same original request, per-operation grant,
response and charge. List and get have distinct uses; list authorization or token
visibility does not grant dependent message metadata access. Awaited current
checks fence actual send, response admission and successful charge consumption
before constructing another Common request. List responses consume the original
byte-only observation ticket; a get supplies its full checked row to the same
RowRun. Query projection does not remove key or declared-field validation inputs.
The last ticket cannot stand in for the list/get prefix, and an incomplete read
cannot finish or capture that prefix as the complete Source.

Vendor any-message search semantics do not by themselves preserve predicates
on first-message Subject or maximum public Date. The existing query/acquisition
Owner must prove pushdown correspondence or retain permitted residual filtering
over the genuinely selected extent. Neither silently shrinking that extent nor
inventing whole-mailbox capacity completes that dependency.

The retained protocol includes all original pages, token/ID maps, dependent
request controls, message/header cursors, exact Date and fallback strings,
Subject and label values, checked column contracts and row wire. Response
chunks, parse trees, FWS/comment scanning, calendar conversion, maximum-date
comparison, output encoding and caller parsing workspaces can overlap those
holdings. Escaped projections retain the same original get; closing the protocol
prevents further work but does not retire those aliases, native transport or
pending charges. Existing Host/Source capacity and custody must cover this
whole graph independently of the finite decoder and request bounds.

## Original installed thread reader binding

The private thread factory receives the existing installed caller's original
RowRun acquisition, run, request identity and Run/dispatch binding. It captures
the provider methods, Site methods and current/charge/row callbacks with their
receivers before asynchronous work. The same original container and opaque
values must remain selected after every Account await. Preparing another reader
for that acquisition or starting the same reader twice is refused.

The original Host LIST authorization remains a LIST authorization. For the first
dependent get, the factory requires the Common reader's actual pending request,
then obtains a separate GET grant from the same Site using its original current
Account decision. The grant retains the original Run and dispatch, and is bounded
by the original get extent. Each subsequent get uses a distinct original use ID;
it does not refresh or replace the grant. The membership assertion exposes no
Common control and cannot itself issue Account permission or physical custody.

The factory retains the child reader, pending-request references, original
RowRun, captured receivers, credential binding, grant and failure graph. Actual
transport close remains separate from raw/row/callback retirement. Completion
of the typed rows does not supply a physical cleanup acknowledgement or release
the original capture reservation. Stop and failure keep the original attempts;
there is no replacement reader, grant retry or resend.

The installed Source profile explicitly selects `resource: "threads"` to bind
this factory. An absent selector keeps the original labels profile and identity;
unknown selectors and mixed limit sets refuse rather than falling back. The
Gmail Catalog supplies the same thread schema and original ID candidate-key
facts to Common's ordinary declaration and Source alias admission. The selected
thread target and binding remain distinct from the label target even at the
same mailbox, Site and runtime. Neither declaration facts nor target DATA issue
Account permission.

The existing Host/Resource supplier must cover both list and dependent-get
response transfers and their overlapping retained/workspace inventory. With
list bound P, get bound T and per-response byte cap B, the original RowRun raw
response envelope is (P + T) × B, one checked row per get and at most T captured
rows. A thin same-Site delegate retains the original issuer method/receiver and
keeps the list grant's P-use bound; the reader's separate original get grant
retains its T-use bound. It does not create a second issuer or retarget a grant.
The configured total-response byte check remains independent, including failure
after charge. Finite decoder bounds are not a capacity issuer. Missing normal
supplies remain unavailable rather than borrowing the labels-only reservation
or treating a final ticket as proof of the whole prefix.

## Installed label preparation

The connector-owned Host manifest selects the label Source factory through the
standard installation table. Its closed Source profile fixes connector identity,
the original mailbox, Site-profile path, Account configuration and independent
reader/declaration/secret ceilings. The Site fixes the original HTTPS origin,
signing identity, namespace, generation, journal and optional TLS authority.
That private override is bounded original ASCII PEM text, read by the existing
bounded configuration/FD owner under its explicit `maxCaBytes` ceiling. Invalid
bytes are refused instead of leniently decoding a different authority before
hashing or handing it to native TLS. The ordinary platform TLS trust store is
unchanged when the override is absent.
Their ordinary identity parts retain a digest of the exact mailbox bytes and
selected TLS authority; configuration normalization cannot collapse distinct
mailboxes. The original Common schema/key declaration and checked Source alias
publication remain the only query inputs.

The trusted Host service selects the existing same-runtime opaque reader capacity;
neither a public profile amount nor transfer/page ceilings issue this declaration.
Labels retain the same original Source initialization, selected installation,
checked declaration/environment and provider implementation. Missing that original
constructor is unavailable before configuration or Site work. The fixed single
complete response supplies both the total-response and one-page bounds. Its
admitted value-text limit also covers the declared id String. The unused positive
cursor field is only the existing non-paginated grammar sentinel; it creates no
cursor, request or permission. These DATA select a recipe that the checked
original Run still funds before reader construction.

The factory uses the existing generic managed provider-reader path, which
reserves on the original Run Ledger and installs its response-borrow cleanup
observation before preparation. One pure request/page constructor is shared
with the original explicit physical reader. It keeps exact mailbox encoding,
all declared cells, whole-page refusal and the original Catalog projection;
no second provider JSON interpretation or label transport owner is introduced.
The Source-owned response holder reaches the physical Credential Resource
unchanged through the scoped invoker, before late current/Journal/outcome
checks. A received body remains accounted even if those checks refuse, and
cannot supply a row or another read. Copied preparations and foreign capacities
cannot create a replacement acquisition.

The shared managed reader retains the original binding, signal, response,
charge and callback/Promise custody. Stop closes admission to further reads;
actual same-reader and binding retirement, rather than Promise completion or
physical-close DATA alone, acknowledges release. Failed close cannot replace
the original read failure. Durable Credential-use Unknown remains a separate
Journal duty even after the same physical child has retired. No factory-local
ledger, cleanup acknowledgement or token-based mailbox identity is introduced.
The independent nested thread factory still requires its complete original
list/get recipe and cannot borrow this label-only preparation.

## Original authentication dependency

The existing label reader accepts the original physical Credential binding;
it does not need a Connector-visible token, hidden resolver request or a second
authentication wrapper. The Credential Owner can prepare and exchange a
registered service-account assertion on that same binding before the reader
consumes its original API use. The original API parent claim and separately
scoped authentication grant/use retain the same Site, generation, Run/task/
attempt and dispatch correspondence. The API grant is never retargeted to the
OAuth origin. The registered dependency owns its exact subject, scopes, native
material generation and current check; a configured mailbox, byte equality or
a returned token is not its issuer.

Only the existing physical Credential port signs and sends the bounded private
form to the fixed OAuth endpoint. It retains the response and access token
privately and returns the original use identity. The reader subsequently sends
the existing label request under the same already claimed original parent use.
There is no second claim for that first API request and no legacy secret lookup
or token getter. The exact configured mailbox remains the explicit path
component; neither `me` nor the authentication response supplies a replacement
mailbox. Google's [label-list contract](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/list)
allows the original read scope and requires an empty GET body. The service's
scope list is not a grant issued by ActQL.

Successful authentication does not override current Account or physical material
checks. Expiry, revocation or retirement before the API send refuses it without
refresh. A lost authentication response keeps the original authentication use
Unknown; a lost label response keeps the original API use Unknown. Neither path
creates a new assertion, claim, acquisition or retry to make the old request
succeed. Journal reopen observes the same original responsibility.

The original signing key, assertion preparation, private form/response/token,
parser workspace, original API request, label response and reader aliases can
overlap. They require the existing installed supplier's complete reservation and
confirmed retirement. Legacy canonical-RowRun component reservations do not fund
this graph. This caller connection does not supply a normal Site/material issuer,
normal numerical capacity, configured Workspace delegation, raw retirement,
normal installation or live Google access. Missing original supplies remain
unavailable in the existing installed path.
