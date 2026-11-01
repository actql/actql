# Calendar list reader custody

## Responsibility

The Calendar catalog owns the declared columns, response interpretation and
checked values. The Calendar page callbacks own the fixed request description,
opaque pagination and whole-acquisition ID/cursor checks. Existing Account,
Credential, RowAcquisition, RowRun and Ledger owners retain authorization,
current installation checks, reservations, capture and cleanup. A projected
`access_role` is data and cannot issue a permission.

The physical request excludes deleted entries and requests all declared cells.
The catalog checks every cell before ordinary Relation projection. Omitted
`items` denotes an empty Calendar list; missing required cells, explicit null,
foreign response kinds and tombstones are refusals. The column names and wire
schema come from the same compiled catalog. The JavaScript sequencer must not
maintain another schema/type mapping.

## Originals and overlap

A received response remains the original credential-resource observation:
`{useCid, accepted, statusCode, headers, body}`. The reader charges its complete
body before status, current, parse or typed-value refusal. Its retained raw
history, ID set and cursor set are independent of selected query columns.
A page may overlap with the following representations:

- transport chunks and the concatenated response body;
- parsed/admitted JSON and the provider's checked page;
- metadata wire plus parsed IDs/cursor;
- row wire plus parsed complete declared rows;
- the caller's RowRun admission and captured canonical rows.

The response byte limit bounds the original bytes, not these representations'
combined storage. Node counts, UTF-16 units, checked-value text bytes, row-wire
bytes and distinct set entries remain separate dimensions. Neither consumed
transfer nor the ordinary canonical-row allowance proves that this whole reader
inventory is reserved. Callback and opaque-provider closures also retain their
original graphs; freezing their envelopes does not measure or retire those
graphs.

## Lifetime and cleanup

Nested compiled projections use the same private Host synchronous invoker.
It captures the original method and receiver and retains any unexpected
returned computation until settlement before reader retirement. This invoker
is internal glue; no author callback receives credential or cleanup authority.

`prepareCalendarListPages` snapshots the original compiled projections, names
and limits before I/O. Its synchronous `fetchPage` and `decodePage` describe
Calendar requests and interpret the same charged response. The callbacks retain
only Calendar cursor/identity state and checked page DATA. They receive no
credential, grant, current callback, stop handle or physical cleanup method.
A query projection never changes the complete declared cells captured by RowRun.

The existing Host `createInstalledCredentialSourceReader` owns the one read
lifetime, current checks, indexed original authorization, Credential binding,
response retention, charge-before-decode and same-ticket page delivery. Neither
success nor `CalendarListReadFailure` exports its raw observation graph. The
provider error preserves the same cause. Stop and cleanup retry stay with that
Host reader and the original RowRun, rather than a Calendar state machine.

Only the original binding's actual close and the joined read/callback graph may
confirm cleanup. An unexpected asynchronous page callback is refused but must
remain retained until that same Promise settles. Pending or failed close stays
unconfirmed; a later cleanup retries the same duty without another send. The
original read error remains primary if physical close also fails. Retirement of
managed aliases is not a GC/RSS proof, row completeness, permission, successful
Run or resolution of an uncertain Credential use.

If Source construction fails after the reader factory was created, the installed
loader retains that same factory with its Site in the existing Host initialization
cleanup. Its original retirement must complete before the Site can close.

## Ordinary installed calendars Source

The Calendar-owned Host manifest registers the private
`actql-installed-calendar-source/0.1` entry. The ordinary installation table
selects it without provider branches in the Host. It exposes only `calendars`;
free/busy and event writes do not inherit this registration. The schema, four
column names and ID candidate-key facts come from the compiled Catalog.
The same checked SQL/Pipe Program selects its original declaration, acquisition,
Account read decision and RowRun; no synthetic filter or replacement Program is
introduced. A projected field selection cannot conceal an invalid known cell.

The profile supplies bounded parser, page, row, credential and declaration
limits, not capacity or authority. The actual installer supplies its original
Source initialization context and the existing service quartet; the service
selects the same-runtime typed implementation/capacity and original Site under
the initial parent. Account configuration, scoped Credential material and
current checks remain separate. The loader captures the original construction and
service methods before configuration awaits and requires the returned reader to
retain the same implementation capacity. A public `readerCapacity` object cannot replace
that original context. Missing context or material remains unavailable. The
transfer envelope is `maxPages ×
maxResponseBytes`, a page holds at most `min(perPage, maxRows)` rows, and total
capture remains bounded by `maxRows`. These dimensions do not measure arbitrary
Node allocation or establish normal numerical funding.

