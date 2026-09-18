# Run-Bound Named Result Publication Implementation

Date: 2026-09-18

Owner: common execution engine

Baseline: `4fcf3b27247ebd3a5792adac93ba437f14ca0bcd`

This document records the accepted implementation contract. It is a work plan,
not a claim that the publication path already exists.

## 1. Completion target

Complete the ordinary Effect-free Program path from admitted execution through
formal publication and authorized delivery:

```text
admitted Run Definition and Run-bound Invocation
  -> checked Program execution through the common Host
  -> owned immutable material for every declared Named Result
  -> required logical identities and evidence
  -> durable payloads and admitted Result Artifacts
  -> one Run Manifest containing every declared Named Result
  -> final Run Receipt and Captured Run
  -> atomic durable publication index commit
  -> authorized manifest or individual-result lookup
  -> bounded JSON, JSONL, or CSV delivery
  -> delivery record and eventual retention cleanup
```

The implementation must support both:

- publication requested before Compute starts; and
- limited late publication of exact Result occurrences retained by the same
  Run.

The latter may not introduce a new name or view, reacquire an input, or rerun
Compute. It is admitted only when the exact immutable generation, Invocation,
authority, policy, provenance, required receipts, capacity, and retention
rights still exist.

This is not a minimal demonstration. All Effect-free Programs that the normal
Local or DuckDB path can execute must use the same publication layer without
operation-specific or backend-specific publication branches. Additional Local
operations must connect by satisfying common contracts rather than by changing
the publication design.

Remote placement and credentials, Effect execution, unfinished-Run crash
recovery, Cloud deployment, resident-result performance work, and formal
27-case performance acceptance remain separate work unless an implementation
dependency proves necessary for this completion target. Published-result
restart availability is included and is distinct from resuming an unfinished
Run.

## 2. Authoritative specifications and implementation facts

The normative sources are:

- `docs/spec/execution.md`
- `docs/spec/protocols/artifacts.md`
- `docs/spec/language.md`
- the pinned machine contracts and independent identity vectors referenced by
  those specifications
- accepted decisions in `docs/design/semantic-decisions.md`

Before changing code, maintain a field-origin and reference table for every
Run-bound object. Each field must name its semantic source, admitting
authority, reference kind, persistence point, and independent fixture.

Existing checked Result occurrences, managed obligations, completion permits,
Store generation checks, bounded readers, and common lifecycle accounting are
inputs to this work. They are not evidence that formal publication is already
implemented. In particular:

- a task completion is not a publication commit;
- an OrderedRows digest is not a LogicalRelation CID;
- a physical digest is not a logical CID;
- a process-local Store handle is not a restart-safe public reference;
- a valid schema-shaped JSON object is not an admitted Artifact; and
- a delivery write completion does not prove caller-side durable storage.

### 2.1 Implementation placement

Portable publication semantics belong in MoonBit. This includes typed contract
admission, canonical preimages, logical CID construction, exact reference
checks, obligation union, publication and delivery state transitions, and the
decision that a common completion or publication may be committed. These rules
must share the existing canonical encoder and checked Program ownership rather
than being reimplemented in JavaScript.

Environment adapters perform effects that the portable core cannot perform:

- filesystem or object-store reads and writes;
- durable synchronization and conditional index installation;
- native database and operating-system integration; and
- network streaming, cancellation, and physical cleanup reporting.

An adapter reports typed outcomes and preserves opaque physical handles. It may
not accept an arbitrary caller CID, recreate canonical JSON rules, decide that
a contract is admitted, or turn an I/O success into a common publication
success. Store interfaces require semantic guarantees such as exclusive
conditional commit and reconciliation after an unknown result; they do not
require a portable core to know about `fsync`, hard links, or a particular
cloud product.

This separation must not force relation cells through JavaScript. Logical view
construction and identity use the existing typed MoonBit evaluator and bounded
batch or stream boundaries. Node-specific file storage remains a valid first
Store implementation, while native, browser, Workers, and other adapters can
reuse the same publication contracts and state machine.

### 2.2 Single owners and migration ledger

The product has one semantic owner for each migrated decision. Adding a
MoonBit implementation beside an active JavaScript implementation does not
complete a migration.

