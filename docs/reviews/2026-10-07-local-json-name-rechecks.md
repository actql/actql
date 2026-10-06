# Retained opaque JSON member-name admission

## Base and scope

Adopted main: `b98a50ff763d1367e344fdfa8aea380ec8749132`.
The prior common REPLACE/LENGTH and captured Decimal negation work is already
merged. A normal merge fast-forwarded the clean working checkout to this main.
The Graph-only contracts, definition domains and identities are adopted as-is.
This component continues the existing retained Local completion work on
`feat/local-json-name-rechecks`; it does not declare all retained routes closed.

The current gap report identifies long opaque JSON names as a synchronous
runtime-recheck residual. `JsonFields` previously called `recheck_text` for the
entire name in one poll. The independent regression shows that after three
polls even the child has been visited, rather than remaining behind the first
name fragment. The valid pre-fix regression failed 0/1 at this boundary
(`run-bJPEOg`, `focused-test-N6zhKL`). A preceding diagnostic did not compile
because the package's `fail` helper has a different signature; that attempt is
not runtime evidence.

## Existing owner connection

`RecheckCursor` now retains a `JsonName` continuation. It shares the existing
scalar-safe Text byte scan, consuming at most 64 UTF-16 units and a surrogate
partner per poll. Child and sibling frames are scheduled only after the name
finishes. No additional pending child or depth reservation is introduced.
Short names keep their original poll count. Original logical nodes and UTF-8
bytes remain unchanged, while long names add quantum-independent control work.
JSON member names preserve decomposed Unicode, CR and CRLF as data. The declared
Object identifier rules and synchronous recheck's results remain unchanged.

The production route is the existing Relation Pool input owner:
`load_pool_field -> relation_cell_recheck -> advance_recheck_runtime_value ->
bind_pool_field`. The installed Host still uses its checked task, existing
Session, record owner, retained Store and publication owner.

## Independent boundaries

- The 130-ASCII-plus-decomposed/CRLF name has 135 UTF-8 bytes. Root, field
  setup, three name fragments, child, exhausted fields and completion require
  eight polls. After poll three, one node and 71 bytes remain.
- A surrogate across the fragment boundary plus raw decomposed/CRLF data uses
  137 bytes. Nodes 2/1, bytes 137/136 and depth 1/0 distinguish success/refusal;
  malformed surrogate tails refuse before visiting the child. Double cancel
  clears pending frames without returning a partial checked value.
- The existing 112-item unused Array precedes the 130-unit name in Pool.
  Its 227 polls replace the old 517-poll Array; the eight-poll JSON object and
  three extra field lookups give `592 - 517 + 227 + 8 + 3 = 313` control polls.
  Exact/one-short work is 313/312. Initial structural custody is 67 slots;
  three retained fields and two links give completion workspace 72/71.
  The latter refusal comes from the output storage reservation, rather than
  the distinct 67/66 initialization refusal. Quanta 1/7/256 agree.
- Cancellation after 255 polls occurs inside the name, before a child or record
  is committed. Cleanup refuses `NotStopped` before stop is confirmed; one
  cleanup succeeds, a second is a no-op, and the borrowed input remains live.

## Public retained route and evidence

The public Program uses VALUES for supported declared columns and the existing
typed JSON literal expression to derive an additional JSON column. JSON is not
added to VALUES' constructible schema. Initial fixture attempts used an invalid
VALUES JSON schema and then collided with a declared column; neither reached
the intended execution boundary. The final source creates a new column and
binds the exact completed producer step before Pool.

The normal installed Local Host retains output in the real Store and reads
`published`, `consumed_a`, and `consumed_b`, each independently fixed to
`{group:1, embedding:[1,2], member_count:1}`. Reusing the request adds no dispatch
or advance. The public JSON name has 513 UTF-16 units, including decomposed
Unicode and CRLF. Poll 256 is inside its nine-fragment name scan. Before the
barrier releases, cancellation is requested but physical stop is unconfirmed
and holdings remain owned. After stop, all Results are unavailable, there is
no new dispatch and the snapshots are reclaimed.

Candidate common/caller checks passed 13/13 (`run-oFrUOI`,
`focused-test-uc2Nis`). Public JSON/Object cases passed 2/2 (`run-0UpsgO`,
`focused-test-MHXFKZ`). Required-evidence removal checks passed 1/1
(`run-YSxi39`, `focused-test-qPozoX`). The extra 72/71 workspace probe initially
expected the startup issue; it is now tied to the output storage's typed
WorkspaceLimit. Final submitted-SHA receipts are recorded in the PR.

Only Local Node and Run Host Core runtime sources were rebuilt; runtime bundles
remain ignored. These are checkout Host checks, not packed or HTTPS acceptance.
Graph Plan and ordinary VALUES/REPLACE/LENGTH caller tests use the new main
contracts; no old saved Run, pin or identity is reinterpreted.

## Remaining work

Preparation/schema lookup, per-poll availability scans, synchronous legacy
drains, runtime buffer assembly and aggregate physical byte custody remain
distinct residuals. Full Store-fault campaigns, whole-Run physical accounting,
packed/HTTPS, Wasm/native execution and CI success are not established here.

A removed JSON-name boundary or public fixture now fails the existing resource
evidence gate. Portable target declarations identify required CI coverage;
they do not imply that those targets were executed locally.

## Cleanup

Removed only the completed Native/Wasm check subdirectories and formatter
output under this working checkout: approximately 107 MiB of reproducible
files. JS incremental output, third-party dependency links, borrowed toolchain,
focused receipts and all failed diagnostics remain. Later verification may
regenerate formatter output, so the deletion amount is not a host-wide net
free-space claim.
