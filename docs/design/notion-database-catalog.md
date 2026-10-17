# Original Notion database metadata

The existing Notion Catalog owns vendor metadata interpretation. A database
is a container with a bounded inventory of data sources; a data source owns
its property schema. The parser does not interpret a database id as a data
source id or select the first source, a matching display name or a compatible
schema. Selection takes an explicit occurrence of the original inventory.
Empty inventories and repeated display names remain valid metadata.

## Original property write encoding

The Catalog's property write codec accepts one original selected data-source
observation, its property occurrence and a Common CheckedValue. The opaque
result retains all three originals with a bounded encoded document. An equal
reparsed schema or copied equal checked value cannot replace them in its
correspondence check. Aggregation uses original property ids, preserves encoded
ids and Unicode, rejects duplicate properties and refuses foreign sources
before returning a body. This operation does not create a Mapping, write
capability, target Reference, key evidence or mutation identity.

Decimal uses Common's exact scalar spelling and the bounded Encoder's decimal
number operation. No binary floating-point intermediate, rounding or text
relabel is used. Exact request bytes alone do not establish the vendor's storage
domain or a successful mutation; the physical Effect must independently retain
its original contract, before/version/overwrite guards, actual response and
after-value correspondence. It must refuse a missing exact physical supplier.

Title and rich text are plain-text objects split at complete Unicode scalar
boundaries, retaining the full original text and the vendor's per-object and
array bounds. Empty text remains an empty rich-text array. URL/email/phone null
is distinct from empty Text and false. Select/status selects only an exact
existing label's original option id, checking and charging unselected options
too; it cannot implicitly create options. A null status write is refused here
because the vendor can replace it with its default option. That operation needs
the actual default original, rather than claiming a null value was preserved.
People/relation arrays carry original checked identifier text, never
manufactured ResourceRefs or permissions. People, relation and multi-select
writes each require both the actual supplied item bound and the vendor's
100-entry request bound. A larger supplied bound cannot bypass the vendor
limit; a smaller supplied bound remains effective. That request bound does not
limit reads, property pagination, the logical Array type, permission or numerical
resource supply. Multi-select checks the complete original option inventory once,
including for an empty selection; every exact supplied label selects an
existing option id. Unknown or normalized-equivalent names cannot create an
option. The encoded request retains supplied order and repeated occurrences;
this is not a claim that vendor storage preserves an ordered multiset. An
empty array clears the property, whereas null is rejected for multi-select.

A single original Common Date or Timestamp encodes the date object's `start`;
the codec never parses Text as a temporal value, chooses a named timezone or
rounds precision. Common's canonical checked scalar spelling remains intact.
Explicit null clears a date. A supplied range Object is not silently reduced
to its start: range fields need their original typed Mapping projection and
remain unavailable through this single-scalar codec. Computed and audit
properties refuse encoding. A separate range projection receives both original
checked start and end from the consuming Mapping. Both contracts must have the
same Date or Timestamp shape, the start must be present, and a null end must be
an explicit original of that same nullable temporal shape. The bounded Encoder
emits both fields without parsing Text, dropping an end, choosing a timezone,
rounding or manufacturing midnight. The range matcher requires the same source,
property occurrence and both original CheckedValues; the scalar matcher cannot
accept it on the start alone. The scalar constructor and its absent-end bytes
remain unchanged. The codec does not establish that the two originals belong
to the same captured input row or approved Mapping: the existing Effect owner
must supply and retain that correspondence. Temporal range and Content/file
writes still need their actual typed physical suppliers; this is an
implementation boundary, not a new public language restriction.

Codec work and output limits cover string/option/identifier scans, property
membership, duplicate detection and bounded Encoder depth/nodes/bytes. Original
source/decode graphs, property definitions, CheckedValue/contracts, Text slices,
option maps, per-property encoded documents, aggregate output and caller aliases
can overlap. The multi-select label-to-original-id map shares its original
strings but retains its own bounded map backing; duplicate input labels are
still charged, and no selected option is free because another occurrence used
it. Single-scalar temporal emission retains the original CheckedValue and text
alongside its encoded document. Every property-write record also has an optional
end slot, including the legacy None case; a range retains the original end and
contract graph alongside start/source/property, the writer and encoded body.
The matcher/constructor callback and aggregate-body overlap remain part of the
same caller lifetime. An extra alias or absent slot is not zero-cost or a
cleanup acknowledgement. Those holdings require the existing Effect/resource
supplier;
structural limits do not reserve capacity, acknowledge physical retirement or
prove normal numerical funding. Approval/current authority, original captured
Mapping/input, Run materials, dispatch, Unknown/nonresend and cleanup remain
with their existing owners.

