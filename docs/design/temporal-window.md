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
select/rename/drop and keyed-distinct projections retain every output alias of
each boundary. Whole-row distinct retains the existing roles unchanged.
Derive transfers exact whole-field copies through its checked input-field or
prior-slot reference, without copying expression trees or evaluating general
expressions. Existing role aliases remain first, and new exact aliases are
retained in binding order. Slot roles are evaluated against the original input
or the precise preceding slot, so self-copy retains a role while a computed
shadow invalidates it. Name indexing and alias/slot visits share the pipeline
text and work budgets; alias combinations are not expanded.
Dropping or computing a replacement for an alias invalidates only that alias; evidence is lost
only when either boundary has no surviving alias. `window_aliases` returns
detached arrays; `window_fields` selects the first surviving pair for consumers
requiring one pair. An ordinary input
with matching column names provides no window evidence. Other transformations
currently invalidate the roles conservatively. Evidence-transfer traversal is
also charged against the shared work budget.

The generated embedded Program schemas require the closed bodies, sliding step,
and lexical numeric/duration/Parameter alternatives. Runtime duration overflow
and bound Parameter domains remain semantic checks, not claims of JSON Schema.
An explicit fixed step has the same positive domain and binding obligations,
is retained in the source, and is never inserted when absent. It does not affect
boundaries, membership or cardinality bounds. Fixed-step corpus examples test
the specification oracle, not an implemented MoonBit window evaluator.

`window_group` requires the selected input's window evidence before invoking the
shared aggregate checker. Its effective key list begins with the two proven
boundaries exactly once, followed by ordinary authored keys in their existing
order, retaining repetitions other than those already supplied boundary keys.
The original source retains all authored occurrences. Empty ordinary `by` and
empty aggregates are admitted; this is grouping by the two boundaries, not an
empty global group. Only boundary aliases present in the effective grouping keys
survive that grouping; aggregate output names cannot manufacture role evidence.
Named aggregate rules,
type derivation and pending validation obligations are the same as for `group`.
The embedded schema reuses the exact group body generator.

Window grouping shares `GroupExecutionCheck` for partitioning, aggregate demand,
scalar result validation and statistical laws, while retaining the actual
`WindowGroup` checked step. Its group keys already contain the verified boundary
prefix exactly once. Consumers must use that retained operation and key list,
not reconstruct a prefix from field names or reinterpret it as an ordinary group.
The formal entry accepts these paths only when all aggregate requirements close.
Array-result resource scopes use the shared item-limit selection and input-proof
machinery with the normative `window_group/aggregates/<name>/items` subject and
`window_group.aggregates` authored guard path. Their limits bound each group,
including its boundary prefix, not all windows' retained contents. The
`unit_group_limit_count/at` readers retain the actual operation source, so ordinary
and window calls remain distinguishable without copying their evidence.
String-result limits likewise use `window_group/aggregates/<name>/bytes`,
measuring each result's UTF-8 bytes. The retained minimum combines an optional
Host string ceiling and literal or bound-Parameter guard; absence of both rejects
construction. Equality with a Host ceiling keeps the authored guard but marks it
currently non-binding. `unit_group_string_limit_count/at` exposes these owned
limits without substituting an ordinary-group subject. Binary64 observation slots
still require window-specific integration and cannot borrow ordinary group slot
identities.

The operation-resolution boundary retains a `WindowExecutionCheck` for time
admission and a separate one for membership assignment. Both identify the exact
window, primary input edge and requirement occurrence. Time admission precedes
input use and validates the declared time domain, including the existing UTC
epoch conversion for timestamps; invalid values are not silently dropped.
Membership assignment applies the closed-open intervals and checked arithmetic:
fixed starts use offset plus integer multiples of size, sliding starts use
offset plus integer multiples of step. Emission follows input occurrences then
ascending membership starts, retaining row multiplicity and existing Carrier.
It does not globally sort or establish a total-order witness. Arithmetic failure
rejects the entire operation output, without wrap, saturation or partial output.

An explicit fixed step still has its own millisecond binding validation even
though it is not used in membership arithmetic. These execution records do not
resolve `ResolveMembershipBound` or `ResolvePublicationResources`; those remain
open until their own owned static/resource integration succeeds. In particular,
adding these records alone cannot produce a completed Program or prove any
observed membership count.

