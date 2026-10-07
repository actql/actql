# Borrowed JSON Pick path execution

## Completion unit and integration

This dependent unit follows #717 -> #708 -> #704. Its final destination is
main after those parents are adopted. Main
`b5a3f9e18d8f87566a0a968771be4a83e7db43a5` was normally merged without
conflicts; current Graph contracts and submission-number preservation remain.

Source inspection found a complete `path.copy()` in `kernel_body()` before
JSON execution could resume. Local capability, obligation and provider
selection also used that defensive export merely to inspect the variant.
This is a metadata-copy boundary, not a newly demonstrated wrong result or
a measured public cancellation delay.

## Existing owner connection

`lowering_relation/json_pick_view.mbt` exposes opaque `PreparedJsonPick` with
typed column/output and indexed path count/segment readers. It borrows the
exact immutable prepared path without exporting its mutable array. The old
defensive `kernel_body()` export remains defensive: mutating its returned
path does not alter the read-only view or prepared kernel.

Local capability, obligation and selected-provider checks use the exact view
before any defensive body export. JSON start obtains that same view after
the existing owner/input checks. Its existing `PickJson` state machine reads
one path segment at a time; scalar name comparison, NULL short-circuit,
logical work and completion/cleanup remain unchanged. No evaluator,
scheduler, ledger, policy exception or compatibility fallback is introduced.
Other kernel body exports are not changed or claimed bounded by this unit.

The original prepared-view entry admission is preserved, including path
length plus two role entries. Logical admission is not a physical heap-byte
certificate. The state field `json_path` now points to an opaque view rather
than an owned Array; this representation change needs Native correspondence
review alongside the unmerged parent changes.

## Independent and normal-Program evidence

The lowering regression checks exact column, output, segment order and
negative/out-of-range index refusal, defensive export isolation and rejection
of an unrelated map kernel. No mutable path accessor is exported.

The execution fixture admits a 128-segment typed schema with explicit test
preparation limits; the installed Host policy is not increased. NULL demands
no object-field probes. Independent control is two row opens plus the
`payload`/`picked` bytes: 15 succeeds and 14 fails with `Rows(RowLimit)`.
The initial test fixture used the ordinary shallow metadata preparation
budget and failed during check, before execution. Its depth and binding
budgets were made explicit rather than changing product limits.

Four non-NULL segments each named 128 ASCII units followed by `😀é` require
four probe entries plus four times 134 UTF-8 bytes, with the same 15 base
units: 555 succeeds and 554 fails with `Rows(RowLimit)`. These independently
derived expectations are identical for quantum 1, 7 and 256. Stopping after
positive progress inside segment three retains charged work, yields no output
and cleans workspace once while keeping the borrowed input live. Pre-cancel
and repeated cleanup also preserve those guarantees.

`public-property-name-retention.test.mjs` sends a normal Values -> nested
JSON Pick -> derive -> select Program through Embedded Local and real
retained Store. A long Unicode interior segment and nullable source produce
fixed rows `(1, 7), (2, NULL)`. It reads all three explicit Named Results,
checks declared types, two consumers, request reuse, delivered post-progress
cancellation, no early stop/release or publication, no extra dispatch and
final Store reclamation. It does not claim that the public cancellation
barrier is inside segment three; the private owner test establishes that
specific phase boundary.

The JSON route requires work, later-segment stop and public roles. Removing
any required role is rejected by the focused evidence-gate regression.

## Verification and remaining boundaries

Working-tree JS passed 35/35 (`run-xdFXAh`, `focused-test-soFKL4`): lowering,
borrowed path and existing JSON/Watermark/Lag/order cases. The selected JS
runtime build passed (`run-xWybdh`) after connecting Local selection callers.
Public Host/checker tests passed 5/5 (`run-HhrBjo`, `focused-test-zfNuUl`),
including existing generated-metadata callers. These are implementation-tree
checks based on `bc0df3d69a2e2223d4436c3840478118ad23b4d1`, not clean-SHA
evidence. The PR records clean submitted-SHA results separately.

Selected `moon info --target js,wasm,native src/lowering_relation` reported
matching interfaces. Runtime assets, Node/Workers fixtures, resource and
differential inventories were checked; ignored bundles are not committed.

The existing reviewed-function extractor confirms `selected_relation_provider`
and its callbacks are byte-identical to #717. Only its support helper changes.
The complete source file hash still changes: G must review source/recipe
correspondence rather than treating unchanged constructors as a blanket
capacity proof or blindly refreshing pins. Native observers also need the
opaque path view represented honestly, not as the former owned Array.

Not run: full Core, Wasm/Native execution, Native capacity campaigns,
packed/HTTPS acceptance or performance. Draft CI is preparation only.
Remaining copied views for bindings/keys/projections, producer preparation,
availability scans, static managed-view analysis and projected-read ceiling
are separate; all-start and whole Local completion are not asserted.
