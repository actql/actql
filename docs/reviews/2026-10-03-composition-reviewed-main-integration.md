# PR 246 adoption of the reviewed common supplement rule

## Subsequent main movement and PR preflight

The first combined push was `c8ad0d0086a7e60e3a71ea92ac5331d944583e34`.
Its exact local HEAD passed full-history validation. Nevertheless, automatic
PR [run 37123341456](https://github.com/actql/actql/actions/runs/37123341456)
failed preflight at GitHub test-merge
`833a05f6e632928353d243f35e1690473f0fae6e`, whose ordered parents were the
subsequently updated main `eec5cae6e5f915b92cdae0ded5d4a44bdef40e54` and
that submitted HEAD. The first concrete error was
`Unlisted foundation source change 833a05f6e632928353d243f35e1690473f0fae6e: .github/workflows/ci.yml`.
This is distinct from the repaired #233 dependency error. Public packed,
interface and Workers jobs were skipped after preflight failure, not verified.

Actual normal merge `290d6ef5c119bf21a0a84504c25fd89319934ec8` retains
ordered parents `c8ad0d0086a7e60e3a71ea92ac5331d944583e34` and
`eec5cae6e5f915b92cdae0ded5d4a44bdef40e54`, adopting #258 main carryforward,
#262 focused verification and #259 graph predicates without conflict. Its
maximal common base is `13bb2c79fac7ac97173f8146266248b1cf36d169`.
`resolve-composition-current-ci-main` binds the actual required workflow path
and 29 source groups. Earlier merge declarations and the supplement are retained.
No declaration for the disposable GitHub merge is manufactured, and neither
the history validator nor CI gates are bypassed. The failed old SHA is not retried;
the updated HEAD receives its own natural PR push run.

## Fixed inputs and actual integration

Normal merge `5f223a77e82ae8676c6d081f42ec92da592e0eff` retains ordered
parents `af7bec7c20cc3e263f6ec0317e71598f1c5bc63b` (D product follow-up) and
`13bb2c79fac7ac97173f8146266248b1cf36d169` (main including reviewed #257,
#242, #255 and #256). Its actual maximal common base is
`b18632b65570713e36c0a83e8afd0063bc37a5c3`.

The sole conflict was the Client scheduling assertion. The merged test retains
main's `select-targets` plus `preflight` dependencies and D's independent
assertion that packed composition is no longer run a second time by Host.
Current workflow preflight/profile selection remains in place. The actual
protected merge paths are `.github/workflows/ci.yml` and `package.json`; the
new `resolve-composition-reviewed-supplements-main` declaration binds both
ordered parents, exact blobs/modes and 46 independently derived source groups.
No inherited declaration is replaced.

## Real-history failure and additive repair

At `48f90689b1831891896804f9458e6eebe81015b7`, after recording the new merge
but before supplementing the old resolution, the exact-source full-history
check fails with `Incomplete or ambiguous foundation resolution inputs`.
The old D resolution still has 23 groups instead of the required 24; the missing
group is `258f86ecd9abf9628d4d98c1da602c16e257873d`, whose
`main-pr233-package-resolution` receipt arrived through #254.

At `0a59819510b72ca0f135707b71df489da16ffce6`, the additive
`complete-composition-frontend-pr233` supplement closes that dependency and
the repository exact-source/deterministic full-history check passes. This is
the real PR 246 branch, separately from the [earlier disposable rehearsal](2026-10-03-resolution-supplement-rehearsal.md).

Original `resolve-composition-frontend-latest-main` bytes retain SHA-256
`d3e29783d130b8f84e262d4ea389dd813b2d83285c07f4075460d9637d495471` and
introduction `df842fb35a51a0a9fc33740a1cca73d4e6f4848a`. Original and
supplement inheritance, exact Git bindings, complete dependency coverage and
introduction visibility are checked by the unmodified reviewed owner.

## Independent product corrections and light checks

Product follow-up `af7bec7c20cc3e263f6ec0317e71598f1c5bc63b` refreshes the
generated `run_publication_host` interface with the existing
`Effects(ClientEffectAllowedRun)` variant. It also admits the inspected
portable `managed-output-custody.mjs` in both Workers artifact profiles.
Neither is inferred to be fixed merely because history validation succeeds.

After integration, 38 Client scheduling/CI selection cases and four focused
Workers artifact cases passed. The Workers cases positively bundle the portable
custody module and retain rejection of Node, unresolved, dynamic and forbidden
tree-shaken dependencies. The initial Workers invocation could not load the
uninstalled `acorn` dependency; after preparing only the selected packages,
their versions/integrities were checked against the existing Workers lock and
all four executed cases passed. No test is counted from the failed invocation.

Focused commands:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'repository foundation composes' \
  proofs/relation-pipeline/history.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/client-ci.test.mjs scripts/ci-targets.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'resolved Workers graph|unresolved and dynamic|actual bundler resolution|completed Local output custody' \
  adapters/workers/artifact.test.mjs
```

Retained relative local evidence: history failure
`_build/local-checks/attempts/run-Hp0TwH`, history success `run-KOxE2f`,
Client/CI `run-n2DUP8`, and Workers `run-EnDuGp`. These are diagnostic records,
not replacements for hosted receipts bound to the submitted HEAD.

## Public composition status and remaining scope

The unchanged JSON Program and independent expected rows remain in
`scripts/fixtures/composed-infer-effect.program.template.json` and
`scripts/fixtures/composed-infer-effect.expected.json`. Its Program SHA-256
is `2d4620eb3de66800f09373d9a292590db814a761c766132e7d46792fa83fe1fc`.
The ordinary packed consumer runs one Program through Local and HTTPS, checks
two Source sessions, Model inputs `[100,200]` exactly once, writes `[0,0,1,1]`,
and same-Run recovery after both dedicated processes stop at capture-waiting
and approval-committed boundaries. Source, Model and Effect are not assembled
by separate consumer executions.

Public acceptance passed in earlier PR run
[37116987111](https://github.com/actql/actql/actions/runs/37116987111), at test-merge
`ca34818c505dfa4537ff73e365b61120c6d571f0` for submitted
`26e2571666eafd8d3eea62259c1248015e923914`. That remains historical evidence.
The integrated HEAD's packed acceptance, interface freshness and complete CI
are to be established by its natural PR push run; no heavy local packed, Core,
proof or performance campaign was added.

B #242 is now adopted through main, using its existing lowerer and Source
occurrence bindings. Text JOIN/INFER/Effect composition remains a subsequent
acceptance unit; this JSON PR does not claim that path complete. Real external
Model/connection acceptance likewise remains separate from deterministic
fixtures and requires explicit configured targets before execution.
