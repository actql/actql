# Interval-join checking

The [interval_join](../spec/language.md#interval-join) checker is part of
`relation_join`, sharing ordinary join's qualified output construction,
left-null extension, semi/anti column selection, alias projection and output
guard admission. Pipeline input occurrences remain ordered left/right, including
when both refer to the same target. The body's `left` object contains temporal
field names, not a dataflow selector. Step `from` retains its normal meaning.

The closed body admits only explicit equality-pair lists. Empty lists and
repeated pairs retain their specified meaning; neither invents uniqueness or
duplicates matched rows. This makes the existing list requirement explicit,
rather than importing ordinary join's additional shorthand. Fixed reference
revisions do not contain an interval-join implementation to reuse: the current
language contract is the authority for this operation.

Both inputs currently require complete flat Relation schemas, as ordinary join
does. Temporal roles require non-null number or timestamp contracts and one
common domain. Number contracts do not prove safe-integer values: checked clock
values, all interval inequalities, and atomic validation before any matching
remain explicit execution obligations, including unmatched input rows. No row
is materialized or matched during static checking.

`IntervalExecutionCheck` binds endpoint and safe-integer-clock admission to both
checked input occurrences before either is used for matching. The temporal roles
and domain come from the checked operation; a numeric field type alone does not
discharge value admission. Timestamp inputs omit only the numeric clock check,
not whole-input endpoint validation. The occurrence-order check retains the
pipeline's existing output-order witness and its producer dependencies rather
than constructing a new one. Semi/anti therefore do not acquire a right-side
order requirement from this link. Missing total-order evidence remains unknown.
These links are not matching results or completeness evidence and do not close
product, output or search-work resource obligations. Those obligations must close
separately before the formal Program constructor admits this operation.

Output ceilings and search-work ceilings are separate obligations, with checked
operand product bounds as fallback. Output guards retain literal or Parameter
form; defaults are not bindings and a guard is not proof of available resources.
Left-major/right-minor ordering remains an obligation, not a fabricated order
certificate. The output contract does not establish candidate-key identity,
external absence, coverage or authorization to execute. Existing window roles
are not transferred through this binary operation without an explicit proof.

The embedded machine schemas constrain source syntax and mode-dependent operand
shapes. Field existence, KeyComparable pairs, temporal domains and projection
availability require product checking. Array-returning accessors detach their
results, and input admission plus source, key and output construction share
cumulative work/node/text limits. Lowering, endpoint evaluation and coverage
proofs are outside this checker implementation.