| Decision or effect | Product owner | Current migration state | Deletion or completion condition |
| --- | --- | --- | --- |
| Result Definition admission, canonical preimage, logical CID, and checked Result inventory | `run_publication` in MoonBit | The checked graph is projected into one opaque inventory, and Run Definition, Invocation, every Result Definition, 12-field Artifact, and the complete Manifest are checked as one bounded root chain. The Store accepts only admitted canonical wire. | Extend the same chain through Receipt and Captured Run; do not add another encoder or adapter-side inventory validator. |
| Run-state action, inventory, per-Result availability, and aggregate consistency | `run_publication` in MoonBit | The portable validator and independent fixtures exist. The wire schema generator remains a build-time schema owner, not a runtime semantic validator. | Connect every response builder to the validator before exposing Run state. No JavaScript response builder may reproduce these relations. |
| Remaining Run publication contract admission, canonical preimages, identities, and publication or delivery transitions | `run_publication` in MoonBit | Closed admission and identity for the finite registry, the complete Effect-free Run evidence-chain check, and Publication Record and Delivery Record transitions are owned by MoonBit. Run Receipt, Captured Run, and delivery-receipt closed shapes are generated from the pinned protocol schema and interpreted only by MoonBit. Product JavaScript has no canonical contract or inventory implementation; its remaining implementation is test-only. | Connect every contract caller without restoring adapter-side semantic decisions. |
| File bytes, physical digest, synchronization, conditional index operation, reopen, and deletion | Store adapter | The Node filesystem Store is the first implementation. It requires an injected MoonBit contract control and accepts only admitted canonical wire. | Keep physical effects in the adapter. It reports bounded typed outcomes and never establishes logical identity or publication success. |

Independent fixed fixtures remain outside the product implementation. They
check MoonBit output without becoming a second product authority. Product
JavaScript must not be retained as an oracle for migrated MoonBit semantics.

## 3. Required 0.1 contract corrections

The accepted guarantees and machine contracts must agree before the runtime is
built on them. Update normative prose, closed schemas, embedded copies,
reference roles, pins, generated artifacts, and independent vectors together.
Do not infer missing fields in old bodies, reuse an old CID for a new body, or
rewrite historical stored data.

### 3.1 Run-bound Result Artifact

The Run-bound `actql-result-artifact/0.1` body is the normative 12-field form.
Add the fields missing from the stale nine-field embedded schema:

- `result_schema_cid`
- `ordering_evidence_cid`
- `effective_retention_policy_cid`

Audit every embedded Artifact in the Run Manifest, Run Receipt, Captured Run,
and any Effect context. Old nine-field bodies are not accepted by inserting
defaults. Before deciding whether an externally deployed implementation forces
a version change, audit stored and distributed consumers explicitly.

### 3.2 Result Definition identity

Register the closed Run-bound identity:

```json
{
  "version": "actql-result-definition/0.1",
  "program_definition_cid": "...",
  "result_name": "...",
  "result_definition_cid": "..."
}
```

The Program Definition and Result name must resolve the complete checked
definition, including source, fields, and ordering. Admission verifies the
exact Result occurrence and port. The self CID excludes only
`result_definition_cid` from the complete body.

This is intentionally Run-bound identity: changing another Result changes the
Program Definition CID and therefore this Result Definition CID. Do not present
it as a future local semantic Result identity.

### 3.3 Run-bound Invocation

Register a Run publication Invocation distinct from the existing local semantic
Invocation:

```json
{
  "version": "actql-run-invocation/0.1",
  "invocation_template_cid": "...",
  "observation_set_cid": "...",
  "invocation_cid": "..."
}
```

Pin the exact schema kind referenced by `invocation_template_cid`. Verify that
the ObservationSet cites the same template and that every required observation
is established and admitted before issuing the Invocation. Reference roles
must say whether they accept a local semantic Invocation or the Run-bound
Invocation. Exclude the Run Definition and Manifest from this body to avoid a
cycle. Equal Invocation content in two Runs does not merge their execution
occurrences.

### 3.4 Run Receipt

Correct `actql-run-receipt/0.1` by adding:

- `compiler_version`
- `aoa_ir_version`

The values come from the provenance of the admitted execution plan and AoA IR,
not from whichever binary happens to publish the Result later. Define their
syntax, requiredness, and consistency checks against referenced plan and IR
evidence.