Membership assignment carries the resolved size, optional step and signed offset,
with the original scalar resolutions from the same requirement group and producer
visit. Duration spelling remains on the retained bound value; an absent fixed
step remains absent. The maximum memberships per input occurrence is one for
fixed windows and the exact integer ceiling of size divided by step for sliding
windows. This factor does not by itself establish an input or output cardinality
bound. The bounded resolution pass charges option and scalar-slot lookups before
returning a complete index; consumers do not rebind Parameters or infer options
from source text.

`collect_window_membership_bounds` selects applicable input Program proofs from
the same capacity closure and retains their original visit/claim/producer
memberships. It applies the exact per-input factor under the row-window or
window-events law, with safe-integer multiplication and no saturation. Sparse
Host slots and inapplicable proofs are charged and skipped, not treated as an
end marker. The retained minimum is conditional on all producer and operation
checks; absent input evidence stays unknown. Host enforcement ceilings are not
input observations and are not multiplied into these Program candidates.
Collection does not discharge the membership or publication-resource requirement:
the consumer still needs the selected enforcement boundary and persistent proof
construction before a completed Program can expose these bounds to lowering.

`link_program_window_membership_limits` binds the Host output ceiling to each
membership requirement and retains every Program candidate. Relation windows use
the relation-output scope; Events windows use temporal-output. This explicitly
selects the window consumer mapping, rather than importing an implicit reference
compiler default. The existing policy wire fields and identities are unchanged.
The minimum is enforced atomically before output consumption; it does not assert
that the input or output has been observed. Publication-resource obligations
remain separate, and re-linking an already resolved occurrence is rejected.

Stage requirement closure connects each remaining window publication requirement
to the same owner's `ProgramPublicationClosure` and its exact membership-limit
enforcement. The retained `WindowPublicationResources` is a static connection:
it does not claim successful serialization, resource enforcement or observation.
Result row and byte selection and enforcement remain at the publication boundary.
In particular, an artifact byte ceiling is not applied to a hidden intermediate
window output merely because a later Result depends on it. Window membership
ceilings still apply independently before operation output consumption.

The connection retains the original producer visit and requirement group. A
missing membership enforcement cannot be replaced by an unrelated bound. Closing
the requirements allocates a new resolution index without modifying the incoming
owner, and charges failed closure visits, connection work and publication scans
to one budget. The publication inventory is reused, not rescanned or charged
twice. This connection does not independently enable a new formal-check path;
persistent limit assembly and full semantic coverage remain required there.

Persistent window proof conversion uses the owning Unit operation subject and
reidentifies the complete input proof graph first. A window witness uses the
rows unit and an explicit multiply derivation referencing that converted input;
its proof body, witness dependencies and self-CID are rebuilt together. This
differs from the source-form array-items witness used by aggregate inputs, even
when the numeric values are equal. The reader accepts only the exact closed
Program's window requirement and candidate membership, not caller-provided Unit
CIDs. Encoding a proof alone does not establish the window's source ownership
or supply a new Program construction path. Failed conversion does not expose a
partial proof or consume the caller's identity budget.

Formal `program_check.check` admits Relation `row_window` only after constructing
all owned membership limits. Each retained `WindowLimit` uses the owning Unit's
operation subject, the selected Host ceiling and every applicable reidentified
Program candidate. The existing resolved-limit encoder verifies the minimum and
dependency graph; a missing input proof remains absent rather than being derived
from a Host ceiling. Imported visits reuse the producer's limit instead of
minting a second consumer-owned subject. Indexed `unit_window_limit_count/at`
readers return the constructed objects without recomputation. Time admission,
checked arithmetic, membership emission and atomic enforcement remain execution
obligations, not completed observations. Events conversion and the rest of the
temporal family still require their separate formal integration.

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

## Relation watermark

`watermark_rows` requires exactly one fixed finite threshold or positive
millisecond skew, an explicit drop/mark policy, and a known non-null numeric or
timestamp time field. Numeric thresholds need not be integral. Skew accepts
exact duration tokens and compatible whole numeric/duration Parameters; fixed
threshold Parameters require non-null number declarations. Binding obligations
remain separate from declaration checks.

The result retains the original fields and adds fresh non-null `watermark_ms`,
`watermark_late`, and `watermark_decision` fields. Existing window roles survive
both policies. The checked threshold distinguishes a fixed value from the
inclusive prefix-maximum law; only the latter requires `WatermarkPrefixOrder`.
This does not establish logical order from provider arrival. Time-row validation,
timestamp conversion and finite threshold arithmetic still require completion
before execution/publication. This implementation performs no row filtering and
does not claim to execute watermark decisions.

Already-windowed external input admission and complete temporal-family integration
remain to be connected. Successful pipeline window checking does not imply
completion of those boundaries.
