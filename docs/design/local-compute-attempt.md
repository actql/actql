# Local Compute attempt adapter

The `execution_relation` Local Compute attempt adapter wraps one already
prepared `GeneratedSequence` and opaque `BoundProducerInput` handles. It uses
the existing sequence driver and completion types. It is a repository-local
implementation boundary, not a public Connector SPI, a replacement
CheckedProgram, canonical acquisition, Run, Invocation or approval unit.
There is no physical-strategy wire or new semantic identity in this adapter.

## Fixed inputs and one-shot execution

Each declared input must have a checked producer and an already completed,
bound producer handle. Preparation rejects missing, duplicate and foreign
bindings. The container is copied only after a preparation-entry budget check;
the completion objects it references are already opaque and immutable.
An input requiring acquisition cannot be supplied as a callback or source
handle. `values` embedded in the prepared sequence remain supported fixed
data, not external observations.

The adapter calls `execute_generated_sequence` with completed producer bindings
and no raw supplied rows. It does not reinterpret source text or bypass fragment
validation. Receiving projection, logical guards, physical accounting, Parameter
ownership and mandatory input obligations remain in the existing driver.
Preparing an attempt is not proof that all runtime obligations will succeed.

States are pending, running, succeeded, failed and cancelled. Execution is
synchronous and one-shot. Only driver success creates a completed result;
pending, failed and cancelled attempts cannot expose successful partial output.
A duplicate execution call is rejected. A new attempt can reuse the same
immutable successful input with a fresh execution budget; this is not automatic
retry or permission to repeat an external observation.

## Cancellation, ownership and representation

Cancellation is supported before execution only. It drops the pending
attempt's references without invalidating independent consumers or upstream
handles. Failed execution retains the typed diagnostic, not partial result
tables. Successful output keeps the existing producer ownership anchors.
Actual allocation reclamation follows the runtime; dropping references is not
a claim about immediate process RSS reduction.

Completed row and typed-column storage use the same producer admission and
driver. The adapter neither materializes all input rows nor requires an
ExpressionFrame suspension API. Unsupported kernel/storage combinations retain
the existing bounded conversion rules; adding this wrapper does not establish
new backend capabilities.

This adapter does not provide in-flight cancellation, crash recovery, durable
capture, SourceView observation evidence, resource reservations or asynchronous
dispatch. Those obligations must be connected at their owning Host and shared
contract boundaries. In particular, an in-memory completed Compute result does
not by itself prove that an external Acquisition has been captured.
