# Native relation-file capture component

## Target file I/O

`prepare_native_relation_file_target_io` retains one original physical child
for a selected record-file read or checked update. It borrows the prepared
provider's original declaration, contract and path, then admits the whole
received document before projecting a row. The returned snapshot contains the
complete canonical before-row and its original version. An update re-reads the
latest file under its same-path lock and uses Common's existing typed replacement
function. A stale row version refuses before staging or mutation.

The installing Host must supply original Account read authorization, the durable
Effect write claim, same-operation byte accounting and all constructor backing
before advancing this child. This low-level component supplies none of those.
Opening requires an entered original Native read context. Each chunk returns to
the caller before a separate projection step, with cumulative received bytes
still observable on failure. Submitted replacement bytes remain consumed if a
later write or directory sync fails. Such a failure keeps the same child and
never opens a retry entrance or reports a successful snapshot.

Ready means the selected I/O and projection completed, not that its physical
children retired. The caller must retain and close the same child before
retiring its operation and Native frame. Cleanup retires the original Writer,
Reader, lock and Root, including failed constructors, and then discards row,
target and raw-document originals. It never removes an already replaced target
or substitutes physical cleanup for a business outcome or Journal acknowledgement.

This package connects one actually observed Native file to the existing Common
RowAcquisition or whole-Source RowInputAcquisition/RowRun owners. It is a component for trusted Host assembly, not an
installed Source or mock profile. It does not enable the CLI, select an Account,
issue a journal/permission decision, or establish full mock workflow support.

The caller supplies the original InstalledArenaHost and retained execution,
checks its own declaration/path authorization, and enters that same physical
execution before preparation or advancement. The component borrows only that
execution's original Ledger. It accepts no arbitrary Ledger or caller permission
callback. Caller-supplied declarations, acquisitions, strings and limits must
already be retained and funded by their original owners.

