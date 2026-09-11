# Capacity source applicability audit

This audit separates source truth from wire integrity, arithmetic closure and
consumer applicability. It does not certify runnable limits. The authoritative
requirements are [resolved limits](../spec/language.md#resolved-limits) and
[Check Environment admission](../spec/protocols/contracts.md#check-environment).
The implementation inspected here is `517c431`; reference evidence is fixed to
Sketch `87dc7144`. The original [pure-operation scope](pure-operation-checking.md)
is unchanged.

## Source branches

| Source | Evidence currently available | Required application boundary |
| --- | --- | --- |
| Host policy | Opaque policy ceilings, reconstructed source witnesses, collection binding and Graph-input preflight applicability. | Other consumer families and policy-selection authority; a ceiling is not observed data. |
| Program proof | Canonical proof-body identity, dependency linking, arithmetic and mixed limit closure; pipeline counts remain attached to actual producers. | Bind the proof's semantic subject and governing transfer law to the checked operation and actual operand occurrences. A self-consistent proof body is insufficient. |
| Author guard | Checked operations retain literal/Parameter guard variants, source cursors and operation-specific scope. | Resolve the actual bound Parameter, retain the exact owner and guard occurrence, and match unit/law/enforcement to that consumer. Program Definition identity must be supplied by its identity owner, not an arbitrary caller string. |
| Pinned Contract | Wire admission retains contract CID and field, but supplies no authority for the referenced body. | Admit the governing contract and its authoritative source closure, then extract its applicable ceiling. A JSON field named `max_items` is not sufficient. |
| Language law | Shared law-name membership and fixed normative operation rules. | Bind an actual pinned law body and its conditions to the selected operation. A fixed option or a law name alone is not a numeric capacity candidate. |

`capacity_witness.WireWitness` intentionally remains a claim. Neither its
canonical self-CID nor `capacity_law.RegisteredLaw` establishes any missing
source/application boundary in this table. Collection validation must include
unused claims and preserve source ownership; matching numbers cannot replace
matching sources.

## Fixed-reference findings

The compiler's `programUpperBound` helper creates a content-addressed proof
from caller-supplied value, law, semantic reference and dependencies. Its
identity construction is useful wire evidence, not an independent proof that
those arguments describe the actual operation. The current separate
`ProgramProofClaim` boundary correctly avoids asserting that stronger claim.

The compiler's Contract ceiling at `infer` uses ModelTask `max_items`, unit
`distinct_keys`, and `actql.contract.model-task-items`. The Effect checker uses
Command `target.max_items` and `actql.contract.command-items`. Those two
registered names do not authorize generic ceilings from arbitrary value
contracts. Acquisition/infer and Effect execution remain outside this increment;
their presence in the shared vocabulary does not expand this scope. Any
applicable Contract facts within the agreed scope still require their own
authoritative bodies and bindings.

The reference's `fixed_language_law` Plan facts include omitted option
completion and timestamp conversion. They are not automatically
`language_ceiling` bound witnesses. Its shortest-path single-result fact also
depends on the old single-source/single-target form: the current selector
language cannot inherit a universal one-row bound from that fact.

## Program proof application prerequisites

Inspection of `capacity_witness/program_proof.mbt` and `program_closure.mbt`
confirms that proof bodies bind the claimed unit, value, law, semantic reference
and input witness identities. The closure checks arithmetic operands and cycles;
it does not bind those operands to actual checked pipeline connections.

The fixed compiler's `boundClamp` and `boundAdd` helpers take their law and
semantic reference from the caller. Its global-group branch constructs a bound
with both a source-path-derived reference and a generated result reference.
Consequently, `semantic_ref` is not necessarily an authored `as` name or a
source pointer. Looking it up in the pipeline's authored-name map is not a
general source validation algorithm. An empty proof-input array also does not
mean that the checked operation has no data inputs: global aggregation can prove
a one-row bound without using its input's row bound.

The operation binding must retain a correspondence between semantic subjects
and exact checked owners/targets. That correspondence must be supplied by the
owner that constructs or validates the semantic graph, not inferred from equal
names, equal counts or caller-provided numeric assertions. Preserve role-tagged
data inputs separately from the subset of capacity witnesses used by a law.
The [checked step application](program-step-bounds.md) now introduces an
owner-relative `checked-step:<index>` correspondence for supported local
proofs, including append, literal clamps and known unpivot/unnest expansion from
verified producer-step applications. Inputs retain exact pipeline owners and
ordered edge roles independently of sorted proof IDs. It does not map arbitrary
imported compiler references, admit external input sources or provide an
enclosing Program identity.

| Law family | Application checks beyond arithmetic closure |
| --- | --- |
| `actql.bound.global-group` | Verify the actual global Group operation with empty grouping keys. The output bound is one even for empty input. `RowCountRule::OneRow` alone is insufficient: pivot also uses that internal numeric rule, but this does not assign it the global-group witness law. |
| `actql.bound.take`, `actql.bound.top-k` | Bind the clamp to the actual operation and its literal or bound count. Retain offset/partition semantics and their validation. A positive authored number is not automatically a selection bound; partitioned top-k cannot use a global clamp without its additional conditions. |
| `actql.bound.append` | Match both capacity operands to the actual ordered left/right input occurrences, including self-append. Same-unit checked addition and a sorted proof-input array do not establish that correspondence. |
| `actql.bound.unpivot`, `actql.bound.unnest-array-items` | Derive the expansion factor from the checked column occurrences or admitted item bound. Repeated unpivot columns count repeatedly; outer unnest of an empty array may still contribute one row. A self-consistent multiplication by a caller-selected factor is insufficient. |
| Graph input enforced ceilings | Use the existing mixed-limit and Graph preflight binding, not a fabricated ordinary Program proof. Input node and edge measures remain distinct; successful static binding does not observe their counts. |

The checked step entry now applies the global-group and input-free literal
take/top-k cases above. Input-dependent and imported semantic-subject application
remain unimplemented. Author-guard Program Definition identity
and bound Invocation consistency are separate prerequisites; a fragment hash or
an authored alias does not supply either identity. No additional law name,
source constructor or runnable Plan is introduced by this audit.

## Extension-local capacity law

The current `actql-expressions.json` contract explicitly registers
`actql.expression-fragment.capacity` only for fragment revalidation, not in the
shared bound-law registry. Language's expression-fragment section fixes its
source to the canonical request CID and exact request pointer, with that CID
as the sole dependency and engine-atomic enforcement. Its units are rows,
bytes and array items according to the addressed request ceiling.

Do not add that spelling to the shared registry merely to make generic wire
admission accept it. Fragment admission must regenerate its scoped witnesses
from the admitted request and governing expression contract. Conversely,
rejection by the shared registry is not a language prohibition on that
extension. The shared-registry prose is broader than this explicit local
exception; any future consolidation must reconcile both normative owners,
not silently change one registry or weaken source validation.

## Next implementation boundary

Bind pure-operation author guards to their checked owners before constructing
or admitting their wire witnesses. Existing accessors cover aggregate item/byte
guards, join/cross/interval output guards, traversal/component output guards
and sequence per-key/output guards. Enumeration must retain repeated operation
occurrences and distinguish absent guards from unresolved Parameter guards.

The binding must obtain a positive safe integer from the actual operation or
its bound Parameter, keep an explicit guard even when another candidate is
tighter, and retain the protected quantity and enforcement scope. Selection
counts such as `take`/`top_k` and window size/step are not author guards merely
because they are positive integers. Do not introduce a caller-provided
`verified` flag or infer Program Definition identity from a pipeline fragment.

This is a dependency ordering for the remaining shared work, not a substitute
for complete source/consumer validation, final all-obligation discharge or the
48-operation acceptance audit. Runtime enforcement remains outside static
checker execution and must not be claimed by these results.