An Effect-free Run has one final Run Receipt. Do not create a second
content-equivalent “final” receipt. Preserve an acyclic reference graph:

```text
Run Receipt -> Manifest and Result Artifacts
Captured Run -> final Run Receipt
public index -> the complete committed chain
```

Creating or storing a Receipt does not make the Run succeeded. Only the outer
durable publication commit does.

### 3.5 Run outcome and current availability

Correct `actql-run-state/0.1` so immutable Run outcome is separate from current
Result availability. Availability is recorded per declared Result as one of:

- `available`
- `unavailable`
- `unknown`

Each observation includes its observation time and a bounded reason or failure
reference. Store-query failure is `unknown`, not `unavailable`.

The Run-level `result_available` aggregate is true only when every declared
Result is confirmed available. Individual confirmed Results may still be read
when another Result is unavailable or unknown. If a Boolean aggregate is
retained, the per-Result state and an explicit confirmation state must make
unknown representable.

`result_available=true` is not read authority. A `read_result` next action means
“perform authorization and then attempt a read.” When availability is false,
next actions must not recommend reading an expired or deleted Result; they may
recommend an authorized state refresh when appropriate. State lookup itself is
authorized and may not reveal existence to an unauthorized caller. Authority
is not folded into availability.

A succeeded Run remains succeeded after expiry, deletion, policy revocation, or
temporary Store uncertainty. Current availability is derived separately.

JSON Schema constrains the closed wire shape and the action kinds admitted for
each Run status. The portable MoonBit Run-state validator owns the relational
checks that JSON Schema cannot express: exact declared-Result coverage, the
all-Results availability aggregate, and the eligibility of every Result named
by `read_result` or `refresh_availability`. A Node response adapter may only
serialize a state accepted by that validator; it must not recreate those
decisions in JavaScript.

### 3.6 Additional closed contracts

Add closed, versioned contracts and reference roles for at least:

- effective Result retention policy;
- durable payload representation binding;
- publication request intent and Publication Attempt;
- append-only publication progress and terminal records;
- manifest-read grant and result-read/egress grant;
- immutable Delivery Attempt definition;
- append-only delivery progress and terminal records; and
- public-index references and reconciliation lookups.

The publication request CID binds the immutable inventory, policy, target, and
other publication intent. It is distinct from an external idempotency key.

## 4. Mandatory obligations and capability admission

For every checked Named Result, derive at least:

```text
LogicalRelation + NamedResult + BeforePublication
```

Union checked minimum obligations, mandatory Host policy, and caller-added
strengthening. A caller `false` or omitted option cannot weaken checked or Host
requirements. The normal public entry includes every declared Named Result.
Callers may choose which Results to retrieve or deliver, but cannot omit a
declared Result from the Manifest.

Before Compute starts, verify that every required Result has a compatible
combination of Compute, logical identity, durable representation, policy,
retention, and publication capabilities. Reject statically known unsupported
or capacity-infeasible combinations before execution. This check does not
promise that future storage, policy, or commit operations will succeed; mutable
facts are checked again at use and commit boundaries.

Candidate support and preparation must not start execution I/O or reserve the
material itself. Selection remains separate from post-selection generation,
authority, and capacity admission. Unknown cost estimates are not treated as
zero.

Identity issuance is occurrence-aware and may be plural. A trusted registered
identity implementation processes the bound immutable material through the
existing canonical encoder. An issuer cannot approve an arbitrary caller CID.
Generation-bound authority exists only after the generation is known, and each
Result occurrence receives its own evidence even when a compatible content
digest is shared.

## 5. Logical identity and exact Result views

Compute the ordered Relation CID from its registered canonical preimage. Do not
substitute the current bare row-array OrderedRows digest, a physical chunk
digest, a payload digest, or a delivery hash.

Resolve the checked publication view, not merely the final task step. A Result
port may select a checked projection or ordering over a task output. Materialize
or interpret that exact view through the existing semantic machinery; do not
create a publication-specific expression evaluator.

The identity reader may run at the Site through an approved verifier. The
Coordinator confirms exact attempt, Result occurrence, view, obligation,
material generation, issuer capability, and holding. It does not require all
rows to be returned to the Coordinator or independently revalidated there.

Equal logical content under the same canonical contract may share the digest
calculation. Publication obligations, authority, Artifact admission, and
completion remain per Result occurrence. Different projection or order never
shares identity solely because it refers to the same physical generation.

