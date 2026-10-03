# Historical PR 246 supplement rehearsal

This records the already obtained rehearsal at common-validator PR 257 revision
`c70ddc224dbe86af5192c9c683124c9ae3ee90d4`. It is historical evidence, not a
normal test's input or a claim of acceptance for subsequent HEADs. The trial
did not publish a supplement to PR 246 or adopt its product changes into PR 257.

The source was published PR 246 revision
`26e2571666eafd8d3eea62259c1248015e923914`; the explicitly integrated validator
was `c70ddc224dbe86af5192c9c683124c9ae3ee90d4`. The old history owner rejected
it with `Incomplete or ambiguous foundation resolution inputs`. After normal
integration and the additive [receipt input](2026-10-03-pr246-supplement-input.json),
full history validation succeeded with 60 declarations and 23 integrations.

The original `resolve-composition-frontend-latest-main` declaration retained
SHA-256 `d3e29783d130b8f84e262d4ea389dd813b2d83285c07f4075460d9637d495471`
and introduction `df842fb35a51a0a9fc33740a1cca73d4e6f4848a` without modifying
its bytes or introduction history. The disposable trial commit was
`141c015f728763034e49a88de93473d6bbae3ff1`; it was not a published adoption SHA.

The retained local evidence is under
`_build/local-checks/attempts/run-5PTxLE/output.log` and
`_build/focused-evidence/focused-test-mUNQpY/001.stdout.log` in the
`actql-foundation-resolution-supplements` worktree. That focused invocation
passed 17 tests, including the then-embedded rehearsal. Those logs are preserved.
The previous 164-test foundation run is separate, earlier evidence, not a full
normal-suite result for later revisions.

The optional explicit command below recreates the trial from published input
commits when those objects are deliberately fetched. Run it using the repository's
bounded local execution wrapper. It is not registered in normal CI, does not
default either revision to HEAD, and accepts an identical already-present receipt
without making an empty commit. Other legitimate receipts do not change its
identity-based assertion.

```sh
node scripts/rehearse-foundation-supplement.mjs \
  --source 26e2571666eafd8d3eea62259c1248015e923914 \
  --validator c70ddc224dbe86af5192c9c683124c9ae3ee90d4 \
  --supplement docs/reviews/2026-10-03-pr246-supplement-input.json
```

Ordinary regressions instead construct their own small Git DAGs, including
unrelated later commits and a second legitimate supplemented resolution. They
have no dependency on these unpublished-to-main source objects or on this
historical trial's aggregate counts.
