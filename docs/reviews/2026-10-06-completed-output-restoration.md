# Completed producer output restoration

## Existing owner connection

The Site journal now saves an exact producer file generation with typed
completion, but neither a historical completion nor file bytes alone can
recreate the runtime's resource ownership. This preparation adds two distinct
connections to the existing owners.

`restore_remote_runtime_completed_custody` verifies an exact NativeSettled,
CleanupActive record with available material and matching durable managed
evidence, subject and measurement. It restores only the original operation's
settled fact. Bundle, output and holding remain unacquired. Success progression
still refuses until their actual handles are separately reacquired and the
original request/revision is confirmed. Restoration remains pending and
resources cannot be reported reclaimed while any handle is missing. The owned
cleanup entry rejects that pending phase rather than treating missing handles
as no original obligation. No new
operation, execution claim, reservation or durable transition is created.

`restore_native_remote_standard_output` reads a reopened journal observation,
reopens only the saved file occurrence/device/inode/size, and verifies the
complete stream against its saved content CID before returning physical output.
Its profile, schema, view, codec, manifest, measurement and Source observation
come from the existing typed owners. It does not call Source acquisition,
capture, Compute, a new export traversal or an evidence issuer.

The mandatory trusted current port must inspect the live Site identity,
generation, authority and exclusive holder slot. Saved fields cannot supply
their own current authorization. The port is checked before filesystem I/O,
during the bounded reads and before returning physical output. Authority loss
and content failure have distinct fixed refusal reasons. Neither failure
rewrites completed execution as unknown or makes it startable.

## Cleanup custody

`restore_native_retained_task_file_cleanup` reconstitutes only cleanup from the
original saved identity. It has no writer, read use or execution authority.
It permits retry of directory synchronization when an earlier exact unlink
succeeded but its sync failed. A same-name replacement is still refused by
the existing generation-aware filesystem owner; it is never adopted or deleted.

Physical restoration failures carry the original cleanup callback. Missing,
replaced, invalid or inaccessible material never falls back to Source
reacquisition. Actual runtime adoption must retain that cleanup handle and
the original capacity obligation until the physical owner confirms cleanup.
The restoration result is a distinct typed Ready/Pending role, not a new
execution-failure observation. Component cleanup success does not change the
original Run outcome or confirm formal release.

## Evidence scope

Portable owner tests verify settlement-only restoration, resource gating and
foreign/incomplete/releasing/released evidence refusal. Native filesystem tests
cover cleanup-only read refusal, interrupted unlink/sync retry and replacement
preservation. Native standard-host tests reopen real SQLite and real files,
verify independent fixture bytes, and reject mismatched content, release
progress and missing bytes without changing original execution evidence.

These component tests use synthetic managed output contracts and trusted
current-port diagnostics. They are not a recreated resident holder, public
Cloud submission, real authorization owner, Source acquisition count or
formal release acceptance. Fixed-source commands and results are in the PR.

## Remaining full execution connection

The completed Runtime owner handoff is now implemented separately in
[Runtime restoration](2026-10-06-completed-runtime-owner-restoration.md).
The actual resident holder and public execution connections remain open.

The Native resident holder must still consume these ports under its existing
exclusive executor slot, validate current owner facts after restoration I/O,
restore each reservation exactly once, and install the completed output into
Runtime without entering the execution callback. The independent Transfer
destination holding and consumer borrow must be reconnected under their saved
custody and checked edge, with their own cleanup responsibilities.

The creation/seal-before-journal-commit interruption window, original reservation
restoration, actual holder recreation, interruption acceptance and the public
Cloud two-task Run remain open. No formal OSS Cloud adoption, Preview deployment
or old #88 Run resolution is included.
