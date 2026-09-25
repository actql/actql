# Distribution R2 review disposition

## Current completion unit: packed Local and Remote AQL

At the current Distribution branch, `@actql/node` includes an installed
embedded Local Host, and the packed source-free Values route reaches a named
Result without Cloud login or a user-assembled provider. The lightweight
`@actql/sdk` still contains no kernel or DuckDB dependency. This is a working
baseline, not completion of the acquired-input unit.

1. **What the user can do when this unit is complete.** Install the standard
   packed Node package in a clean directory and run the same AQL Program from
   the same application function against embedded Local and an actual Remote
   Host by changing only `connect()` options. The Program acquires real input,
   performs checked downstream computation, and exposes a named Result. Local
   needs no Cloud connection or login; Remote does not silently upload a
   local path. Result reading, attach, request uncertainty, cancellation,
   limits and cleanup retain the agreed Client semantics.
2. **Remaining implementation and acceptance.** The embedded Host currently
   stops at its empty source catalog and source-free Run preparation. Connect
   an installed source's authorized acquisition, checked input identity,
   captured Run, downstream compute and publication to normal `aql()` and
   `start()`. Extend the actual Remote Host through the same common Run seam.
   Pack both real implementations and run one independent acquired-input
   fixture through Local and HTTP Remote, checking exact values/order,
   attach, unknown reply reconciliation, read limits, cancellation and
   release. The existing packed Values smoke is insufficient for this test.
3. **Dependencies and owners.** Distribution owns Client composition, the
   shared acquired-input Run/publication bridge and the packed acceptance.
   The Local owner supplies the installed bounded acquisition/compute
   capability; the Connector owner supplies source Catalog and Acquisition
   semantics. Cloud owns the physical Remote Host adapter but must consume
   the one shared OSS Run boundary rather than duplicate its decisions.
   The exact missing connections are recorded in
   [the acquired-input handoff](2026-09-26-acquired-input-client-gap.md).
4. **Existing plan outside this unit.** The two Hybrid ownership forms,
   Effectful submit, SQL, Python embedding, expanded native CLI and optional
   tools remain in the distribution plan. Closing this Node AQL unit does not
   complete those milestones or Cloud deployment.

The source-free packed distribution gate passed locally at
`c9ed2cc2221489c40372e2e3718d67462e74fd42` using the pinned MoonBit
toolchain. Linux CI and the acquired-input acceptance remain unverified.

Review input: `/Users/t14i/Downloads/03-distribution-client-cloud.md`,
written against `92dd4410ea9eadf278b312ec6020564883f0ec9a`.
This disposition compares that snapshot with the current distribution branch;
the review SHA is historical evidence, not the implementation base.

| Review item | Current disposition | Product evidence |
| --- | --- | --- |
| DIST-R2-1, isolated Connector assembly omits Client wire | Closed. The isolated assembly includes the generated Client wire and runs the standard Node Host. The packed standard Host installation is also exercised from installed package archives; it is no longer a missing acceptance gate. This does not establish Linux CI at the final SHA. | `scripts/check-connector-addition.mjs`, `scripts/connector-addition-wire-dependency.test.mjs`, `scripts/test-node-client-package.mjs`, `check:distribution-client` |
| DIST-R2-V1, request and Run Definition mutual binding | Covered in the normal Node issuance path before journal admission. Independently valid changed Program, changed Parameters, and changed context Definitions are rejected; the physical journal stays empty on the foreign-Definition case. | `adapters/host-node/client-program-bridge.test.mjs`, `src/run_publication_host/client_values_run_binding.mbt` |
| DIST-R2-G1, reserved dispatch through terminal state | Open. One-time reservation and reconciliation after restart prevent an unsupported second Compute. The failure matrix from reserved-but-unstarted through publication and cleanup is not yet a complete product recovery proof. | `adapters/host-node/client-request-journal.test.mjs`; shared Run and output owner work remains |

The Local Values public path computes and reads an independently expected
Named Result. That does not prove the Cloud-owned Site output path, active Run
projection, or Linux CI at the current branch SHA.

Local verification at `edc8362e773c0bfcdc18dbfa20377a366c11cf80`:
`npm run check:connector-addition` passed. It checked the generated Client
wire dependency, both isolated all-target assemblies, the third Connector on
JS/Wasm/native, and the isolated standard Node Host. The gate retained its
report and logs under `.artifacts/connector-addition-bLW52D/`.

The same gate passed again at `41bf983820adc740fda2248ce1128f21228a1b85`.
Its report is `.artifacts/connector-addition-P53uZY/connector-addition.json`:
both isolated all-target assemblies, the independent third Connector on
JS/Wasm/native, and the isolated standard Node Host passed. At that SHA, this
gate did not by itself prove a packed installation or Linux CI. The current
`scripts/test-node-client-package.mjs` separately packs and installs the
Client wire, SDK, Run Host core, Local Host, and Node client archives outside
the source tree. Its standard Values path checks submit, status, Result read,
request replay, attach, and restart from the installed packages; it also
exercises the installed remote HTTP Host. The separate
`scripts/test-packed-run-host-core.mjs` checks portable Host admission from
its archive. These local gates do not replace final-SHA Linux CI.

At `78e6877ad4ee9c6a591d0f925fbe59586b115706`, the checked Values Site
endpoint can open the retained output through the same manifest-preserving
physical source binding as the standard native Site. The ordinary Values
fixture reads the independent expected rows through that endpoint and rejects
a foreign dispatch or Result intent before opening a reader. The native test,
all-target check, public API check, native remote runtime gate and Cloud's
local native mTLS smoke passed. This supplies the Site-side physical source;
it does not transfer bytes to Cloud or publish a Named Result.

At `dae70d26a`, the Values endpoint rechecks the Coordinator output intent,
observed Site subject and admitted Output Plan before borrowing the common
native direct Transfer sender. The sender uses the retained manifest reader,
native HTTP client and durable Transfer journal; its destination origin comes
from Site configuration rather than the poll envelope. This is an OSS source
entry point, not yet an HTTPS execute route or Cloud destination. The all-target
MoonBit check, native Values fixture, native remote runtime gate and generated
public API check passed locally. The fixture still verifies the physical source
and independent rows; it does not exercise the new direct send through Cloud.

At `a214fddb3`, the native Values HTTPS Site exposes `/outputs/execute` only
when a physical destination, bounded client and durable Transfer journal are
installed. The route passes the exact output poll into the shared Values
sender and returns the common Transfer reply. The destination origin is fixed
by Site configuration. The native mTLS gate verifies that an unconfigured
route is 404 while existing dispatch, query and Output Plan behavior passes.
All-target checking and the generated API check passed. This gate does not yet
exercise a configured destination, Cloud payload custody or Result publication.

At `060b58a3c`, the native runtime gate installs an HTTPS direct Transfer
receiver with the common MoonBit control and durable destination journal. A
checked Values Program is dispatched once, its two-chunk Output Plan is
executed through the configured Site route, and the destination commits the
exact Transfer request. The receiver yields the independent expected bytes
`[{"id":1},{"id":2}]`; a repeated Output poll returns the same reply without
another physical chunk write or an extra holding. The receiver's committed
receipt proves destination custody, not public Result publication or Client
receipt. The full native runtime gate, all-target check and Cloud's existing
external native mTLS smoke passed locally. The latter still stops at the
admitted Output Plan and does not exercise Cloud R2 storage.
