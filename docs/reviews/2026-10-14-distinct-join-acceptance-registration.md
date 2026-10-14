# Restore the original DISTINCT JOIN acceptance selection

Base: `3605d1829df24df9d826efc3e35bb5cbf462306b`.
Refs #640. This is acceptance registration preparation, not new capacity or
public execution evidence.

## Exact original input

The restored `scripts/fixtures/distinct-join-order-source-input.mjs` is
byte-identical to Git blob `7f4bebce4e3a8340b59661b1ad695c9b24021fdd` at
`57c5ce979025c57ac8d2dc65affaa9bedb83b0b7`.
It retains seven successes, three preparation refusals and one runtime failure
per transport. No syntax migration, query/Program rewrite, expected-result
change, Host budget change, source-profile change or capability-pin change is
included.

The original pipe case retains JOIN ceiling 25, `l.id > 0`, projected DISTINCT,
post-DISTINCT ordering, LIMIT 2 / OFFSET 1, nullable `amount` and the independent
rows `[{"amount":-1},{"amount":-2}]`. The demanded-sort failure retains its own
source rows, so `1 / (amount + 2)` encounters the authored zero denominator.

## Existing public route

The explicit `--distinct-join-order-only` flag selects those eleven cases in
the existing packed public-query driver, standard profile, transport workers,
installed Local/HTTPS Hosts and shared public acceptance helper. It does not
add cases to the default full corpus or replace the existing harness.

The driver now rejects unknown arguments before source lookup or packing.
This selection rejects other CLI selectors and conflicting inherited selection
variables; an environment-only DISTINCT JOIN selection is rejected. A misspelled
flag cannot accidentally launch the full corpus.

Before product setup, the selected worker's expected inventory must contain
the eleven original identities in order. Before any coordinator tail, both
Local and HTTPS completion reports must contain exactly the seven successes,
one runtime failure and three refusals, with unchanged case-content digests,
one retained cohort per transport and no tail requirement. Existing complete
inventory checks, Source counters, Run/result assertions, same-submission reuse,
package audits and artifact identity checks remain active.

## Mandatory preflight correction

The base's mandatory `public-query-profiles.test.mjs` still asserted 4178 cases,
2612 successes and 1513 refusals, while the adopted inventory pins 4181 cases,
2616 successes and 1512 refusals. This mismatch predates this restoration.

PR #1808 independently added four successes (`general-element`, `array-field`,
`conditional-array`, `lazy-array-branch`) and removed the former
`general-element` refusal. Its base is
`14ef2d54f2c7d860dc106f51a2a18fe1d2a1bad5`; its head is
`172c3de3810a1ead84dd19b3a3eff6f1976283e6`; its adopted merge is
`3b5e68efa59d4cb1b56eb88233d65101b51dc324`.

The resulting ARRAY fixture blob
`702f1f717d6df25ca28f4d16e35ba61fb270247e` and inventory blob
`f29960c7feff612bdc48b68cc013b76d1732d780` are identical at that head, merge and
this base. The stale profile-test blob
`b6c782f4744df828eb8656126f5ca074705fa79e` is unchanged across the same adoption.
The three hardcoded count/profile assertions are aligned with that independent
four-success/one-refusal delta. The inventory JSON and digest are unchanged;
the existing enumerator's exact digest/count/profile/repeated-failure equality
checks remain mandatory. Full current inventory freshness is not inferred from
this static correction.

## Verification and next execution

Static source review confirms the restored historical blob identity and the
selected registration paths. No executable tests, syntax checker, compiler,
runtime build, package producer or public consumer was run in this environment.
The available task-environment list was empty and the canonical guard home was
read-only. No guard relocation, alternate HOME, source overlay, timeout increase
or direct unguarded test was used.

On a usable executor, first read the repository verification skill and use the
checked-in toolchain and dependency pins. Focused checks retain their existing
60-second/TERM5 bounds:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 60 --kill-grace-seconds 5 -- scripts/distinct-join-order-source-input.test.mjs scripts/public-query-profiles.test.mjs scripts/packed-query-transports.test.mjs
```

The normal producer and selected consumer commands below must run serially
inside the existing `runLocalCheck` shared heavy guard, preserving the normal
300-second producer / 900-second consumer and five-second TERM grace:

```sh
node scripts/packed-client-packages.mjs "$PACK"
ACTQL_PACKED_CLIENT_PACKAGES="$PACK" node scripts/test-packed-public-query.mjs --distinct-join-order-only --keep-artifacts
```

Use an outside-checkout package directory, normal prepack, clean exact source,
the original five-package manifest/digests and independent external installs.
Preserve the 512 MiB execution budget and every original oracle. Retain both
eleven-case transport inventories, actual command receipts and package/runtime
identities. Failed, partial or old-source receipts remain separate. The original
22-case fixed-source acceptance is still required before #640 can be closed.
