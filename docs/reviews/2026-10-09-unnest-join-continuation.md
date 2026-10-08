# Ordinary JOIN after UNNEST: source continuation

## Problem and scope

The starting main revision is `366025722444feff823840a330fc56030e4c6974`.
A complete, independently authored JSON Program can expand an ARRAY and join
the resulting Relation, but equivalent SQL and Pipe source is rejected before
lowering. The adopted grammar already permits successive ordinary JOINs; the
normative query-text document recorded this as an implementation coverage gap.

The minimal example uses nullable ARRAY parameter `items = [2, null, 2]`:

```sql
SELECT element, position, k.key
FROM UNNEST(@items) element WITH OFFSET position
JOIN (SELECT 2 AS key) k ON element = k.key MAX_OUTPUT_ROWS 10
ORDER BY position
```

The independently expected rows are
`[{"element":2,"position":0,"key":2},{"element":2,"position":2,"key":2}]`.
The NULL element does not match, duplicate elements remain separate rows, and
the authored JOIN bound remains 10. The complete scalar and nullable-object
JSON controls are in `scripts/fixtures/unnest-join-source-input.mjs`; they are
not generated from compiler output and are never patched by the consumer.

## Implementation boundary

- SQL binds the already expanded prefix through the existing private producer
  continuation before parsing the following ordinary JOIN. Earlier JOINs stay
  before expansion; later JOINs consume the expanded row.
- Pipe admits the same private Relation continuation. SELECT and AS still
  replace the visible scope; discarded aliases are not revived.
- `JoinChainScope` retains nullable object value-table receivers as well as
  ordinary visible columns and immutable ranges. Existing JOIN slot remapping
  carries them into the next Relation operation.
- Object contracts come from existing checked prefix typing, including empty
  input. There is no row sampling, new execution Owner, schema fabrication,
  identity evidence invention, provider change or limit increase.

The public fixtures cover INNER/LEFT/RIGHT/FULL JOIN, SQL/Pipe/quoted names,
NULL and empty arrays, duplicate elements, nullable object fields and whole
objects, SET versus immutable range values, DATA, predicate and LIMIT placement,
and an acquired right input with exactly one Source read. Existing correlated
expansion followed by CROSS JOIN is now a positive eight-row obligation.
Dropped aliases, invalid element properties, non-ARRAY input and a zero JOIN
bound retain preparation refusal obligations.

INNER/LEFT *correlated expansion*, comma expansion and correlated expansion
after a Pipe set expression remain separate coverage gaps. This change does
not claim all GoogleSQL UNNEST forms or all query compositions are implemented.

## Identity and generated artifacts

EBNF bytes are unchanged. Updating the normative coverage statement changes
the query-text rules hash and consequently the grammar manifest and Run CID.
It does not change the Program wire, value/Graph contracts, Unit or ResultPlan
identity. Existing saved Runs are not reinterpreted.

- Previous grammar: `sha256:a85a3517afd7a705e99e746f5a08332370b072ddc77868372db19b977ee87ecb`.
- Current grammar: `sha256:62780078db668a0488bde0f683d6de3f2e15aa04875aa8593c64d60d7c187cf0`.
- Previous independent Values Run: `sha256:6e1a597d8e0473c402cca0fd54e582189c4d1da5064aadab98a647bb6888f645`.
- Current independent Values Run: `sha256:cf1e1ea739a4345c77648eecf9a605ff2b29d905a99b92e36b8dd923e9a2256f`.

`scripts/fixtures/pre-unnest-join-grammar.json` preserves the complete previous
grammar and independent Run preimage. The independent canonical computation
first reproduces the previous Run, then substitutes actual current normative
inputs. Expected CIDs are not copied from product failure output. Existing
compilation-manifest, document-metadata, spec-family and canonical-vector
generators update the dependent artifacts.

## Executed local evidence before publication

All paths below are relative to this worktree. Tests use pinned Node 22.22.0
and MoonBit `0.10.12+1634b282e` through the existing bounded/nonzero wrappers.

1. Before repair, focused JS execution of
   `src/query_program/unnest_join_continuation_test.mbt` is **1/2**: the common
   JSON Program checks; equivalent source fails parsing. Evidence:
   `_build/local-checks/attempts/run-Kx0nbX`.
2. The first repaired run is **10/11**, with an obsolete parser-refusal
   expectation for ordinary JOIN after expansion. The obsolete negative is
   replaced by the positive eight-row public case, not by changed row or limit
   expectations. Evidence: `_build/local-checks/attempts/run-8K7Tfr`.
3. Focused JS tests of the new continuation plus correlated UNNEST, Pipe JOIN
   ranges and joined UNNEST stars pass **18/18**. Evidence:
   `_build/local-checks/attempts/run-gH1mun`.
4. Focused parser, continuation and actual Values Run identity consumer tests
   pass **13/13**. Evidence: `_build/local-checks/attempts/run-G4toN7`.