Preparation checks the declaration/requirement/acquisition originals (or the
whole-Source acquisition's stored original declaration), reserves
metadata before copying paths or parsing mapping originals, and reserves the
complete transport/document overlap before opening the Root or receiving bytes.
The transport spends its original attempt before opening the Root, uses an actual
Root observation and Reader, and charges every received chunk once into the same
original cumulative ticket. Cancellation cannot refund a received prefix, and
zero-byte operations still consume their attempt. It verifies the same
observation after reading and closes the Reader before the Root. The completed
ticket must match the exact document length at admission; no chunk
ticket or copied byte count replaces that original. Common owns typed projection,
query execution, captured Source and the supplied original relation Read.
Whole Source input consumes the same response ticket before nominal/schema
checks and funds its real typed input through the existing RowRun owner. It
never fabricates a Query requirement, replaces the Native execution Ledger or
refunds received bytes. Listing uses its separate same-Plan entrance below.
Content and current Account authorization remain separate existing obligations;
the ordinary row entrance does not supply them.

Call `advance` with a positive quantum while the original execution is entered.
A completed `capture` borrows the same result, not a detached copy. A construction
or advancement failure retains its first issue and acquired owner for cleanup.
Retain that carrier and call `retry_cleanup`, or call the owner's `close`, under
the same normal or cleanup execution scope until cleanup acknowledges success.
Failed closes are not retirement acknowledgements. Captures and original Reads
become unavailable after close. Drop every escaped owner, failure, capture, Read
and Read-allocated diagnostic/usage alias before retiring the physical execution
and then its domain. A successful logical close alone does not retire those
physical aliases.

The default quote retains the whole declared peak until final RowRun cleanup.
An installed prepared provider may instead select received-byte construction
backing once at preparation. Transport buffers and all original page, work,
chunk and attempt guards remain unchanged. Before parsing a completed charged
response, this mode grows the SAME original reservation to the complete
simultaneous constructor extent. A failed grow refuses admission; received work
is not refunded and prior Source outputs remain retained. The response length
is measured from the original charged Bytes, never an announced length.

Raw parser backing uses that measured length. Parser/index arrays grow from
observed tokens, so received bytes also bound their node/container count. Typed projection keeps its full
declared envelope except for closed Text-only rows, whose cumulative text bound
uses the canonical NFC output inventory and JSON escaping bound, plus the
received-node bound and the whole declared field frontier. Original policy
guards remain at parsing and projection. Listing output
writers retain their full original allowance. Numeric, reference and nested
Contracts do not acquire a byte-length projection shortcut. The successful grown
peak remains held through the same final cleanup.

The quote combines the
Common constructor inventories, a documented managed-control census, checked
path/buffer/diagnostic extents and the filesystem's actual compiled `sizeof`
facts, including observation and acquisition objects. It is a logical accounting
recipe, not a measured heap bound or a new funding/profile issuer. The original
Native domain independently enforces physical allocation.

## Keyed file Content DATA

`project_native_relation_file_content_bytes` consumes an admitted original
physical document and the Source's selected file roles. The Source must resolve
the keyed request's nominal ResourceRef to its original identity first. The
projection checks the same full-row version definition as listing, measures
UTF-8 length before allocating the returned bytes, and preserves Unicode, line
endings and empty content. A reused authored version label cannot conceal a
changed row. Temporary typed row/document projections retire on either outcome;
the original response and returned bytes stay in their caller's custody.

The companion construction inventory counts this projection, before-wire and
version writers, control carriers and output buffer. Raw response, physical
Reader, Store construction and failed-child overlap require their separate
same-parent backing. This entry supplies no ContentRef, Store persistence,
keyed-request completion, authorization or physical cleanup acknowledgement.
Only the existing checked capture/Store/ReferenceIssuer connection may turn the
returned DATA into an admitted ContentRef.

## Original keyed Content Store connection

The keyed capture entrance may retain one `NativeRelationFileContentInput`
containing the original keyed acquisition, request, compiled Run and publication
Definition, Store and Source role selection. Its pure correspondence check
compares those original objects without another current callback. A copied
selection or equal-looking request cannot replace them.

The same file-capture owner resolves the nominal Resource, reads its actual
file, projects content bytes and version, and retains the Store child before
persistence. Only the Store's original persist/confirm sequence permits the
run-bound issuer to return a nominal ContentRef. The returned keyed page carries
that reference, not a synthetic String. Original row response admission still
checks the same request and cumulative charged ticket. This path supplies no
Account, provider permission, Model result or Effect write authority.

The original metadata reservation covers simultaneous file parsing, content
projection, Store construction, confirmation and reference/page output. Before
the Store child exists, its constructor is not pre-reserved as a retained child.
After the original candidate exists, the Source grows that SAME byte-only token
to cover the actual Store record and all simultaneous Source/Content backing,
then prepares and retains the child before any I/O. This creates no send attempt
or transfer allowance, and returns no earlier backing as phase credit. Failure and
reentrant close retain the actual Store/reader children. Close returns their
original duties before settling the token; logical completion is not physical
cleanup. The installing caller remains responsible for retiring escaped aliases,
leaving the actual Native execution frame, and then retiring the SAME Run.

## Caller preparation inventory

`native_relation_file_caller_preparation_inventory` describes the allocations
before Source's metadata token exists: one original mapping construction, its
quote evaluators, bounded Contract walks, validation and refusal carriers. It
uses the exact selection and page limits. It excludes the later Source-owned
mapping, transport and retained payload, and excludes the caller's arena borrow
and Resource reservation constructors. Those have separate owners.

The companion evaluation inventory describes the query's own construction,
which must be funded before evaluating that query. Neither function issues
capacity, authorization or an installation original. For the accepted minimum,
the diagnostic page (8192 bytes, 512 nodes, depth 8, two rows, one path item),
and the maximum accepted page/path shape, the independently authored full
caller totals are 222539, 23076038 and 296410790 logical bytes. The larger bound
does not imply that any installed envelope can admit it.

## Explicit scoped diagnostic

`capture_physical_scoped_wbtest.mbt` requires a selected scoped Native runtime and
the externally prepared `ACTQL_TEST_INSTALLED_PROCESS_ROOT` fixture directory.
The scoped-test namespace owner exclusively creates the directory with mode 0700
and four files with mode 0600 before the test process:

- `row-source-input`: the exact 62-byte two-row JSON document.
- `row-source-malformed`: the exact 10-byte malformed JSON document.
- `row-source-oversized`: an 8193-byte file.
- `row-source-backing`: the original 384 MiB backing file.

The test only opens the existing backing and reads the selected input files. It
owns and closes the actual backing FD and physical owners. The external namespace
owner removes the files afterward; no fixture-creation FFI is added to the product.
The authored diagnostic uses a 256 MiB child domain, 96 MiB retained allowance and
128 MiB execution allowance. These are explicit test bounds, not an installed
profile or default capacity. Before opening the backing, the fixture prints the
exact existing metadata, acquisition, provider and page-scratch logical quotes
for all three input geometries, using checked sums. It refuses before physical
acquisition if those quotes exceed the authored allowances. The capacity test
also emits the same quote without reading a Source or creating a physical owner.
A printed quote is not a reservation or runtime success evidence.

The observed Native quote for the `/tmp` selection was 22,720,246 metadata bytes,
26,404,096 acquisition retained bytes / 41,404,096 acquisition execution bytes,
31,025,714 provider bytes, and 8192 execution scratch bytes. The complete totals
were 80,150,056 retained bytes and 95,158,248 execution bytes. The authored
96 MiB / 128 MiB allowances cover these separate dimensions; their combined
224 MiB remains below the 256 MiB physical child. The full path-dependent
preflight remains authoritative for each actual fixture directory. These numbers
justify only this finite test geometry, not any product quote reduction or
normal-profile selection.

The response page ceiling is 8192 bytes / 512 nodes / depth 8 / 2 rows, with
7-byte reads and 128-byte diagnostic detail. The mapping admission also parses
declaration originals under those page bounds. The actual positive file is
62 bytes and contains two original rows; the query captures one. A malformed
10-byte file exercises charged failure and retained cleanup. A fourth attempt
reads one seven-byte prefix then cancels, retaining its transfer charge without
publishing a capture. The successful attempt also checks its full charge before
document admission. The fixture also
checks original identity rejection, unavailable scope, an oversized file, and
capture invalidation. Changed-generation races and injected uncertain OS close
outcomes are not covered by this component fixture.

## Same Request managed input

`prepare_native_managed_relation_file_input_capture` consumes the original
`ClientInstalledSourceRead`, whole-input capacity and provider retained by the
same checked Request Plan. It starts that read's existing RowRun once, requiring
the exact physical Ledger before consuming the start slot. Provider amounts or
equal declaration bytes do not substitute for these originals. The separate
`native_relation_file_provider_capacity` query supplies immutable geometry
before Plan construction; it grants neither backing nor permission.

The managed fixture prepares immutable installation contracts outside the
payload, checks and compiles the Program once on its real backed Request, and
constructs logical Request identity and long-lived Run controls in the outer
caller lifetime. Actual Source file access and child cleanup occur only in the
same entered Native payload. Final parent accounting and physical retirement
remain distinct. This fixture does not supply normal Host first-entry backing,
Account/Journal permission, installed Source/Content/Model/Effect configuration,
approval, Result publication or Saved acceptance.

Stopping the existing Compute DAG drops only its cached supplied Read gates.
Those gates close over the DAG and otherwise root a reciprocal allocation after
stop. Active implementations retain their own admitted inputs and cleanup duties.
After actual read cleanup the managed Run drops its cached read slots, rather
than merely clearing array length. A completed Resource retirement drops its
now-unneeded capacity callback only after the original retirement returns true;
pending/failure and physical ACK remain with their original owners.

A normal declared-file caller can prepare `NativeRelationFilePreparedProvider`
once under its original metadata scope. Its opaque Common prepared contract,
selection snapshot and exact immutable capacity accompany the same managed
Plan. At read time, `prepared_provider` checks those original correspondences
and reuses the checked contract and quote. It does not create a Ledger or an
Account/read grant. Mutable input path arrays cannot replace the retained
snapshot. Public limit records are immutable DATA compared by quantity, while
the managed Plan still requires the same capacity original.

The independent component entrance retains its original 64 KiB envelope. A
managed caller supplies and funds its selected implementation profile instead;
that component envelope is not another normal Source acceptance policy. The
file owner checks the observed generation against the selected ceiling and
allocates the receive backing for that generation's actual size. It charges
only actual chunks once and checks the exact generation/extent through EOF.
No support maximum is itself an observed file size or physical-release ACK.

## Declared file listing projection

`project_native_relation_file_listing_page` converts one original admitted
physical document using the same prepared provider's schema and field roles.
It asks the original Source to issue each observed identity's ResourceRef;
neither physical rows nor this converter supply reference authority. It requires
live nominal file references and fences document/row liveness after issuance.
The bounded writer emits only the public listing fields and terminal page
tokens. It never exposes inline physical content as a synthetic ContentRef.
Versions bind the declared label to the original complete typed row digest,
using the same canonical two-field preimage as the declared Node file supplier.
The fixed 113-byte preimage expansion is distinct from the raw-body limit.

The caller composes `native_relation_file_listing_construction_inventory` with
its same-parent original document/provider and Source-issuer inventory BEFORE
construction. The additional quote covers typed projection, co-held page and
row writers, row/version hashes, closed reference emission, one live row and
returned UTF8 bytes. It is quantity DATA, not a reservation or a physical bound.
Every temporary row mark and projection mark is cut on success or refusal;
the caller's raw document, response ticket, references and physical children
retain their original duties. A converter result is not a completed listing.

`prepare_native_relation_file_listing_provider` retains the public listing
declaration, separate physical provider, checked field roles and original
Source issuer/method. Construction invokes neither issuance nor currentness.
Its quote composes raw admission, one physical typed projection, listing
construction and transport. It does not add the ordinary provider quote again
and double-charge that same projection. The actual installing owner funds this
record and quote construction before calling it and retains the original issuer
and known-resource inventory through every later borrower.

`prepare_native_managed_relation_file_listing_capture` requires this SAME
Plan-held capacity and listing read on the original Native Ledger. It starts
the original listing request, reads and charges physical chunks once, converts
the admitted original document and consumes that SAME physical-body ticket
through the existing resumable Core listing protocol. It never charges the
derived envelope as another physical response or manufactures a Query/RowRun.
Issuer refusal retains its original Result; after successful issuance the
original read/current fence runs before continued work. Existing partial-child,
sticky-failure and child-first retirement duties stay with the file owner.

The caller drives `advance_listing` with elapsed milliseconds from its original
Host monotonic clock, whose initial observation precedes preparation. Negative
elapsed values and use of untimed `advance` refuse rather than silently report
zero elapsed time. Core owns completion and duration/monotonicity checks; the
adapter does not issue another clock or permission. Ordinary capture retains
its original untimed `advance` behavior and still refuses listing acquisitions.

The physical listing fixture exercises the real file, SAME Request/Plan/Ledger,
original 242-byte ticket, two nominal rows, DAG binding and original Source,
execution/domain/arena retirement. Its issuer and elapsed values are explicit
component inputs, not a normal Account or Host-clock qualification. This does
not enable the CLI mock profile, capture Content, run a Model, approve an Effect
or qualify Saved. Those existing full-workflow obligations remain open.


## Correlated Content read

`prepare_native_managed_relation_file_keyed_capture` consumes the original
managed keyed read/acquisition on the same Native execution Ledger. Its existing
capture owner reserves raw physical provider/decoder backing beside its metadata
before starting I/O; the keyed RowRun separately owns its checked response.
The original request attempt is debited before opening a file, including empty
and failed reads. Received chunks extend one original page ticket.

At `ContentReady`, `keyed_content_document` borrows the same admitted raw
physical document. The installing Source resolves its original nominal Resource
and version, funds exact-byte projection and Store custody, then verifies the
stored original before issuing its ContentRef. `complete_keyed_content_page`
requires that same document and continues the existing keyed RowRun with its
original issuer. Core admits the typed page/cardinality and retains the completed
keyed capture; derived reference wire is not charged as another physical read.
These ports do not supply the Source's missing constructor backing or issuer.

Keyed construction and retirement share one start-state word. A reentrant close
cannot acknowledge an unfinished constructor; the actual returned child is
retained before normal work or later cleanup. Entry checks the original current
parent, and internal post-callback handoffs use retained identity/state fences
instead of repeating that external current observation. Source/Store failure
keeps the original capture for child-first cleanup and never reacquires a request.

Completed automatic keyed Content retains the same RowRun, Store custody and
nominal ContentRef. In a later advance frame, after original Reader/Root, raw
document and keyed-page constructors have retired, the capture drops finished
local selection/provider/parser aliases and contracts both byte extents of its
SAME capacity reservation to the retained inventory. Common reference backing
remains until the Model input receipt; checked rows keep their own RowRun
reservation. Work/attempt/transfer history and durable Store quota are unchanged.
An unresolved child or failed contraction retains the original cleanup owner.


## Original lookup raw custody

The installed Native caller binds its original Host retention with
`bind_lookup_raw_retention` before the capture opens a file. After EOF and the
original generation/byte-ticket checks, this SAME capture retains the actual
raw Bytes and their digest. The `RawResponse` continuation runs before physical
JSON document admission, Content extraction or typed page admission.

`prepare_client_keyed_native_raw_response` reads the activation retained by the
SAME selected request, its checked response data policy and original Request
scope. It preserves the supplied retention's custody/time bounds, derives the
Source-specific effective retention envelope, and binds byte identity, call
slot, first attempt and original issuer. It does not acknowledge an attempt,
Journal entry, successful response or adopted page. Closed metadata and its
holding name are funded by the existing lookup reservation before construction.

The Source grows its own original capacity reservation for the existing
`CapturedContentCustody` raw alternative before creating the Store child,
retains that child before persistence, verifies exact bytes and retires its
I/O before returning to document admission. Later Content construction includes
the co-held raw Store inventory; constructor retirement retains both actual
Store children and original raw bytes. No disk quota supplies this live backing.

Failed persistence/confirmation keeps the original child on this Source and
cannot produce a page or retry with another Request. Close reconciles the same
Store, retires both children and only then cuts raw metadata/retention/byte
aliases. The CLI stops lookup assembly without returning its reservation,
closes the original Source children, then reclaims lookup/prefix backing. A
borrowed `keyed_raw_response` is metadata of confirmed Store custody only; it is
not a page-adoption/event receipt, Result Artifact or renewed read permission.
