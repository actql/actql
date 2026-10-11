# Remote credential use pre-send retention

## Existing Owner connection

Add an explicit installer for the existing `NativeCredentialResourceService` whose required callback retains the actual nominal Remote credential use. No request/grant/use is regenerated and no new Resource, execution, journal, Ledger, or permission Owner is introduced.

The shared credential Owner already selects a fresh ordinal, issues the use, and saves its exact bytes. The new Remote-only callback runs after this durable use insert and any existing Local preparation raw reservation, before the final trusted clock, Host send authorization, caller current guard and durable revocation checks. Local and Local-preparation use domains never enter this callback and retain their existing paths.

Failure or uncertain custody returns the callback's issue unchanged. The original use remains claimed; no failed/sent/successful outcome is invented and no Provider call occurs on that branch. Repeating the same request encounters the original retained claim rather than reissuing a use or re-running retention. The caller must retain the same nominal use/cleanup responsibility for reconciliation; losing that context cannot authorize another read.

Callback success grants no send permission. The existing final lifetime, authorization, caller current and revocation checks still decide whether physical I/O may begin. The normal installer is unchanged; the resident calling integration must explicitly install the required retention callback. The new installer is not yet selected by production Resident CLI.

## Dependencies and remaining connection

This isolated Resource unit is based on D #1496, fixed `1c664703363592afb1a57b79feb13370b97af96f`. Its Local raw/Host assembly remains D-owned and is not modified here. F's independent Site-journal seam is #1497, fixed `b887425906e47671ac4c95818202e88d4397b19f`. Their calling integration will retain the original consumer dispatch/grant/use before GET and inspect the same responsibility after reconstruction.

A latest-main merge attempt exposed the parent's unmerged Local original-Checkpoint projection conflicts with main's final read fences and upload fixtures. That own merge attempt was aborted without modifying either submitted head. Preserve the D parent until it is integrated, then normally adopt main without dropping those fences. Final merge target is main, not the dependency branch.

Original initial-use eligibility, legacy/missing custody no-send, credential DB continuity, custody funding, actual Host/current read/publication permission installation and physical/public Effect acceptance remain uncompleted. A saved use, a callback success, missing Checkpoint, process-local flag, or fresh DB is not a durable authorization or proof of never-sent. Production evidence-read default-deny is unchanged.

## Limited validation

Three pure JS cases execute nominal identity handoff, typed failure propagation and Local/preparation separation. These do not execute a credential DB, Provider, Site, approval or public Run.

Two strict Native fixtures compile the actual Resource call path: unconfirmed retention retains the original claim and prevents reaching send authorization; successful retention cannot bypass the final current guard. Real fixture dependencies must be present for execution; absence fails rather than passing early. Native execution is not performed here.

The affected Resource and fixture receive matching Native compile checks; the interface uses the existing `moon info` generator for JS/Native/Wasm. All local commands use the existing nonHeavy lock and finite guard. Hosted CI, Heavy, package producer, Native/Provider I/O, Preview, deploy and merge remain unexecuted.
