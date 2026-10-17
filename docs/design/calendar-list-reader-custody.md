# Calendar list reader custody

## Responsibility

The Calendar catalog owns the declared columns, response interpretation and
checked values. The physical Calendar sequencer owns the fixed HTTPS operation,
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

Success and `CalendarListReadFailure` retain original response observations.
Their frozen arrays are shallow: response bodies and externally captured aliases
can outlive the read promise. A promise settling, finishing page processing,
closing a credential, cancelling logically, or dropping one local array is not
physical reader retirement. Callback delivery can retain rows independently.

A normal installation must snapshot the trusted reader's complete simultaneous
retained/workspace envelope and bind it to the original prepared acquisition
before I/O. Reservation belongs to the existing RowRun/Ledger and remains until
the same original reader's physical cleanup is confirmed. The existing nominal
response borrow and cleanup-confirmed observation are the connection boundary;
listing-report capacity is not an alternative for an ordinary Calendar Source.
Missing inventory, placement, original binding or cleanup confirmation remains
unavailable/pending. Do not add a second ledger, reinterpret transfer as holding,
use a fixed spare margin, or infer a cleanup ACK from a resolved promise.

`createCalendarListReader` snapshots the original invocation before I/O and
returns one private physical-reader handle. Its `read`, `requestStop` and
`observe` methods require that same receiver; copied handles cannot observe or
stop the acquisition. A read starts at most once. The caller retains the handle
and its original methods before installing the existing response cleanup
observer. If the factory refuses, previously acquired credentials, reservations
and cleanup handles remain the caller's responsibility.

The observation contains only phase, stop request, original response count/body
bytes, custody status and an unconfirmed cleanup result. Requesting stop aborts
the same reader's signal without substituting credential close or Run cleanup.
The handle does not accept a mark-clean callback. In particular, its succeeded
or failed phase leaves escaped raw observations retained and cleanup unconfirmed.
This conservative observation is not a complete physical-retirement port: a
normal caller must keep the original reservation pending until an existing
trusted custody owner can actually confirm retirement of the same reader and
its escaped observations.

The bounded catalog and TLS caller tests establish response meaning, original
Account/Credential checks, charging and sequencing. They do not establish this
normal-installation capacity/retirement connection, credential token minting,
public installed acquisition, or the other Calendar read/write operations.

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
cannot be represented by the current millisecond timestamp contract, including
nonzero sub-millisecond precision. It does not round, use a local time zone, or
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
and are not numerical funding. The original observer reports retained custody
and `cleanupConfirmed: false`, including after read success, cancellation,
Promise settlement or Site close. No GC, cleared diagnostic, copied handle or
transport-only close is promoted to raw-observation retirement. A normal
installer must connect the original reader and complete overlap to the
existing Ledger/custody owner and obtain actual retirement there; this private
sequencer does not implement that missing connection.

The source fixture exercises actual Common Account/RowRun, signed Credential
scope, SQLite journal and loopback TLS using explicitly supplied component
bounds and a private fixture Bearer secret. It is not the Google service-account
token protocol, normal installation, a funded normal profile or live Google
acceptance. Its retained fresh DBs/keys and response-loss Unknown remain
evidence; they are not retried or removed to pass a test. A real installation
still requires the separately scoped original auth dependency and original
secret/key generation, normal capacity, physical-retirement integration and
the normally packaged Source path.
