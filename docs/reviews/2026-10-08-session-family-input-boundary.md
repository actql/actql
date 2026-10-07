# Session and pipeline scientific input boundaries

Adopted main: `ca39ec1a82c89a0e038af3862af4de8a383b26fb`.
Implementation and clean final execution:
`4fe695effcbaff1d833ebb00a070229ab8a205e2`.

## Actual dependency and correction

The shared image executor eagerly imported pipeline pristine/fixed validators,
their receipt/oracle graph and generator dependencies even for Session. Its
action-input collector consequently included the entire pipeline directory in
all 30 Session actions. This was a real dependency, so removing its input list
alone would have been unsound.

The executor now loads those scientific consumers only after selecting a
registered pipeline profile. The existing three validators move unchanged to
`isolated-pipeline-results.mjs`; their combined function bytes retain SHA-256
`61407197add2f8191ea922050b8dbf76192b51e2c763c0011a21b096b4babb38`.
The actual executor awaits this dispatch, and both the Actions collector and
local worker await execution before recording its result. Failures still pass
through the existing owned container/image cleanup. No generic validation
callback, owner, campaign, profile or target override is introduced.

Session's remaining eager pipeline import is `inventory.mjs`, used by shared
source utilities for the explicit pipeline profiles. Its current imports are
Node built-ins; its constants/functions have no top-level filesystem reads.
Keep its actual bytes, mode and exact reviewed import/effect fingerprint in the
Session input key. Missing or changed bytes add an unresolved reason rather
than issuing a closed key. This finite fingerprint is a manual dependency
review boundary, not a general JavaScript parser or proof of runtime closure.

Only after changing the actual import boundary does Session stop listing the
separate pipeline directory. Pipeline profiles keep their own complete staged
snapshot, compiled fixtures, original scientific validators and independent
expectations. All 30 protected Session descriptors, the Lean model/claims,
receipt authentication, original/application separation and reuse policy remain
unchanged. Controlled fixtures now carry the real reviewed inventory bytes;
they do not override the new unresolved-boundary refusal.

## Input scope observation

For each of the actual 30 descriptors, the old extractor on adopted main binds
471 pipeline files / 2,356,695 bytes; the new extractor on the implementation
revision binds 1 file / 1,826 bytes. The complete per-action analysis is in the
archive. It retains an explicitly unqualified runtime and `eligibleForReuse:
false` throughout. These are source inventory counts, not measured runner-time,
transfer savings or an authenticated comparison between main executions.

The actual-tree regressions independently change a pipeline oracle and retain
all 30 Session keys; related Session implementation and Events theorem edits
still invalidate their existing connected scopes. Controlled negative fixtures
retain source/oracle bytes, addition/deletion/rename, mode, target, descriptor,
transitive package imports, unknown configuration and changed/missing inventory
refusals. A new import or top-level read in the remaining inventory cannot be
silently treated as closed.

## Executed local validation

The working implementation passed 131/131 selected Node tests in
`run-KOzPVm` (nonzero wrapper): inputs, actual input obligations, actual module
load/dispatch, local isolation contract, preserved pipeline originals,
comparison plan, applications, acceptance and costs. This precedes the last
controlled cost/final fixture inventory updates; it is not a clean-SHA claim.
The updated cost fixture passed its affected 18/18 in `run-yBHeQA`.

At the clean implementation SHA, `run-HJArS6` passed 30/30 using actual installed
Lean `4.30.0-rc1` and workflow-pinned Node `22.22.0`:

```sh
PATH=/Users/t14i/.elan/toolchains/leanprover--lean4---v4.30.0-rc1/bin:/Users/t14i/.local/share/mise/installs/node/22.22.0/bin:$PATH \
/Users/t14i/.local/share/mise/installs/node/22.22.0/bin/node --input-type=module -e '
import {runLocalCheck} from "./scripts/local-checks-guard.mjs";
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:true,
  timeoutSeconds:240,graceSeconds:5,steps:[{
    name:"fixed-source actual pinned Lean final and receipt consumers",
    command:process.execPath,args:["--input-type=module","-e",
      "import {runFocusedTests} from \"./scripts/test-execution.mjs\"; process.exitCode=runFocusedTests(\"node\",process.argv.slice(1),{cwd:process.cwd()});",
      "--","proofs/ci-evidence/final.test.mjs",
      "proofs/ci-evidence/receipts.test.mjs",
      "proofs/ci-evidence/session-module-boundary.test.mjs"]}]});'
```

The 6 final and 23 receipt tests execute the real Lean plan checker and bind its
certificate, including all 30 fresh obligations, authenticated fixture
push/manual main mixed plans, feature/PR origin refusal, and related-input
return to fresh execution. Provenance/API fixtures remain controlled fixtures,
not live Actions authentication. The module-boundary test loads the actual
collector, final consumer and executor while refusing pipeline scientific
module resolution, then reconsumes the retained Session original's 13 logged
assertions through the real scientific dispatch and rejects failed restoration.
It retains the original execution SHA; it does not apply that old image to the
current source. Registered pristine/fixed dispatch replays also propagate
rejection and refuse cross-family observations.

The first clean final attempt (`run-YAuDcM`) passed 22/29 and failed 7 during
Lean version startup through the inherited installation shim. Those plans did
not reach Lean. Its original failure is retained; it is neither an expected
semantic refusal nor a pass. Selecting the already installed pinned binary via
PATH resolved this without changing the checker, guard or expectations. No
download or Actions environment impersonation was used. `git diff --check`
passed. Later publication adds only this review and its original text archive.

## Remaining scope and goal

This implements a reusable family boundary and removes unnecessary invalidation;
it does not authorize more actions or demonstrate CI cost savings. Only
`mutations-js` remains a potential reusable Session action. Successful fresh main
origin, compatible later-main qualification, ordinary-PR reuse, related-input
fresh execution and authentication/transfer/checker-inclusive net savings stay
unverified. No Actions was queried for those origins, dispatched or retried.

No new physical image/mutation campaign, Native/Wasm or full integration run was
performed here. The saved pipeline originals are reconsumed at their actual
historical source identities; moved validator equality is not new physical
acceptance. The complete Session runner on adopted main separately needs the
published Nest inherited-input correction in #896; this PR does not duplicate
its protected sources or depend on an unpublished worktree. All changed files
here are outside the 89 retained-history protection paths verified in #896;
no protected-source declaration was invented. No current whole-history pass
for this new SHA is claimed.

Continue the project-wide goal through the existing family interfaces and local
obligations, preserving unresolved boundaries. Do not mechanically mark all
input-equal actions reusable, delete semantic/physical regressions, or replace
the deferred Actions acceptance with these local diagnostics.

## Original evidence

[Compressed originals](evidence/2026-10-08-session-family-inputs-4fe695eff.json.gz)
contain unchanged logs, guard/nonzero receipts, both clean final attempts,
per-action input scope, exact changed source bytes/modes digests and selected
Node/Lean executable digests. Executable digests are identification, not a
complete runtime closure; binary bytes are not embedded.

Raw JSON: 609,975 bytes, SHA-256
`482c353481ccc2360a54e3a353afbe80f8d0eebde374e5278e86e892b214d36b`.
Gzip: 60,896 bytes, SHA-256
`d13f993728c7672e56caf7e31eaf29780b9fd88a6198a01729d0fe6ad6a416fa`.
