# Traverse path emission from public source

Base: `7e32faa5a455dc4beafa02a8cd06313e83772d50` (`origin/main`).
This is an independent Frontend connection; no unmerged PR is required.

## Problem and connection

The ordinary checker, Property Graph traversal owner and standard Host already
accept `traverse.emit: "paths"`. The public source lowerer admitted only the
node emission and assigned its three columns to every supported traversal.
The independent path Program passes the checker on the base; the same authored
source failed with `UnsupportedGraph` (baseline focused test: one of two failed).

`lower_script_traversal_rows` now selects the existing five path output names
for explicit literal `emit: 'paths'`: `start_id`, `end_id`, `hop_count`,
`node_ids`, `edge_ids`. Node emission keeps its three existing names.
Argument values, producer references, source positions and operation limits
still pass to the ordinary checker. Types, path admission, identity, resource
evidence and execution remain common-owner responsibilities.

No syntax redesign, implicit Relation conversion, new execution owner, sorting
implementation, acquisition, key evidence or capacity adjustment is introduced.
Missing/unknown/parameter-valued emission has no static output scope and is
refused. A direct installed selector Source still requires the existing checked
capture/share connection; an earlier DATA Relation is reused as a producer.

## Independent acceptance obligations

The complete expected Program in `traversal_paths_test.mbt` is authored
independently. It includes the selector producer, explicit hop/output limits,
all five output fields and ordinary Result declarations. Current-column and
quoted-DATA scope tests keep malformed arguments available for common refusal.

The external packed fixture includes one JSON path control and seven authored
source cases, plus the existing five node-emission cases. Two distinct keyed
parallel self-loops in definitions E and F must yield four length-two WALK
paths, two TRAIL permutations, the zero-hop ACYCLIC path, and an empty nonzero
ACYCLIC result. Each path compares complete typed node/edge identities and the
ordered identity arrays; no endpoint-tuple collapse is permitted. An unordered
output Relation is compared as a multiset, retaining multiplicity. The fixture
does not claim a new same-definition parallel-edge or snapshot proof.

Other cases exercise a quoted selector DATA binding, reordered columns after
WHERE, an empty selector and an empty ordered-hop label set. `Result.describe`
must match the declared column order and array/JSON/number nullability even on
empty results. Existing attach, request retry, lookup and source-I/O counters
remain in the shared public acceptance. Seven existing node refusals plus
eleven path refusals must leave Run admission and provider I/O unchanged.

## Identity and pin impact

The query-text rules are a Grammar Manifest input. Documenting the connected
path emission changes that manifest to
`sha256:6eadd94b7226575a88196089cb8a63fe54e0a01630d1dfbf7252806f3474d36e`.
The manifest's containing document CID, normative imports, generated compiler
pin and canonical vector follow the actual source bodies. Contract versions,
Program schema, operation registry and barrier pin remain unchanged.

Compiled plans, invocation templates and Run definitions bind the changed
grammar. The independent Values oracle retains the old grammar/Run preimage
and derives the new Run CID
`sha256:205f8330784cae5c7af4cde8f6269e947b46d1f679ed1653512f3e8ef6b7d829`.
Values Unit, bound proof, Result Plan and Graph definition-domain identities
are not changed by this documentation pin. Expectations do not come from a
product issuer or failed-test output.

## Common documentation follow-up

The generic traversal paragraph in `docs/spec/language.md` still describes
`edge_ids` using the historical `{src,dst,rel}` shape. The current Property
Graph contract, path checker and existing standard-Host path fixture preserve
full `{definition,domain,key,key_types}` identity. This Frontend unit uses that
current contract and does not downgrade an edge. The generic paragraph needs
alignment by the common Graph specification owner; no common-owner execution
change is claimed here.

## Executed and pending validation

- JS traversal files: 9/9; Values Run fixed-vector consumer: 1/1.
- Selected Node grammar/profile/independent-vector tests: 16/16.
- Read-only compilation freshness, 368 canonical identities and specification
  family closure (10 owners, 255 machine imports, 23 document imports) passed.
- Changed MoonBit formatting and three packed-fixture script syntax checks
  passed. The unmatched test-name selection executed zero tests and is not
  counted as successful evidence.
- Clean source `bbf63803fe3b4422e5d12f35a94edf456130aa77` passed normal-prepack
  external Embedded Local and authenticated HTTP acceptance: 13 positives and
  18 preparation refusals per transport (eight path positives plus five existing
  node positives). The command was `node scripts/test-packed-public-query.mjs
  --graph-traverse-paths-only --keep-artifacts`, serialized through the existing
  shared heavy-check guard. Receipt `public-query-evidence-7ApkHg` records a clean
  checkout, all twelve commands at exit zero, complete output and no evidence
  errors. README Local/HTTPS and missing-asset controls passed separately.
  Named rows, ordered full type contracts, empty results, path multiplicity,
  same-Run resend/attach/lookup, completed streams, no private columns and zero
  acquisition passed. Refusals had zero Run admission and provider I/O.
- Five packages were produced by ordinary `npm pack` with their prepack hooks,
  then installed outside the checkout. The consumer has no compiler on PATH.
  The source identity and package digests below are original receipt evidence;
  subsequent evidence-only documentation is not another packed execution.
- Submitted-HEAD required CI, Wasm/native and full integration: pending;
  no full local gate or manual CI rerun is part of this unit.

| Package | Tarball SHA-256 |
|---|---|
| client-wire | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| sdk | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| run-host-core | `93ba3347347da36ceebe19df8a5806d0c65d1c717961537479cc1e1d6df4f2c3` |
| local-node | `c149ec2fd0c727d0d6ce344c37ffbe4ea4d36a3933aec245d44636fe15824988` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |
