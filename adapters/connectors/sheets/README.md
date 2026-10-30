# Sheets provider interface

## Declaration and configuration

`host/installed-sheets.mjs` supplies an explicit installation profile, published
generation, Site binding and ordinary Source/Effect adapters. A missing profile,
changed publication, unavailable credential or unknown operation is not a grant.
Its static Source/Mapping declarations enter the existing Common declaration
owner. Dynamic range Command/Catalog interpretation is in
`src/connectors/sheets/catalog/range_declaration.mbt`. Common remains responsible
for checking all resulting contracts and their dependencies.

Clear's input/output roles use operation-qualified
`<connector>.sheets.clear_range.command_input` and
`<connector>.sheets.clear_range.command_output` identities. Update retains its
original role identities and complete bodies. This permits both role inventories
to coexist without assigning different meanings to one `(id, version)`;
the ordinary Common registry still rejects such conflicts. Clear's exact role
references and dependent Command CID change together. Its ValueContract bodies,
Command identifier and provider meaning stay the same. This does not rewrite
captured old Catalogs or requests, infer permission or issue an installation.
Physical request and ResourceRef domains remain independent and unchanged.

The provider-specific ResourceRef identity domains and request preimages live in
`range_identity.mbt`. Configuration identity uses the historical NFC convention;
data canonicalization preserves exact payload strings and keys, including
decomposed Unicode and CR/LF. The private Host profile, provider request identity,
Common semantic artifact identity and permission are different bindings.

## Original range request

`RangeBinding` and `RangeRequest` in `range_request.mbt` are same-process opaque
provider handles, not wire envelopes, approval or send capabilities. A request
retains its original installation binding. Equal bodies or CIDs do not admit a
foreign binding; a copied JS physical projection has no original handle.
The Node glue uses `host-common/runtime-result.mjs::checked` and explicit typed
failure projections. It never inspects a compiler Result/Option representation
or reconstructs an opaque handle from JSON.

The binding owns the immutable configuration, scalar column array and canonical
target wire. Each prepared request owns the body, original value wire, path and
CID, and references that same binding. The JS physical projection retains the
original handle/binding through its private WeakMap association. It owns parsed
value/target/metadata objects and borrows the exact immutable body string through
a separate typed getter. It does not stringify that body inside a second
request-sized JSON envelope. Preparation may simultaneously retain the incoming
wire, bounded parse/canonical workspace, ordered scalar row arrays, encoded body
and UTF-8 hash workspace. No equal-content copy is implicitly free.

Recovery additionally owns the bounded saved Effect/recovery trees and all
rebuilt member/request projections until the existing Common consumer releases
them. The original sealed Preview, retained request facts, publication binding
and current target are still checked by their existing Common/installation
owners. Recovery does not acquire a Source, create a new approval or infer an
unsent request from missing data. A saved configuration is data to compare, not
authority to replace the current installation. Original aliases cannot be
treated as physically released because a callback returned or GC became possible.

The applicable limits are the existing Common installed-row Effect limits in
`adapters/host-node/installed-row-effect.mjs`, the immutable selected codec Limits,
and `site/sheets-exchange.mjs::SHEETS_LIMITS`. They include the original bounded
member/row/input/preview/recovery/request/response constraints. A byte clamp is
not simultaneous capacity funding. Any selected Host must account for the
listed overlaps in its existing reservation/holding envelope; this refactoring
does not issue another Ledger, change limits, supply normal numeric funding,
or authorize an allocation/send because an identity check succeeded.

## Physical exchange and lifecycle

`site/sheets-exchange.mjs` invokes the existing scoped credential operation and
passes physical responses to the provider MoonBit codecs. Grid data, literal
cell encoding, exact rectangle validation and acknowledgement meaning belong
to the portable provider catalog. Response decoding does not issue a Common
success or retry grant. The physical path keeps the checked credential origin,
operation and request identity; one fresh existing durable claim permits at
most one send. A lost/invalid reply remains subject to the existing Unknown
reconciliation, never an automatic resend.

Source pages are charged and admitted through the existing row acquisition and
capture owner. Blank rows, explicit NULL, duplicate rows, data text and exact
grid coordinates retain their existing provider laws. A driver's successful
return alone is not completion. The same existing capture/dispatch/Store owners
retain cancellation and cleanup responsibility. Waiting approval, response
capture and physical release remain distinct phases. No provider callback can
replace those transitions.

All catalog operations are synchronous pure projections with caller-selected
finite codec limits. They perform no physical I/O or asynchronous reentry.
Physical callbacks retain their original signal/current/credential checks;
cancellation acceptance is not acknowledgement of resource release.

