# Retained record identity: bounded wire hashing and exact matching

## Production boundary

Parent implementation: `7c3fb0ac50b7271ae906be160b0e43d08e3dc14b`
(#551). The integration adopts main
`2338fca4c86dbe76aeb1e738eac5e86c3d3ed628` by an ordinary merge, including
#555's independently derived
Pool key-test limits. The PR records full integration and publication SHAs.

The previous shared append cursor emitted a long identity incrementally, then
assembled its entire wire into a String in `FinishKey`. String-key Map lookup
also hashed/compared the complete wire synchronously. This was distinct from
the already stepped record value emitter and from typed Pool comparisons.

[The existing storage owner](../../src/managed_record_storage/append_steps.mbt)
now emits identity wire into the existing hashing writer. Its final digest has
fixed length and is an internal index, not a new semantic identity or CID.
The index selects prior retained records, not giant retained key Strings.
Collision links use the same retained record objects; there is no second
record buffer, external storage engine, scheduler or ledger.

Digest agreement is never equality. A candidate's identity fields are located
one field per poll, then
[the shared wire matcher](../../src/managed_record_storage/identity_steps.mbt)
re-emits both identities into existing buffered hashing writers. Each poll
emits one value frame or compares at most 64 UTF-16 units. Each drain is bounded
by one emitter frame (at most 388 escaped bytes including punctuation); the
512-byte buffer is not an arbitrary aggregate identity restriction. Reference
envelopes use the same bounded canonical emitter. Matching crosses fragment
boundaries and preserves exact wire, Unicode, escaping and tuple order.

The old synchronous append API uses the same index/equality domain, so records
from either API participate in duplicate detection. Its drain remains
synchronous and is not used as a Pool fallback. It admits both comparison
stacks before allocating them. Stepped callers reserve the additional stack,
borrowed prior identity references and fixed comparison custody before lookup
scanning or stream allocation. Failed/unfinished comparison stays reachable
until explicit cleanup. Borrowed prior rows are not cleared by cursor cleanup.
Completion drops the private lookup index so it cannot retain discarded rows.

Canonical wire bytes, original construction nodes/overhead, record order,
schema and public APIs are unchanged. The retained byte charge still includes
the original full identity wire: removing its String does not relax budgets.
Comparison polls are cumulative control work, not another construction charge.

## Independent resource and semantic evidence

[Shared fixtures](../../src/managed_record_storage/identity_steps_wbtest.mbt):

- One 130-ASCII identity: `["<130 a>"]` is 134 bytes/two nodes. Record wire
  is 144 bytes/four nodes; width overhead two makes construction **8/7**,
  aggregate bytes **278/277**. Cursor `8+2+1+3*2=17` plus retained row three
  gives workspace **20/19**. Success takes 22 polls. Work-short fails at the
  value-node check (poll 16), not an unrelated rejection; workspace/byte-short
  fail at poll 21. Original typed priority is preserved.
- Duplicate matching reserves another `8+1+3*2=15`: prior row three plus cursor
  17 gives **35/34**. Exact reaches typed `DuplicateIdentity`; one-short gives
  `WorkspaceLimit` before comparison allocation. Prior construction eight and
  retained bytes 278 survive until builder cleanup, which releases them once.
- A forced digest collision with unequal wire must commit, then reject a real
  duplicate from the synchronous API. Replacing exact equality with digest-only
  rejection fails `Err(DuplicateIdentity) != Ok(true)` (`run-Dj9gmI`,
  `focused-test-yPN94P`). The mutation was removed before integration.
- Composed/decomposed Unicode, CRLF/LF, escaped controls, crossing surrogate
  pairs and long late differences retain exact equality rules. Vector/JSON
  Array wire equality tests different emitter continuation boundaries without
  making structured values eligible Carrier keys.

[The Pool boundary](../../src/local_veca/pool_identity_output_wbtest.mbt)
uses one two-dimensional member and an 8,096-unit Text group. Starting from
61 scalar control units, Text adds 8,095 typed validation units and two sets of
127 wire polls: **8,410/8,409**. Quanta 1, 7 and 256 have the same literal group,
member count and construction work 18. Before append there are 8,125 control
units; the key's Text chunks occupy 8,138 through 8,264. The 32nd 256-unit
quantum, **8,192**, is inside identity hashing, not input validation or record
emission. Cancellation retains output and borrowed input before confirmed stop;
cleanup releases the pending append/output once, with input still available.

## Ordinary retained Host

[The installed Host case](../../adapters/host-node/public-pool-key-retention.test.mjs)
uses the ordinary Program shape:

```text
Values(id=1, group=<8,096 g>, embedding=[1,2])
  -> to_vectors -> pool_vectors(sum) -> vectors
  -> published + consumed_a + consumed_b
```

All three explicitly named Results are read from the real retained Store and
compared as ordered arrays with authored rows. Reusing the same request creates
no Compute/dispatch. An awaited existing Host hook sums Pool child work after
the bridge and suspends at 8,192. Cancel persists the request without claiming
physical stop or publication. Snapshots remain unchanged until the hook is
released; confirmed stop leaves all three Results unavailable, no further
Compute/dispatch and an empty Carrier snapshot directory. Core fixtures supply
borrowed-input/cursor custody evidence; snapshot emptiness is not a full holder
or reservation census.

The first public fixture used 16,384 characters and failed before publication
(`run-mAG5bl`, `focused-test-Dijxid`): the installed record provider has an
unchanged 10,000-byte value ceiling. The three existing public cases passed.
The corrected fixture fits that configuration and passed one selected case
(`run-QKqeWl`, `focused-test-17cJGZ`). No product limit was increased or failure
expectation weakened to accept that initial refusal.

## Focused verification and residuals

Integration source: `9f15740b32fd48bc27dfa7da9a7de61fe42bac92`.
Shared storage/runtime and direct Pool fixtures passed **43/43**
(`run-KZuvG8`, `focused-test-xAODZc`). That run includes the earlier 16,384-unit
kernel fixture; the final smaller public-aligned fixture is separately selected.
The normal Git-history checker passed on this clean integration source and
wrote only its ignored foundation artifact. It was not a proof campaign.

Only `local-node` and `run-host-core` runtimes were prepared from integrated
sources (149 build tasks). They remain ignored. The later fixture/docs edits
do not change their production inputs; this is checkout Host acceptance, not
a newly packed or HTTP distribution campaign. No public MoonBit signature or
schema/pin changes are introduced.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/managed_record_storage src/managed_record_runtime \
  src/local_veca/pool_wbtest.mbt src/local_veca/pool_text_comparison_wbtest.mbt \
  src/local_veca/pool_output_steps_wbtest.mbt \
  src/local_veca/pool_identity_output_wbtest.mbt
node scripts/local-checks.mjs test moon -- --target js \
  src/local_veca/pool_identity_output_wbtest.mbt
node scripts/local-checks.mjs test node -- \
  --test-name-pattern 'inside output identity hashing' \
  adapters/host-node/public-pool-key-retention.test.mjs
node scripts/check-local-resource-accounting.mjs
```

The selected gate/inventory checks passed **6/6** (`run-DNjSxc`,
`focused-test-KxWj9r`); the actual resource CLI passed while explicitly not
asserting full boundary completion.
The gate requires identity limits, collision equality/custody, operator control
and the suite-connected ordinary Host case. Removing a required role fails;
declared three-target connections are not unexecuted target success.
Final focused commands, SHA and automatic Draft CI state are recorded in the PR.

Still separate: synchronous field/schema/type/name checks, unconverted record
append callers, Pool Relation composite identity concatenation and other
operator scans. Wasm/native, full Core, packed/HTTP, new Store fault campaigns,
whole-Run exact Ledger budgets and measured cancellation latency were not run.
Existing Store/cleanup owners are reused, not re-proven by this case. This is
one retained identity boundary, not all-Local completion.
