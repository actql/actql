# Sheets provider interface

## Declaration and configuration

`host/installed-sheets.mjs` supplies an explicit installation profile, published
generation, Site binding and ordinary Source/Effect adapters. A missing profile,
changed publication, unavailable credential or unknown operation is not a grant.
Its static Source/Mapping declarations enter the existing Common declaration
owner. Dynamic range Command/Catalog interpretation is in
`src/connectors/sheets/catalog/range_declaration.mbt`. Common remains responsible
for checking all resulting contracts and their dependencies.

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
