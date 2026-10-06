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

## Public normal-package result

Normal five-package source: `f57db80706b211d431a3ba6503cb82c6f6ddfa80`.
Both Embedded Local and public HTTPS passed 12/12 successes and 5/5 refusals
with unchanged input/oracles and Host limits. The existing helper checked
Named Result rows and describe column contracts/order, one Source acquisition,
no added I/O on reads/attach/request retransmission, same Run on identical
request replay, and refusal before Run admission/provider I/O.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-right-join-20261007-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-right-join-20261007-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-graph-composition-probe-e90/npm-cache \
npm_config_offline=true npm_config_include=optional \
node scripts/test-packed-public-query.mjs --right-join-only
```

Pinned MoonBit/Node PATH and MOON_HOME were used by the producer. Evidence:
`worktrees/.codex-scratch/public-query-evidence-ip0hbe`, with passed/complete
summary and captured Local/HTTPS output. The successful harness removed its
external installation after preserving logs/source/tarball evidence. Producer
directory retains all five tarballs and `packed-client-packages.json`.

| Package | Tarball SHA-256 |
|---|---|
| client-wire | `fb29996f1d058d505ab2ea2220e53370f91cf3e945816cf9c85711f22f6006ef` |
| sdk | `2dc2a4e12609945cf747a4c897bf1527a8597ef43fcfc5434966166f39623c09` |
| run-host-core | `b84dfbd73d4a91818c1465a928e447b59d1d16a273a5f27479a6faa41582c1d3` |
| local-node | `27945416daecc79c64c34077c303c18d9dce7248c722f3a44a0e5141200b2514` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Submitted-HEAD CI/content review remain distinct. The later evidence-only
commit is not another runtime build. Keep Draft; final destination is main,
with no unmerged feature dependency. No universal JOIN/backend conformance or
closure of the unrelated #680 capacity reproduction is claimed.
