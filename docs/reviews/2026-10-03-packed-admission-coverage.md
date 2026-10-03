# Packed admission coverage: bounded follow-up

This is the obligation map for #230, which supersedes the broader #201
plan. It adds one representative new-request regression, not a new Graph
inventory or a second component fault matrix. #230 remains open for the
existing-request and current-authorization gaps below.

## Fixed comparison baseline

- Main: `8b21ddd3f4a17fcecbb9bcf5878082148af0aa99`.
- Merged positive Effect acceptance: #188,
  `20f4cc69001776bcb09421be7f7feb9a087a14df`, retained in main's
  `scripts/test-packed-salesforce-source.mjs`.
- Graph #164: `c37d204c73a453fd88d4d56821f8c27f7d1abc4f`, unmerged
  when compared. Its inventory-derived unsupported operation payloads and
  internal installed-host import are not treated as proof of this new
  language-valid input/public-export obligation.
- Frontend #174 is historical; replacement #233 is
  `1d2b47a2b51d6b6bc847bc1a93cb7fe340fb4468`, based on #164. Neither
  branch is silently included in the main baseline.
- Retained traversal #232: `a46a509b044891c8c0f3c6898584a71d147437a9`,
  unmerged. Its supported traversal route is not a new-request refusal
  fixture. #182 remains the composition/lifecycle owner's work.

## Obligation-to-test map

Existing-test links below are pinned to the comparison baseline. A passing
component test is not described as installed public acceptance.

| Obligation | Existing evidence and remaining gap | Change here |
| --- | --- | --- |
| Valid, unsupported new Program; no provider I/O, dispatch or durable acceptance | [Generic public refusals](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/scripts/fixtures/public-query-input.mjs) permit several input-error codes and do not prove semantic validity. #164's operation inventory remains separately owned. | Extend the existing [packed Salesforce acceptance](../../scripts/test-packed-salesforce-source.mjs), using its exact successfully completed Read→Compute→Effect bytes in a fresh source-only installation. Both Local and HTTPS require `ClientProgramUnsupported`, `not_found`, zero actual provider HTTP requests, and empty before/after SQLite request rows, including dispatch/start reservation fields. |
| Same-intent existing request is resolved without replacement by a new unsupported rejection | [Public query success/replay](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/scripts/fixtures/public-query-input.mjs) and [fresh-process two-source replay](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/scripts/fixtures/two-source-public-query.mjs), `verifyTwoSourceRetained`, cover unchanged supported profiles. They do not cover an existing request whose new preparation is unsupported. | Reuse existing successes; no duplicate replay test. Existing-request support precedence remains open. |
| Changed intent stays conflict; unreadable/unresolved ownership stays unknown | The public query `sql` case requires exact `ClientRequestIntentConflict` for changed supported parameters. [Journal tests](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/adapters/host-node/client-request-journal.test.mjs), including `retained identity corruption is not reported as absence`, cover the owner. [HTTP reply tests](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/adapters/host-node/client-http.test.mjs) preserve unknown replies through a supplied handler. These are not a passing packed unsupported-resubmission test. | No new corruption matrix and no expectation that blesses Unsupported in place of conflict/unknown. The [#201 reproduction](https://github.com/actql/actql/issues/201#issuecomment-5956620408) remains a known gap. |
| Current authorization remains enforced when resolving an existing request | [Two-source Checkpoint tests](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/adapters/host-node/client-two-source-checkpoints.test.mjs) cover rechecking before physical start and reconciliation after a reserved start. HTTP handler tests cover authentication and connection authorization. Neither establishes the requested current-authority change across both installed public existing-request routes. | Not claimed complete. No private authorization injection, replacement owner, or proxy bypass is added. |
| Actual installed SDK/exports, source/package digests, explicit profile | Existing external Salesforce harness installs four normally packed packages and uses `@actql/node` plus `@actql/local-node/http-host`, without MoonBit on the consumer PATH. | Reuse that installation and its package digests. Emit source revision, exact Program SHA-256, transport, source-only profile, and independent observations. No additional pack loop or workflow is introduced. |

## Observation and contract boundaries still open

At the baseline, `performClientSubmit` in
[`client-submit.mjs`](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/adapters/host-node/client-submit.mjs)
calls preparation before the durable submit owner. Unsupported preparation
can therefore prevent resolution of an already owned request. The earlier
#201 public-package reproduction demonstrates the conflict/unknown masking;
this test-only change neither repairs that order nor records it as correct.
The common lifecycle owner in #182 must supply the intended resolution
boundary before a passing packed regression can discharge it.

For current authorization, the installed HTTPS entry point exposes an
authentication callback. The installed Local route binds the OS principal;
`hostConnection` and `authorizedScope` in
[`embedded-local.mjs`](https://github.com/actql/actql/blob/8b21ddd3f4a17fcecbb9bcf5878082148af0aa99/adapters/host-node/embedded-local.mjs)
bind access to that installed principal and scope. The HTTP callback is not
a general mutable Local request-authorization port. A transport token
revocation alone must not stand in for a current Source/Effect authorization
decision or change the existing rule that reserved execution is reconciled.
The missing representative public existing-request authority scenario and
its expected outcome need to be selected with that owner, rather than
invented by this fixture.

## Verification correspondence

The regression is reached by the existing `check:local-node-assets` command
in the Host CI job. Its positive path must first finish successfully,
compare independent rows and exact Effect bodies, and verify no duplicate
write after restart. An unsupported positive submission aborts before the
new case; a stale Program file cannot turn that failure into a pass.

A bounded local run used the main CI producer's archived tarballs from
[run 37091557711](https://github.com/actql/actql/actions/runs/37091557711),
artifact `11262239685`. The ZIP SHA-256 is
`e2cf81fb3d1aede725701956471106ea1cc369fb601a1a81704d5175d5d0c821`.
Its manifest's revision is the baseline above, and every tarball was checked
against the manifest. Only the local test copy's pack loop and dependency
installation were substituted to use those archives and cached locked
DuckDB `1.5.5-r.4`; no ActQL package contents were changed.

The complete existing Salesforce acceptance and both added refusal cases
passed in that run. Both cases reused Program SHA-256
`27c203f24f2a392bb3b92215875740f242c1596638690dc52a616eb61e48aad5`.
This is baseline-package evidence with the edited test, not a normal repack
of the submitted source. Exact-submitted-source normal prepack/installation
and the remaining required checks belong to the PR's hosted CI.

| Installed package | SHA-256 in the bounded local run |
| --- | --- |
| client-wire | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| sdk | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| local-node | `0e21e7ef7d17b1cf6cd7e3e07c196d8437476a2caa70e6ea32a770cfb4da2a14` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |
