# Physical accounting boundaries

This audit describes the measurement implementation, not a new language limit.
The pinned logical work, value bytes and live-root contracts remain unchanged.
All column layouts are private white-box experiment code; product execution still
uses row tables.

## Units and ownership

| Measurement | What it counts | What it does not establish |
| --- | --- | --- |
| Process peak RSS | Peak of the fresh runtime process, including warmup, fixtures and observation | Memory of an individual operation or phase |
| Retained table entries | The common store's bounded structural entries | Unique heap objects or bytes; shared entries can appear in multiple logical tables |
| Owned buffer slots | Live source row/cell slots, generic column slots and composed selection slots, once per registered physical buffer | Allocator metadata, nested immutable payload bytes or the entire heap |
| Owned typed bytes | Numeric capacity times nine, boolean capacity times two, including one validity byte per cell | Actual runtime representation size on JS, or allocator headers |
| Construction budget | Conservative cumulative structural/typed capacity reservations and control work | Number of allocator calls, copied payload bytes or live RSS |
| Logical value budgets | Contract-defined value occurrences, nested sizes and work | Unique physical objects after sharing |

The units must not be added as if all were bytes. In particular, an A-side null
owned-buffer metric means that the row backend does not use that instrument; it
does not mean that rows occupy zero memory. C uses numeric arrays in the JS
backend, not an asserted `Float64Array` representation.

## Enforced lifetime boundaries

The following files are under `src/execution_relation/`.

| Boundary | Implementation and independent regression coverage |
| --- | --- |
| Charge before construction | `layout_leases_wbtest.mbt`: a rejected allocation never calls its builder; release clears the actual strong reference |
| Shared column lifetime | `layout_owned_columns_wbtest.mbt`: projection retains a shared buffer until its final owner disappears, without duplicating its capacity charge |
| Conversion overlap | `layout_capture_owner_wbtest.mbt`: capture row/cell storage remains charged while destination columns are constructed; exact limit succeeds and one below fails |
| Producer ownership | `layout_producer_owner_wbtest.mbt`: a real completed producer remains retained during import; importing is not evidence of permission to release the producer |
| View composition | `layout_owned_columns_wbtest.mbt`: old and new occurrence buffers coexist during composition; selection depth does not grow with the view chain |
| Failure cleanup | `layout_store_leases_wbtest.mbt`: operation/commit failure releases newly owned buffers even with exhausted work, while retained branches remain valid |
| Small result, large backing | `layout_additional_profile_wbtest.mbt` and the nested fixture: taking one row does not pretend that all backing payload has been freed |
| Prepared input reuse | `layout_input_snapshot_wbtest.mbt`: immutable buffers survive repeated invocations, but each invocation gets fresh admission and capacity budgets; released pins cannot be revived |

For prepared-input measurements, the original ledger holds the physical input
buffers. Each new invocation reserves an existing-capacity floor for those same
buffers. Summing both ledgers would double-count physical allocation. Source
captures and producer completions are separate owners and must still be included.

## Temporary storage and conservative limits

The common row kernels use `RowWorkspace` for structural scratch and separate
value/control budgets for expression traversal, comparisons and nested values.
The column builder additionally precharges full destination capacity before
constructing buffers. A capture-to-column import uses one row scratch at a time;
its cumulative construction budget charges each scratch occurrence, not merely
the final output. Selection construction charges the new index buffer while the
old selection remains live, and failure rolls back only newly acquired owners.

These independent bounds do not constitute a single allocator-level live-byte
limit. They cover different scopes and include conservative charges for borrowed
or repeatedly used entries. The owned-buffer ledger alone must never be advertised
as covering every temporary array, canonicalization allocation or nested object.

## Interpretation of traffic metrics

Capacity reservations are not allocator-call counts. Registering an existing
capture or attaching a prepared buffer creates an ownership record without
allocating the underlying cells again. Conversely, a typed column construction
creates both a values buffer and a validity buffer. A sharing operation creates
handles but copies no cell payload. Selection composition copies row indices,
not the retained row payload.

Allocation and copy diagnostics must distinguish these events, and must remain
separate from the timing samples. An allocator-wide count is not available from
the existing capacity counters. Do not infer one from `work`, ledger owner counts
or differences between RSS peaks. This limitation cannot be turned into a claimed
memory win or used to waive the fixed end-to-end adoption conditions.
