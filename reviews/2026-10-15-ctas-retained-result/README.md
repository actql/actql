# CTAS: retained Result before the filtered Table write

F07 already requires `CTAS RESULT -> WHERE -> write` through normally installed
Local/HTTPS Clients. The whole outer CTAS wrapper is Compute
(`docs/spec/query-text.md`, `src/query_syntax/query_context_test.mbt`). A public
Result retained before `WHERE id = 2` must keep the original `{id:1,tag:null}`;
the Table operation must receive a typed empty Relation. Dropping the Result,
pushing the filter before its capture, or ignoring the write filter are all
incorrect. The corresponding machine Program and its independent value/schema
oracle are authored directly, never captured from lowering or execution.

Add JSON/SQL/AQL controls for both public transports to the existing Table
fixture and approval/restart path. A genuinely fresh process approves the same
Checkpoint, completes the same Run and reads the earlier Named Result. Reattach
and the identical request must return that Run without another Catalog commit.
The real physical generation must contain zero rows. Preserve its scratch,
DB/WAL, synthetic keys and any unresolved responsibility, including on failure.

The existing twenty physical cases and their assertions remain in the default
selection, followed by the six controls. The closed `ctas` selection requires
the original four Effect-only CTAS controls plus the six Result/filter controls
(10 actual tests); it does not claim the other original groups ran. Their
existing per-child360s, checkpoint/poll30s and physical byte/file/operation
limits are unchanged.

`ACTQL_TABLE_NORMAL_RELEASE=/absolute/normal4-RC` selects the existing exact
clean-source normal-release verifier before any Host or fixture creation. It
never packs or falls back to development archives. All four final archives are
installed normally outside the checkout and audited. The same source,
manifest and archives must still verify after execution. The selected optional
Table Python installation must match the existing hashed requirements lock;
no checkout Python worker or adapter may replace installed package assets.
Normal release source must match the submitted fixture source: an older RC is
not silently qualified for this child.

The copy inventory includes the actual relative module closure and the literal
schema readers, including the existing mandatory protocol schema read by the
publication fixture. The Node preparation checks the real esbuild import graph
and negative missing-module/schema controls, rather than only checking that a
fixture name appears in a list. The existing aggregate Node entry imports these
preparation tests.

Preparation uses `prepared-checks.mjs <full-source-sha>` with pinned Node,
non-Heavy60/TERM5/child30/j1. It is not Table/Host/Result execution. The public
recipe is `prepared-release-public.mjs <source> <normal4-RC> <selected-python>`:
a separate exact-source normal4 consumer with `ACTQL_TABLE_CASE_GROUP=ctas`,
explicit `ACTQL_TABLE_PYTHON`, preserved scratch, existing nonzero discovery and
the original per-group360-second budget. A finite1200/TERM5 outer budget covers
the two groups plus their normal setup; normal resource admission still applies;
no new producer, product limit, authority, Table engine or Common Owner is added
by this harness change. Physical acceptance remains unverified until the
matching normal cohort and selected Python environment actually execute it.