The physical shapes and limits follow the selected vendor's
[page properties](https://developers.notion.com/reference/page-property-values),
[page update](https://developers.notion.com/reference/patch-page) and
[request limits](https://developers.notion.com/reference/request-limits).
No API version or ActQL canonical preimage changes here.

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

Each database and data-source Catalog retains an independent bounded snapshot
of its original UTF-8 response before decoding or hashing. The declaration
already retains its independently snapshotted authored source. Their bounded
original-text getters preserve CRLF, key order, unknown fields, numeric lexemes,
Unicode and escape spellings exactly. A newly encoded Cursor or matching digest
cannot replace this source material. The getters do not expose mutable byte
backing, reselect a source, perform I/O or issue publication/current authority.
Output exhaustion returns no partial text and leaves the original Catalog
unchanged. A mutable caller Buffer cannot rewrite the captured observations.

The physical response, private snapshot, UTF-8 decode/parser workspace, retained
Cursor and property/source inventory overlap with hash workspace and each
returned text backing. The two Catalog records each add a snapshot reference;
an additional getter alias extends the original lifetime even if the runtime
shares immutable text. Copying, hashing and UTF-8 conversion are bounded work,
not free metadata storage, transfer credit or a cleanup acknowledgement. The
actual installation/publication supplier must retain and fund this graph until
confirmed physical retirement. These original-text projections are a necessary
input to saved original publication; they do not themselves serialize a new
publication contract, finish its persistence or authorize rediscovery on restore.

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

Each issued request and response has a private one-time self seal. All consumers
check the physical original before trusting copied control fields, including
completion, continuation, request DATA and original-response projection. A copied
record cannot remove a nonterminal cursor and upgrade a partial response into a
completed cell. The seal is ordinary original correspondence, not authority.

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
Each request/page also retains one private seal cell and its original self
reference; this cyclic control backing remains part of the same retained chain.
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

## Original complete property rows

The existing Catalog assembles every property column under the same original
query row and complete checked property schema. Scalar admission runs before
dependent property I/O. Pending title, rich-text, people and relation columns
accept only completed property-item originals for that exact row occurrence and
column. Another observation with the same page id, an equal schema/value or a
copied assembly cannot replace the original. Missing columns and incomplete
chains never produce a complete row. There is no JS contract evaluator or
wire-to-original factory.

The row uses the existing Common object builder in canonical field order and
rechecks the complete Value against the original schema. Aggregate nodes, text,
depth, columns and bounded work apply to that entire object, including names.
Original input work and logical runtime usage remain distinct: Decimal input
punctuation is charged as input, while Common measures the retained exact
coefficient in the logical object. Neither representation passes through a
rounded JS Number. Writer exhaustion returns no partial row and a completed
read-only Value may be projected again without replacing its original schema.

Common also aggregates the exact complete row inventory for a query page, in
the original order and with no missing, duplicated or foreign row occurrence.
The outer array and every row contribute to whole-page nodes, depth, text, work
and encoded output bounds. The same Value builder, runtime recheck and Encoder
make this decision; individually bounded rows never imply a bounded full page.

The physical caller queries the exact selected data-source id with the existing
vendor POST operation. It checks cross-page ids, opaque cursor progress and
aggregate page/row/response/output bounds before delivering each complete page.
An empty nonterminal query is not completion; duplicates, cycles, malformed
native values, changed discriminants and whole-contract failures refuse. This
caller obtains property values through the existing original property reader,
never by treating truncated inline arrays as complete. The selected vendor
protocol remains [query a data source](https://developers.notion.com/reference/query-a-data-source).

Query and property operations require separately scoped original grants/uses
from the same declared Site/request relationship. A query grant is never
retargeted to authorize a property read. Original Credential binding and current
Account/authorization remain independently checked before and through each
physical send. Token replacement, foreign parent bindings and missing property
authority refuse; completing a typed row grants no additional operation. A lost
dependent reply retains its original journal Unknown and the same child reader;
neither the parent nor child may resend that use.

Earlier actual response charges are consumed as observations. Exactly the last
actual response ticket is retained for the complete page's row delivery, after
every required cell has been checked. No charge is fabricated for canonical
output bytes. Failed callback/current/stop paths retain the same parent/child
and original observation responsibility. Already delivered complete pages do
not turn a later failed acquisition into a completed Run.

The assembly retains the original binding/schema/query-row graph, one private
self-seal cell and cycle, a bounded array of CheckedValue aliases, aggregate
counters and a cached complete Common object. Canonical field selection,
object-builder storage, runtime recheck frames and output overlap those cells.
Each query page also retains raw/decode/row metadata, per-page original assembly
references, JSON wire/parsed output and callback aliases. The parent holds all
child readers before awaiting them, child results/failures and original property
chains, pending actual charges, response observations, cross-page id/cursor sets,
provider/current callbacks and Promise/abort state. Distinct backings and escaped
aliases remain holdings even where immutable Values share their original data.

Cancellation aborts the same original readers. Query/child Promise completion,
Schema/Value equality, Site close and GC are not physical retirement. The parent
and children continue to report `cleanupConfirmed:false`. Actual installed
configuration/revision/current-schema suppliers, ordinary Source/Run integration,
standard system columns, saved-Run recovery, confirmed raw retirement and normal
numerical funding remain required; this property-row caller does not claim those
capabilities from a private Catalog pair or explicit fixture observation tickets.

Every returned response charge is also retained by the parent and on its result
or error, even after a later admission/output/current/callback failure. This
inventory contains original tickets, including ones already passed to callbacks;
only the original RowRun/Ledger determines their actual disposition. It cannot
be read as consumption, an ACK, a new charge or permission to retry consumption.

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

### Original dependent property authorization

A complete-row reader may retain the existing early property grant, or capture
one `propertyAuthorizationFor` callback before I/O. These choices are exclusive.
The callback is entered only after the same original query response and checked
row identify a pending original property request. It receives that request,
original declaration/source/checked-contract binding, column and query/row
occurrences. No query scope is retargeted and no grant is inferred from that
DATA. Every property use still passes the existing Credential and Site owners;
query/property remain separate operations of the same original Run/acquisition.
This is unrelated to the earlier installation-metadata subject.

Before and after the awaited selection, retain current/abort checks. The
returned property operation and complete existing invocation bindings must
match, and Common must still recognize the same request/checked-column pair.
A missing, foreign or failed supplier cannot fall back to the query grant or
repeat preparation. If no property is pending, no supplier is called. The old
early-property path retains its bytes and behavior.

The reader keeps the callback and the actual immutable argument record through
selection; that record references the existing request, declaration, source and
contracts, rather than cloning their inventories. The pending Promise and
continuation overlap the query response, original ticket, row and checked
schema; a callback may retain its escaped argument after returning. These
references/records/workspaces are not zero-cost and limits are not funding.
Do not consume the pending query ticket for row delivery or release its custody
before the selected original/current checks finish. Failed selection retains
its original cause, raw response and ticket. Reader/Site close, Promise
settlement and GC are not raw retirement or a cleanup ACK.

### Provider-declared query incompleteness

The selected query response's optional `request_status` is admitted by the
existing Common query-page Owner before any row is exposed. Absent status remains
valid. A present status has the documented `complete` or `incomplete` type and
only the optional known `query_result_limit_reached` reason. Unknown or malformed
status is refused. A declared incomplete result is refused on every page, even
with `has_more: false` and a null cursor. The vendor may cap a query while
reporting cursor exhaustion; cursor exhaustion by itself is not completeness.
The official SDK permits the known reason with either status type, so the
reason is validated without manufacturing a contradiction or replacing type.

The physical caller consumes only successfully admitted original pages. Failure
keeps the actual response, original charge tickets, previous child readers and
unconfirmed cleanup custody. Earlier successful page observations remain
retained, but a later incomplete response cannot finish the whole acquisition
or publish that page. This correction introduces no automatic partitioning,
retry, replacement authorization or permanent product-wide row ceiling. A future
complete partition strategy still requires its original planning/acquisition
contract; it is not supplied by rejecting a capped query.

## Original database discovery requests

The private `createNotionDatabaseDiscovery` caller connects the existing Catalog
selection to actual database and data-source retrieval. It receives the original
checked alias declaration, reads its bounded database id through the private
Common bridge and retains that same declaration. After the first response,
`notion_database_read_source_index` alone chooses a singleton or the explicit
id's occurrence in that original database inventory. The second request uses
only that occurrence's id. Duplicate display names, first position, a matching
schema or a compatible replacement do not select a source. The selected original
schema and declaration then form the same `NotionDataSourceReadContracts` used
by typed query and property completion; JS does not reconstruct their Contracts.

Database retrieval and data-source retrieval have separate original operation
grants/uses. Both belong to the same Site/runtime/connector/Run/task/dispatch
scope, and current Account authorization is checked before, through and after
each request. The caller cannot retarget one operation's grant to the other.
The fixed GET paths and existing selected Notion API version do not come from
response URLs. Dot-segment coordinates and overlong encoded targets refuse.
No retries, redirect authority, public CID grant or second selection Owner is
introduced. A current refusal or lost reply retains the same reader; a lost
reply remains the original Credential journal's Unknown and is never resent.

Every response is retained before charging/admission/current callbacks. Every
actually returned charge remains on the same success or failure along with the
original response, including the body that exceeds an aggregate limit. The
existing observation callback does not retire the Catalog or grant a release.
The reader is one-shot and has nominal methods; copied handles cannot dispatch.
Stop aborts the same pending operation. `cleanupConfirmed` remains false on
success, failure and stop: transport completion and protocol completion are not
physical retirement or reservation release.

The declaration/checked Contract graph, both response bodies and decode/Catalog
graphs, original inventory, bounded metadata writer/String and parsed coordinate
array, selected schema/property array, canonical schema writer/output, current
and charge callbacks, credential/material references, pending Promise/handlers,
original failure and returned aliases can overlap. Existing per-response and
aggregate byte, metadata, Contract and output limits bound this work; they are
not a numerical supplier, transfer allowance, lease or complete heap price.
Aliases still extend the original lifetime and do not cost zero by sharing.

This path supplies original remote observations to the existing selection and
row readers. Trusted installation/configuration-revision membership, saved Run
originals, standard system columns, Source/RowRun funding and physical retirement
remain independent required integration. A discovery result is not permission,
a currentness certificate or an installed Source. Actual Account/Credential/
SQLite/local-TLS tests exercise singleton/explicit selection through typed rows,
foreign/missing schema contracts, original charges, current denial, Unknown,
nonresend, bounded output and nominal handles. They do not establish a pristine
installed or live Notion profile.

### Original schema occurrence and delayed authorization

The Catalog captures the declaration's exact bounded UTF-8 bytes before parsing
and hashing them. `notion_database_read_declaration_source_cid` identifies this
SOURCE, including whitespace, CRLF, key order and Unicode. It is not a semantic
Contract identity, installation identity, credential issuer or permission.
Equal source CIDs do not replace the retained declaration original.

`select_notion_read_source` checks bounded comparison work and retains the same
declaration, observed database and selected occurrence in an opaque
`NotionReadSourceSelection`. Its match operation requires those physical
originals; schema projection and Contract binding retain that database and index.
The original singleton/explicit-id selection rule remains authoritative. There
is no first-entry, display-name or compatible-schema selection.

An optional `sourceAuthorizationFor` supplier is captured before I/O and is
mutually exclusive with the existing early `sourceAuthorization`. After the
actual database observation and Common selection, it receives the same opaque
selection, declaration and database plus the exact selected GET origin/path and
empty-body fact. Its returned original operation authorization is checked before
schema I/O. Missing, foreign or wrong-operation authorization refuses without
falling back to the database grant or the generic authorization callback.
Provider methods and the supplier are snapshotted before awaiting. Current
authorization and stop are rechecked before and after the awaited supplier.

The earlier Run-scoped discovery route retains its existing grant/use checks.
The delayed supplier is a sequencing seam, not an installation-preparation
grant. A pre-schema installation action additionally needs the original trusted
Host publication request, Account/Site/credential originals, the closed
preparation subject and separately scoped database/schema uses in their existing
owners. Callback DATA, selection shape and SOURCE CID cannot issue these
originals. Query/property operations keep their actual Run scopes. Offline
EXPLAIN does not discover metadata, and restore must retain the original
declaration/schema instead of rediscovering them from current configuration.

A supplier rejection or post-await current/stop refusal retains the first
response and its actual charge on the same one-shot reader. Unknown/nonresend,
failure aliases and `cleanupConfirmed: false` remain unchanged. There is no
physical retirement acknowledgement from selection, callback completion or GC.

The input Buffer and its private byte snapshot may overlap with decoded cursors,
Contracts and the cached SOURCE hash. The selection adds two original graph
references and an index; its returned aliases extend those original lifetimes.
The frozen supplier descriptor, captured callback/receiver, provider methods,
pending Promise/handlers and returned authorization may overlap the retained
response, charge and later schema. Hashing/copying and all inventory comparisons
remain bounded work, not free shared storage or numerical funding. Existing
byte/work limits do not establish a complete physical metadata capacity supply.

Independent exact-byte and selection-work vectors exercise these Catalog
boundaries. Actual Common/Account/Credential/SQLite/local-TLS cases exercise the
delayed original/path, separate operations, absent/foreign refusal, method
snapshotting and post-await current/stop custody. Those cases use explicit
Run-scoped fixture grants and observation tickets; they do not establish the new
preparation subject's authority, installed publication or normal funding.

## Original Source system columns

The public database Source includes the original page's `id`, `url`,
`created_time`, `created_by`, `last_edited_time`, `last_edited_by`, `resource` and
`version` alongside its properties. The existing property-only projection is
still useful as a component and retains its exact schema bytes. It is not a
complete public Source schema. The same Catalog owner explicitly augments its
opaque property binding with the eight fixed system contracts and constructs
one complete checked Object schema. It retains the original declaration,
selected data-source occurrence, property metadata and checked Contracts;
no reparsed schema, invented property or matching CID replaces them.

System `resource` is exactly the original page id and `version` is exactly the
original `last_edited_time` String spelling. They are correlation DATA, not an
issued ResourceRef/ContentRef, a version capability or mutation identity.
The two logical Timestamp columns use the existing ValueAdmission physical
normalizer and checked Timestamp contract. A known offset is converted exactly
to UTC milliseconds; the original response and version coordinate retain its
spelling. Unknown offsets, nonzero submillisecond digits and malformed times
refuse. User columns require the actual returned partial User object/id; no
missing identity, nullable value or lookup is synthesized. All eight fields
must be present and admitted before a full Source row can finish.

An original property's chosen column cannot overwrite a system column. The
existing checked Object constructor refuses duplicate names; the existing
explicit read declaration can choose a distinct property column. Standard
columns never become property-item requests or replace a paginated property
completion. The same original row, complete Value builder and whole-page
admission check every property and system cell together. Field count/name
bytes, schema and row bounds, original response scans, conversion, validation,
canonical output and cancellation remain charged and fail closed.

The augmented binding adds a bounded system-contract vector, tuple records and
complete schema graph sharing original property references. Row assembly adds
system CheckedValues, decoded/normalized timestamp backing and input/output
text, with all original page/decode/property history, metadata and pending
completion arrays still live. Shared aliases do not remove layout or overlap
costs. The complete graph and physical reader still require their actual
installation, original Run/funding and confirmed retirement suppliers.

The thin discovery caller requests this full schema explicitly for Source
preparation and forwards that same opaque binding to query/property assembly.
No JS schema reconstruction, authority, second parser, wire version, permission
or numeric profile is introduced. Actual private Account/Credential/SQLite/TLS
coverage remains separate from ordinary installed and live Notion acceptance.
The vendor metadata fields are defined by the existing selected
[Page object](https://developers.notion.com/reference/page) and
[data-source query](https://developers.notion.com/reference/query-a-data-source)
contracts; this implementation does not migrate the selected API version.

## Original installation metadata consumption

The same discovery reader can consume the existing Credential Owner's explicit
installation-metadata control as part of one trusted Host publication request.
Its Subject and per-use Scope remain opaque originals. The reader obtains
operation and origin DATA through the original control's Common projection;
it never spreads a Scope into a primitive record, invents Run fields or
re-admits an equal body to obtain authority. The shared invocation boundary
checks that both scopes belong to that same original Subject. This differs
from the existing Run route's complete thirteen-field correspondence; neither
route substitutes for the other.

Metadata requires the delayed schema supplier. Only the actual observed
database and Common-selected occurrence can provide the schema target; an
early speculative schema grant is not admitted in this mode. The reader checks
the exact schema operation and the same original Notion origin before consuming
the first response charge. The shared physical Credential port checks the
per-use GET, exact selected path and empty body before sending. Database and
schema uses are separate originals; a query/property grant is not a fallback.
The old Run-scoped early and delayed paths retain their original behavior.

Current Host publication/profile, Account, Site, issuer/material, egress and
resource checks remain duties of the actual operational preparation. The
reader rechecks current/stop before and after the supplier await and on each
physical operation. A profile or Account replacement, copied/foreign Scope,
wrong purpose/origin/path or cancellation refuses the operation and retains
the original observed response and charge. Lost replies retain the same
Credential journal Unknown and one-shot reader; selection, transport close,
Promise completion or GC does not acknowledge raw retirement or permit resend.

The captured credential/control and opaque scopes coexist with a frozen
six-field request projection in the prepared record. Later scope projections,
returned authorization, supplier Promise/handlers, initial and selected scope
aliases, database/schema decode graphs, responses and original charge records
can overlap. Getter and matcher work and temporary projection records are not
free merely because their strings or opaque graph references are shared.
Actual metadata lifetime funding must be supplied by the existing resource
Owner before I/O. Parser/response ceilings, a read tuple, fixture tickets or
the presence of a publication request cannot manufacture that supply.

This consumption seam does not itself implement the installed database profile,
operational Site issuer, publication persistence or final declaration/Run
adoption. Those consumers must retain the actual original declaration and
selected schema; static checking never fetches missing metadata and same-Run
restoration never rediscovers it from current configuration.

## Exact original page observation

The existing Catalog admits one bounded original Page response for the exact
requested page id. It snapshots the response bytes before decoding and retains
the original cursor, properties, response digest and raw version spelling in
one private-constructor observation. Parent admission preserves the returned
discriminant and actual coordinates: a data-source parent may also contain its
database id, while a workspace parent has its actual `true` marker and no
invented id. Page, database, block and agent parents remain distinct.
The original `in_trash` and legacy `archived` aliases must be Boolean and agree
when both occur; absence or malformed metadata never becomes `false`.

The checked metadata projection retains the page id as correlation DATA, the
original last-edited spelling as version, and exact normalized UTC millisecond
timestamps using the existing ValueAdmission normalizer. Unknown offsets and
nonzero submillisecond digits refuse. Properties remain original vendor DATA:
this observation does not complete paginated titles/properties, infer their
logical Contracts or issue a ResourceRef, current-version guard or mutation
identity. The private metadata wire is a bounded projection, not a new public
Source schema, canonical identity domain or authority-bearing preimage.

The thin exact-page reader captures its original compiled methods and receiver,
Credential control/scope, current callback and response/observation callbacks
once. The existing physical Credential port admits only the separately
authorized page operation, exact GET path and empty body. The original current
and stop checks surround asynchronous work, secret resolution, response charge
and observation consumption. An Account change, abort, malformed response,
foreign page or output-budget refusal preserves the same response and charge.
Lost replies retain the original use's journal Unknown; neither another reader
nor repeated `read` can resend that use. Copied JS handles are not originals.

The reader retains its original failure and all raw response aliases after
success or failure. Its cleanup observation remains unconfirmed; response,
callback or Promise completion, transport close and GC do not acknowledge
physical retirement. The bounded raw snapshot, decoded node/key/property
graph, parent variant, optional database coordinate, normalized timestamp
backings, digest and opaque observation coexist. Metadata encoding also holds
a bounded pair vector, Encoder key inventory, text/output backing and the
original graph. The JS reader adds its request record, compiled methods and
receiver, Credential/current/callback references, composite signal, abort
controller, pending Promises and handlers, original error and response/charge
aliases. Layout, shared references and empty/optional arms are not free.
Actual installation lifetime funding and confirmed cleanup must cover this
overlap; parser/transport bounds and fixture observation tickets are not that
supply.

This exact-page prerequisite does not prove complete workspace membership.
The vendor [search limitations](https://developers.notion.com/reference/search-optimizations-and-limitations)
provide no exhaustive or stable workspace index, including trash. A configured
root traversal proves only its selected collection unless an actual
authoritative original inventory establishes full membership and coverage,
including archived pages. The public all-visible-pages target still requires
that supplier; missing coverage is Unavailable at that boundary. Terminal
search pagination, first-page selection and this single-page observation do
not replace it. The selected [Page](https://developers.notion.com/reference/page)
and [parent](https://developers.notion.com/reference/parent-object) contracts
also do not issue permission, installation currentness or a write target.

Verification separates bounded portable Catalog cases from the actual
Common/Account/Credential/SQLite/TLS caller cases. The latter use explicit
private fixture issuer/material and observation tickets, preserving original
Unknown journals and keys. They do not establish a normal operational issuer,
complete page inventory, numerical funding, installed publication or live
Notion acceptance.

## Checked rows from exact page originals

An exact-page observation can enter the same complete checked row Owner used
by database queries. The shared private property projection checks its actual
data-source parent, optional database coordinate, every original property
name/id/kind and the complete original schema inventory. It does not wrap the
GET in a fabricated query/list response or infer a missing source from names.
The historical query-row type holds those checked property occurrences; the
issued row additionally retains the exact original Page object. A read-only
matcher requires that same row, schema binding and Page, not equal ids, bytes
or CIDs. Ordinary query rows retain their existing behavior and output bytes.

The row and its pending-property request share one nominal original occurrence.
Only its actual completed property page can fill that cell. A separately
assembled equal row, another query observation or copied row record cannot
substitute. Scalar admission, exact Decimal conversion, Timestamp/system fields,
whole-object admission, duplicate completion and cancellation use the existing
algorithm. The bounded original response/schema scans are charged before the
new row is assembled, including every name/id/kind occurrence and the actual
identity bound. Budget exhaustion remains fail closed, without a hidden reset.

The thin parent reader captures the original compiled methods and receiver,
then holds the exact-page child before its first await. It retains that actual
response charge for whole-row delivery. For each pending column it obtains a
separate original property authorization only after Common issues the actual
row-bound request; page authorization never substitutes for property purpose.
Current/stop checks surround the supplier await and every physical read. Earlier
original charges go to observation; exactly the last actual response charge
accompanies the complete checked row. Synthetic canonical output never becomes
transfer input. A scalar-only row needs no property operation or speculative
property grant. Every returned charge remains held in the same parent graph,
including aggregate-bound refusal after a child returned its actual response.

The existing property reader owns cursor history and completion. The parent
retains every child before awaiting it, original results/errors and charge
aliases after success or failure. Lost replies remain the same Credential
journal Unknown; a new explicit reader cannot resend that original use.
All child and parent cleanup observations remain unconfirmed. Promise/consume
callbacks, transport close, array freezing and GC do not prove physical cleanup.

The optional Page reference changes the row's layout even on the legacy None
path. Its Some path overlaps the original raw/decode/Page graph, projected
property records and checked schema/cells/output. The parent also retains a
WeakMap/token/state, compiled method closures and receiver, frozen context and
schema wire, callbacks and pending authorization/result Promises, composite
signal/controller, child/result/charge arrays, bounded pending-column DATA and
returned row wire. Shared aliases, rest-call arrays, Encoder workspace and
private matcher work are not free. Actual installation/phase funding must cover
the entire lifetime; per-response/aggregate limits are not its supplier.

This is a full-diff read prerequisite, not an issued target, complete Preview,
write authorization, snapshot-isolation promise or conditional mutation. The
actual installed before/apply reread, current original version guard, writes,
reconciliation, saved-original recovery, complete workspace inventory and
normal resource supplier remain separate obligations. No public schema,
canonical preimage, wire/version or permission domain changes here.


## Saved original database read material

The existing Catalog can capture one bounded read snapshot from its same
original declaration, observed database, selected data-source occurrence and
checked schema binding. It retains those references and a private self seal;
a copied record cannot issue or match its getters. Its complete canonical body
stores exact original JSON text as String values, the checked schema/CID and
the actual property-only/full-system distinction. The snapshot SOURCE hash is
an identity of that representation, not a semantic replacement for the
embedded declaration source or a credential/installation identity.

Cold admission reads only that saved material. It constructs new local Catalog
originals from the saved bytes, applies the existing singleton/explicit
selection and complete checked Contract algorithms, reproduces the exact schema
and rejects a mismatch or alternate canonical body. Those reconstructed
originals do not nominally equal another live observation, even for equal saved
bytes. Same-Run or installation custody has to be authenticated by its existing
Store/Journal/installation owner; a caller-supplied body/CID is not that proof.
There is no provider I/O, current-profile lookup, grant, cleanup acknowledgement
or mutable byte/array getter in the codec.

The snapshot adds a record, self-seal Ref, selection/source/read-binding graph
references, checked schema text/CID and canonical body/CID. Its original three
raw snapshots/decode graphs and Contract inventories remain live. The bounded
pair/encoder inventory, UTF-8/hash backing, outer-body parse/copy and decoded
source Strings overlap with re-encoded saved-source copies, the newly admitted
Catalog graphs and returned opaque aliases. Each existing structural and
selection/Contract work limit remains active; a finite sequence of independently
bounded stages is not a reservation, zero-cost sharing or a normal numerical
supplier. Cancellation is limited to bounded encoder failure; physical current,
stop/Unknown/nonresend, raw retirement, installation publication persistence and
final Run adoption remain separate consuming duties.

### Ordinary Relation declaration intake

The same sealed full-system snapshot can project its checked field-contract map
into the existing `RowRelationViewSpec` input for one explicitly selected
resource name. A property-only schema is refused using its original binding,
even when authored columns happen to have system names. The existing Common
row-source declaration owner remains responsible for schema/Catalog admission.
Its existing Relation representation is a field map, not the complete Object
contract retained by the snapshot. The existing Contract emitter preserves every
checked child, including enum order/repetitions, extents, exact Decimal shape
and nullability; the derived map has its own CID. It does not replace or reuse
the snapshot's complete Object schema bytes/CID.
The projection adds no facts, key evidence, request/acquisition profile,
Reference, classification, installation membership or authority. Cold intake
uses saved originals and performs no metadata discovery.

Its bounded encoder frames, field-map String/hash/UTF-8 backing, resource text
and returned specification String overlap with the saved snapshot, schema and
checked Contract graph. Both sequential encoders retain independent output/node
bounds; those bounds do not claim a single aggregate memory envelope.
Generic declaration intake then retains its own decode/canonical/preimage
workspace and new declaration alongside those originals. Structural bounds do
not supply their funding or make returned aliases free. Installation, Run
custody, current checks and physical reader retirement remain independent.

## Installed metadata target projection

The existing Notion installer retains its original declaration as the database
metadata target. Only after the actual database response has been admitted and
Common has selected its singleton or explicit data-source occurrence does the
schema callback retain that exact selection and database. Its target projection
accepts those original references and the same declaration, never a matching id,
display name, copied selection or body/CID as a replacement. The selected wrapper
carries the opaque references; the wrapper's JSON shape alone cannot issue them.
Selection is one-shot, including when a later Site action fails.

The existing Common selection retains a private self-reference in addition to
its declaration/database/index. Matching, schema projection, Contract binding
and snapshot capture require that same original selection record; copying its
retained fields cannot recreate it. This adds a Ref/record slot and retained
alias to the existing graph, not a wire field, grant or cleanup receipt. The
read-only id projection remains DATA and is never sufficient for a Site use.

The thin private adapter projects the fixed retrieve operation, original origin,
GET method, exactly encoded path and empty body, plus the installation's explicit
Account resource. It snapshots each existing provider function and its receiver
once. Selected input fields must be own data properties; accessors, unknown
fields, foreign originals, wrong purpose/path and a different receiver refuse.
The URI coordinate retains exact Unicode/percent spelling without normalization;
its input lower bound is checked before allocation and its encoded UTF-8 target
has an independent bound. The public database declaration and all wire/CID
domains remain unchanged.

These synchronous target facts are DATA for the existing Site's independently
scoped metadata grant/use. They neither issue a grant nor replace the original
Host publication request, current Account decision, Site generation, physical
issuer/key/secret, egress or resource supply. They cannot retarget a query/property
Run grant or invent a metadata Program Run. The portable selection alone is not
proof that a response was physically observed by this installation.

The installer closure retains provider methods/receiver, declaration, origin,
resource, database path and, after selection, the actual database/selection and
selected path. Original and encoded coordinate strings, UTF-8 measurements,
projected fact records and the Site's own copies/claims may overlap with the
reader's raw responses, charges, parsed Catalogs and callbacks. All structural
bounds remain distinct from lifetime funding. There is no asynchronous work,
retry or cleanup acknowledgement in the projection; only the existing physical
cleanup owner can retire those original aliases. Parent publication/reader
cleanup must continue to retain the graph when it remains unconfirmed.

The ordinary row Source Check Environment assembly preserves the complete
checked Contracts as data. In particular, Text enumeration vectors retain exact
Unicode, line endings, order and repetitions alongside their original carrier
CIDs. Member sorting and the enclosing evidence preimage use the existing exact
data canonicalizer. Host Account/configuration normalization remains separate.
This projection holds the original parsed members, sorted arrays and canonical
wire/hash workspace until the caller releases them; exact text is neither a
grant nor a memory reservation. The original Source checker still admits the
result before SQL/AQL preparation and does not relax an input Contract.

The Site-backed discovery consumer binds the same original Host publication
request, Account decision and installed credential issuer before the database
GET. A separate schema use is issued only after the admitted database response
selects its original data-source occurrence. Current publication, Account and
Site observations fence each protected operation; changing an original across
the dependent selection cannot authorize the schema request. A lost reply keeps
that use's Journal Unknown and does not permit another reader or refreshed
material to resend it.

Closing that Site or its Journal does not retire the discovery reader's retained
response, charge, parsed Catalog, selected schema or failure aliases. The actual
preparation phase must fund their full overlap before I/O and retain it until
physical custody is confirmed. Post-response charging is not that supplier;
missing installation-phase originals remain Unavailable before ordinary I/O.
