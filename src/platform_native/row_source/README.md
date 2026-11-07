# Native relation-file capture component

This package connects one actually observed Native file to the existing Common
RowAcquisition/RowRun owners. It is a component for trusted Host assembly, not an
installed Source or mock profile. It does not enable the CLI, select an Account,
issue a journal/permission decision, or establish full mock workflow support.

The caller supplies the original InstalledArenaHost and retained execution,
checks its own declaration/path authorization, and enters that same physical
execution before preparation or advancement. The component borrows only that
execution's original Ledger. It accepts no arbitrary Ledger or caller permission
callback. Caller-supplied declarations, acquisitions, strings and limits must
already be retained and funded by their original owners.

Preparation checks the declaration/requirement/acquisition originals, reserves
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

The quote retains the whole peak until final RowRun cleanup. It combines the
Common constructor inventories, a documented managed-control census, checked
path/buffer/diagnostic extents and the filesystem's actual compiled `sizeof`
facts, including observation and acquisition objects. It is a logical accounting
recipe, not a measured heap bound or a new funding/profile issuer. The original
Native domain independently enforces physical allocation.

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
caller totals are 222451, 23075950 and 296410702 logical bytes. The larger bound
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
