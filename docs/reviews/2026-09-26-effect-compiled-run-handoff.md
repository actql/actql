# Effectful compiler and durable Run-start handoff

## Ownership and dependency

Distribution owns the common compiler, request acceptance and start boundary.
Connector owns capture, current Effect admission, apply, reconciliation,
publication and physical cleanup. No Salesforce branch is added to the compiler.

This change follows `4c583cacbf31abbfd707f8f826d87387c6907c0d`, on the shared
`44f00eab0a73819b45a0f64627898f796717ea29` integration base. It supersedes the
Fragment-only limitation of `2026-09-26-effect-fragment-compiler-handoff.md`.
Connector HEAD `ec750750383cd20336f78be982368ee6ce84b7d8` already contains
that dependency. The handoff commit is the fixed delivery point; no DuckDB Source Evidence WIP
or later Distribution functionality is a dependency. Connector's additional
commits remain on its branch. Merge this handoff rather than importing an
alternative compiler or extracting the old Fragment proposals again.

## Issuance and owner binding

`issue_prepared_client_effect_compilation` accepts the original
`PreparedClientEffectComputation`, pinned `ClientCompilationManifests`, and
bounded lowering/encoding limits. It returns an opaque `ClientEffectCompilation`
retaining that same owner. Shared task lowering, Template issuance, execution
material, fact/witness generation and compiled-plan sealing are reused.
The original Program, parameters, Check Environment and Effect declarations
remain bound. Nothing is stripped or rechecked as an Effect-free Program.

The issued artifacts are:

- Formal Executable Plan and its fact manifest, including Effect roots and
  checked EffectPlan identities where the existing contract defines them.
- Bound Invocation Template and the checked Compiled Plan envelope.
- Prepared Invocation and Run Authorization after the installing Host has
  authorized the caller, through the shared policy-evidence issuer.
- Run Definition with the existing empty initial captured-input set, and an
  exact `PreparedClientEffectRun` bound to the original computation.

`admit_prepared_client_effect_compilation` rejects changed Plan, fact manifest,
Template or compiled-plan evidence. `bind_client_effect_compiled_run` rejects
another owner, even an independently prepared equal owner. Recovery recompiles
from its newly checked owner and re-admits the saved policy records against
that compilation; it does not borrow the old in-process handle.

The initial supported profile is one source-free checked Unit beginning with
Values, named Program Results, and Result-correlated Effects using the existing
supported Relation lowering. Multiple members and rows are supported. External
acquisition, multi-Unit plans, Command Effects and unresolved opaque bindings
are not claimed by this profile. Unsupported shapes fail before acceptance.
Create retains its existing lack of an EffectPlan terminal; its declaration and
mapping remain bound by the complete checked Program and Check Environment.

Program Plan/Template identities are not local Unit or local Invocation
identities. Continue using the existing local identity issuers, Preview,
account allow/deny/delegate owner and send-time Effect admission. Compiler
issuance and a Run-start claim are neither an apply permit nor evidence of a
successful Effect.

## Usable Host entry

The installed package exports `@actql/local-node/effect-run`, containing
`installNodeClientEffectRun` and the existing `openClientRequestJournal`.
The same source entry is `adapters/host-node/client-effect-run.mjs`.
`@actql/local-node/runtime` exposes the typed MoonBit bridge.

Minimal composition, given a checked `prepared` Effect owner and the Host's
current authorizer and Connector callback:

```js
import * as moon from '@actql/local-node/runtime';
import {installNodeClientEffectRun, openClientRequestJournal}
  from '@actql/local-node/effect-run';

const journal = openClientRequestJournal(stateDirectory);
const runs = installNodeClientEffectRun({
  moon, journal,
  authorizeRequest,  // Current caller/scope check; returns policy or denies.
  authorizeRunStart, // Current authority checked again before physical claim.
  execute: captureApplyPublish, // Connector-owned callback; see below.
});
const accepted = await runs.accept({
  prepared, authorityScopeCid, requestId, tenantId, principalId,
  connection, lookupExpiresAt,
});
// Save the accepted ref before attempting start; acceptance itself is inert.
const started = await runs.start(accepted);
if (started.kind === 'reconcile') {
  // Inspect this existing Run/Effect owner. Do not call capture/apply again.
}
```

`authorizeRequest` returns `{executionContextCid, hostPolicyCid, createdAt,
expiresAt}` only after current authorization. Those CIDs do not authenticate a
caller by themselves. `authorizeRunStart` returns a boolean for the current
principal/connection and retained exact Run. Original policy evidence is saved
atomically with the request in the existing SQLite journal and is never
replaced with newly authorized evidence on resend. Old records lacking that
evidence fail closed rather than being backfilled with invented authority.