One same-attempt list grant has at most `maxPages` uses. Each actual page obtains
its own original use ID and repeats the existing current checks; API `me` is a
fixed vendor path, not permission inferred from a token. The target retains the
selected HTTPS origin, resource and exact field set. The installation binding
also retains the actual Account context, runtime, Site generation/configuration
and selected TLS authority bytes. The factory captures provider callbacks and
receivers before awaiting Site/profile work. Equal target or schema DATA cannot
replace these operational originals.

All complete response bodies are charged before status/current/type refusal,
and every page enters the original accounted RowRun. Cross-page IDs/cursors,
partial-page failures and a lost response retain their existing refusal/custody
semantics. There is no retry or replacement-use loop. Confirmed physical close
does not rewrite a Credential journal `Unknown` or resend that use. The normal
Host's actual supplier, installed/live Google acceptance, token minting and
other Calendar operations remain separate consuming boundaries.

## Free/busy request and complete response

The same Calendar Catalog owns `calendar.free_busy`'s fixed three columns:
`calendar_id` is a non-null string, `start` and `end` are non-null Common
timestamps, and the relation has no candidate key. `prepare_calendar_free_busy_query`
snapshots the original ordered calendar IDs and canonical query window. Its
private constructor issues a bounded vendor request, not a Source, Account,
Credential, egress permission or execution grant. It neither expands a group
nor infers a calendar identity from the returned values. The request explicitly
asks for UTC and at most the vendor's 50-calendar expansion limit. The Google
[free/busy protocol](https://developers.google.com/workspace/calendar/api/v3/reference/freebusy/query)
defines the POST body, response calendar map and inclusive-start/exclusive-end
busy intervals. A physical caller must still select the registered operation
and original separately authorized Credential use.

`project_calendar_free_busy` admits the complete bounded original response
before returning any page. Its echoed window must denote the requested
instants. The calendar map must contain exactly the original selected IDs:
missing, additional or substituted calendars, group expansion, and any
calendar-level error refuse the complete page rather than publish partial
availability. An omitted empty `busy` array means no busy intervals; explicit
null and malformed arrays do not. Every interval is checked before a selected
projection. Calendar order follows the original selection and each busy
occurrence is retained; no deduplication, sorting, clipping or key is invented.

The vendor RFC3339 reader admits explicit offsets and exact fractional seconds,
then uses existing Common timestamp conversion to represent the same UTC
instant. It rejects invalid dates, unknown `-00:00` offsets and instants that
cannot be represented by the current exact timestamp contract, including
nonzero precision beyond nanoseconds. Canonical UTC output retains three to nine
fractional digits, preserving finer instants without millisecond projection. It does not round, use a local time zone, or
change the general language's temporal semantics. A page retains the same
opaque query and original response digest; physical equality of that query is
available separately from byte-equal query content. Neither equality nor the
digest is an authority or source-capture receipt.

The query retains its ID array, window strings and emitted request string.
Projection overlaps the original bytes, parser tree, admitted cursor tree,
normalized timestamp strings, temporary cell cursors, checked row cells, page
and original query. Emission adds a bounded writer/output; bridge metadata adds
its small projection. Every retained cell occurrence consumes the explicit
value node/text allowances, including repeated IDs. Request, response, parser,
calendar count, row count and output ceilings remain separate. These local
ceilings do not adopt a normal numerical profile, fund an existing Ledger or
measure native/RSS use.

This Catalog and its compiled Node bridge are synchronous: there is no physical
send to cancel, journal to claim, retry or cleanup acknowledgement to emit.
On refusal the caller retains its original response and cleanup responsibility.
No free/busy transport, normal installer registration, resource supplier,
physical-retirement port or service-account token exchange is established by
these projections. The existing physical/Run/Account/Credential owners must
retain those responsibilities when connecting this query to an actual Source.
`free_busy_wbtest.mbt` independently checks request/response correspondence,
precision, errors and budgets; `calendar-free-busy-projection.test.mjs` consumes
the actual compiled bridge. Those tests are not normal installed or live Google
acceptance and do not establish Calendar event writes or the other profiles.

## Free/busy physical sequencing

`calendar-free-busy-read.mjs` consumes the original Catalog query without
parsing its request JSON or interpreting response fields in JavaScript. It
snapshots the trusted compiled functions, request body, invocation scope,
credential reference, callbacks and limits before its first await. The fixed
registered operation is `calendar:free_busy:query`, POST
`/calendar/v3/freeBusy`; a Calendar-list grant or a different original request
binding cannot substitute for that operation. The original Account and
Credential owners recheck current authority before the physical send and
after awaits. The query does not select an OAuth endpoint, create an auth grant
or turn successful token resolution into API authority.

Every complete response is retained and charged before status/current/type
failure. The synchronous Catalog checks the complete selected calendar set and
window before any rows reach the original RowRun. The private sequencer emits
the complete three-column declared relation even if a later query projects a
column away. A per-calendar error, malformed unselected cell, row limit or
foreign window never completes a partial Source. Keyless carrier facts omit
the `relation_keys` evidence component (`{}`); the existing Common facts Owner
requires a nonempty candidate list whenever that component is present. It must
continue rejecting the invalid `candidate_keys: []` declaration rather than
repairing it into evidence.

The private reader's `read`, `requestStop` and `observe` require the original
receiver. Read starts once; stop only requests cancellation of that same
operation. A lost POST reply remains the original Credential journal use's
Unknown. The sequencer has no retry, token refresh, replacement use or resend
loop. Its retained failure preserves the original cause and received bodies,
including when charging, current checks or delivery fail. It never infers
unsent from zero observed responses or from an exception.

In addition to the Catalog graph, the invocation snapshots, request body,
transport request, original response/header/body, temporary checked page,
metadata/row output, observation arrays, failure cause, callbacks, original
reader/method receivers, abort signals/listeners and pending/settled Promise
graphs can overlap. Body/request/response/value/output ceilings remain distinct
and are not numerical funding. The free/busy observer reports retained custody and
`cleanupConfirmed: false`: that private sequencer borrows its original binding
and does not own its physical close. The actual owner must still confirm any
acquired native transport/FD duty; copied observations and ordinary managed
allocation do not require a separate GC/RSS retirement receipt. This list
installation does not register the independent free/busy operation.

The source fixture exercises actual Common Account/RowRun, signed Credential
scope, SQLite journal and loopback TLS using explicitly supplied component
bounds and a private fixture Bearer secret. It is not the Google service-account
token protocol, normal installation, a funded normal profile or live Google
acceptance. Its retained fresh DBs/keys and response-loss Unknown remain
evidence; they are not retried or removed to pass a test. A real installation
still requires the separately scoped original auth dependency and original
secret/key generation, normal capacity, physical-retirement integration and
the normally packaged Source path.

## Invitation response request data

The Calendar provider response constructor consumes the complete selected
event body and the caller's original calendar, event, participant and request
marker. It retains the exact target text and etag. Missing or null prior
attendee responses remain unknown observations; setting a new explicit response
does not fabricate their previous values. A projected Source row is not a
substitute for this original target observation.

Its participant-only PATCH contains one exact attendee email and response,
`attendeesOmitted: true`, and the original marker in the private
`actql_request` property. It does not reconstruct unrelated attendee or event
fields. Incomplete attendee observations, ambiguous/missing participants and
markers that would be truncated refuse. The provider's `self` flag and equal
target DATA do not issue connected-Account, scope or permission evidence.

The actual caller must retain the scoped read and approved version, bind the
participant to the connected Account, recheck current decisions and use the
same original request and etag condition. Preparing DATA performs no write,
claim, confirmation or cleanup acknowledgement. Native move/delete retain
their separate evidence contracts; this constructor implements neither.

Parser and encoder limits bound construction work only. Original response
bytes, admitted cursor, retained target text, request body, typed input and
caller evidence may overlap and need complete parent/failed-child backing
before normal use. Encoder failure cancels only its own partial output; it
creates no new resource owner or capacity. Actual dispatch, provider outcome,
Unknown handling and cold request restoration remain caller obligations.
