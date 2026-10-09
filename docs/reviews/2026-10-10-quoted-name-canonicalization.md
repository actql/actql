# Quoted name admission across declarations and references

## Existing contract and counterexample

Baseline: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.
This repair applies the existing common authored-name contract; it does not
introduce a new GoogleSQL Unicode equivalence rule. The authoritative rules are
in `docs/spec/language.md`, Source representation and Field names and nested
paths: authored names use Unicode 16.0 NFC and LF line endings. STRING data values
retain their exact decoded scalar sequences. `docs/spec/query-text.md` explicitly
requires decoded backtick names to pass the common authored-name contracts.

```sql
SELECT 1 AS `e\u0301`
```

Before the fix, the ordinary builder normalizes the `select` object member name
to `é`, while the generated Result fields array retains decomposed `e` + U+0301.
The complete generated Program therefore disagrees with an independently
authored ordinary Program using `é` consistently. The normal checker rejects
the generated Program with `LocalConstructionFailure.Source`.
An escaped CR in a quoted alias has the same declaration/reference boundary;
the repaired regression also compares its complete Program with an independently
authored LF-name Program.

The baseline test failed 0/1 in `run-7Eybwr` / `focused-test-FXIe2y`.
The follow-up probe retained the generated Program and normal checker cause in
`run-xfnIJa` / `focused-test-bzmiAA`. Both attempts are under this worktree's
`_build/local-checks/attempts` and `_build/focused-evidence`, respectively.
Only the decomposed-name baseline was executed before the repair; the CR
regression's post-repair success is not represented as a separate pre-repair run.

## Repair

The admitted token stream caches common canonical spellings for quoted names
and parameter names. Raw decoded lexemes and their original source spans remain
unchanged. Query names, published relation alias parsing, expression references,
property names, and scalar/limit/frame/SGA parameter references use that admitted
name. STRING and JSON payload values never enter this cache.

Normalization is performed once per decoded name, within the original lexical
work budget. Additional UTF-8 bytes from NFC expansion are charged to the
existing literal-byte limit. No new runtime Owner, evaluator, wire type, value
canonicalization, schema pin or compatibility route is introduced. Current
machine artifact admission and common name collision checks remain intact.

## Independent coverage and publication status

- Complete ordinary Values Program expectations for decomposed Unicode and
  escaped CR output names, with ordinary checker acceptance.
- SQL ORDER and Pipe RENAME/WHERE/ORDER scope controls; canonical-name collisions
  must produce `DuplicateOutput`.
- Raw decoded lexemes, original spans, expression/property/parameter paths,
  published relation alias parsing, NFC expansion and lexical limit refusals.
- Existing escape, STRING, limit/frame parameter, SGA and parameter case tests.
- Public fixture controls include a complete authored JSON Program, SQL and
  Pipe, Unicode/CR names, exact decomposed/CR STRING values, quoted parameters,
  empty typed Result, range/CTE names, and pre-admission collision/retired-range
  refusals. They join the existing normal public acceptance corpus.

Focused JS: 37/37 (`run-grxx7k`, `focused-test-vUufo6`).
Targeted Node fixture/manifest/public-profile checks: 18/18 (`run-wfDYAi`,
`focused-test-hdMvD7`). The selected syntax interface also compiled for JS/Wasm/Native in
`run-HfHU6G`, using `moon info --target TARGET src/query_syntax`.
These are local results, not CI or public execution proof.
Fresh exact-SHA five-package Local/HTTPS execution is pending at this recorded
preparation point. The PR body will retain its final source revision, manifest,
digests, receipt and counts after execution. Full Core, proof, performance and
Native/Wasm execution are not claimed by these focused checks.
