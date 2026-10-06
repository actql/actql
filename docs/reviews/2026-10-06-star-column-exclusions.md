# SELECT star column exclusions

This unit connects the adopted GoogleSQL `SELECT * EXCEPT (name, ...)`
syntax to ordinary Program projection. It does not implement another
execution operation, checker, Source reader or Result owner.

## Counterexample and implementation

Before the change, the ordinary checker accepts a Program selecting `id`
and `amount` from the existing four-column fixture, but the equivalent
`SELECT * EXCEPT (customer_id, status) FROM orders ORDER BY id` is rejected
by the parser. The pre-repair focused test failed 0/1 (`run-Q8W8Ne`).

The parser retains each excluded identifier and owns its list. Star
expansion resolves exclusions against the current logical columns and
retains their evaluated physical slots in their existing order. GROUP
validation and SELECT-list ordinals use the retained expansion, rather
than counting or validating excluded input columns. Existing common
checking retains types, nullability and DISTINCT behavior.

The independent complete expected Program is authored in
`src/query_program/star_exclusion_test.mbt`. The public fixture contains
an independently authored JSON control and seven source cases, with
hand-authored rows and ordered type contracts. SQL hidden ordering,
Pipe quoted names, mixed projections, current SET slots, grouped
ordinals, CTE columns and typed empty output are covered. Five refusal
cases cover unknown/removed names, ungrouped retained columns and an
empty exclusion list. The same cases join the ordinary packed corpus;
`--star-exclusion-only` selects them for bounded local acceptance.

Pipe ordering in the quoted-name case uses the retained `amount` column;
the SQL case independently exercises sorting on excluded input `id`.
This avoids relying on an unverified restoration of an excluded Pipe
input after SELECT.

## Identity and verification

The normative query rules and grammar change their compilation pin to
`sha256:92c856defd0bc75bb8b5592bab01327343421f2498ecf2a8fd8549f3c2197d45`.
The Values Run vector is
`sha256:cdb7ea45586739d1b8fd7e3d4b030c1df0957760e35f7df1b938094c95db2eb1`,
calculated from an independent canonical preimage. Historical grammar
and Run vectors remain. Registry, schemas, common value/expression laws,
Unit and Result Plan are unchanged.

Focused precommit results: query-program selection 14/14 JS
(`run-J0SYyB`), parser 2/2 JS (`run-mLWGuE`), affected fixture/profile/
identity consumers 18/18 Node (`run-AZZ4z2`), revised public fixture
2/2 Node (`run-a1HhAd`) and actual Values Run issuer 1/1 JS
(`run-sohOqq`). Relevant generator freshness checks passed.
An invocation without the pinned MoonBit PATH failed with ENOENT
(`run-isOESd`); it is not a product failure or a passing test.

Clean-HEAD five-package production and external-install Local/HTTPS
acceptance are still to be executed. Those results and exact SHA belong
in the PR's evidence record; precommit test success is not public
execution success or submitted-HEAD CI success.

Full Core, Wasm/native, proof, performance, the complete packed corpus
and Cloud are not run locally. Qualified/expression star, REPLACE and
unsupported JOIN/Graph star remain separate implementation gaps. This
unit is not completion of the overall Frontend migration.
