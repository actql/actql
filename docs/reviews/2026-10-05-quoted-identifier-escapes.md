# Quoted identifier escape alignment

Base: `7e32faa5a455dc4beafa02a8cd06313e83772d50` (`origin/main`).
This Frontend unit has no unmerged dependency.

## Counterexample and selected reference

The source `SELECT 1 AS` followed by `` `space\040name` `` was rejected by the shared lexer,
although its decoded field name is accepted by the ordinary Program checker.
The baseline runs six independently authored tests: one passed and five failed.
The failures cover decoded identifiers, physical newlines, bounded decoding and
ordinary column/alias/parameter lowering; they are not execution failures.

The selected GoogleSQL reference is
[`d82db99a923a46571f543a13899dc791a7b6f743`](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/lexical.md).
Its quoted identifiers use the STRING escape repertoire. The
[pinned identifier decoder](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/public/strings.cc)
uses the same non-raw scalar decoder with a backtick closing delimiter.
This is a selected lexical contract, not live Google service validation or a
claim of complete GoogleSQL compatibility.

## Minimal implementation

The existing bounded `Scanner::quoted` decodes escapes for STRING and names.
Remove its backtick-only exclusions for quote/control, octal and hex escapes,
and allow physical control scalars in nonempty backtick names. Three octal
digits still require a first digit of 0..3 (maximum U+00FF). Unknown, incomplete,
surrogate and out-of-range escapes retain their precise refusal kinds.
Physical CR/CRLF becomes LF as in the pinned decoder; escaped CR remains CR
at decoding. Original byte/line spans and decoded-byte/work ceilings remain.

Backticks produce names rather than STRING values. Identifiers do not acquire
raw/triple/chunk-concatenation syntax. The ordinary authored-name constraints,
case rules, published relation lookup, parameter declarations and authorization
remain independent of quoting. Decoding does not relax those contracts or
normalize all STRING values. This unit does not claim a new identifier
normalization policy or complete unrestricted field-name support.

The shared STRING, raw/triple/chunk and Graph annotation behavior is unchanged.
No parser, executor, wire format, Host owner or admission bypass is added.

## Independent public obligations

The normal packed corpus includes an independently written JSON control and
source cases for octal, hex/Unicode, physical newline, escaped punctuation and
control characters, qualified input/range lookup, Pipe alias lookup, a declared
quoted parameter and typed empty output. Rows and ordered column contracts are
written directly; the harness never repairs the emitted Program.

Both Embedded Local and authenticated HTTP must retrieve Named Result rows and
`describe()` columns, complete streams, and preserve the same Run on
resend/attach/lookup without repeated acquisition. Malformed and empty names
must have typed input refusal with zero Run admission and provider I/O. The
`--quoted-identifiers-only` selection is a bounded local acceptance option;
the same fixtures also belong to the ordinary packed suite.

## Identity impact

Changing query-text rules changes the Grammar Manifest to
`sha256:326eba3f9a470d6a0c5efc2170e7080f9c07af70e4d53ec8e77f1fa2190ee1db`.
Its containing document, normative imports and generated compiler/vector pins
follow the actual source bodies. All contract versions remain 0.1; operation
registry, barrier, Program schema and stored String semantics are unchanged.

Compiled identities bind the changed grammar. The existing independent Values
preimage derives Run CID
`sha256:f18cc670d9641a309394b03a5fbfae37bc2aaeae1b79be26d0265d3dd77ad225`,
while retaining the old grammar/Run vector. Values Unit, Result Plan and bound
proof identities are unchanged. The expectation is computed from independent
contract bodies, not a product issuer's returned CID.

## Verification

- Baseline narrow JS: 6 tests, 1 passed and 5 failed (expected counterexamples).
- Repaired narrow JS including lexer, STRING/literal forms, Graph annotation,
  Program/checker and the changed Values Run consumer: 33/33 passed.
- Selected Node manifest/import/independent-vector/corpus checks: 12/12 passed.
- Read-only compilation freshness, 368 canonical identities, and specification
  family closure (10 owners, 255 machine imports, 23 document imports) passed.
- Three packed-fixture script syntax checks and changed-source formatting passed.
- Clean source `01897b4ce67bedcda9c01168125d4a29875d11cc` passed normal-prepack
  external Embedded Local and authenticated HTTP acceptance: nine positives
  (one JSON control and eight source cases) and nine preparation refusals per
  transport. Command: `node scripts/test-packed-public-query.mjs
  --quoted-identifiers-only --keep-artifacts`, serialized through the existing
  shared heavy-check guard. Original receipt `public-query-evidence-1ZbN1T`
  records a clean checkout, all twelve child commands at exit zero, complete
  output and no evidence errors. README Local/HTTPS and missing-asset controls
  passed separately.
- Named rows, ordered full column contracts, nullable/empty output, completed
  streams, same-Run resend/attach/lookup and acquisition counts passed. Refusals
  left Run admission and provider I/O unchanged. The post-execution coverage
  table/report changes are documentation only, not another packed run.
- Five ordinary `npm pack` tarballs include their prepack output and were
  installed outside the checkout; the consumer has no compiler on PATH.
- Submitted-SHA required CI, Wasm/native and full integration: unverified.
  Actions is currently blocked by billing; no manual rerun or full local campaign
  is used to replace those checks.

| Package | Tarball SHA-256 |
|---|---|
| client-wire | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| sdk | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| run-host-core | `a8a2fa4987710fb6fe3e305bea07bfdc1ed10be64379fa527e9117c2df056025` |
| local-node | `39b12d06fe4e02ddefec3d5a97c180b5cf28492e422df8fd098c85f6a1a060bf` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |
