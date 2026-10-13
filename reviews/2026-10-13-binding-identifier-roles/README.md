# Ordinary binding and alias identifier roles

This is the existing F06 identifier-admission repair tracked by [#1834](https://github.com/actql/actql/issues/1834). It does not complete Calendar, authenticated score publication, or the full Frontend matrix.

## Counterexample and existing contract

`WITH ROWS AS (SELECT 1 AS id) SELECT id FROM ROWS` was accepted by the original parser even though the selected reserved-word contract requires a quoted WITH name. The same permissive `name()` call was used by explicit SELECT and source aliases. The implicit SELECT alias and adopted SGA OutputName already used the selected keyword owner.

At clean `43fad7f3d`, the focused regression executed three tests: two controls passed and the reserved-binding refusal failed. `run-qUeYe1` exited 2; its first failed source is the WITH example above. The other refusal cases in that test's loop were not reached in this original run and are not separately claimed as executed reproductions.

`QueryParser::binding_name()` checks the existing case-insensitive `query_reserved_word` owner before the ordinary name parser. WITH binders, optional source aliases, explicit output aliases and required output aliases use that seam. UNNEST element/OFFSET aliases, Pipe AS and Pipe UNPIVOT aliases use the same ordinary row-alias role. The general `name()` implementation, fixed signature/schema keys, quoted identifier canonicalization and path components remain unchanged. Original work accounting, duplicate/scope resolution and point diagnostic origins remain with the existing parser.

The original submitted repair did not connect the four manual row-alias paths. At the follow-up pre-fix source, `run-VFuBuA` executed eight tests: all four manual-alias refusal cases failed and all four normal/control tests passed. The failure is retained separately from the original WITH-only failure. Their independently counted refusal positions are 35 (UNNEST element AS), 55 (OFFSET AS), 19 (Pipe AS), and 42 (Pipe UNPIVOT AS).

The independent refusal positions are byte 5 for the ASCII WITH binder, byte 12 for `SELECT 1 AS ROWS`, and byte 26 for `SELECT id FROM records AS ROWS`. Quoted `ROWS`, `result_rows`, later `r.ROWS`, fixed `by:`/`as:`/`where:` and literal `SELECT`/`NULL` keys are controls. No new public reason code, wire contract or keyword set is introduced.

## Ordinary Program and installed acceptance

The quoted output control has a hand-authored complete ordinary Program expectation and reaches the existing common checker. Public expectations are ordinary Number columns with independent one-row values. Their JSON controls are authored independently of lowering.

Nineteen normal controls and sixteen refusals are appended to the existing delivered quoted-identifier fixture. SQL and AQL-text use the same submitted text. The existing ordinary corpus and `--quoted-identifiers-only` selection include them; there is no new Host, driver, Source adapter or execution path. Existing quoted-name controls and their independent values remain intact. The selected cohort contains 38 normal cases and 28 refusals per transport. The OFFSET control has an independent JSON expectation of zero, distinct from the element value one.

The existing public helper checks the refusal code, zero additional admission/I/O, same-submission identity, attached Result reads, lookup and cleanup. Those assertions are preparation until a new exact-source normal package producer and Local/HTTPS consumer actually execute. The accepted RRF packages from `9372ea55d87f726c1cb22ef74693f8e8b55eeeb7` cannot establish this changed parser's public behavior.

## Evidence boundaries

The initial repair `ffb242971b60c2911f42767ba3ef5073c03f8f50` passed 14 focused JS tests in `run-2URCOr`, including the refusal positions, quoted aliases, WITH scope, sequence keys and existing SGA OutputName cases. The subsequent public fixtures, complete Program control and pinned formatting require their own final-source verification.

No new installed E2E, Calendar runtime success, authenticated max/weighted score supplier, Hosted CI or formal release is claimed for this unit. Local bounds remain 60 seconds with TERM grace 5; any allocated normal producer and public consumer retain their existing bounds and clean-source/digest fences. Original RRF and earlier failure records remain immutable.
