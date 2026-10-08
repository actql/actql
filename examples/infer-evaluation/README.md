# Named INFER evaluation Evidence

This bounded, user-owned example executes instruction candidates A and B as
fresh ordinary Programs, then sends authorized copies to a separate evaluator
process. The deterministic fixture proves the connection, not an improvement
in real-model quality. Selection cases and final cases are disjoint; the winner
is frozen before final evaluation. The evaluator never receives a Client,
provider credential, or execution-control handle.

`evaluation-evidence-reference/0.1` is separate capture metadata, not an
ArtifactRef, access grant, or execution-completion receipt. Its closed `kind`
discriminates `model_capture`, `result_delivery`, and an actual existing
`artifact` reference. This first resolver implements `model_capture` only.
Other kinds require their existing authorized Result/delivery or Store resolver;
they are never disguised as captures. Unknown provenance is preserved.

Opaque data values and their member names use the existing SDK canonical
JSON option `dataKeys: true`. Composed/decomposed Unicode and CR/LF/CRLF keys
and nested strings remain distinct. Configuration identity rules are unchanged.

The public examples execute a source-free named INFER, and one saved DuckDB
Source consumed independently by two named INFER Units over two items. The
second Program combines both outputs into one ordered Named Result. Each
submitted Run acquires its Source once and sends four separately authorized
calls through the existing Local task driver and Model journal. The projector
copies existing typed schema/input and key contracts, the exact physical-port
rendering and known context, validated response and original common capture
bundle. Restored calls without their original rendering remain incomplete.
The projector uses the accepted owner's complete call inventory and matches
successful captures by call-slot identity. A response-less call remains an
explicit incomplete item; it cannot shift the next response or disappear from
the required inventory. `inferEvidence.target` accepts an explicit name or a
bounded, distinct list of names. Each manifest contains an `items` array.
The sink's `lookup(subject, target)` requires the original scope and logical
target, so independent INFER receipts in the same Run cannot overwrite each
other. The Source example terminates its actual Host/execution process before
another process reopens the user sink and supplies saved references to an
independent evaluator. Restoring and evaluating Evidence has no Source,
Compute or Model execution callback. This establishes completed-Run Evidence
restoration, not resumption of a partially executed multi-INFER Run.
The ordinary Effect-free Host binds an explicit unknown-provenance Result
Policy original; Model egress is never used as its substitute. For a
Source-backed compiled Run, Evidence retains its actual checked Result policy
original, including Source restrictions and unknown Model provenance. Effect-bearing
profiles keep their separate required policy. Source restrictions are preserved.

Capture, current read authorization, and evaluator purpose/destination permission
are separate. The sink checks current permissions and expiry before and after
reading and immediately before external handoff. References bind Run, authority
scope, attempt, part, content, original capture and policy identities. Missing,
expired, denied, cross-subject or altered originals cannot become scores. No
missing content is filled by executing, retrieving context or resending a Model.

The opt-in Host `inferEvidence.maxBytes` bounds the optional projection and
reserves a conservative copy envelope in the existing physical Ledger before
serialization (64 times the content cap plus 128 KiB). Only one such projection
is in flight per configuration. Its cleanup joins ordinary dispatch custody.
Capture budget exhaustion cannot change normal Model dispatch or Run success.
The sink bounds transient copies, retained bytes, file count, and finite leases;
retained accounting is reconstructed on reopen. Immutable files are fsynced,
linked without overwriting, and followed by directory sync. Cleanup failure
retains its handle/path for retry. Each sink directory has one application owner;
concurrent external writers are outside this example's guarantee.

Embedded user callbacks must settle within their declared finite work. Arbitrary
callback CPU, networking, or shutdown behavior is application-owned; callbacks
are outside publication transactions. The supplied evaluator adapter bounds
stdin/stdout/stderr and time, and keeps ownership until child process close.
Failure yields `error`, while required Evidence failure yields `incomplete`.
Neither becomes a zero score or changes the original Run.

The experiment budget bounds trials, provider-call allowances, evaluator calls,
retained Evidence and elapsed time, with final-test allowances reserved before
selection. Actual sends are independently observed in acceptance: allowances
are not send receipts. Instruction-only proposals cannot change schema, Model,
authority, context selector, assertions, budget or Effect target. Dataset,
instruction, Program, ModelTask, provider binding, Run, attempt, reference,
evaluator and rubric identities are recorded without requiring A/B Run CID
identity. Labels go only to the evaluator.

## Source-backed A/B example

The complete submitted Program, independently authored rows and expectations
are in `scripts/fixtures/source-multi-infer-evidence.mjs`. Its shape is:

```text
saved Source (once) ─┬─ unique id → first_assessment  ─┐
                    └─ unique id → second_assessment ┴─ JOIN → ordered answer
```

`compare-source-instructions.mjs` is a small user-owned experiment adapter.
Candidate A uses exact lowercase urgency; B changes only `first_assessment`
to case-insensitive urgency. `second_assessment`, Source Policy, assertions,
schemas, provider installation and execution limits are fixed. A and B use
fresh submissions and independent Host processes. Selection cases are `URGENT`
and `ordinary`; final cases are `urgent` and `not urgent`. The winner is frozen
before the final submission. Each of the three Runs costs four call allowances
and four evaluator allowances; selection cannot spend the final four. The
experiment also bounds retained bytes and elapsed time.

The external deterministic evaluator reports case/target scores and reasons.
For `first_assessment`, A scores `[0, 1]` and B `[1, 1]` on selection. Both
targets are evaluated on every item, including legitimate equal business keys
in different logical INFERs. Evidence arrives as separate two-item manifests,
in reverse target and call order. Identity, typed keys and exact raw text,
rather than delivery position, establish the associations. Unicode/newline
fixtures are separate from the A/B quality rubric. This fixture demonstrates
the connection; it makes no real-model quality claim.

Run the focused source acceptance with the pinned toolchain environment:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 240 -- --test-concurrency=1 adapters/host-node/source-multi-infer-evidence-public.test.mjs
```

For clean fixed-SHA packages, the existing packed acceptance includes both
examples without another packing job:

```sh
node scripts/test-packed-infer-evaluation.mjs --keep-artifacts
```

It packs the normal five runtime packages once, installs them with the pinned
DuckDB dependency into an external directory, records source/tarball digests,
and executes Local/HTTPS plus OTel-disabled and real trace-sampling-zero cases.
The receipt records the exited Host PID, original Run and call identities,
Source count, evaluator process IDs and per-case scores. Permissions, expired
or missing originals, foreign Run/attempts, tampering and bounded-copy refusal
are checked separately; they do not alter the original successful Run.

## Boundaries

Compiler-retained Model components must form the complete original task
inventory before one common Observation/Run Invocation can be issued. Partial,
duplicate, reversed and foreign inventories are refused. Each call retains its
logical INFER, original attempt, typed key and original call-slot occurrence.
For multiple components, the logical prefix CID binds the ordered array of
`{node_id, logical_cid}` pure prefixes. The complete Executable Plan binds all
Model barriers, edges and Result processing. Singleton logical CID behavior is
unchanged; A/B Program/Run CIDs are allowed to differ.

Serial INFER is a deliberately limited public negative: the existing preparation
owner records `SubmissionPreparationFailed` / `ClientProgramRejected`, and
the downstream provider send count remains zero. It is not treated as malformed
language. The example neither invents another egress contract nor executes a
rejected pipeline. Planner task splitting, provider batch dispatch, Graph/text
expansion, Cloud, and partial multi-INFER execution recovery are not acceptance
claims for this unit.
