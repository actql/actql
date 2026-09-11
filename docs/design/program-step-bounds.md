# Checked Program step bound applications

`capacity_program_step` binds supported Program bound claims
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

The proof must use the existing `DerivedInputs` form. Its role is
`proven_upper_bound` and its unit is `rows`.

| Actual checked operation | Required proof application |
| --- | --- |
| Global Group with empty grouping keys | `actql.bound.global-group`, source derivation, value one. This holds independently of the input row count, including empty input. Other internal `OneRow` rules do not inherit this law. |
| `take` with a literal or bound count | `actql.bound.take`, input-free clamp with the exact resolved count as maximum and value. Offset and order obligations remain on the checked operation. |
| `top_k`, or `top_k_by` with no partition keys, with a literal or bound count | `actql.bound.top-k`, the same exact input-free clamp. Nonempty partition keys cannot use this global bound. |
| `append` | `actql.bound.append`, checked addition of both input upper bounds, with the actual left/right witness IDs in the derivation. Repeated inputs count twice. |
| `unpivot` | `actql.bound.unpivot`, multiplication by the authored column occurrence count, including repetitions. |
| Array `unnest` with known `max_items` | `actql.bound.unnest-array-items`, multiplication by the checked expansion factor. Outer expansion of a zero-length array uses one, not zero. Unknown bounds remain unresolved. |

`check_with_inputs` also accepts one input application for selection,
clamping its bound to the exact checked count. Offset does not weaken this upper
bound and remains an independent checked-operation obligation. `check` is the
input-free convenience entry.

Input applications must retain the exact physical producer pipeline owner and
match the actual producer step on each data edge. For a local step this is the
current pipeline; for a `ProducedInput`, the check follows its retained owner and
target through forwarding inputs. Equal source text, names or counts never
substitute for that owner. Ordinary external input facts cannot be substituted
for these owners. Proof input IDs are sorted with repetitions;
derivation operands must additionally preserve their actual left/right roles.
Checked arithmetic rejects overflow rather than rounding or saturating. The
result retains immutable child applications without rewalking their ancestors.

Parameterized counts stay unresolved unless `check_with_inputs` receives a
`CountBindings` from `bind_parameters`. This opaque lookup retains the exact
checked pipeline and a complete `BoundValues` from its original declaration
owner. One entry and its admitted ASCII name bytes are charged per bound
Parameter before building the reusable lookup; unrelated nonnumeric Parameters
remain valid. Defaults are applied only by the ordinary Parameter binder, never
by the capacity checker. The referenced count must be a positive safe integer,
even if its declaration merely admits a number. The result retains the bindings
and their supplied/default provenance; it does not substitute the smaller
computed bound for the derivation's actual count maximum.

Binding checks are local application evidence, not whole-Invocation consistency.
Applications and their ancestors retain their respective binding owners; the
combined boundary must still establish compatible invocation contexts rather
than treating equal local subjects or independently bound values as one Run.
External input proofs and Program-Definition-bound proof forms still
need their respective source application owners. Successful application
retains rather than discharges order, type/data admission and runtime failures.
Tighter available input bounds and other applicable capacity candidates must
still participate in final resolution. This entry never creates a ceiling or
converts a guard into a measured bound.

The local check inspects one already-admitted step and at most two child
applications in bounded constant work; oversized input arrays are rejected
before traversal or copying. A Parameter count adds one lookup in the bounded
name table; the name is already admitted by that table's declaration owner.
Following producer inputs is optional and uses
`max_input_work` (default zero): one work unit per visited input link, shared
across both operands, including repetitions. `input_work` reports consumed work
on success. Negative limits fail; exhaustion fails without exposing a partial
application. Forwarding walks are iterative, do not copy input trees, and stop
only at an actual producer step. A plain external input without a retained
producer is explicitly rejected rather than inventing source evidence.
Existing source/claim admission owns recursive byte/node limits;
there is no new unbounded collection traversal. Collection-wide application and
completeness remain required at the combined boundary.

Tests construct integrity-valid claims, including intentionally false claims,
and verify subject, operation, law, unit, value and derivation independently of
hash correctness. SHA and wire identity correctness remain covered by their
separate fixed-oracle suites. Owner retention, invalid indices, offset, global
versus partitioned selection and unresolved Parameter defaults are also tested.
Input-dependent tests cover foreign owners, swapped data roles, repeated edges,
false arithmetic claims, overflow, repeated unpivot columns and outer unnest
of empty arrays. These are operation-application tests, not evaluator tests.
Producer tests additionally cover repeated cross-owner operands, a wrong owner
on the second operand, ordinary external inputs, exact work boundaries and a
2,000-owner forwarding chain. Retaining a producer does not discharge its
runtime obligations or establish whole-Program/Invocation identity.
Bound-count tests cover supplied/default values, unrelated string Parameters,
same-text foreign declaration/pipeline owners, exact lookup budgets, positive
safe-integer boundaries, all three selection forms and a tighter input bound
whose derivation must still retain the larger resolved maximum.