## 6. Durable publication Store

Add a durable publication Store layer rather than treating the current
process-temporary local Store as the public index. Reuse its exact generation,
integrity, bounded streaming, pin, capacity, and cleanup principles where they
fit.

The first durable payload representation is framed canonical typed rows. The
common publication API deals in a verified logical view and a durable
representation provider; it must not permanently require every backend to
expand through JavaScript row objects or row strings. Batch and columnar
providers can feed the common bounded writer, and future durable formats may be
registered when they satisfy the same contract.

Keep these identities separate even if one pass computes them:

- durable framed-payload physical digest;
- ordered LogicalRelation CID; and
- JSON, JSONL, or CSV delivery-byte hash.

Batch boundaries must not change logical or delivery identity. An existing
conforming durable representation may be adopted without a redundant rewrite.

Durable commit ordering must be specified and tested:

1. write and validate payload generations;
2. persist payload bytes and required metadata;
3. persist admitted Artifacts and evidence;
4. persist the Manifest, final Run Receipt, and Captured Run;
5. persist required parent directories;
6. atomically install the public-index entry with conflict exclusion;
7. confirm durability before reporting publication success.

Atomic rename is not conflict exclusion. Use CAS, a fenced exclusive create, or
an equivalent Store primitive to enforce one commit. Crash injection at every
stage must yield either a complete committed chain or tracked reclaimable
unpublished material. Orphan cleanup must not remove allocations shared by a
different live attempt, Run, or committed publication.

The durability claim is limited to the guarantees of the selected Store,
filesystem, and device. A single local copy does not claim survival of media
loss.

## 7. Publication attempt and commit semantics

Use an immutable Publication Attempt identity plus serialized append-only
progress and terminal records. `prior_record_cid` alone cannot prevent forks;
updates require CAS or equivalent serialization.

The tenant/authority-scoped exact Run Definition is the uniqueness key. A Run
has one committed Manifest:

- the first commit fixes the Invocation and Manifest;
- a retry of the same intent returns the existing commit;
- a different Invocation, Manifest, or intent conflicts;
- concurrent commits are decided atomically in the Store; and
- repeated delivery never changes the Manifest.

The commit boundary is installation of the durable public-index entry after all
declared Result Artifacts, payload holdings, policies, Receipt, and Captured Run
are admitted and durable. Constructing a Manifest body or CID is not a commit.
Prepared objects remain invisible to ordinary Result lookup before commit.

Publication has explicit states including:

- preparing;
- committing;
- `publication_unknown`;
- succeeded;
- failed; and
- cancelled.

When a commit response is lost, reconcile against the Store before doing
anything else. While outcome is unknown, do not start another commit attempt.
Move from unknown to failed or cancelled only after a fenced, sufficiently
consistent noncommit proof. A failed Store query preserves unknown. Cancellation
racing a durable commit does not rewrite the committed fact as cancelled.

Prepared Artifacts are not orphans while referenced by a live attempt, a legal
retry, or another holding. Reconciliation metadata may identify an uncertain
commit without being treated as a successful public reference.

If publication fails, completed internal tasks remain completed. Return the
primary cause, publication state, pending cleanup, and remaining holdings.
Do not claim unrelated Program or Run obligations succeeded.

## 8. Run-bound chain and reference order

Fix the complete acyclic dependency table before implementation. The generated
order need not match this prose order, but the committed chain contains:

- admitted Program and Run Definition;
- Bound Invocation Template and ObservationSet;
- Run-bound Invocation;
- Result Definitions for every declared Result;
- immutable payload generations and representation bindings;
- Result Artifacts for every declared Result;
- one Manifest containing every declared Result exactly once;
- one final Effect-free Run Receipt;
- Captured Run; and
- the atomic public-index entry.

Every CID comes from the actually admitted contract. Do not use a task number,
configuration hash, Local computation CID, current compiler version, or test CID
as a placeholder. Admission verifies referenced kind, authority, Run, Result
occurrence, and expected dependency direction.

Publication and delivery are distinct success boundaries. Delivery failure
after commit never revokes publication. Expose publication state, delivery
state, and cleanup state separately, including a possible partial external
send.

## 9. Authorization and information exposure