The Host also checks the saved Prepared Invocation and Run Definition deadlines
against its current clock. New expired admissions are rejected. For an accepted
but unstarted Run, this check runs after asynchronous current authorization and
immediately before the one-time physical-start claim. At the exact deadline
execution is denied and the confirmed pre-dispatch failure is retained. A Run
whose physical start was already claimed remains a reconciliation case even if
its saved admission subsequently expires; expiration never proves that its
Effect did not run or releases its cleanup owner.

`accept()` returns a local opaque handle plus `ref`, `durability`, `revision`
and `lookupExpiresAt`. It returns only after durable admission and never starts
capture. Existing lookup/attach operations remain read-only. An accepted handle
is not a transferable JSON execution capability.

Only the physical-start claim winner invokes `execute`, with:

- `owner`: the exact bound `PreparedClientEffectRun` for the existing
  `clientProgramOpenSourceFreeLocalEffectHost` operation.
- `prepared`, `compilation`, `allowed`, `definition`: the original checked
  owner, formal compiler output, admitted policy evidence and Run Definition.
- `identity`, `ref`, `runDefinition`: the common logical request and exact
  durable Run; do not create a separate Effect request scope or start claim.

The callback owns any opened execution, capture pins, Effect owner, publication
and cleanup. It must preserve that owner after uncertain results or failed
cleanup. The wrapper does not release another consumer's holdings, confirm
physical stop, or mark cleanup complete. Use the existing close/cleanup paths
and mark physical close only after their confirmation. Throwing from the
callback leaves the durable start claim intact. A callback that never began
because the process died after claiming still requires reconciliation.

Connector should replace test-authored full Plan/Template evidence with
`clientProgramCompileLocalEffects` (or the composed entry), use the accepted
request identity, and move its existing capture-to-publication composition into
`execute`. No compiler implementation or provider processing needs copying.

## Verification and limitations

The shared MoonBit package passes 15 tests on each of JS, Wasm and native.
These include Effectful issuance, foreign owner/evidence rejection, saved
policy binding and the existing Values regressions.

The Node acceptance test uses the actual SQLite journal and real Local capture
for a two-member Program. It checks concurrent acceptance and physical start,
same-ID resend, changed intent, reservation-before-start restart, lost callback
response, current authority denial, and a fresh process that either starts the
unstarted Run once or returns reconciliation with zero capture calls. The
existing multi-Effect tests now use formal compiler output for their provider,
unknown/no-resend, restart and publication cases. Provider services and Host
policy in these tests are local fixtures, not live Salesforce.

The first broad run overlapped native compilation with process-based tests;
two child processes exceeded their unchanged 20-second timeout. Sequential
reruns and the final gate are recorded in the workspace verification logs.
This handoff is not proof that the public SDK's complete Effectful submit,
Checkpoint UI, Cloud-owned Run or real-input Local path is complete. Those
consumer connections remain separate. No live provider, deployment, push,
main merge or same-SHA hosted Linux CI is claimed.

## Final local acceptance evidence

- `check:salesforce-site`: 170/170, including the new shared entry and actual
  local provider HTTP fixtures, unknown/no-resend and fresh-process recovery.
- Request journal, lookup, attach and `run-host-core`: 44/44.
- Shared `run_publication_host`: 15/15 on each of JS, Wasm and native.
- Three-target warning-denying checks, interface generation and formatting.
- Clean packed Node/browser Client smoke and packed Local Host source-free
  and acquired-computation smoke. The installed Effect Host export is loaded
  without a workspace import. The acquired smoke remains an internal Host
  check, not completion of standard Client acquired-input submit.
- Generated Node/RelA bridges, Local runtime assets, `run-host-core` and
  adapter package freshness checks.

The packed Local tarball is 1,752,143 bytes, SHA-256
`6fc591d32d869bcc2d3b2c670c5b2e250727ff60273b7cbea67804cd87593087`.
The `run-host-core` tarball is 741,690 bytes, SHA-256
`3633bbc3dcff0bbe0a8982a107f42031486389deb6607a1a8f6da67008bf71f1`.
These are the actual tested package archives, not installed-size or startup
measurements. The complete artifact map and source SHA are retained in
`_build/integration/effect-handoff-artifacts.json`; verification output is
under `_build/integration/effect-*.log` in the integration worktree.
