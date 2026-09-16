# Identity boundary review — existing contract and new profile

## Latest approved direction — 2026-09-16

The user's subsequent decision supersedes the universal no-omission wording of
the earlier main answer below: **preserve the existing contract, and make logical
content identity conditional in a new profile**. This is an approved direction,
not merely a proposal to reconsider CID requirements. It is not permission to
omit mandatory fields while claiming the existing contract.

The local main checkout inspected for this update remains `3820ea11`. The new
profile's normative identifier, boundary-specific requirements, wire/pins and
independent fixtures have not been identified in that checkout. Consequently,
shared-contract integration and new-profile execution remain unfinished; this
record does not invent a profile identifier or change a canonical preimage.

| Track | Decision | Remaining work |
| --- | --- | --- |
| Existing contract | Keep required observation and published Result identities; improve physical paths and reuse valid evidence | Product evidence reuse, direct output, conformance and formal measurements |
| New profile | Require logical content CID only under the agreed applicable obligations | Main-owned normative contract, implementation, independent fixtures and separately registered measurements |
| Existing experiment | Preserve all 27 cases, 21 large direct-path targets, 1 GiB and registered performance criteria | Independent equivalent-obligation comparison and formal acceptance; new-profile timings cannot substitute |

The main shared-contract handoff must specify:

1. The profile identifier and explicit selection/admission rules, and exactly
   which acquisition, internal completion and publication boundaries require
   which identity. Existing profiles retain their guarantees.
2. Required versus unestablished logical identity representation, consumer
   permissions, and later identity requests via additional admission. No dummy
   CID or physical digest may stand in for logical content identity.
3. The applicable semantic/execution contract, consumer/publication requirements,
   Host policy and additional user requirements that determine the obligation
   set before candidate comparison. The planner cannot lower that set.
4. Normative prose, affected machine contracts and pins, compatibility rules and
   independent positive/negative fixtures. Canonical preimages for identities
   that are computed remain explicit and distinct from execution provenance.

Physical-path work under the existing contract continues in parallel. Reusing
an already computed CID does not implement conditional CID in the new profile.
Report contract integration, physical-path conformance and performance acceptance
separately. New-profile implementation is not complete until the adopted shared
contract, implementation, fixtures and separate measurements are connected.

## Earlier main answer — applicable to the existing contract

Initial implementation inspection: `86429b48`. On 2026-09-16 the user relayed
main's contract answer, following the checker integration at `3820ea11`.
The agreement below records that answer, not an independently rerun main audit.
That answer authorized no omission of mandatory identities. The registered experiment
continues to require its original guarantees. Implementation, independent
fixtures and measured cost attribution remain separate unfinished work.

### Existing-contract decision and exact identity domains

- Acquisition observation: retain mandatory content identities and the distinct
  observation/access/evidence associations used by fixed-observation consumers.
- Internal task completion: content identity is conditional on the applicable
  capture/publication/persistence/consumer contract, not a new universal hashing
  requirement for every task. Exact producer, attempt, input, output, ownership
  and holding still determine execution completion.
- Published Result: retain mandatory `logical_result_cid` for ordered logical
  equality, artifact verification and delivery correspondence.

Do not conflate their canonical preimages:

| Identity | Preimage / authoritative reference |
| --- | --- |
| `received_rows_cid`, output `rows_cid` | Canonical JSON UTF-8 of the ordered typed-wire row array; `docs/spec/execution.md`, acquisition output/receipts |
| Relation logical Result CID | `computeCid({sort: "relation", value: canonical_rows})`; `docs/spec/protocols/artifacts.md`, Relation value/ResultArtifact |
| Observation CID | Completed observation, including actual access, coverage and snapshot; `actql-query-acquisition.json:/schemas/completed_observation` |
| Process evidence CID | Record including requirement, issuer, attempt, role and output; `actql-query-process-evidence.json:/schemas/record` |
| Two-receipt associations | `actql-query-two-receipt.json:/schemas/receipt`, `/schemas/record`, `/schemas/completed_observation` |

Equal row content never equates observations, attempts, authorization or actual
access evidence. Sharing the content hash for identical native receipt/output
rows does not collapse their roles or receipts.

