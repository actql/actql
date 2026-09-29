# Public source input in the native Client

## Implemented transport boundary

The native CLI sends the explicit source format, Program parameter
declarations and separate parameter values through the existing Client-Host
submit operation. It preserves registered preparation rejection codes,
unknown admission with the original request ID, and held requests without a
fabricated Run reference. The Graph/Relation frontend corrections are shared
with the SDK routing branch; the CLI does not embed the parser.

The test copies the executable into an isolated installation directory, uses
that directory as the working directory, and supplies an empty PATH to the
native process. No Node, MoonBit or curl executable is available to it.
The mTLS mock checks request/response semantics; it is not a real Host
Frontend or provider execution test.

## Verified artifact

Transport source and harness commit: `3c87f4e0f855ed26e40b1031cba69ae1d171b898`
(darwin arm64, pinned
MoonBit 0.10.12+1634b282e). Native binary SHA-256:

`f3029573276ad0ef4b09b3c0bed29efafbe1f6dc70863989658a1cb45e37357a`

Passed:

- Native release build of `src/cmd/native_client`.
- `scripts/test-native-client.mjs`: copied binary, empty PATH, mTLS transport,
  SQL parameter declaration/value separation, typed refusals, held request
  validation, exact request/Run/attempt binding and no automatic submit replay.
  Invalid UTF-8 submit responses retain the original request ID as unknown.
- `node scripts/local-checks.mjs run lint` at preceding CLI commit
  `c72428145fc0a0259aea8ebef87495002d280050`; not rerun for the later
  invalid-response regression and shared acceptance fixture merge.
- Script syntax, diff whitespace and MoonBit formatting for the response fix.

The working tree also contained only the README and this evidence document
while the fixed source/harness was tested. These documents are committed
separately from executable changes.

`runtime_conformance: false`. No Linux CI result or real source-text Host
execution is asserted. The
separate Client Checkpoint crash-recovery failure is recorded in the
[projection review](2026-09-29-frontend-projection-review.md).

## Remaining acceptance

C owns the installed alias publication and Host parse/lower/check connection.
Use the [Host handoff](2026-09-29-public-frontend-host-handoff.md) and its shared
raw query acceptance application. Then run the installed native CLI against
that real Host through Named Result reading, including confirmed rejections,
uncertain acceptance, approval and cancellation. The supplied CLI example is
for that connection and does not mark it implemented. CLI Checkpoint answer
commands are not implemented; existing public Client operations remain the
answer path.
