# Slack user pages

The Slack Catalog owns the `slack.users` field declaration and vendor-page
projection. It reuses source-value parsing, decode admission, ValueContract,
CheckedValue and the bounded wire writer. Node only forwards typed calls to
that owner; it does not interpret compiler fields or infer a second schema.

The page is a bounded observation, not a selected workspace, Credential grant,
complete Source, planner/Ledger declaration or raw-custody retirement receipt.
Physical acquisition must retain the original workspace/token/request and
response correspondence, check the complete sequence of cursors and user ids,
and refuse repeated cursors, duplicate ids, limits and incomplete acquisition.
An empty page with a nonempty cursor is not end-of-input. Nothing in the page
projector dispatches, authorizes, retries or ACKs cleanup.

The declared key is the original `id` within the selected workspace. Names,
display names and email are values, not keys or authority. `real_name` comes
from `profile.real_name`; the top-level legacy copy is not an inferred
fallback. The other declared fields may be absent or null in Slack's varying
user objects, so this new declaration makes them nullable. An absent boolean
remains null rather than fabricated false. Empty supplied strings remain empty.
Email presence or absence is not evidence of a `users:read.email` grant.

Every declared cell and same-page id is checked before projection. Unknown
vendor fields are still included in the bounded parsed original, but do not
become columns, permissions or ActQL contracts. `ok` must be true, `members`
must be an array, and an error envelope cannot be relabelled an empty page.
The original nonempty opaque cursor is preserved. Slack's
[pagination contract](https://docs.slack.dev/apis/web-api/pagination/) defines
absent, empty and null `next_cursor` as terminal, including when member rows
are present. This does not admit a null `response_metadata` object, an error
envelope or other malformed/oversized cursor values. Supplied field values pass
the existing typed validator without string/number/boolean coercion. Value and
row/cursor/output bounds fail instead
of returning a partial page or silently deduplicating ids.

The implementation follows the existing public
[Slack Connector](../connectors/slack.md) target and Slack's
[users.list](https://docs.slack.dev/reference/methods/users.list/) and
[user object](https://docs.slack.dev/reference/objects/user-object/) contracts.
Slack documents profile values as absent, null or empty, user-object variation,
and cursor-based pagination. The source parser retains duplicate-key and UTF-8
refusal. Original API response bytes, parsed trees, checked cells, ids, cursor,
wire output and aliases require physical holding and release accounting; this
pure projection does not supply normal quantities or transfer that custody.

## Credential-bound acquisition

The private user-list reader uses the existing Credential binding for both
`POST /api/auth.test` and each `GET /api/users.list`. The trusted caller supplies
separate original grants and uses for these declared operations within the same
original invocation. The binding retains the secret returned by its original
trusted resolver and refuses changed bytes before later sends. Byte equality
and a shared callback are not proof of an original physical secret generation;
normal Site material membership and current generation remain independent.
Neither a token string nor a `team_id` query
argument proves workspace membership: Slack ignores that argument for workspace
tokens. The Catalog checks the actual bounded
[auth.test response](https://docs.slack.dev/reference/methods/auth.test/), and
the observed team must equal the originally selected workspace before any
user-page request. The private-constructor observation is not a grant, Ref,
permission, or evidence about a different binding. User and response digest are
read-only observation data; they never expose credential material.

Each operation independently rechecks current Account and Credential authority
after awaits and at the physical send fence. The identity result does not grant
`users:read` or `users:read.email`. An organization-token workspace selection is
not inferred from a compatible response, display name or callback. Installed
publication and the trusted original Site/token/workspace selection must provide
their own correspondence; the low-level reader is not their issuer.

The reader requires explicit page, total-row, per-response and aggregate-response
bounds, and an explicit page size below 1000 following the method contract.
Only a terminal cursor ends acquisition, including on an empty page. Every id
is checked across the complete sequence before the corresponding page is
delivered, even if projection omits it. A repeated cursor, duplicate id, incomplete
page limit or row/byte excess fails acquisition; no final capture or partial
success is returned. There is no hidden retry, cursor repair, token refresh or
second reader. Rate rejection is retained for the original request rather than
replayed. Normal admission/pacing remains with the installed caller.

The original RowRun caller charges each actual response before interpretation.
The identity response consumes its exact non-row observation charge; data pages
consume their own charged-page tickets. The reader returns observed rows and
completion, while the original caller owns finish/capture. It does not start or
finish another Run. A lost response remains the original journal use's Unknown,
and the same use cannot resolve another token or resend. Original handle methods
use the same receiver; copied handles and a second read are refused.

## Retained inventory and retirement

Before I/O the trusted caller must reserve the entire simultaneous reader graph
through the existing planner/Ledger/RowRun owner. Page and byte ceilings alone
are not such a declaration or a normal numerical supplier. The graph includes
the original Credential binding, grants/uses and retained secret; preparation
context, callbacks and original methods/receiver; signals and read/stop/current
Promises; the auth response, parsed identity and team/user/digest; all received
raw responses and error/result aliases; page parse trees, checked cells, metadata,
id and cursor strings and their sets; full/selected wire strings, decoded rows,
and escaped canonical capture. Parser, hashing, wire output and asynchronous
callback workspace overlap with these holdings, including on failure. Reference
sharing is not zero retained cost, and total byte/row/page bounds include the
identity observation where applicable.

Success totals are not peak simultaneous holdings. Aggregate refusal can retain
the previously accepted raw history plus the last per-response-bounded body that
causes failure. Admission must cover that extra response and its transport
workspace, not merely `maxTotalResponseBytes`. A current decoded page can likewise
overlap the previously accepted rows before a total-row refusal. Cursor target
encoding workspace follows the bounded cursor's encoded size before the final
target ceiling check. Shape/length checks precede set allocation and Unicode
scanning of the bounded original selection and workspace id.

The reader always reports `cleanupConfirmed: false`: raw observations escape to
the result, failure and callbacks. Socket close, a settled Promise, cancellation,
freezing, dropping a reference or GC cannot acknowledge their retirement. The
existing trusted custody-transfer/retirement owner must close that responsibility
before normal reservations can be released. Legacy canonical-RowRun component
reservations do not fund this complete graph or prove its retirement. Missing
normal supply or original installed correspondence remains unavailable; this
module does not substitute constants, a new ledger or a cleanup assertion.


## Installed users Source

The connector-owned Host declaration selects the existing users Catalog and
private installed Source adapter. It does not replace the public Connector
configuration reader or add another schema evaluator. The selected workspace
bytes, Account configuration, Site generation, runtime and selected TLS
certificate are part of the original physical binding. Closed profile and Site
readers snapshot own data properties without invoking accessors; Unicode is
neither normalized nor used to infer a workspace identifier.

The adapter borrows the original acquisition, RowRun and declared reader
capacity after Common begins the same session. Its synchronous factory performs
no I/O. It captures each provider, Site and Host callback with its original
receiver, then admits one read only. Before network work it rechecks the
original current Account decision. The same Site issues a separate workspace
identity grant for the original invocation; the users grant is never retargeted.
The exact identity response consumes its original observation charge, while
each data page consumes its own ticket in that same RowRun. The aggregate raw
byte ceiling must fit the generic Source's declared finite transfer budget;
this consistency check does not issue a capacity reservation or permission.

The wrapper retains the actual reader before method capture or awaits, along
with its original binding, separate grants, read/stop Promises, provider and
callback receivers, signal graph and error/result aliases. The configuration,
workspace and TLS original bytes, decoded declaration, request/target wires,
canonical binding hash workspace and those reader holdings overlap. A current
failure or stop closes the transport without preparing another reader or
replaying a request. Escaped observations still keep cleanup unconfirmed, and
the existing recovery Owner retains the same Run and reservation on failure.
Site close, Promise settlement and weak-reference collection do not retire
those aliases. Missing original reader capacity remains unavailable at the
normal Host entrance; neither profile bounds nor startup-only capacity fills
that independent supplier responsibility.


## Original Command request encoding

The same Slack Catalog encodes the closed post, reply, reaction and archive
inputs from an original CheckedValue. Its private request retains that original
value and contract; an equal rechecked value is not the retained input. Every
declared field and supplied value is checked before emission. Text constraints,
including enumeration and extents, remain with the original contract. There is
no JSON-to-CheckedValue adapter, implicit optional field or scalar coercion.

Message `ts` and `thread_ts` are exact String identities. They never pass through
binary64, a Host Date, or the derived Timestamp domain. The bounded writer
preserves Unicode and mrkdwn text without normalization. The post/reply text
limit follows Slack's documented 40,000-character truncation boundary: the
codec refuses a larger scalar sequence rather than changing approved text or
creating an implicit upload. Writer and input-recheck bounds remain separate
from that vendor write-request bound.

Post and reply require an explicit item marker, emitted as metadata with
`event_type: actql_effect` and `event_payload.effect_item_id`. Reaction and
archive requests forbid that marker because Slack does not return equivalent
reconciliation evidence for them. The marker String is DATA: only the existing
Effect/Preview owner can bind it to the original item. A request codec or
matching text cannot create that identity, a current target, approval, a
Credential use, an authenticated outcome or permission to resend.

The retained request, original checked object and child contracts, channel and
marker Strings, recheck frames, encoded document and escaped body can coexist.
Their bounds do not fund these holdings. Existing installed Effect, Site,
Journal and Resource owners retain currentness, exact request binding, claim,
Unknown resolution, response evidence and physical cleanup responsibilities.
A successful codec does not supply those originals or close the public Command
execution and recovery boundary.
