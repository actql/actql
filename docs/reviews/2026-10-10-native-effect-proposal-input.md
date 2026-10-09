# Native retained Effect proposal input

## Connection

The existing Native consumer already retained actual Source/Transfer input and
verified a supplied Preview against its checked Plan. Its Provider connection
still lacked a way to derive proposal selectors and changes from that actual
input. `ResidentSourceCompute.read_effect_proposals` now advances the existing
completed Result exporter and common captured Effect proposal Owner together.
It checks the exact member, local Result and shared borrow before reading, then
confirms the original export receipt and complete row count.

The bounded callback receives canonical selector and intended-change wires.
They are data for Provider preparation, not a grant, approval, authored Preview
or apply permit. No Program plan is interpreted by the adapter. An incomplete
batch must be discarded after a typed error. The later existing Preview binder
and Plan verifier still check the held input independently.

The input/Transfer/capture owners retain their existing responsibility. This
reader cancels only its temporary export and proposal cursor. Receiver refusal,
encoding bounds and pin revocation do not return the holding's reservation.
Current input custody is checked before reading, after callbacks and before
accepting the completed receipt. No Source or Compute is executed by retrying
this read.

## Fixed-source verification

Implementation SHA: `f0bdbcbbbf1df21d7f2edda427387c9ab57b1aa6`.
Dependency: [#1173](https://github.com/actql/actql/pull/1173), published parent
`9be0698d3e5aac751110b46cc43a4f77eac5f4dc`. The final merge target is OSS main,
after the existing Native capture dependency series; this does not make that
series a formal Cloud adoption.

At the clean implementation SHA, the bounded nonzero-test wrapper executed:

```text
moon test --target native --strip src/platform_native/remote_resident_source_compute_tests/retained_compute_wbtest.mbt
```

All 9 tests passed using the pinned real DuckDB library, Native SQLite, crypto,
actual filesystem Transfer and existing Runtime fixtures. The new case checks:

- Independent selector `3` and intended change `{"state":"present","value":{"Name":3}}` from the Native consumer's row.
- A producer owner and a different local Result cannot deliver proposal rows.
- An undersized encoding bound fails before the receiver is called.
- Receiver failure preserves the held bytes; retry reads the same original input.
- Returning a separate pin inside the callback leaves that batch incomplete, while the original pin remains usable.

The enclosing actual fixture continues to check Source acquisition once,
consumer execution once, original Artifact/Manifest binding and formal cleanup
of independent receiver, borrow and producer holdings. The existing cancellation
and saved-envelope/Runtime cases are part of the nine-case selection.

Formatting, generated Native interfaces and `git diff --check` passed.
Native test executable SHA256:
`e8399040de5d746cbdbfb67a1935a7c6444a1c7c598471701a8e9fc79c8946de`.
This identifies a whitebox acceptance executable, not a production Site binary.
Local evidence: `_build/native-effect-proposals-1791567519587`.

The initial diagnostic's new case passed, but its separate Runtime selection
aborted because the verification wrapper omitted the signed runtime bundle
fixture. That failure remains in `_build/native-effect-proposals-1791567275237`.
The full affected selection above used the existing signed runtime fixture and
passed; no product assertion was weakened. A deprecated Ref constructor found
in the initial test was removed before the fixed-source run.

## Remaining execution boundary

Actual Provider target I/O, capability/target-read authorization and Preview
authoring are not performed by this read API or its callback tests. They must
connect to the existing installed Provider Owners and use their real observations.
Run waiting commit, authenticated approval, physical restart restoration,
Effect apply/reconciliation and final Effect publication/release remain separate
unfinished #138 connections. Current authorization must be checked independently
from Source permission. No new scheduler, Ledger or successful mock response is
introduced. Hosted CI remains disabled; no CI run or deployment was started.
