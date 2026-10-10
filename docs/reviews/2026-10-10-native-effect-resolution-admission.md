# Original-holder Effect Resolution admission

## Completion unit

The Native resident review holder can admit a signed Resolution for its original
confirmed encrypted Checkpoint. This is a consuming boundary for Cloud's durable
Resolution commit. It creates no execution permit, resume claim, Provider write,
replacement Source acquisition or new Ledger.

The common Checkpoint Owner re-admits the original Resolution and approval evidence
against the original Checkpoint and independently supplied current reviewer
authentication. Re-sealing through the existing Owner must reproduce every verified
wrapper field and its canonical identity. Native verifies the exact Host attestation
preimage using an independently installed Ed25519 key. Missing or duplicate Host key
identities, substituted policy/scope, foreign Checkpoints and revoked current authority
are rejected.

The wire's canonical padded Base64 signature is decoded strictly and converted to the
existing Native signature API's unpadded Base64url transport encoding. Signed bytes,
wire identities and contract versions are unchanged.

The original live holder, retention report and Run lifetime are rechecked after
reentrant authorization and clock callbacks. Starting cleanup during the final clock
callback rejects admission and preserves the pending original retention owner. It
neither returns capacity early nor supplies an Effect execution permit.

## Executed boundaries

Scoped diagnostics on the implementation tree based on
`d4c8ed4987e8e25d4fc4f408b98705d90e7b7f53` established:

- Common reconstruction: 2/2 JS tests, including a self-consistent substituted wrapper.
- Actual Native/OpenSSL signature boundary: 1/1 test, including missing, duplicate,
  empty duplicate and foreign Host keys, current revocation and foreign reviewer scope.
- Actual original producer/consumer holders, Native Source/Compute, physical HTTPS
  Provider Preview and encrypted SQLite retention: 1/1 test. The test admits the exact
  signed original Checkpoint and exercises reentrant retirement with pending cleanup.
  Existing Source/Provider observation counts and zero Provider writes remain enforced.
- Native consuming package compilation, generated interfaces for all supported targets,
  JavaScript syntax checks for the changed fixture and harness, and diff whitespace check.

The selected actual-holder command is
`node scripts/test-native-salesforce-effect-preview.mjs --resident-original-holder-review`.
The common selection is `moon test --target js src/checkpoint_runtime -f 'attested Effect reconstruction*'`.
The signature selection is
`moon test --target native --strip src/platform_native/salesforce_effect_preview/native_test/resolution_test.mbt`.
Local diagnostics use the existing cooperative lock and bounded, nonzero execution
helpers. Fixed-commit receipts and exact source SHA are reported with the PR.

Initial diagnostic failures remain retained separately: the signature transport
encoding mismatch, the fixture's invalid certificate-only HTTP constructor, diagnostic
and regression compilation errors, and combined actual-holder runs that exceeded the
unchanged 180-second bound. A later successful run does not establish the cause of the
timeouts. One owned retry was intentionally stopped after the invalid fixture
constructor was identified; it is not counted as acceptance. No deadlines were extended.

## Remaining integration

Production reviewer-role registration and current authorization, independently
installed Host signing keys, durable resume-claim delivery, Native Provider write and
saved/unknown outcome reconciliation are not established by this admission test.
Cloud waiting commit, public SDK approval, restart-to-apply and formal release remain
Cloud #138 completion requirements. The local HTTPS issuer is an independently authored
signed test fixture, not a deployed Cloud Owner or a real approval grant.

No formal npm cohort, production Native binary, Preview deployment or hosted CI result
is produced by this change. Hosted CI remains stopped by instruction. Native test
executables are diagnostic artifacts and cannot replace formal Cloud adoption.

## Integration review and authority correction

The main integration retains #1238's target-only test package. Portable code
does not import Native FFI test dependencies. Actual HTTPS and signature tests
are selected from `salesforce_effect_preview/native_test`.

Review found a cached reviewer-authority result before the final clock callback.
That callback could revoke reviewer authority without retiring the holder. The
final clock is now read before the current authority check. The original-holder
regression covers this independent revocation as well as holder retirement.

On the corrected integration tree, bounded `run-Sr05lg` passed the affected
JS/Wasm/Native denied-warning checks, 2/2 common reconstruction tests and 7/7
actual Native/OpenSSL/HTTPS target and signature tests. These are selected
checks, not a full Core or final distribution campaign.

The author's clean source `acb3019fcda715672f93bcc2cfca4bcd749f3ae1`
has a separately inspected actual original-holder receipt: 1/1, 139.46 seconds,
one resolution request, one Provider read and zero Provider writes. Its tested
binary digest is
`77347faf03274b1356bb0112b59e6f44964f4f317fabf439d542fc9d08175fbb`.
It does not cover the subsequent integration correction.

The integration operator's original-holder attempts `run-dDDUS6` and
`run-EQJu6m` exceeded the unchanged 180-second consumer bound before requesting
a signed Resolution. They provide no completed holder-regression counts. The
release-mode preparation `run-Me8OgP` also reached its 300-second build bound.
The new holder regression is compiled but has not completed in these attempts;
it is not reported as passing. No timeout, resource limit or admission rule was
relaxed. The clock-order correction is additionally reviewed directly at its
synchronous consuming boundary.
