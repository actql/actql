# Pipe scalar aggregate expressions

## Source gap and selected contract

The adopted GoogleSQL checkout is
`d82db99a923a46571f543a13899dc791a7b6f743`. Its Pipe AGGREGATE
expression list permits scalar expressions around aggregate calls, and requires
an aggregate in every aggregate output. The ordinary common group and derive
already admit the independent complete Program in
`src/query_program/pipe_aggregate_expression_test.mbt`. This source was rejected:

```aql
FROM pair
|> AGGREGATE COUNT(*) + 1 AS n GROUP BY x AS bucket
```

Pre-fix evidence `run-g8c1fR` / `focused-test-4fIlUD`: the control checks, then
source parsing fails, 0/1. This is a parser counterexample, not an observed
public execution failure. The first connection differed from the independent
control only in private slot allocation; the compiler allocation was corrected
without changing the expected Program.

## Connection and scope

Reuse the SQL aggregate-expression parser and ordinary aggregate argument
lowering. Pipe grouping metadata retains exact parser-owned embedded call names,
independently copied by observation; no string-prefix classification is used.
Aggregate calls run in the pre-group input scope. Only semantically identical
calls share a checked physical aggregate slot.

The enclosing scalar expressions lower through the existing expression bridge
and ordinary derive after group. Retained input keys and embedded calls form
that scalar scope; grouping aliases and authored aggregate siblings do not enter
it. Output columns remain grouping outputs first, then authored aggregate
expressions. The ordinary projection removes private call/scalar fields before
WHERE/ORDER/LIMIT and Result publication. A grouped input and an aggregate may
have different physical slots while publishing distinct authored output names.

Repeated grouping subexpressions, including nullable object properties, bind to
an evaluated group key only after input-prefix resolution proves the same
meaning. The syntax helper clones an owned subtree, prunes replaced descendants,
remaps indices and retains original spans/work evidence. It does not evaluate
expressions. Binding work is bounded by the existing expression work limit;
private binding names cannot capture authored references. Existing SQL aggregate
scope/evaluation and the ordinary expression-subtree caller remain covered.

No common checker, planner, runtime owner, capacity ceiling, wire/value law or
legacy client-wire fallback is added or relaxed. Missing modern package assets
must still fail. This does not claim support for every aggregate signature or
for the separate common zero-column Result boundary.

## Independent expectations and focused checks

- Parser metadata, refusals and subtree ownership: 3/3,
  `run-ghDaBE`, `focused-test-LOo77a`.
- Complete independent Program controls and scoped argument/refusal matrix:
  4/4, final `run-xdvTja`, `focused-test-PKnMSv`. The matrix retains empty input,
  COALESCE, grouped arithmetic, qualified inputs, alias collisions and repeated
  calls. Expected complete JSON is authored rather than compiler-generated.
- Existing SQL aggregate-expression callers: 5/5, `focused-test-PyNpNl`.
- Existing Pipe shorthand ordering callers: 3/3, `focused-test-8CGtUg`.
- Existing object-property subtree caller: 1/1, `focused-test-fh1g4W`.
- Independent normative/Run vectors and public profile controls: 13/13 in
  `run-ghDaBE`. That guard's last freshness check failed because broad formatting
  had reformatted generator-owned canonical output. The existing generator
  restored it; no freshness check was disabled or generated body hand-edited.
- Final canonical freshness: 377 independent identities verified in
  `run-xdvTja`. Ordinary Values Run caller: 1/1, `focused-test-I1etYD`;
  canonical grammar manifest caller: 1/1, `focused-test-BYhWIn`.
- Compilation manifests, normative document imports and spec-family read-only
  checks pass in `run-ghDaBE`. Their earlier writers and scoped syntax interface
  generation ran in `run-2A8JhE`. Only affected JS/Node checks were selected.

The query EBNF file is unchanged from the shorthand-ordering parent. Normative
rules now describe the newly connected expression list. Independent sorted-key
preimages give grammar CID
`sha256:2a433f295994301675ad42d4acc1859474b8e0e31b3583482f057602164c8951`,
rules SHA-256
`f5f1f5767586ab84b569d4d3126ada4c36e0ae244dbf33c41a46d800cab922fa`,
and ordinary Values Run CID
`sha256:13bb9883431cd034e3e9056e249f5c25c01604506736da187bd0d506171d0a07`.
The complete independent preimage is retained under
`_build/independent-evidence/aggregate-expression-run-preimage.json`.
The shorthand-ordering predecessor grammar/Run vectors are preserved. Only the
containing Run's grammar dependency changes; value, Unit and ResultPlan laws
are unchanged.

## Public acceptance prepared, not yet executed at this record

The normal group corpus now includes ten normal cases and seven preparation
refusals; `--pipe-aggregate-expression-only` selects those same fixtures.
They include an independent complete JSON control, nullable property groups,
repeated calls, computed key reuse, input/output name collisions, subsequent
WHERE/LIMIT and empty global/keyed groups. The existing consumer checks exact
Named Result rows, declared column order/full describe contracts, stream
completion, hidden-field absence, owned-submission resend/attach/reread, and
refusal before Run admission/provider I/O. No generated Program is patched.

Next: normally pack the five packages from the same clean committed SHA and
run the selected external Embedded Local/HTTPS acceptance in one bounded guard.
The PR body will record the actual subsequent result, source SHA, digests and
logs separately. Parser/checker success is not public execution evidence.

This unit depends on the unmerged shorthand-ordering PR #906. Preserve that
stack until the parent reaches main; final merge target is main. No full Core,
all-target, full packed campaign, proof/performance campaign, manual CI rerun or
merge has been performed for this unit.

## Published-parent control correction

The SQL private-looking-star control fails on published `324a326a90a6b42696b2353e68348c49114dc095`
(`run-pIuEjG`, `focused-test-el0DgH`): the expected aggregate slot still used
`aql_select_aggregate_4`. The current allocator reserves eight entries independently
of the proposed SQL grouped-subexpression change: two input columns, two group
keys, two named GROUP projections and two retained result keys. The complete
expected Program now uses `_8`. Values, key bindings, projection, sort, public
columns and contracts are unchanged. This fixture correction does not claim a
new runtime acceptance or relabel the earlier package evidence.
