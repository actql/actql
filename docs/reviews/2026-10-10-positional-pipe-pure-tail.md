# EXTEND and AS over positional Pipe input

## Existing requirement and independent counterexamples

Pipe EXTEND appends evaluated outputs to the current input snapshot. Pipe AS
binds the current authored columns and displaces earlier range aliases. Neither
operator makes an anonymous positional occurrence accessible by its private
storage name. The current projection and range rules in `docs/spec/query-text.md`
remain authoritative; this repair does not change the language contract.

The preserved baseline is `4d8c0b32c316dc58e17b59bb218b14c02a4948f9`.
Its tracked tree equals the published RENAME parent
`b680a1cf91192d01701777e17837ac7a2666a177` (tree
`3580daec9b80ef2f3052c82540f8758797d500d7`). These complete inputs both
fail with UnsupportedProjection:

```aql
SELECT 0 AS a, 0 AS b, 0 AS c
UNION ALL (
  FROM t |> SELECT x AS kept, -x |> EXTEND kept + 10 AS extra
)
ORDER BY a, b, c
```

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, -x |> AS r |> WHERE r.kept > 1
)
ORDER BY a, b
```

For x=2,1, independently expected rows are respectively
(0,0,0),(1,-1,11),(2,-2,12) and (0,0),(2,-2). Two independently authored
ordinary JSON Programs pass the existing checker. Typed baseline guard
`run-0ddAVY` reports 1/3: the combined JSON control passes and the two sources
fail specifically with UnsupportedProjection. The preserved test is
`/private/tmp/actql-b-positional-pure-tail-4d8c0b32c-typed-baseline.mbt`;
complete JSON candidates are recorded in
`/private/tmp/actql-b-positional-pure-tail-independent-candidates.json`.
This establishes a frontend refusal, not an incorrectly published Run.

## Minimal connection

Continue the positional-role search through EXTEND and AS. Reserve future
EXTEND destinations using the existing identifier rules and private occurrence
allocator, just as for RENAME. Legitimate authored names resembling internal
slots remain valid; anonymous storage never becomes an authored name.

Pass EXTEND arguments through the existing current-column expression guard.
For AS, construct the range from authored names and evaluated physical slots,
excluding anonymous occurrences and retaining ambiguity for duplicate authored
names. Keep the ordinal star layout separate from that named range. Qualified
ambiguous receivers fail rather than arbitrarily choosing an occurrence.
Existing range snapshots, AS displacement and normal non-positional paths remain
intact. No execution owner, fallback, consumer-side Program patch, wire change,
identity change or capacity exemption is added.

## Independent public obligations

Fourteen normal cases include two complete ordinary JSON controls, both source
counterexamples, parameter/WHERE/ORDER/LIMIT over an opposing current value,
sibling EXTEND snapshot reads, authored destinations resembling both private
namespaces, AS followed by SET with an immutable range value, quoted AS
rebinding, a legitimate private-shaped authored input, window output, nullable
values and a typed empty Result. Fifteen refusals cover anonymous private
references, original and qualified ambiguity, duplicate destinations, a sibling
output used too early, dropped inputs, displaced ranges, actual private slots
after an authored destination is reserved, and an undeclared parameter.

The existing consumer checks Named Result values and order, full
Result.describe column contracts and declaration order, hidden-field absence,
one Source acquisition for source inputs (zero for Values JSON controls),
same-request Run reuse, and zero Run admission/provider I/O on preparation
refusal. Expected Programs and rows are independently authored; no lowered
Program is patched by the fixture. Cases are registered in both the normal
corpus and the existing selected packed cohort.

The data-only inventory has 3,523 occurrences: 2,222 normal, 1,254 refusals,
47 execution failures; digest
`1af68cb9ace3f6a450ba38caeebb7a720dfc4b345d889ee05d5cdd438abe6e39`.
The selected cohort registers 240 cases per transport (144 normal, 96 refusals).
Registration and fixture assertions are not public execution evidence.

## Integration and validation

Normal merge `42fbcb1a31fe0a8ce88a2fac852b2ad2ea531c6a` adopts main
`fd6b429d00959c103ab8dd92fa7eec9d1741eeb0`, including merged RENAME #1309.
No unmerged parent dependency remains; the final destination is main.

On the resulting working source, guard `run-83zhxc` passes 46/46 focused JS
tests across this repair, positional projection helpers, RENAME/DROP/SET,
ordinary EXTEND/range snapshots, window EXTEND, property ranges and UNNEST
scope. Guard `run-hheZXM` passes 53/53 targeted Node tests: 17 independent
fixture tests and 36 inventory consumer tests. Both guards record complete
output and released locks. Formatting and `git diff --check` are also checked.

Exact clean-HEAD normal five-package Local/HTTPS acceptance is pending at this
commit. Full Core, all targets, the full packed corpus and CI are not claimed.
The broader frontend goal is still incomplete; this closes one existing
positional composition boundary only.