## Extension and verification references

`src/connectors/sheets/host-bundle.json` declares the existing installation roles.
An independent Source and Command enter through the same installed connector
table and generic owners; they do not add another scheduler, approval or recovery
implementation. `scripts/check-source-command-addition.mjs` selects the existing
independent fixture connector's actual checks, Source capture, approval, physical
storage and same-Run process recovery. The independent third-Compute acceptance
remains `scripts/check-connector-addition.mjs`; neither checker substitutes for
the other or for normal distribution acceptance.

`test/fixtures/range-owned-baseline.json` preserves the pre-move bytes and CIDs.
`test/sheets-owned-baseline.test.mjs`, `test/sheets-range-command.test.mjs` and
`src/connectors/sheets/catalog/range_request_wbtest.mbt` cover original identities,
foreign range/config/Effect/permission/nominal handles, input refusal and exact
recovery. The same portable catalog tests execute on Node/JS and Native; Native
semantic execution is not evidence of a Native physical Sheets installation.
The public Local/HTTPS fixtures retain independent physical expectations and
their own artifact/source-qualified acceptance. Availability of a test is not
a statement that it passed for an arbitrary source or distribution.

## Original clear request

The closed installation choice `rangeCommand: "clear"` publishes the existing
`sheet_range` Source and a separate `sheets.clear_range.v1` Command. The historical
`rangeCommand: true` selects update, and the absent choice selects append; their
declarations and request preimages are unchanged. The business Command suffix is
not a contract version: the Command, installation and provider domains remain
on their current initial 0.1 baseline. Clear's input is exactly `{}`; update rows,
NULL and extra fields cannot request clearing accidentally. Common admits the
original Command/Catalog and the current acquired range Ref before approval.

`catalog/clear.mbt` owns the bounded Google batch encoding and response meaning.
The first request has the exact original GridRange, no supplied rows, and only
the `userEnteredValue` field mask. Google clears masked fields in the uncovered
range, preserving formatting. The second request creates DOCUMENT metadata in
the same batch on the same sheet, with the original exact range and UUIDv4
request marker. A marker is correlation data, not a permission or a replacement
for the Common request identity. Both acknowledgement replies, the original
spreadsheet, range and marker must match for a typed Applied response; missing,
foreign or uncertain acknowledgements remain Unknown.

`ClearRangeBinding` and `ClearRangeRequest` in `catalog/clear_request.mbt` retain
the original configuration, target, encoded body, marker and request CID.
Their physical identity checks reject equal-content foreign handles and copied
JS projections. `site/sheets-clear-request.mjs` retains only those original
handles in its private language-lifetime WeakMap. The driver gets the exact
captured `entries[index]` from the existing installed-row Effect owner when
serializing recovery. It never mints a marker from a Preview or a current DTO.

Clear recovery preserves ordered saved markers under the exact original
Command, binding, Effect, range and target. Restoration does not prepare another
UUID or reacquire a Source. The provider's rebuilt requests are still compared
with the existing durable claim's original canonical request CID, approved
value/target and capability by the installed Effect owner. A rehashed recovery
record alone cannot approve a different request. Current installation and
credential checks remain independent and are repeated before send.

The clear driver uses the existing `sheets:cells:clear` scoped credential
operation and existing durable claim, signal, response custody and cleanup.
Update permission is not clear permission. A lost reply is not proof of
nonexecution: the same saved request and cleanup responsibility remain Unknown
after restart, with no automatic resend. External developer-metadata lookup and
revision-based reconciliation are not implemented by this extension; a marker
or an observed empty range alone does not settle an Unknown.

Clear keeps the same finite codec, rectangular cell, member, row, recovery and
physical request/response limits described above. In addition to the original
configuration and body, preparation retains one bounded marker and the small
metadata request; recovery retains the bounded marker list, JSON/hash workspace
and rebuilt original handles until the existing consumer releases them. No
new reservation, free workspace, numeric funding or GC release ACK is implied.
Pure catalog operations cannot cancel I/O; the physical callback forwards the
original signal through the existing credential owner and propagates failures.

`clear_wbtest.mbt`, `clear_request_wbtest.mbt`, `clear_declaration_wbtest.mbt`
and `test/sheets-clear-command.test.mjs` cover the independent body/CID,
declaration, nominal/copy, exact input, current target, ordered recovery and
acknowledgement refusals. `test/sheets-public-acceptance.fixture.mjs` drives the
real Source/Effect/Account/Checkpoint/SQLite/credential owners against a local
TLS Google-shaped fixture, including approval after Host reopen, postcommit
child attach and lost-reply nonresend. This is not live Google acceptance or
evidence that short Command input-key verification has completed. The existing
normal package and installed acceptance gates remain separate qualifications.

