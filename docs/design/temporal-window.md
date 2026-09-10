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

Pipeline dispatch, preservation/invalidation of window roles across operations,
`window_group` consumption, schema generation and complete temporal-family
integration remain to be connected. A standalone successful window check does
not imply completion of those boundaries.
