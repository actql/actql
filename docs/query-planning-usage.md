# Query strategy experiment

The source-checkout `query_planning` package compares and computes the two initial
mock query realizations. It issues process-local mock records, captures a complete
observation and binds its immutable output to a checked local consumer. It does
not dispatch a real Connector, publicly publish a Result or construct a runnable
Program/Plan.

The initial derivation accepts only a checkpoint-free selected snapshot mode.
A checkpoint on that mode returns `UnsupportedShape`, whether the mode was
selected explicitly or by default. A checkpoint on an unselected mode does not
exclude an otherwise supported snapshot. This experiment does not retain or
advance checkpoints.

Use `program_identity_stage_requests(identity, stage_index)` to obtain the
Program's existing owned requests for shared derivation; do not reconstruct
equal requests as a substitute for their owner.

1. Obtain `execution_query.QuerySequence` from the shared query derivation and
   matching checked/lowered preparation. See [local usage](local-compute-usage.md).
2. Call `offer_mock_query` with `NativeQuery` or `BroadWithResidual`. Obtain cost
   slot meanings with `query_work_count` and `query_work_at`.
3. Supply serial estimate lines covering those slots, and separate optional
   transfer/retention bytes and money quantities. These are estimates, not limits.
4. Call `choose_query_strategy` for offers owned by that exact preparation.
   `Deferred` requires more information or explicit Host priority. `Proposed`
   contains a physical proposal whose runtime requirements are still pending.
5. For the local fixture only, use `prepare_mock_query_attempt` with the immutable
   source cursors and a preparation entry bound. Call `execute_mock_query` once
   with separate source, receipt and local computation limits.

The native route computes before receiving selected rows; the broad route applies
receipt limits before the local residual. Both validate the entire supplied source
under the shared checked semantics. A successful `MockQueryComputation` exposes
source/receipt/output counts but no consumer input handle. `mock_query_computation`
reports `NotComputed` before execution and retains typed failures afterward.
`cancel_mock_query` can withdraw an unstarted or awaiting-capture attempt. Use a
new attempt for a retry; it does not implicitly reread or choose another route.

Query adapter functions and types below belong to `execution_query`; candidate,
attempt and capture functions belong to `query_planning`. The engine's former
query API locations are removed rather than retained as forwarding wrappers.

For integrations needing full-scan material after computation,
`admit_query_receipt` returns an immutable, preparation-owned `QueryReceipt` and
`execute_query_receipt` runs it with a fresh computation budget. The convenience
`evaluate_query_receipt` composes these operations. `query_receipt_rows` exposes
only immutable admitted material, not capture evidence; passing the receipt to
a different preparation is rejected. The mock retains the complete admitted
scan even on the native route, so receipt savings do not imply retention savings.

Use `execution_relation.identify_captured_rows(query_receipt_rows(receipt), limits)`
or `execution_relation.identify_completed_rows(output, limits)` to compute canonical
ordered-row CIDs directly from immutable material under engine `RowWireLimits`.
`row_wire_usage` returns canonical wire bytes, value nodes and row count.
`row_wire_matches_captured` / `row_wire_matches_output` check the exact retained
handle, not just equal content. These APIs support capture verification but do
not themselves issue records or authorize capture. A bytes/node/depth/order
limit failure returns no identity and does not consume the retained input.

Selection needs one candidate entry plus the common helper's duration/preference
entries: two offers require four entries without priority and six with a two-item
priority. Offer estimation separately budgets its work inventory, line count and
slot references before traversing them. Missing retention or other work makes
the estimate unknown. Duplicate transfer coverage is rejected.

Observation capture consumes verified process evidence before this experiment
can return a completed acquisition to a consumer. Input
relative order is not total-order evidence; this profile requires null source
order CID. Existing performance regressions remain accepted development debt,
not a passed performance gate. No performance improvement is claimed here.

`admit_query_evidence_contracts` accepts the admitted immutable canonical bodies
of the Acquisition and process-evidence contracts, and checks their actual hashes
under one aggregate `QueryEvidenceLimits` budget. It rejects schema-only or
digest-only substitutes. `query_evidence_contract_usage` reports hashed bytes
and nodes. This is verifier-contract selection, not permission to issue records
or execute the proposed strategy. `check:docs` also verifies that the filesystem-free test
copies match the current complete shared contract bodies.

See [design](design/query-physical-strategy.md) for ownership, scope and limitations.

`prepare_query_material` builds the resolved request and request/filter/used-value
CIDs from that same `QuerySequence`, under `QueryMaterialLimits`. Read them with
`query_material_request`, `query_material_cids`, and `query_material_usage` (work,
encoded/hashed bytes, nodes). Request encoding and hashing both consume the
aggregate allowance. The owner remains available through `query_material_owner`.
These are static requirement components, not a complete requirement, Program
identity, capture record or observation. Preparing them performs no source I/O
and does not evaluate the predicate.

`prepare_query_requirement(material, program_identity, guards, limits)` binds
those components to the main-owned `ProgramSourceIdentity`. The identity must
retain the exact stage request owner used by the query, not merely the same
Definition CID. `query_requirement_document` and `query_requirement_cid` expose
the canonical shared requirement; `query_requirement_usage` reports this call's
work/bytes/nodes separately from material preparation. Read-only helpers expose
its material, Program owner, guards, source, field-map contract CIDs and authored
stage/input site. This Local profile supports nonnegative machine-Int guard
values. They are requirements to enforce, not completed runtime checks.
Program source identity, requirement construction and final Program/Plan execution
permission remain distinct; no capture or consumer input is released by this API.

