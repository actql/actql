# As-of join contract

The normative owner is [asof_join](../spec/language.md#asof-join). This decision
record closes source and evidence boundaries for Relation and Events alternatives.
`relation_join.check_asof` implements typed operand admission for both alternatives;
it does not implement matching or an evaluator.

## Search measurement boundary

The search contract measures captured left/right occurrence-pair visits, not
output rows. For a realization visiting each pair at most once, the exact product
of applicable operand row bounds is a fallback ceiling. Repeated visits require
another admitted bound. Even a zero product retains both inputs' validation
obligations. Candidate comparison, sorting and retained memory need separate
physical budgets; the pair ceiling does not certify those resources.

This specifies the previously unresolved search quantity without changing
matching, tie selection or source syntax. Its operation-specific contract is a
direct local dependency alongside the separate output-row law, so selecting it
changes the as-of local contract closure identity. Contract selection alone is
not an applied limit or backend conformance evidence.

`capacity_program_step.check_asof_search_product` binds a single-visit product
to the exact checked pipeline, step and ordered operand occurrences. Each
supplied `TargetRows` must belong to that operand, including an otherwise unused
bound when the opposite side is zero. The result retains both original proofs;
repeated use of one producer does not merge the left and right roles. Its fixed
work charge includes the operation and both operand checks. Arithmetic is shared
with interval search, while the opaque products and operation admission remain
distinct. Application-closure membership, producer obligations and actual
single-visit conformance still require their own validation boundaries.

`collect_asof_search_bounds` scans the owning Program application closure for
both operand occurrences. It retains each applicable membership with its original
claim index and producer visit, including proofs after Host-only slots, and
selects only the minimum value per side for product arithmetic. The scan and
rejected applicability checks share a work budget; candidate alternatives are
not expanded into a Cartesian product. Its indexed readers expose the retained
memberships without reconstructing their owners.

`link_program_asof_search_limits` binds the product to the exact unresolved
search requirement as a future single-visit enforcement check. Missing operand
evidence and arithmetic overflow cannot be replaced with a Host output ceiling.
The input resolution index is immutable, a failed call returns no partial result,
and an already linked requirement cannot be silently rebound. Output limits,
clock/identity validation and tie selection remain separate checks. Persistent
Unit rebinding and the formal Program constructor must consume these results
before this path is a complete lowering input.

## Decisions and evidence

The existing contract fixes left/inner, three directions, positive tolerance,
null-key nonmatching, stable ascending left time/identity order and unresolved
first-place tie failure. The fixed reference compiler requires explicit alias
projection, named temporal roles and pair-shaped equality keys. Those source
shapes are retained; a deprecated `null_key` author option is not restored.

The following previously implicit choices are now explicit:

- Empty equality keys mean global temporal correlation, not a no-op. Rejecting
  them solely because the old decoder requires a nonempty array would conflict
  with the established partition criteria. Empty or repeated tie fields provide
  no extra uniqueness proof. Repeated equality conditions do not multiply rows.
- Numeric milliseconds and canonical timestamps represent the same UTC clock.
  Mechanical clock conversion follows the existing reference lowering while
  keeping the original fields visible in projection. Unlike interval_join's
  separately specified same-representation rule, as-of matching admits the two
  representations together. Numeric values and distance arithmetic still require
  validation; no lossy string coercion is allowed.
- The explicit comparison clock need not be the intrinsic Events time role.
  Selecting a comparison field does not mutate carrier identity or payload.
  Events identity remains intrinsic; an explicit identity spelling can only
  reaffirm it. Relation identity omission needs a whole retained candidate key.
- Author tie fields use AuthorOrderable ascending comparison with nulls last.
  Internal completion may use a proved candidate key, including internal Ref
  order. Completion is journaled; a typed field list alone is not proof.
- Tolerance shares bounded positive millisecond source admission, including
  whole Parameters; literal-only parsing is not a language restriction.

## Reference differences and implementation obligations

The reference compiler selects the first field of a preferred candidate key for
the left ID. A composite key cannot safely be reduced that way. The new contract
requires the entire tuple and rejects omission when proof is unavailable. It
does not invent a hidden identifier to make checking succeed.

The reference decoder rejects empty equality/tie lists, and the AoA executor
uses string record IDs. These limitations are not imported into the language.
Lowering must preserve complete typed identity, arithmetic and tie semantics or
explicitly reject unsupported execution; lexicographic stringification would
even reverse some numeric ID orderings.

The checker retains source-located diagnostics, detached output collections and
cumulative budgets. Unknown unselected payload does not require a fabricated
type; explicit keys, roles, tie fields and selected output require known types.
Candidate-key
inputs require a validated proof boundary, not public booleans. Ordinary join
projection/nullability can be reused, but ordinary join's left-major input order
is not the as-of output ordering contract. Runtime time validation, uniqueness,
first-place tie rejection and resource discharge are distinct from static type
acceptance and from the schema checks introduced with this contract.

`check_asof_sources` accepts either an ordinary Carrier or an opaque candidate-key
collection bound to its own Relation. An omitted Relation `left_id` selects an
eligible complete non-null key using deterministic completion, retaining every
component in canonical field order and the original declaration separately.
Explicit left IDs and intrinsic Events IDs are not replaced by preferred keys.
The ordinary `check_asof` entry still has no implicit key evidence.

Right-key selection uses internal canonical-order eligibility, including Ref
domains. `asof_tie_break` retains the authored option, including omission versus
empty and repeated terms. `asof_completed_tie_break` appends only missing fields
from the selected canonical key; internal reference order does not authorize
authored Ref tie fields. Left completion and added right terms retain journal
obligations, and `asof_key_completion` retains the selected declarations with
their original admission requirements. An already sufficient authored list still
retains the supporting right-key declaration without inventing added terms.

For an operation-established key, `key_origin` and the corresponding
`key_producer`, `key_calendar_producer` or `key_time_series_producer` identify the original producer;
`ValidateKeyProducer` retains its obligations. Such a key
is not relabeled as a local-input declaration or permission to normalize away
duplicate producer output rows.

The pipeline passes both sides' retained collections through this same boundary,
including keys transferred through earlier derive/projection steps. Source
admission, key selection, completed terms, temporal options and projection share
one budget. Key declarations remain conditional on input admission and uniqueness
validation. Unresolved first-place ties remain a failure obligation even when
authored tie fields or conditional key completions are supplied. The checker does
not certify actual stable order or coverage merely from the output contract.

## Output key transfer boundary

`asof_input_records` retains each original operand Knowledge handle, including
open field sets and present-but-untyped fields. It is not the typed-only schema
snapshot used to check projection. A structurally equal reconstruction is not
the same evidence source. Indexed projection access avoids copying the entire
alias array for each key component. The pipeline now transfers output keys
through the checked as-of producer.

The at-most-one match rule permits surviving left candidate keys to transfer
for both left and inner forms. Right-only uniqueness does not follow: multiple
left occurrences may select the same right row. All aliases of every surviving
left key component must be retained; projecting away one of several aliases
must not discard the others. Identity/tie/value obligations remain attached to
the as-of producer. An explicit left identity or intrinsic Events identity needs
its own conditional producer evidence rather than a fabricated input declaration.

The as-of checker and its selected key evidence are mutually dependent, so their
implementation now lives together in `relation_evidence`. `relation_join` keeps
its public entry points as aliases and delegating functions. The lower
`relation_join_shape` remains independent of evidence, and evidence does not
import the upper facade. This keeps an actual checked producer, without an
unchecked projection descriptor or a synthetic select operation. Source
admission, diagnostics and shared completion budgets are unchanged by this move.

`transfer_asof_keys` binds supplied keys to the original left Knowledge handle,
retains all surviving left keys and the complete checked left identity. An
identity covered by an existing source key does not create another redundant
candidate. New identity witnesses point to the checked as-of operation, not a
fabricated input declaration; inherited witnesses also retain their parent key.
`ValidateKeyProducer` requires the original identity, tie, value and other
obligations to be checked. Projection away from every alias of a component loses
that key. Right-side fields alone never inherit left occurrence uniqueness.
