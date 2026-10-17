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
original invocation. The binding retains the original secret and refuses a
replacement before later sends. Neither a token string nor a `team_id` query
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

The reader always reports `cleanupConfirmed: false`: raw observations escape to
the result, failure and callbacks. Socket close, a settled Promise, cancellation,
freezing, dropping a reference or GC cannot acknowledge their retirement. The
existing trusted custody-transfer/retirement owner must close that responsibility
before normal reservations can be released. Legacy canonical-RowRun component
reservations do not fund this complete graph or prove its retirement. Missing
normal supply or original installed correspondence remains unavailable; this
module does not substitute constants, a new ledger or a cleanup assertion.