Main permits reuse of an already accepted owned validation/identity handle only
when a trusted issuer actually completed validation and identity generation,
and it binds the exact material/generation, owner, managed immutability, holding,
contract pin, schema, canonical representation, order and validation scope.
The retained result must cover this consumer's requirements. Same Run, matching
paths, inode numbers, digests or caller assertions alone are insufficient.

Consumer guards, demand, selected capacity, authorization, input binding and
current liveness/holding remain checked. Logical rows/value quantities/work are
charged per consumer even when physical scans or hash computations are avoided.
Completion admission's explicit `resolved_request_cid` recomputation remains
mandatory; reading an accepted observation is not admitting a new completion.

Material/generation changes, lost holding, incompatible contract/scope and
unverified transfer/deserialization invalidate reuse. Process evidence cannot be
restored from JSON after process loss. Ordinary consumer failure does not revoke
an independently completed upstream observation.

The earlier answer is a clarification of implementation conditions, not a wire/preimage or
mandatory-field change. No machine-contract CID/pin change is required for this
earlier decision. The later new-profile decision above is separate and must not
be represented as this identity-neutral clarification.

## Boundaries, beneficiaries and costs

| Boundary | Beneficiary and guarantee | Current mechanism and cost | Proposed decision for main |
| --- | --- | --- | --- |
| Acquisition observation | Replay/capture consumers identify the exact ordered observation, including duplicates and typed values | `docs/spec/execution.md` defines output `rows_cid` and native/scan receipts; validation and canonical hashing traverse the required values | Retain the current requirement for this experiment. Review any weaker observation contract separately, not as a transport optimization |
| Physical task completion | The receiving task needs the exact producer/attempt/output and satisfied execution obligations, not merely a matching hash | Common completion and owned input admission establish provenance; retained output also carries its canonical content receipt | Determine which internal consumers actually require content-addressed identity. A hash alone cannot prove execution; do not pre-approve CID-free completion |
| Same-Run reuse of a managed immutable representation | Consumers need an unchanged representation of the admitted producer, with live ownership and retention | `retained_producer_scan.mbt` re-decodes and canonical-hashes all stored columns for each receiving read, then checks its receipt | Reuse already established content evidence only while the exact representation generation and its managed immutability remain valid. This need not change CID definitions or omit the initial computation |
| Consumer-specific admission | The particular consumer needs its own demand, work/value budgets and join limits | `connectors/duckdb/compute/input_stream.mbt` attaches measurement, join validation and demand to the same scan | Keep these obligations. Separate them from reusable content verification; a previously valid producer is not proof that this consumer fits its budget |
| Physical storage/transfer | Storage and receiving implementations need intact bytes and a valid mapping to the logical result | File integrity and logical identity checks are separate, sometimes repeated | Keep physical integrity at the appropriate trust boundary. A physical file hash never substitutes for the logical CID; validate representation conversion, preferably during conversion |
| Published named Result | Delivery, audit and representation-independent comparison need the ordered logical Result identity | `docs/spec/protocols/artifacts.md` requires `logical_result_cid` in the closed Result Artifact, distinct from row payload | Preserve current publication contract unless main adopts an explicit change. Formal Result publication is not implemented by the physical-task benchmark |

The table above records the original proposal and cost model. The main decision
now appears above; measured cost separation remains outstanding. Specification
text alone is not the user-value justification. This document does not mark the
implementation or the complete cost review finished.

## Existing coupling that must be separated safely

At the initial inspected revision, `runResidentFixedCompute()` calls `port.consumeInput()` even when it imports
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

- Implement existing-contract evidence reuse without omitting its required CIDs.
- Connect the approved conditional-CID profile to main's shared contract,
  implementation, independent fixtures and separately registered measurements.
- Measured validation, canonical encoding/hash, physical integrity and holding
  costs, with interval nesting and shared work identified.
- Positive reuse tests and negative generation/owner/attempt/corruption/expiry
  tests, plus unchanged consumer guard and budget failures.
- Independent array-versus-Relation preimages, equal content with foreign
  owner/attempt, unverified restoration, and upstream completion preserved after
  consumer failure.
- Any adopted semantic change: coordinated contracts, implementation,
  independent fixtures and a separately registered experiment.
