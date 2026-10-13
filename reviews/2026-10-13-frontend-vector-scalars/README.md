# Adopted vector scalar frontend connection

This independent PR-6/F05 unit connects the four already adopted public names
from `spec/frontend/frontend-profile-r1.json` to the existing expression Owner.
It does not change a numerical law, add a cast, admit a new profile, or repair
the separate legitimate `RetentionLimit` control.

The original test-only overlay on main
`d879fb93ae19a314c44f5fb8e1fea1461bc3d0d5` reached the common checker for an
independently authored Program, but the four public expression names and the
complete SELECT source failed: JS 1/6, `run-tk2Dy0`. Raw original evidence is
preserved outside the worktree under
`/Users/t14i/workspace/20260822/reviews/2026-10-13-b-vector-scalar-evidence`.
The later `run-LDf0CM` failed three serialized-object-key-order expectations;
`run-5QUAkl` failed a checked Vector contract expectation omitting the normative
`element_type: f32` (`docs/spec/language.md`, Value contracts). Both failures are
retained. Those corrections change neither the authored operator tree nor the
expected typed result.

`run-d2sXnf` then executed JS 11/11 and Node 19/20. The sole Node failure
is the existing WITH-cutover profile assertion rejecting the inherited
`Token.annotation_compatible` field (`query_syntax/lexer.mbt:19` and generated
interface); both sources are byte-identical to main for that field. It is
reported separately and not removed or weakened by this unit. The guard
terminated with exit 1; the four later read-only steps were not reached.
`prepared-checks.mjs --remaining` selects only those previously unexecuted
read-only steps, not a replacement success for the failed aggregate.

## Existing meanings

| Surface | Existing expression | Result |
|---|---|---|
| VECTOR_COSINE_SIMILARITY(a,b) | vector_score cosine | Number |
| VECTOR_INNER_PRODUCT(a,b) | vector_score dot | Number |
| VECTOR_L2_DISTANCE(a,b) | negate(vector_score l2) | Number |
| VECTOR_CONCAT(a,b,...) | vector_concat | Vector with summed dimensions |

Common typed Vector, profile, NULL, zero-vector, binary32 input, numeric failure
and evaluation/resource obligations remain intact. The public names are
ActQL's adopted forms, not aliases claiming GoogleSQL distance conformance.
An ARRAY remains an ARRAY. Ordinary Parameter declarations exclude Vector;
the public controls therefore require a typed Relation supplied by the
existing Source owner rather than an invented parameter or literal path.

Metric functions have distinct public reuse identities even though they share
the same vector_score node tag. Existing quoted/case-insensitive function
lookup is retained. Scores have exactly two arguments; concatenation has at
least two, preserving authored order and repeated operands.

## Finite evidence and pending public boundary

`prepared-checks.mjs` uses the existing nonzero-test wrapper and 60-second,
TERM-grace-5, non-Heavy guard. It selects only the changed expression/source
controls and the existing function-identity caller, targeted Node fixture and
identity checks, and read-only manifest/metadata/spec-family/canonical checks.
No full Core, Provider, Native/Wasm execution, package producer, or Hosted CI
is included.

The independent grammar/Values vectors in `preimages/` preserve the prior
source, Program, Values dependencies, numerical contracts and resolved limits.
The new source rules reidentify grammar-bound compilation/Run bodies only.
`vector-scalar-identity-oracle.mjs` hashes authored/retained bytes and normative
contracts; it imports no product compiler or canonicalizer. Canonical generated
vectors come from the existing generator and are not independent expectations.

`scripts/fixtures/vector-scalar-source-input.mjs` prepares 12 positive controls
(four operations in JSON/SQL/AQL-text) and 8 refusals, with independent values,
full ordered schema, NULLs, dimension and arity boundaries. The JSON control
uses ordinary typed Values. The text requires the admitted `vectors` Relation
with exactly the declared schema/rows. It is not currently registered in the
packed public consumer: that consumer's existing Source installation exposes
other schemas. The next finite acceptance connection must use its existing
Source/Host/cleanup owners to install this typed Relation and route these same
controls, without enabling a Vector Parameter or modifying lowered Programs.
No public scenario or consumer execution is claimed by prepared fixture tests.

External installed Local/HTTPS acceptance, same-request replay, actual Run/
Result values/schema and physical cleanup remain unexecuted. The ordinary
five-package producer and consumer each retain the existing 300/5 caps and
require an explicitly assigned shared Heavy window. No Heavy window is acquired
by this unit. Sequence #1780 and the original 98-case repair are separate fixed
sources and evidence; neither is rerun here.
