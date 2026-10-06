# RIGHT JOIN: preserve SQL roles through ordinary LEFT JOIN commutation

Base: main `be30c8fdf2b3133219f7becc74c5667619806c70`.
Source inspection found no RIGHT query entrance although the common LEFT JOIN
can represent the same operation by exchanging inputs, keys and projection
sides. The independent regression failed at parsing before the fix
(`focused-test-Os65C1`).

Reference: [GoogleSQL RIGHT JOIN](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#right_outer_join)
and its USING column rules. The preserved side is the authored right input;
unmatched authored-left columns are NULL, duplicates multiply normally and
post-join WHERE still discards FALSE/NULL.

The existing shared JOIN lowerer now emits an ordinary LEFT JOIN with swapped
from/with and equality-key sides. Private projection slots retain original SQL
range names. RIGHT USING exposes the preserved key unqualified and keeps both
qualified keys distinct; its public key columns lead the row in USING order.
MAX_OUTPUT_ROWS, pre-join Pipe conditions and post-join predicates retain their
logical positions. Static Values cardinality accounts for an empty original
left while preserving right rows. No owner, provider, physical strategy,
authorization, re-acquisition, custom NULL rule or invented evidence is added.

RIGHT is routed through the existing shared scope, not duplicated in the
projection-only specialization. Unsupported predicates and public duplicate
output fields remain explicit. FULL/other JOIN restrictions are not weakened.

Independent JSON control, rows and complete column contracts are authored in
`scripts/fixtures/right-join-source-input.mjs`. Cases distinguish preserved
USING keys from nullable qualified-left keys, check key-first column order,
empty inputs, NULL keys, duplicate matches, post-outer WHERE and opposite
output-alias versus qualified-input ORDER. The compiler's Program is not used
to generate expectations or patch a failing submission.

Local checks before public execution:

- RIGHT JOIN JS 3/3, affected JOIN chains 8/8 and ORDER 6/6 (17 executed cases).
- Targeted Node public corpus/independent manifest checks 9/9.
- Existing generators refreshed grammar/import pins, canonical vectors and
  Workers/Node fixtures; read-only manifest/spec-family/canonical checks passed.
- Query syntax interfaces generated for JS/Wasm/Native (6 metadata tasks), not
  all-target execution evidence.
- Independent canonical grammar preimage:
  `sha256:436d5d5ed652cbdf5b1ddc22c50de549bcf57241022d6a0bc4b1636aa8dd61bb`.
  Prior grammar/schema identities are retained rather than relabeled.
- Focused evidence: `focused-test-UVp13z`, `focused-test-0diWWg`,
  `focused-test-fqQtBN`, `focused-test-4PBrrl` under `_build/focused-evidence`.

The unchanged public corpus is registered in both ordinary acceptance and
`node scripts/test-packed-public-query.mjs --right-join-only`: 12 planned
successes and 5 refusals per Embedded Local/HTTPS transport. Acceptance must
use normal five-package distributions, compare Named Result rows/schema/order,
preserve shared Source acquisition and request replay, and refuse invalid inputs
before admission/provider I/O. This pre-execution checkpoint establishes no
packed execution success. Exact source SHA/digests and result follow below.

No full Core, proof, performance, Cloud campaign, manual CI retry or merge is
performed here. Other Frontend/common-capacity obligations remain separate.