Separate:

- permission to request publication before a Manifest exists;
- `manifest:read` for one exact committed Manifest; and
- `result:read` plus egress admission for selected exact Results and formats.

Individual Result access does not require permission to inspect the full
Manifest. The Host resolves the exact internal binding. Post-commit grants bind
the exact tenant, authority, principal, Run, Manifest CID, Result names,
formats, purpose, data ceiling, byte limit, use limit, and expiry. Do not issue
an unknown-CID or unrestricted wildcard grant.

Authorization is current at each lookup and Delivery Attempt. Process-local
handles and past grants are not restored as authority after restart. Unauthorized
responses, listing, errors, and logs must not expose publication existence.
Do not claim timing noninterference without a dedicated model and tests.

## 10. Delivery

Implement canonical JSON, JSONL, and CSV through one bounded streaming API and
format-specific serializers. Independent fixed expectations cover:

- empty Results, including empty JSONL;
- NULL;
- Decimal;
- nested values where the format supports them;
- string escaping and Unicode;
- canonical field order;
- ordering and duplicate rows; and
- final-newline rules.

Define exactly what Host-observed successful delivery means. A completed Host
stream write does not prove that the caller durably stored the bytes.

A Delivery Attempt has an immutable definition containing request, unique
attempt identifier, exact target, authorization, and egress admission. Separate
append-only progress and terminal records cite that attempt and record confirmed
bytes, outcome, and any success-receipt reference. A content-addressed terminal
record CID is not the attempt identity. Multiple attempts may cite the same
success receipt while remaining distinct delivery occurrences.

If the sink cannot report the exact sent prefix after a failure, record the
confirmed prefix and an explicit unknown additional exposure range. Do not
assert an unconfirmed sent-byte count.

Delivery retry performs fresh authorization and egress admission and starts at
byte zero. Duplicate bytes may reach the caller; v1 does not promise midstream
resume or exactly-once delivery. Grant byte, use, and expiry limits apply across
retries. Distinguish serializer failure, sink failure, authorization failure,
and Artifact corruption.

## 11. Retention, availability, and deletion

Keep these concepts distinct:

- Store availability guarantee;
- current read authority; and
- mandatory deletion deadline.

`available_until` is the Store guarantee for otherwise authorized reads. It is
not authority. After it expires, reject new Delivery Attempts unless a separate
retention extension was admitted within maximum-retention and deletion policy.
Expiry does not erase history and does not release capacity immediately.
Physical bytes, holdings, and cleanup responsibility remain until reclamation
is confirmed.

Admission for `delete_by` accounts for stopping active delivery, releasing
pins, and deleting material in time. Readers cannot postpone deletion
indefinitely. Publication retries do not renew deadlines. If the availability
guarantee expires during publication, publication cannot succeed under that
guarantee.

Use a defined trusted Host clock. Restart or clock rollback cannot extend a
deadline. If clock certainty is insufficient, do not claim availability or
deadline compliance. Receipt and provenance metadata also have explicit
retention and deletion policies; they are not implicitly permanent.

## 12. Restart behavior

After a Host or machine restart, a committed publication remains resolvable
until its admitted retention deadline. Recovery must:

- discover the durable public index;
- resolve the complete referenced chain;
- verify physical integrity and exact generation binding;
- derive current per-Result availability;
- enforce current authorization, policy, retention, and egress admission; and
- reject incomplete or conflicting chains.

Do not restore process-local readers, issuer permits, or past authorization.
Crash tests cover every step before and after the commit point. The public index
must never refer to an incomplete chain. Uncommitted material remains tracked
and reclaimable without damaging shared allocations.

This work does not resume an unfinished Compute Run after a crash.

## 13. Failure, cancellation, and cleanup

Preserve existing lifecycle distinctions:

```text
API promise settled
  != physical access stopped
  != material generation established
  != publication committed
  != delivery completed
  != material reclaimed
  != capacity released
```

On cancellation or failure, retain each pin until the physical access that uses
it is confirmed stopped. Destination cleanup that no longer touches the source
does not retain the source pin. Cleanup failures preserve the exact owner and
reservation until retry confirms recovery. Diagnostic history is distinct from
current unresolved cleanup responsibility.

A corruption or generation substitution invalidates the affected material
under existing rules. An ordinary publication or delivery failure does not
retroactively invalidate a correct internal completion or independent holding.