The existing provider catalog owns extensions to clear encoding, identity and
response classification; its typed Node bridge only transports original
handles. It adds no new execution, approval, claim or recovery owner. Google
references: [UpdateCellsRequest](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/request#UpdateCellsRequest)
and [developer metadata](https://developers.google.com/workspace/sheets/api/guides/metadata).

## Pure grid pages for the shared Reader

`site/sheets-grid-pages.mjs::prepareSheetsGridPages` captures the exact
spreadsheet ID, numeric rectangle, complete declared scalar columns, finite
codec limits and original portable provider methods/receiver. Its synchronous
callbacks encode the existing `getByDataFilter` request and project one complete
typed grid page. All declared cells are checked before downstream column
selection, preserving blank-row exclusion, duplicate rows, exact literal text,
formula results and refusal of error cells or foreign grid identity.

The fixed configuration is DATA; it does not issue an original Source request,
publication, Account decision, credential or grant. The synchronous projection
invoker belongs to the same Reader callback frame. Request/response/page bounds
remain the existing finite Sheets limits, not constructor or retained-workspace
funding. The callbacks do not send, charge, cancel, close, retry or acknowledge
physical release. Current checks, attempt/byte accounting, response custody,
stop and cleanup remain with the same shared Reader and Host owners. Any error
keeps its original cause through `SheetsGridPagesFailure`.

The installed loader's existing physical path is separate from these callbacks;
normal adoption requires its actual original Source, parent construction and
failed-child/output overlap backing. The callback API does not select a second
Reader, Ledger or cleanup engine and does not enable a partial normal path.
`test/sheets-grid-pages.test.mjs` checks callback capture, bounds and refusals;
`test/sheets-grid-pages.actual.test.mjs` consumes the actual portable provider
and independently authored Google-shaped grid fixtures. These selected tests
are registered in the existing remote-site runtime check, not a new CI lane.

## Typed tab metadata

`catalog/tabs.mbt` projects the documented `sheets.sheets` metadata columns
`id`, `title`, `index`, `row_count` and `column_count` under their original
spreadsheet binding. IDs and positions are nonnegative provider int32 values
admitted as logical Int64; titles preserve exact original text. Grid counts
are nullable Int64 because object tabs contain no grid. GRID and DATA_SOURCE
tabs require their actual grid extents; OBJECT tabs are retained with NULL
counts, rather than silently filtered out or assigned invented zero extents.
The API's absent sheetType has its declared GRID meaning. Missing identity,
title, position or required grid values, malformed numbers, duplicate IDs,
contradictory kind/grid data and foreign spreadsheet identity refuse the page.

Integer admission uses the original JSON number span, existing exact decimal
normalization and canonical scalar reader before the existing typed Value
recheck. It cannot turn a rounded binary64 placeholder into an ID or extent.
All five fields of every tab are checked and bounded before column selection.
The opaque page retains typed values, spreadsheet identity and the original
response digest. Its canonical rows use the existing Int64 wire encoding;
its schema uses the existing ValueContract emitter. Neither is a ResourceRef,
publication, grant or proof of a currently authorized physical read.

`site/sheets-tabs-pages.mjs::prepareSheetsTabsPages` supplies only synchronous
GET metadata request and complete typed row-wire callbacks. Original provider
methods/receiver, spreadsheet ID, full columns and finite limits are retained
before callbacks. The existing read operation is reused; no new permission
or Source request is issued. There is no I/O in the projection or callback
factory. Actual credential/current, attempts/body charge, retained response,
cancellation, stop and cleanup remain with the original shared Reader. An
error retains its original cause through `SheetsTabsPagesFailure`.

Raw body/decode workspace, typed rows, encoded row wire and the Reader's
physical response may overlap. Finite byte/node/row/value/output limits are
checks, not constructor, simultaneous-retention or failed-child funding.
The existing installed loader is unchanged. Normal adoption still requires
an original published Source, exact checked request, same-parent backing and
the existing Account/Host lifetime; this helper enables no partial normal path.

Google's [SheetProperties and GridProperties](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/sheets)
define stable nonnegative sheetId, tab kinds and object-tab grid absence.
The [spreadsheets.get](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/get)
field mask supplies metadata without grid cell data. Pure provider tests
retain independent complete rows and malformed-boundary expectations; Node
tests exercise the actual standalone provider and separate explicit ports.
