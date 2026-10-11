# UNPIVOT String row-value aliases

## Boundary and independent counterexample

Baseline: `26d63b4060d25aded2cf469e421530b3b41fb2de`. This is an
independent Frontend unit after merged #1400. Its completed 9-normal/6-refusal
acceptance is separate evidence and is not repeated by this change.

```aql
FROM pair
|> UNPIVOT INCLUDE NULLS(value FOR label IN(x AS 'first', x AS 'second'))
|> ORDER BY label
```

For input `{x:7,y:9}`, the independently expected ordered rows are
`[{y:9,value:7,label:"first"},{y:9,value:7,label:"second"}]`.
The initial two-test probe accepted the independently authored ordinary JSON
Program and rejected this source in the parser: `run-5KNT9x`,
`focused-test-VYpQtz`, 1/2 passing. The exact probe and designed rows are retained
at `/private/tmp/actql-b-unpivot-row-label-26d63b406/`; no public execution was
performed by that probe.

The selected [GoogleSQL UNPIVOT reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#unpivot_operator)
allows literal row aliases, defaults omitted String aliases to column names,
and retains different selected occurrences of the same column. Its String and
INT64 alias contracts are distinct. This unit connects String aliases; it does
not claim complete multi-column or exact INT64 support.

## Implementation and identity

The parser retains one optional decoded literal per selected occurrence.
`lower_unpivot_row_labels` projects an evaluated input slot into a unique
private column for each occurrence, then calls ordinary common `unpivot`.
An ordinary conditional expression maps each private name to its authored
String label. Repeating one input with two different aliases therefore keeps
both labels. Equal aliases and repeated input rows preserve multiplicity.
Omitted aliases use resolved current names, including RENAME outputs.

Labels are values. Empty strings, CR and decomposed Unicode are not converted
to identifiers or normalized. No input expression is reevaluated. Existing
UNPIVOT owns expansion, exact typing, NULL retention, key evidence and capacity;
ordinary filtering implements EXCLUDE NULLS. Existing explicit sorting and
Result projection remove private fields. The no-row-alias path is unchanged.

The common Number contract cannot represent exact INT64 aliases such as
`9223372036854775807`. Accepted decimal integer alias syntax is explicitly
refused by lowering as `UnsupportedProjection`, projected by the existing
public check Owner to `ClientProgramImplementationLimit`. No conversion to
binary64 or String is introduced. Mixed alias types and missing aliases beside
integer aliases are invalid under the selected reference. Exact INT64 value
support is a concrete common-contract dependency, not a permanent language ban.

Grammar and query rules change their manifest and grammar-bound Run identities.
The complete previous grammar and Values Run preimages are preserved in
`scripts/fixtures/pre-unpivot-row-label-values-identities.json`; Unit, Program,
ResultPlan, AoA and barrier meanings are unchanged. Current expected identities
are calculated by the existing hand-assembled normative oracle, without a
product compiler or returned Run CID. Old Runs are not reinterpreted.

## Verification and remaining acceptance

- Focused working-source JS: parser, lowering, independent complete Program,
  unchanged callers, and all six new authored normal inputs through the real
  Frontend and normal checker: `run-K6q887`, `focused-test-pHxWUS`, 47/47.
- Selected generated syntax API: `run-IRHNSQ`; existing `moon info` generator,
  two compile tasks. This is interface evidence, not Wasm/Native execution.
- Node preparation: `run-91lSh4` passed fixture/profile, compilation and import
  checks (47 tests) but failed one stale current Run expectation. The changed
  vector file was then rechecked alone: `run-Keeoo1`, 35/35. These are separate
  working-source receipts, not a successful replacement of the failed run.
- Read-only compilation manifests, document metadata and canonical vectors
  are fresh (510 canonical identity vectors); changed MoonBit formatting and
  whitespace checks pass. Final submitted-HEAD checks remain separate.
- Public fixtures: six normal cases and five typed refusals, registered both
  in the ordinary packed corpus and `--unpivot-row-label-only`. Normal cases
  cover an independent JSON control, repeated labels, NULL exclusion, current
  renamed defaults, typed empty input and equal labels. Refusals retain old
  range/consumed-input, expression alias, mixed type and exact-integer gaps.
- Public acceptance is **not yet executed** for this unit. It requires a clean
  fixed source, ordinary five-package producer and that same package cohort's
  Local/HTTPS run to Named Result, complete inventories and actual retained
  values/schema/termination receipts. The existing consumer checks resubmission,
  reattach and read counters; refusal checks require zero admission/source I/O.
- Hosted CI, all-target execution and whole-system conformance are unverified.
  No shared Heavy slot is reacquired by this work. No merge is performed.

Intermediate compile/test diagnostics remain in their original guarded receipts;
the initial public-AST inspection and one current-vector expectation were fixed
in the test code, without changing product semantics or independent expected
rows. No failure is relabeled as a successful run.
