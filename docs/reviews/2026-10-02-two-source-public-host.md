# Two-source public Host, 2026-10-02

Integration baseline: `16d93c2bf7c9c7aa0c485416a7ea1436fd8a060a`, including
merged #172, #173, #175, #176 and #177.

This unit connects an ordinary JSON Program with two independently configured
DuckDB acquisition-prefix stages to the existing relational JOIN, explicitly
ordered Named Result, Embedded Local Host and HTTP Host. The public call is
`client.aql(JSON.stringify(program), {format: 'json', requestId})`.
The complete input and independent expected rows are in
[`two-source-join.program.json`](../../adapters/host-node/fixtures/two-source/two-source-join.program.json)
and
[`two-source-join.expected.json`](../../adapters/host-node/fixtures/two-source/two-source-join.expected.json).

Before this implementation, both checked acquisition requirements admitted
independently, but combined task compilation returned
`Compilation(Plan(TaskGraph(UnsupportedGraph)))`. The same public fixture on
the unmodified #177 package set returned `SubmissionUnknown` without source
I/O; that observation was not treated as a definitive rejection.

## Installed profile

`installation.sourceProfilePaths` selects exactly two absolute profile paths
for Embedded Local. `openInstalledRemoteHttpHost` accepts the same option.
It is exclusive with `sourceProfilePath` and `ACTQL_LOCAL_SOURCE_PROFILE`.
The existing singular option and its serialized identities are preserved.
The public HTTP factory export and packed consumer harness are supplied by
[#177](https://github.com/actql/actql/pull/177).

The bounded plural execution profile requires:

- Two distinct DuckDB bindings, with independently admitted environments,
  connector bindings and current read authorization
- Two independent acquisition-prefix stages, each with one checked source
  input and a candidate accepted by the existing native acquisition owner
- Existing checked success ordering between prefix stages; source data or
  supplied-input dependencies into the acquisitions remain unsupported
- Downstream operations supported by the existing Local compute profile
- Complete final Result source-policy provenance from both acquisitions;
  multiple final Results must have the same checked effective policy

Installation only publishes bindings. A one-source Program using the plural
installation performs no I/O on the unused source. Conflicting connector
bindings, ambiguous configuration and unsupported plural acquisition profiles
are refused before their provider I/O. Plural broad acquisition is currently
unsupported. The existing singular broad fallback is unchanged.

The existing single-source public check and disclosure behavior is preserved.
Plural installations conservatively return `check_unavailable`, with no source
I/O or partial report, until the disclosure adapter supports independently
authorizing each source occurrence.

SQL/Pipe text lowering for the two-source JOIN remains B's subsequent work.
Effects, INFER, new providers, arbitrary interleaved acquisitions and Cloud
execution are outside this unit. #170 separately concerns single-input native
versus broad/residual acquisition competition; this report makes no additional
plural-broad commitment.

## Ownership and evidence

The checked occurrence, its stage/input/task coordinates and the exact Program
and QuerySequence owners select each capture. Source references select installed
bindings; logical content CIDs never substitute for occurrence ownership.
The original CapturedInputSource liveness and identity checks remain in force.

One existing Run ledger is created before the first physical acquisition.
It includes both existing NativePhysical capture capacities, their installed
transport envelopes and the existing Local import/output allowance. Each native
issuer retains its original capture and positive holding until the exact DAG
task accepts that holding through `retain_captured_task_allocation`. The existing
`release_confirmed` predicate keeps the holding live until the original issuer
and cleanup owner confirm release. Closing an earlier capture cannot establish
that a later unknown acquisition stopped. Cleanup retries the original owners
without another source read or computation.

The multi-root Host uses the existing installed-offer selection. It does not
apply the first capture's statistics to every independent input. Existing
reservation formulas are reused. These are declared accounting capacities;
this work adds no allocator-byte or RSS guarantee and does not change the
separately reviewed capacity-proof foundation.

Each Source Evidence entry retains its own checked source policy. The final
ObservationSet and Result use the existing checked publication source-policy
owner's effective CID. The existing `source_evidence_cids` array and
`independent_snapshots` consistency describe both occurrences. The Result's
`input_relation_cids` field is a unique logical-content dependency set, as
required by `actql-lookup-identities.json`; equal-content inputs can share that
content dependency while retaining two captures and two Source Evidence entries.

## Durable admission and restart

The public caller-input intent remains `selection: "none"`. Physical placement
and installed generation do not become a new public request fingerprint.

A separately tagged Host-private multi-source captured submission records the
ordered occurrence pair. Each required read approval binds its own occurrence
and the complete captured submission. Earlier approvals are checked again at
trusted time before physical start. The singular captured-submission and
acquisition-intent bodies retain their existing bytes.

All-allow admission atomically retains a canonical `sourceInventory` string in
the existing request row's private Run admission evidence. It includes the
complete occurrence pair and environment identity. The schema, table and
database also retain exact UTF-8 bytes alongside normalized display strings.
Duplicate or racing unstarted admission cannot replace or retrofit that
inventory. Private inventory drift yields the existing public
`ClientRunStartDenied` classification while lookup preserves the original
accepted Run. It does not imply that the original submission was never accepted.

After physical start is durably reserved, a restarted Host reconciles the
original Run. A lost capture remains `started_unknown` unless retained
publication proves completion. It does not reacquire the first input, even if
the current installation's physical binding has changed. A successfully
published Result can be attached, looked up and read after a fresh process
without reopening either source.

## Verification

Focused source verification uses pinned Node 22.22.0 and MoonBit
0.10.12+1634b282e. The fixtures use actual independent DuckDB databases and
existing capability admission; expected rows are authored independently.

- Common publication and physical strategy packages: 51 tests passed on each
  of JS, wasm and native, including exact two-source policy coverage and
  ObservationSet encoding
- Native capture custody: 7 tests passed, including final cache-release hygiene
- Post-integration focused Host compatibility: 211 tests passed, including
  existing single-source Checkpoint initialization cleanup, public check and
  disclosure, Effect acquisition, and the suites below
- Request journal and two-source Checkpoint suite: 93 tests passed, covering
  immutable admission, racing/restarted inventory, corruption, strict UTF-8,
  two held approvals, expiration, current configuration, cancellation and
  original singular intent bytes
- Live capture boundary suite: 6 tests passed, including configuration
  exclusivity and immutable profile-path copying, distinct and equal
  content, tuple/requirement/evidence substitutions, foreign equivalent
  Program owners, pre-I/O preparation refusal and unknown acquisition ends
- Public Host recovery suite: 11 tests passed, including six Local/HTTPS
  success cases, six fresh-process retained cases, exact pre-start replay,
  binding/generation refusal parity, post-first-acquisition crash, a real
  second-provider failure, cancellation at the awaited second boundary and
  failed first-capture cleanup followed by exact-owner retry

The cleanup fixture observes a positive 139,926,400-byte first Native holding,
then confirms zero held/reserved byte fields after retry, unchanged cumulative
attempt/holding counters, no rereads and distinct primary/cleanup failures.
Actual Native in-flight cancellation and budget exhaustion are exercised by
the lower-level native custody suite. The unrelated pending-record-failure
race tracked by #159 is unchanged.

Final packed public-entry acceptance, broader compatibility checks and the
fixed-head hosted CI outcome are recorded in the implementation PR. Source
execution and local focused checks alone do not establish that final outcome.
