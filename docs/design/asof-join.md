# As-of join contract

The normative owner is [asof_join](../spec/language.md#asof-join). This decision
record closes source and evidence boundaries for Relation and Events alternatives.
`relation_join.check_asof` implements typed operand admission for both alternatives;
it does not implement matching or an evaluator.

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

For an operation-established key, `key_origin` and `key_producer` identify the
original producer and `ValidateKeyProducer` retains its obligations. Such a key
is not relabeled as a local-input declaration or permission to normalize away
duplicate producer output rows.

The pipeline passes both sides' retained collections through this same boundary,
including keys transferred through earlier derive/projection steps. Source
admission, key selection, completed terms, temporal options and projection share
one budget. Key declarations remain conditional on input admission and uniqueness
validation. Unresolved first-place ties remain a failure obligation even when
authored tie fields or conditional key completions are supplied. The checker does
not certify actual stable order or coverage merely from the output contract.
