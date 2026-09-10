# Temporal window checking

`temporal_window` checks fixed and sliding window bodies against Relation or
Events Carrier knowledge. It implements the argument and output-contract
boundary for [canonical windows](../spec/language.md#event-windows), not window
evaluation, lowering, row-count planning or publication approval.

The options reader distinguishes positive size/step milliseconds from signed
offset milliseconds. Duration tokens use the shared exact duration reader.
Omitted offset becomes zero; explicit zero is accepted and offsets are not
reduced modulo size or step. Whole Parameter references retain their name,
duration interpretation and required domain; declarations are checked without
reading defaults or pretending that bound numeric values have already passed
safe-integer and positivity checks. The source cursor retains authored spelling.
Sliding requires step. A supplied step is read and retained even in fixed mode;
this layer does not silently erase an authored option.

Relation time requires a known non-null number or timestamp contract. Timestamp
input records the need for the specified UTC epoch-millisecond conversion while
preserving the authored field contract. Events already have an admitted numeric
clock and identity role. The operation preserves its input Carrier and adds
non-null numeric boundaries: `window_start`/`window_end` for Relation and
`window_start_ms`/`window_end_ms` for Events.

Generated names must be proven absent. An open field set cannot establish that
absence, but a closed set with unrelated unknown field types is sufficient.
Those unknown types stay unknown; no placeholder `json` or number type is
introduced. Trusted immutable child contracts are shared without recursive
copying. Limits bound source traversal, declaration-name indexing, field-name
inspection and generated fields; they are not a bound on all pre-existing
contract memory. Source traversal is iterative and source/text/work accounting
is cumulative. Callers admit external contracts before invoking this checker.

Opaque window roles identify the two boundaries under the fixed closed-open
interval law. Only successful checking constructs this evidence. An ordinary
schema with coincidentally named fields cannot construct it. Input validation,
checked arithmetic, membership bounds, Parameter binding and publication
resources remain explicit obligations, not claimed runtime conformance.

Pipeline dispatch enforces the operation-specific input Carrier before checking,
retains the single primary input occurrence, and debits the shared budgets.
Validated filters and row-order/subset operations preserve roles. Explicit
select/rename/drop projections transfer both roles only when both fields remain;
overwriting a boundary in derive invalidates the evidence. An ordinary input
with matching column names provides no window evidence. Other transformations
currently invalidate the roles conservatively. Evidence-transfer traversal is
also charged against the shared work budget.

The generated embedded Program schemas require the closed bodies, sliding step,
and lexical numeric/duration/Parameter alternatives. Runtime duration overflow
and bound Parameter domains remain semantic checks, not claims of JSON Schema.

`window_group` requires the selected input's window evidence before invoking the
shared aggregate checker. Its effective key list begins with the two proven
boundaries exactly once, followed by ordinary authored keys in their existing
order, retaining repetitions other than those already supplied boundary keys.
The original source retains all authored occurrences. Empty ordinary `by` and
empty aggregates are admitted; this is grouping by the two boundaries, not an
empty global group. Boundary roles survive that grouping. Named aggregate rules,
type derivation and pending validation obligations are the same as for `group`.
The embedded schema reuses the exact group body generator.

## Lag

`lag` reuses the Relation field, partition, OrderKey and positive safe-integer
count readers. Its output preserves the selected field contract with nullable
set to true and rejects any existing output field. Empty partition keys and
repeated partition references are retained; the order list is nonempty. The
default offset and explicit numeric one both produce `Literal(1)`. A whole
numeric Parameter reference remains unbound with the required minimum of one.
No string-to-number coercion or reference-implementation-only default-value
member is introduced. Row count and the window roles are preserved.

`LagCandidateKeyOrder` is an explicit unresolved requirement for retained
candidate-key-based total partition order, not proof provided by a typed
`order_by` list. This static result cannot authorize lag execution until the
planning/evidence boundary discharges that requirement. No candidate key or
provider-arrival ordering is fabricated here.

Already-windowed external input admission and complete temporal-family integration
remain to be connected. Successful pipeline window checking does not imply
completion of those boundaries.
