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

## Original query responses and property bytes

`project_notion_query_page` receives the same selected data-source Catalog and
one original bounded response. Every page must identify that source as its
parent; a supplied containing database must also match. Every property name,
id and native discriminant must correspond to the original schema. Missing,
extra, renamed or substituted properties refuse the whole page projection.
Response order is retained, duplicate page ids within the response refuse,
and cursor/`has_more` pairing is exact. The per-response vendor limit of 100
is distinct from a Program's acquisition row limit across many responses.
A later acquisition must check cross-page ids, cursor progress, limits and
current authority without treating a projected page as completion.

One bounded independent byte snapshot is retained before parsing and hashing.
Property-value JSON is sliced from the original source span in that snapshot,
not emitted from the parser's numeric representation. This preserves all
original decimal digits/exponents and native nested value syntax even when a
binary floating-point representation could round them. An external Node
Buffer change cannot rewrite either the admitted decode graph or those exact
bytes. Encoded property ids and Unicode property names remain unchanged.
The snapshot, decoded graph, source/schema aliases, rows, property records,
within-page id map and caller's original response overlap, along with hash
workspace and each bounded output String. A shared snapshot is not a zero-cost
holding, a loan, a physical response release or normal funding.

These projections retain vendor DATA. Present null is distinguished from a
missing field; no nullable value, flattened string or Content reference is
invented. Inline title/rich-text/people/relation arrays and their native
truncation flags are not proof of complete property items. Computed formula/
rollup discriminants do not determine a promised logical shape. The installed
reader must finish property pagination and check every value against its
original per-property checked read contract, bound to the same property id,
schema observation, data-source occurrence and configuration revision. Display
number formats provide no precision, scale or rounding authority. Temporal
shape/range fields likewise require that original binding; current replacement
profiles must not rewrite a saved Run's originals. The supported installation
supplier remains required, rather than being replaced by sample inference.

A nested data-source entry returned for a wiki is currently an explicit
unsupported-entry result with no partial page set. This is an unimplemented
traversal boundary, not a language prohibition or permission to skip entries.
Malformed/error responses, foreign parents, schema changes and exhausted
input/output bounds similarly produce no projected page. Private indexed
getters return only original opaque records/cursors; array backing and byte
snapshot do not escape. There is no I/O, grant, retry, cleanup acknowledgement
or canonical ActQL identity introduced here. The existing Site/RowRun owns
acquisition, authorization, response loss and actual physical retirement.

