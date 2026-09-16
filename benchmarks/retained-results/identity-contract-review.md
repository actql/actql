# Identity boundary review — proposal, not an adopted semantic change

Inspected implementation: `86429b48`. This records the required contract review;
it does not declare main agreement or authorize omission of existing identities.
The registered experiment continues to require its original guarantees.

## Boundaries, beneficiaries and costs

| Boundary | Beneficiary and guarantee | Current mechanism and cost | Proposed decision for main |
| --- | --- | --- | --- |
| Acquisition observation | Replay/capture consumers identify the exact ordered observation, including duplicates and typed values | `docs/spec/execution.md` defines output `rows_cid` and native/scan receipts; validation and canonical hashing traverse the required values | Retain the current requirement for this experiment. Review any weaker observation contract separately, not as a transport optimization |
| Physical task completion | The receiving task needs the exact producer/attempt/output and satisfied execution obligations, not merely a matching hash | Common completion and owned input admission establish provenance; retained output also carries its canonical content receipt | Determine which internal consumers actually require content-addressed identity. A hash alone cannot prove execution; do not pre-approve CID-free completion |
| Same-Run reuse of a managed immutable representation | Consumers need an unchanged representation of the admitted producer, with live ownership and retention | `retained_producer_scan.mbt` re-decodes and canonical-hashes all stored columns for each receiving read, then checks its receipt | Reuse already established content evidence only while the exact representation generation and its managed immutability remain valid. This need not change CID definitions or omit the initial computation |
| Consumer-specific admission | The particular consumer needs its own demand, work/value budgets and join limits | `connectors/duckdb/compute/input_stream.mbt` attaches measurement, join validation and demand to the same scan | Keep these obligations. Separate them from reusable content verification; a previously valid producer is not proof that this consumer fits its budget |
| Physical storage/transfer | Storage and receiving implementations need intact bytes and a valid mapping to the logical result | File integrity and logical identity checks are separate, sometimes repeated | Keep physical integrity at the appropriate trust boundary. A physical file hash never substitutes for the logical CID; validate representation conversion, preferably during conversion |
| Published named Result | Delivery, audit and representation-independent comparison need the ordered logical Result identity | `docs/spec/protocols/artifacts.md` requires `logical_result_cid` in the closed Result Artifact, distinct from row payload | Preserve current publication contract unless main adopts an explicit change. Formal Result publication is not implemented by the physical-task benchmark |

These recommendations require a recorded main decision: **retain mandatory /
require under specified conditions / unnecessary**, with beneficiaries, value
and measured cost. Specification text identifies the current requirement, but
is not by itself its user-value justification. All decisions are currently
pending; this document is not a completed review.

## Existing coupling that must be separated safely

`runResidentFixedCompute()` calls `port.consumeInput()` even when it imports
zero rows. `append_retained_producer_scan_wire()` currently performs all of:

1. Exact input availability checks.
2. Full row decoding and value admission.
3. Canonical encoding/hash accumulation for the stored representation.
4. Projection onto the receiving input columns.
5. Consumer measurement and join-key collection.

`finish_retained_producer_scan()` compares owner, target, schema, CID, rows,
bytes and nodes, then finishes consumer guards. Skipping that call or returning
a cached Boolean would bypass consumer obligations. A replacement must keep
steps 1 and 5 and the consumer's demand checks, while accepting reusable evidence
for steps 2–3 only from the managed exact representation generation.

Evidence must bind producer/attempt, representation identity/generation,
schema/order/format, verification contract and discharged obligations, ownership,
liveness and retention. Same Run includes admitted execution-process delegation;
it does not mean every component must be in the same process. Path, inode or CID
equality alone does not establish immutability. Existing readmission remains
available for data outside this managed reuse scope.

## Additional requirements and failure handling

Known downstream requirements must propagate before retention or representation
choices become irreversible. Unknown later requirements undergo additional
admission of live material, authority, retention, budget and implementation.
Cancellation or failure of additional identity computation does not revoke the
original completion. Detected corruption or mismatched material instead revokes
use of that representation and reports a retention-integrity failure; these are
not ordinary additional-computation failures.

## Evidence still required

- Main's boundary-by-boundary agreement; no speculative CID omission.
- Measured validation, canonical encoding/hash, physical integrity and holding
  costs, with interval nesting and shared work identified.
- Positive reuse tests and negative generation/owner/attempt/corruption/expiry
  tests, plus unchanged consumer guard and budget failures.
- Any adopted semantic change: coordinated contracts, implementation,
  independent fixtures and a separately registered experiment.
