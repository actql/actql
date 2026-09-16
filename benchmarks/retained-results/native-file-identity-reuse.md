# Existing-contract native file identity reuse

The standard DuckDB Host now reuses an already mandatory ordered content CID
after a scoped native import from its exact admitted immutable file. This is an
existing-contract optimization, **not** new-profile permission to omit a CID.
Output CID generation and old Acquisition/Artifact fields are unchanged.

## Adopted implementation and evidence

The trusted implementation is the installed bounded Node Host plus the pinned
DuckDB Node `1.5.5-r.4` single-thread session, restricted by the existing compiler to uniquely
mapped Number, Boolean and Text columns. Unsupported wrappers, ambiguous names
and user `rowid` remain ineligible before native I/O. The native value probes
cover finite boundary vectors; this implementation is part of the declared
trusted base, not a new mechanized AoA/Smooth correspondence proof.
The bounded session checks its SDK revision before native use. Unbounded or
multi-thread configurations retain ordinary ordered hashing after import until
their correspondence is adopted; native file import itself remains available.

`NativeFileInputPlan` is constructed from the exact `ComputeNodeRun`, receiving
port, retained `ProducerRead`, and bounded compiler-produced SQL. It is one-use
for evidence installation and rejects a different run/port or a closed run.
The installed Host executes only that plan's CREATE/read_json command in the
private session against the Store-granted exact path. It waits for the entire
borrow, including final file identity/integrity checks, before installing the
copy verifier. No table mutation occurs between import and its ordered scan.

The copy verifier is trusted Host wiring, not a provider-controlled option or a
certificate obtained from arbitrary SQL success. The new low-level exports do
not sandbox malicious native code. As with other installed Host verifier APIs,
they must not be exposed as caller-selectable proof issuance.

The common retained scan still binds the exact receiving input and material,
checks current liveness and wire limits, and verifies the complete row count.
When compatible, its receipt comes from the original successful typed admission
and content identity. Equal hashes or equal schemas cannot select another input.
If the reuse preparation does not apply, the unchanged ordered hashing path
remains; failed native I/O is not retried as a successful alternate import.

## Work removed and work retained

Removed: the typed scan's repeated canonical row-array encoding/content hash.
`logicalCidPasses` is zero and `identityReused` is true when this path applies.
The required CID remains present and identical to the admitted producer's CID.

Retained: physical file integrity verification and import, complete typed input
validation, consumer-specific demand and join checks, per-value measurement,
logical guards and accounting, retained source liveness, output generation,
required output identities, and independent retention/cleanup. This does not
yet eliminate the full input scan or Host cell transport. The broader managed
profile and unchanged-value evidence-transfer work remains outstanding.

Import can coerce a JSON string into a Number, as the
[negative probe](native-file-correspondence.md) demonstrates. Therefore the rule
is limited to exact already-admitted immutable input, never arbitrary JSON whose
physical bytes merely happen to hash correctly.

## Validation scope

The normal benchmark correctness smoke covers 27 combinations (100, 1,000 and
10,000 rows across the nine workload/layout shapes), not the registered large
27-case matrix. It checks independent expected final CIDs/counts, process exit,
retention and cleanup. Added assertions require identity reuse and zero logical
hash passes on every fresh-file input while all input rows remain typed-scanned.
The smoke passed before fixed-SHA performance sampling; its elapsed times are
not alternating-pair acceptance results.

No registered ceiling, comparator, fixture, wire, preimage or contract pin changes.

Verification passed: adapter 22 tests on each of JS, Wasm and native; standard
Host, typed fixed Host, native conversion and delegated/direct-file integration
22 tests; installed representation boundary 5 tests; JS Host deny-warning check;
cross-target API, full documentation/contracts and formatting/whitespace checks.
After restricting reuse to the SDK-checked bounded single-thread session, the
10,000-row numeric-64 reuse case passed again with all new phase assertions.