5. The final seven-file Node selection passes **33/33**:
   `node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/unnest-join-source-input.test.mjs scripts/correlated-unnest-source-input.test.mjs scripts/joined-unnest-star-source-input.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/compilation-manifests.test.mjs scripts/sga-query-call-contract.test.mjs scripts/canonical-json.test.mjs`.
   Evidence: `_build/local-checks/attempts/run-WfD16Q` and
   `_build/focused-evidence/focused-test-aM6lW0`.
6. Read-only compilation-manifest, document-metadata, spec-family and canonical
   checks pass; 380 canonical identities match their generated inputs.
   Changed MoonBit formatting and `git diff --check` pass.

## Integration and first packed attempt

Main `2fa91dd62fc300f509687f34a9990a7d76c3e031` was normally merged into
integration revision `26553404ed04dbe6933da869f1fe876e52423005`. No conflict was
reported; the existing conditional-aggregate implementation and public fixture
registration were retained. The focused parser/continuation/Run consumer
selection passed **13/13** again (`run-RUCzGd`), and the read-only pin checks
also passed after integration.

That clean integration revision produced the usual five packages through normal
prepack, followed by independent manifest/digest verification. The existing
`test-packed-public-query.mjs --correlated-unnest-only` consumer failed during
Local preparation of `unnest-join-full`, before later cases and HTTPS. The
producer/digest checks succeeded; the campaign itself did not. Evidence:
`_build/local-checks/attempts/run-2B8PZY` and the external receipt
`worktrees/.codex-scratch/public-query-evidence-VRHlzd`, whose command 010 logs
retain the exact failure and preceding successful cases.

The newly authored FULL fixture omitted the existing common requirement for
identity evidence on both Relation inputs. A bounded diagnostic compared the
same source with an independent JSON FULL Program: both preparations rejected
with `check_unclassified`. The focused MoonBit regression verifies the exact
cause `Closure(Joins(MissingEvidence(_)))`. FULL is not allowed to invent a key
from an OFFSET name, a constant, or an observed row sample.

The corrected source and independent JSON control explicitly validate
`position` on expanded rows and `key` on the right input through existing
`assert_rows.unique_by`. The duplicate elements, NULL extension, unmatched key
3, expected four rows, column order/types, and JOIN bound 10 are unchanged.
This is an authored fixture precondition correction, not a checker relaxation
or a change to expected product output. The keyed source also preserves the
actual UNNEST → assertion → FULL JOIN continuation under test. The original
unkeyed source and its failure remain above and in the MoonBit regression.

Focused continuation/FULL tests pass **8/8** (`run-eBxfP2`), and the updated
three-file fixture Node selection passes **9/9** (`run-nhVRYL`). The public
cohort now has 58 normal cases and 17 preparation-refusal cases, including 19
new normal cases and five new refusals. Those counts are obligations, not yet
successful public execution evidence.

### Separate common diagnostic boundary

Unkeyed FULL rejection reaches the existing common checker but its category
falls through to `UnclassifiedFailure` in
`src/program_check/diagnostic_category.mbt::closure_diagnostic_category`; the standard
preparation bridge reports `check_unclassified`. Public Local consequently
returns `ClientHostFailure`/500 and the SDK returns `SubmissionUnknown` for
`packed-local-unnest-join-full`. This is not evidence of an admitted Run failure
or a wrong row order. The precise missing-evidence classification belongs to
the common checker/diagnostic owner; it is not repaired here by changing the
SDK's uncertainty rule or bypassing the checker.

The bounded diagnostic commands and evidence are retained as
`/private/tmp/actql-b-unnest-join-full-preparation-probe-20261009.mjs`,
`/private/tmp/actql-b-unnest-join-full-preparation-bounded-20261009.mjs` and
`_build/local-checks/attempts/run-iqmK5U`. They compare source, independent JSON
and the explicitly keyed source using the actual generated runtime at the
integration revision; they are preparation diagnostics, not packed execution.

Submitted-HEAD CI, Wasm/Native execution and broader Core coverage remain
unverified. The existing correlated UNNEST public cohort includes these
fixtures in both normal and selected routes; fixture registration alone is not
successful execution evidence.

## Second packed attempt and complete object expectation

Clean revision `044181f6dcc2ef71612abf42380a1b82748a6584` normally produced all
five packages and verified their digests. Public Local passed the independent
FULL JSON control and keyed source, predicate placement, LIMIT-before-JOIN,
object JSON/SQL/Pipe controls and DATA. It then stopped at `unnest-join-whole-object`
because the independently authored expected describe contract omitted the
fixed checked member `additional_properties: false`; value comparisons had
already passed. The campaign is a failure, and HTTPS remains unexecuted in it.
Evidence: `run-qko2kT` and external receipt
`worktrees/.codex-scratch/public-query-evidence-dtC4io`.

The authoritative `docs/spec/language.md` **Value contracts** section explicitly
separates the author object contract (omitting this fixed member) from its
checked machine contract (inserting `additional_properties: false`). The
expectation now includes that fixed checked member; the authored parameter
declaration still omits it. A fixture regression compares the complete expected
contract and prevents moving the machine member into authoring vocabulary.
This changes neither product code nor expected rows, nullability or column
order. Both failed campaigns and their original evidence are retained.