The private Node bridge forwards those same originals. Actual Catalog and Node
counters cover exact-number-token preservation, external Buffer mutation,
null/missing distinctions, foreign/equal-reparsed source correspondence,
complete property matching, duplicate pages, terminal/pending cursor pairing
and bounded input/output. Their per-response success does not establish
physical paging, typed rows, installed selection/currentness, funding or
read/write acceptance. The vendor inputs are the existing selected API's
[query data source](https://developers.notion.com/reference/query-a-data-source),
[page property values](https://developers.notion.com/reference/page-property-values)
and [retrieve page property](https://developers.notion.com/reference/retrieve-a-page-property)
contracts; their pagination obligations are retained separately.


## Original checked property declarations

The database declaration may carry `data_source_id` and `read_contracts` as
specified by [the existing contract owner](../spec/protocols/contracts.md#notion-read-contracts).
This is configuration DATA, with no new envelope, version, CID domain or
permission owner. The original scalar/id-only object forms keep their bytes.
A read binding retains both the original declaration and selected schema;
physical equality, not equal JSON or ids, relates a query row to that pair.
The actual installed supplier must additionally bind its configuration/revision
and current Site. This Catalog pair alone does not complete that supplier.

Every declared entry is checked through the existing checked ValueContract
reader, including unused entries. Explicit column aliases preserve original
vendor names while satisfying Common's canonical field-name rules. Decimal
precision/scale and temporal projection are supplied, never inferred from
number display format, expression text or example values. Numeric cell admission
uses the private original response token and Common's exact Decimal codec;
the parser's binary number is used only to recognize the native number kind.
Common's existing admission/recheck and writer retain enum, extent and nullable
requirements. Formula/rollup native discriminants must agree. Inline paginated
property kinds request completion rather than claim their arrays are complete.

Calendar's existing strict RFC3339 physical conversion now lives in the existing
ValueAdmission owner, with Calendar forwarding unchanged bounds. Known numeric
offsets normalize exactly to the same UTC millisecond, while the response retains
the source spelling. Canonical logical Timestamp admission is unchanged.
Unknown offsets, nonzero submillisecond digits and range overflow still refuse;
named zones need their real timezone supplier. Start/end selection cannot discard
a range end, change its temporal shape or silently fabricate midnight.

The declaration Cursor, all Contracts/enum vectors, source and property aliases,
column inventory and canonical Object schema remain live with the binding.
During cell admission the full query snapshot and decode graph overlap with the
exact numeric token, normalized text, converted Cursor, checked value, iterative
validation frames and bounded writer/output. These are separate records, arrays,
references and backings where applicable; aliasing is not free allocation or
retirement. Aggregate row/page callers must charge returned admission usage and
all simultaneously retained work, and keep actual cleanup responsibility.
There is no I/O, current capability, release ACK or normal numerical supplier in
this typed projection. Complete property pagination and the installed original
configuration/Run path are still consuming implementation obligations.

## Original property-item completion

The existing Catalog creates a private property-item request from the same
original query row, original property and checked column. A copied or reparsed
schema cannot replace that pair. The first request and every continuation retain
the immutable prior response chain. The physical caller obtains bounded page id,
property id and opaque cursor DATA from that original request; it cannot replace
them with a name-selected property or a representative row. This DATA does not
issue a Site grant, installation/currentness, Run binding or transport ACK.

Title, rich text, people and relation values use the vendor property-item list
protocol. Every response and item must match the original property id and kind.
The shared property id is not a unique item key. Repeated values and their order
are retained. A nonterminal list, even an empty one, cannot produce a completed
cell. Continuation cursors are opaque and cycles refuse. The metadata's
`next_url` is retained as untrusted response DATA and never followed as an origin
or resource selection. The original page/property request supplies the fixed
path; existing percent escapes in returned ids are not encoded a second time.
Physical dot-segment ambiguity refuses instead of dispatching another path.

Only a terminal chain can flatten title/rich-text `plain_text` segments or form
ordered people/relation id arrays. Common then checks the entire resulting Value
against the original checked Contract, including enum, extents and nullability;
individual text chunks need not themselves be enum members. Empty complete text
and arrays remain distinct from missing, null or incomplete values. Rollup
calculation and complete file/Content projection need their own actual supplier;
this four-kind reader does not pretend an unsupported result is a value.

Every response uses a bounded independent byte snapshot and preserving decode.
Limits bound each response and cumulative pages, items, raw bytes, actual decoded
nodes/string bytes, cursor history and remaining work. Checked subtraction
precedes every cumulative addition. Selection, response copying, original decode
usage, item projection, cursor comparisons and complete-value construction are
charged. Output/node/text exhaustion refuses without emitting partial typed
values. Writer failures cancel the existing writer. These are finite structural
bounds, not normal physical capacity or a second Ledger.

The request/response records retain the original row/property/schema and prior
chain, raw/decode graph, selected cursor/string aliases and per-item UTF-8 counts.
Completion overlaps that history with a bounded reverse-page inventory,
StringBuilder or Source-node array, converted decode graph, Common validation
frames/CheckedValue and writer/output. The JS reader also holds the immutable
provider functions, original request/contract/column, credential/context/current
callbacks, stop signal, request target/query, await/Promise state and every raw
response observation. Aliases do not remove distinct backings or record costs.

The physical reader snapshots its functions, receiver and limits before await.
It rechecks current Account/authorization before every operation and through the
existing Credential boundary before send. Each page uses its own original
journal use and the same selected token binding; a changed operation, parent
binding or resolved token refuses. A lost reply remains the original journal
Unknown and the reader cannot resend it or resolve new material for that use.
No response can grant another operation. Prefix charges go to observation
consumption; a completed value carries the terminal response's original charge
to its parent, which still owns complete-row assembly/admission. Synthetic
canonical output bytes are not transferred input. Callback failure retains the
original response and cleanup responsibility; it does not issue a value/ACK.

Cancellation/stop and failed current checks retain this same reader's original
raw observations and pending custody. Read/stop Promise completion, Site close,
GC, dropping an opaque page or an exported value is not physical retirement.
The reader reports `cleanupConfirmed:false`; its consuming actual Source phase
must supply original capacity and confirmed retirement before returning holdings.
The tests' observation tickets are explicit doubles, not RowRun funding. Actual
installation/configuration revision supply, full Source rows, query/Run restore
and normal numerical acceptance remain separate required implementation work.

The private Node bridge forwards the same originals and existing checked writer;
no compiler representation fields, new shim, issuer or public wire are exposed.
Common tests cover complete/incomplete/empty chains, original/foreign columns,
whole-value enum admission, repeated shared property ids, cycles, native mismatch
and exact cumulative bounds. Actual Common Credential/SQLite/Account/local-TLS
cases exercise original paged token/current checks, bounded value delivery and
Unknown/nonresend. Their success is not pristine installed or live Notion proof.

The reviewed wrapper and completion protocol is the existing
[Notion property-item reference](https://developers.notion.com/reference/property-item-object)
and [retrieve property endpoint](https://developers.notion.com/reference/retrieve-a-page-property),
under the already selected vendor API version. No ActQL version or identity domain
changes for this implementation.
