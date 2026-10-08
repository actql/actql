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

The Host projects one source-free, explicitly named, successfully captured INFER
with one item. It copies existing typed schema/input, the exact physical-port
rendering and known context, validated response and original common capture
bundle. Restored calls without their original rendering remain incomplete.
Source-backed and multi-call projection are outside this first completion unit.
The ordinary Effect-free Host binds an explicit unknown-provenance Result
Policy original; Model egress is never used as its substitute. Effect-bearing
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
