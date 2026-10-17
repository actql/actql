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
envelope or other malformed/oversized cursor values. Supplied field values pass the existing typed validator without
string/number/boolean coercion. Value and row/cursor/output bounds fail instead
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
