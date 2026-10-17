# Original Notion database metadata

The existing Notion Catalog owns vendor metadata interpretation. A database
is a container with a bounded inventory of data sources; a data source owns
its property schema. The parser does not interpret a database id as a data
source id or select the first source, a matching display name or a compatible
schema. Selection takes an explicit occurrence of the original inventory.
Empty inventories and repeated display names remain valid metadata.

## Original selection and identity

`project_notion_database` admits the original database response. Its opaque
result retains exact id/name pairs and the original bounded decode graph.
`project_notion_data_source` receives that original plus its selected index,
checks the returned source id and containing database, and retains the same
database object. An externally synced source may have another data source as
its direct parent, but must still identify this containing database. A newly
parsed equal database, matching ids or equal response hashes do not replace
the original association. This is metadata correspondence, not an installed
issuer, currentness, egress capability or permission to query/write.

Both readers use the existing preserving JSON parser and decode admission.
Vendor property names are data: decomposed/precomposed Unicode, whitespace and
empty names are not normalized. Each property's declared name must exactly
match its key. Nonempty property ids are unique; ids are not URL-decoded or
rewritten. The type discriminant must have an object body. Unknown vendor
kinds retain their ordinary bounded definition, without acquiring an ActQL
logical type, nullable default, writable field or grant. Typed property/row
projection must independently admit supported definitions and complete values.

## Bounds, ownership and extension

Byte/node/depth limits cover the entire original response, including unselected
sources, definitions and unknown metadata. Separate counts and UTF-8 identity/
name bounds are checked before retaining the inventory or hashing. Duplicate
ids, malformed Unicode/JSON, missing fields, inconsistent names, foreign source/
database and exceeded limits return no partial catalog. The bounded wire
writers emit ordinary metadata in retained inventory order, preserving every
name and id. Output exhaustion cancels the existing writer, returning no
partial JSON. No canonical ActQL identity domain or version is added.

Private arrays never escape. Index access returns immutable scalar pairs or
read-only opaque metadata; definition/original getters return existing decode
cursors, not mutable syntax backing or a second parser. These cursors and
metadata aliases extend retention of their original graphs. There is no I/O,
async state, retry or resource-release operation in this Catalog. Cancellation
and physical response loss/retirement stay with the existing Credential, Site,
RowRun and Resource owners. A hash, parsed page, completed Promise or catalog
drop does not acknowledge physical cleanup.

Original response bytes at the physical caller, source/decode graphs, string
and field storage, source/property arrays, identity maps, metadata records and
references overlap with hashing and bounded writer/output storage. Structural
limits are not a complete heap inventory, reservation, transfer allowance or
normal numerical supplier. The consuming installation/acquisition must account
for that simultaneous graph and preserve original current/cleanup responsibility.
No normal funding or current binding is derived from this metadata.

## Consumer and verification

The private Node bridge forwards the same opaque originals and limits. It does
not reconstruct them from metadata JSON or expose compiler fields. Moon tests
cover multiple/empty inventories, nominal equal-data refusal, direct/synced
parents, complete definitions, duplicate ids, exact Unicode and structural
bounds. Actual compiled Node tests also exercise the original pair and bounded
metadata output. Native/Wasm API checking is type evidence, not runtime evidence.
Physical discovery/query, public database-alias resolution, typed row completion,
installation/current authority, approval/recovery and installed read/write
acceptance remain distinct consuming boundaries.

The reviewed vendor model follows [retrieve database](https://developers.notion.com/reference/retrieve-database),
[retrieve data source](https://developers.notion.com/reference/retrieve-a-data-source)
and the [data-source object](https://developers.notion.com/reference/data-source).
Those endpoints distinguish database inventory from property schema; this
Catalog adds no implicit alias-selection policy to public configuration.