## 14. Implementation sequence

Use small, independently reviewable commits while completing the whole feature:

1. Audit and correct the 0.1 contracts, schemas, embeddings, pins, and vectors.
2. Add Result Definition, Run-bound Invocation, policy, binding, grant,
   publication-attempt, and delivery-attempt contracts.
3. Connect all checked Named Result obligations and occurrence-aware identity
   issuance to standard candidate admission.
4. Implement exact Result-view materialization and LogicalRelation identity.
5. Implement the durable representation provider and publication Store.
6. Admit the complete Run-bound chain and atomically commit the public index.
7. Add authorized lookup and JSON, JSONL, and CSV bounded delivery.
8. Add late publication through the same admission and commit path.
9. Add retry, reconciliation, retention, restart, crash, and orphan-recovery
   tests.
10. Run all fixed-SHA gates and record the completion report.

Do not wait for approval for ordinary implementation details inside these fixed
contracts. Stop only if implementation reveals a new semantic contradiction or
requires changing a guarantee.

## 15. Required acceptance matrix

At minimum, verify:

| Area | Required cases |
| --- | --- |
| Program path | Real checked Local and DuckDB Effect-free Programs through the standard Host, not hand-built completion fixtures |
| Inventory | One Result, multiple Results from one producer, multiple producers, two names over shared content, exact projection and order |
| Atomicity | All declared Results or no committed Manifest; prepared partial objects remain invisible |
| Identity | LogicalRelation differs from OrderedRows and physical digests; ordering, duplicates, NULL, Unicode, and batch boundaries |
| Evidence | Missing or mismatched schema, ordering, Invocation, policy, provenance, compiler version, or AoA IR version is rejected |
| Publication retry | Lost response after commit returns the same commit without duplicate Manifest or holding; conflicting intent is rejected |
| Publication unknown | Store query failure stays unknown; fenced noncommit permits a new attempt; cancellation cannot overwrite commit |
| Crash | Every persistence stage before and after public-index commit; complete chain or reclaimable unpublished objects |
| Availability | all available, partially available, unavailable, and Store-unknown; Run outcome remains immutable |
| Authorization | manifest-only, result-only, expired, wrong principal/tenant/Run/Result/format/purpose, and unauthorized existence probing |
| Retention | expiry, extension within policy, forbidden extension, deletion with active delivery, clock rollback and clock uncertainty |
| Formats | canonical JSON, JSONL, and CSV over empty, NULL, Decimal, nested, Unicode, escaping, field order, and final newline |
| Delivery | success, byte-zero retry, partial known prefix, unknown extra exposure, serializer error, sink error, Artifact corruption |
| Late publication | exact retained Result success; missing generation, evidence, authority, retention, or capacity rejection; no recompute |
| Cleanup | cancellation, stopped and unconfirmed readers, cleanup failure and retry, shared allocation preservation, reservation return |
| Restart | committed lookup and delivery with fresh authorization; incomplete chains and stale process handles rejected |
| Compatibility | old nine-field Artifact rejected under corrected contract; no silent body upgrade or CID reuse |

Tests must use independent expected bodies and CIDs. Product encoders may not
generate their own expected fixtures. Negative tests must exercise the standard
Host and Store boundaries, not only schema validators.

## 16. Gates and completion report

At one fixed SHA, run the repository's required format, documentation,
generated-freshness, API, dependency-boundary, independent-connector, Workers,
Node, DuckDB, and three-target MoonBit gates. Verify a clean environment without
the DuckDB SDK for common tests and the dedicated real-DuckDB job separately.
The same SHA must pass Linux CI before it is merge-ready.

The completion report records:

- fixed SHA and exact contract versions;
- supported Effect-free Program and representation matrix;
- full field-origin and reference graph;
- durable Store and device assumptions;
- public API examples for publication, lookup, and all three formats;
- failure, crash, retry, retention, and authorization matrix results;
- identity, copy, scan, encoding, transfer, peak holding, and cleanup counters;
- local gate and Linux CI status; and
- explicitly deferred remote, Effect, unfinished-Run recovery, and performance
  work.

Publication is complete only when the entire ordinary path in this document is
usable. Passing an intermediate schema, CID, or internal completion milestone
does not complete the publication feature.
