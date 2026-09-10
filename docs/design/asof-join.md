# As-of join contract

The normative owner is [asof_join](../spec/language.md#asof-join). This decision
record closes source and evidence boundaries before implementing both Relation
and Events alternatives. It does not claim an implemented checker or evaluator.

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

The checker implementation needs both Carrier alternatives, source-located
diagnostics, detached output collections and cumulative budgets. Candidate-key
inputs require a validated proof boundary, not public booleans. Ordinary join
projection/nullability can be reused, but ordinary join's left-major input order
is not the as-of output ordering contract. Runtime time validation, uniqueness,
first-place tie rejection and resource discharge are distinct from static type
acceptance and from the schema checks introduced with this contract.