When starting from a Program, use main's public `program_check.check` and obtain
its `program_check.source_identity`. Derive the query from that identity's owned
stage requests, lower the same pipeline and bind its exact Parameter values.
Pass this identity to `prepare_query_requirement`; do not substitute a separately
checked equal Program. The executable source-checkout example is
`src/query_integration/query_checked_program_wbtest.mbt`. It exercises both mock
routes through capture and the existing consumer. Main's static source execution
inventory is retained; real Host authorization and Program/Run execution are not
implemented by the mock setup.

For requirement-bound computation, use `prepare_requirement_mock_query_attempt`
with a strategy owned by the requirement's exact query preparation. Pass
`guard_measure=Some(QueryGuardMeasureLimits)` to `execute_mock_query`.
Omitting it returns `GuardLimitsRequired` without starting the attempt. Guard
failure after execution starts fails that attempt and provides no successful
computation/capture. The older unbound mock constructor remains a diagnostic
computation path; it is not proof that a canonical requirement was enforced.

The adapter's `execution_query.execute_query_receipt_guarded` accepts retained scan material,
the existing computation limits, explicit output-row/per-value guards and
physical measurement limits. It returns a completed computation plus physical
measurement usage `(work, bytes, nodes)`. These counters span input and output;
they do not reset per row. This operation adds no source access, authority or
capture evidence and preserves the same reusable preparation and immutable input.
It delegates measurement, demanded-root ceilings and execution to the engine's
`execute_fixed_input_guarded`; mutable ledgers, storage and contexts are not
package APIs. `query_sequence_owner` supplies the exact lowering owner when
constructing a checked downstream consumer, without inspecting private fields.

After requirement-bound computation, `retain_mock_query(attempt, limits)` checks
actual receipt and full-scan-plus-output wire quantities under
`MockRetentionLimits`. Its measurement bytes/nodes span both hashes; column-order
and depth allowances apply per artifact. Read `(received_wire_bytes,
retained_wire_bytes, measured_nodes)` with `mock_retention_usage`, or scan/output
row CIDs with `mock_retention_row_cids`. These are not allocator bytes, RSS or
logical-budget discounts; existing source/driver limits still apply.

This transition is one-shot and precedes capture. A retention-limit failure fails
the attempt; cancelled, unbound or already-retained attempts cannot reenter it.
No output handle is exposed, and retaining this opaque value does not authorize
capture after the attempt is cancelled. Live issuer verification and final
consumer admission remain separate steps.

For live mock records, the trusted Host first calls `prepare_mock_query_issuer`
with the admitted contracts, exact requirement and a fresh process nonce (bounded
in UTF-16 code units). The Host must not reuse that nonce across process lifetimes.
Use `prepare_issued_mock_query_attempt` instead of adding authority after execution.
Issuer/attempt suffixes are allocated internally, never by an offer. This is
trusted mock setup, not real provider authorization.

`mock_query_attempt_identity` exposes the allocated issuer/attempt names for
diagnostics before execution. These names are not authority, completed evidence,
or a prediction of the output CID; capture still requires the live opaque handles.

Run guarded computation and retention as above, then `issue_mock_query_records`.
`mock_query_record_at` exposes diagnostic document/CID pairs for indices
0/1/2 (source validation/filter/select); `mock_query_record_usage` reports aggregate
serialized/hashed bytes and nodes including scope hashes. All three are issued
atomically. Use `verify_mock_query_records` with the expected Host issuer and
attempt, not values taken from record JSON. Foreign attempts, cancellation and
`close_mock_query_issuer` invalidate this pre-capture verification. There is no
record deserialization authority at this stage.

Call `capture_mock_query(issuer, attempt, records, limits)` to construct the
completed process observation. These artifact byte/node limits include previous
scope/record work as well as request-CID verification and observation encoding
and hashing. Read the immutable document, CID and cumulative usage with
`mock_query_observation_document`, `mock_query_observation_cid` and
`mock_query_observation_usage`. A second capture is rejected; successful capture
is no longer cancellable as pending acquisition.

Use `bind_captured_query_input` with that exact issuer/attempt/observation, the
checked receiver/input index and expected bound producer. The returned existing
`BoundProducerInput` feeds `prepare_local_compute_attempt`; its ordinary driver
enforces receiver projection, ownership and resource limits. A failed consumer
may be retried with a fresh compute attempt and budget using the same capture,
without another source read. Hold the observation for its process-local evidence
lifetime. No durable capture, Run admission or public Result publication is implied.

### Representation and conformance scope

The supplied finite mock source and its execution use the default row path.
There is no mock option that promises an end-to-end columnar acquisition.
The shared value guard and canonical row hash operate on the existing layout
reader, including typed numeric columns and selection views. Repeated selected
rows count repeatedly; NULL and work/byte/node failure frontiers do not depend
on whether those values came from row storage or a typed view. Typed completion
and receiver projection use the existing completed-input boundary.

The independent observation oracle exercises both mock routes through the public
CheckedProgram entry, capture and a checked consumer with empty, filtered-out,
duplicate and nullable input. It checks complete observation content and the
three record identities, not just final rows. This is mock conformance evidence,
not external-provider attestation or proof of a general vectorized executor.

The multi-column fixture keeps `amount` outside `filter(id > $minimum)` and
`select(["id"])`. Native receipt evidence lists only `id`; broad receipt evidence
lists `amount,id` and hashes the full received rows. Changing only `amount` leaves
the final output and native access scope unchanged, but changes broad access
scope. The full-known-scan profile still validates unused values: permitted NULL
succeeds, while type/nullability violations and per-value guard overflow fail
before issuance and capture, including rows the filter would discard.
