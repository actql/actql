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
