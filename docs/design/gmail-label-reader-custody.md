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

## Installed label preparation

The connector-owned Host manifest selects the label Source factory through the
standard installation table. Its closed Source profile fixes connector identity,
the original mailbox, Site-profile path, Account configuration and independent
reader/declaration/secret ceilings. The Site fixes the original HTTPS origin,
signing identity, namespace, generation, journal and optional TLS authority.
Their ordinary identity parts retain a digest of the exact mailbox bytes and
selected TLS authority; configuration normalization cannot collapse distinct
mailboxes. The original Common schema/key declaration and checked Source alias
publication remain the only query inputs.

The trusted installer supplies the existing same-runtime opaque reader capacity;
neither a public profile amount nor transfer/page ceilings issue this declaration.
Absence is `GmailReaderCapacityUnavailable`, and missing original Credential
material is unavailable before opening a Site. A normally discovered factory is
not evidence that these independent supplies exist. In particular a test's
explicit capacity declaration is not an adopted normal quantity.

The factory uses the existing generic provider-reader path, which reserves on
the original Run Ledger and installs its response-borrow cleanup observation
before the synchronous I/O-free reader factory. One private wrapper obtains the
already selected original read grant before creating its child reader, binding
the original resource, mailbox, fields and request occurrence. It forwards
current checks and cancellation around those awaits without retry or fallback
to an ordinary reader. Whole-page charging and row admission use that same
original RowRun. Copied preparations and foreign capacities cannot create a
replacement acquisition.

The wrapper retains its child, original binding, signal, close failure, Promise
and callbacks along with the original reader inventory. Closing the physical
transport does not settle raw/callback/capture aliases. Failed close cannot
replace the original read failure, and observation remains unconfirmed until
the existing custody Owner supplies an actual original transfer/retirement
receipt. The enclosing capture therefore keeps its reservation and recovery
responsibility. No factory-local ledger, cleanup acknowledgement or token-based
mailbox identity is introduced.
