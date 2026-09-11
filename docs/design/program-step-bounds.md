# Checked Program step bound applications

`capacity_program_step` binds supported input-independent Program bound claims
to an actual immutable checked pipeline and step. It is an operation-law
application boundary, not Program identity admission, source authorization or a
runnable Plan.

## Local subject convention

`subject_ref` returns `checked-step:<zero-based index>` only for an existing step.
This is an internal owner-relative subject convention, not an authored `as`
name, source pointer, semantic CID or external compiler reference. The checked
result retains the exact pipeline and index as well as its proof. A naked
reference string is not the resulting evidence and cannot replace that owner.
Two owners may use the same local spelling without being the same Program.

The fixed Sketch compiler also uses generated references, but does not promise
this spelling. Existing proof bytes cannot be relabeled without changing their
preimage identity. General semantic-graph import/mapping and Program Definition
identity remain separate work; this entry does not guess that mapping from
authored names. No language syntax or existing canonical Program identity changes.

## Supported laws

The proof must use the existing `DerivedInputs` form with no capacity input
witnesses. Its role is `proven_upper_bound` and its unit is `rows`.

| Actual checked operation | Required proof application |
| --- | --- |
| Global Group with empty grouping keys | `actql.bound.global-group`, source derivation, value one. This holds independently of the input row count, including empty input. Other internal `OneRow` rules do not inherit this law. |
| Literal `take` | `actql.bound.take`, input-free clamp with the exact checked count as maximum and value. Offset and order obligations remain on the checked operation. |
| Literal `top_k`, or `top_k_by` with no partition keys | `actql.bound.top-k`, the same exact input-free clamp. Nonempty partition keys cannot use this global bound. |

Parameterized counts are explicitly unresolved here; defaults are not silently
applied. Input-dependent proofs and Program-Definition-bound proof forms need
their respective dependency/source application owners. Successful application
retains rather than discharges order, type/data admission and runtime failures.
Tighter available input bounds and other applicable capacity candidates must
still participate in final resolution. This entry never creates a ceiling or
converts a guard into a measured bound.

The check inspects one already-admitted step and an input-free proof in bounded
constant work. Existing source/claim admission owns recursive byte/node limits;
there is no new unbounded collection traversal. Collection-wide application and
completeness remain required at the combined boundary.

Tests construct integrity-valid claims, including intentionally false claims,
and verify subject, operation, law, unit, value and derivation independently of
hash correctness. SHA and wire identity correctness remain covered by their
separate fixed-oracle suites. Owner retention, invalid indices, offset, global
versus partitioned selection and unresolved Parameter defaults are also tested.
