# Installed Calendar controls and remaining API boundary

Inspection/adoption source: `16319a4c67b5c95d9cfca7e57d43af991f6d0604`, tree
`2cac5661a5a3f86b69c559e150c716fc6df98ea2`. This preserves the already adopted
Calendar unit and adds preparation for its original examples, not another
Calendar implementation or a broader completion condition.

`scripts/fixtures/calendar-source-input.mjs` retains the original two-day UTC
series and month-bucket controls in JSON, SQL and AQL-text. The six prepared
entries share the independently specified rows and ordered full schema in
`reviews/2026-10-13-frontend-calendar-source/expected.json`. The timestamp fields
remain non-null, the month boundary remains a closed non-null object, and the
Result field order remains `start,end,month`. The checker's canonical schema
storage order is a separate concern and does not replace authored Result order.
All entries require zero Source acquisition. They use no Timestamp parameter,
cast, mocked Calendar output or supplier.

The fixture exports the exact original synthetic UTC artifact, its selection
and explicit admission limits. The file newline is retained for comparison with
the original file; the admitted artifact is its canonical body without that
newline. Its original CID remains
`sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca`.
This is an explicit test selection, never a product default or ambient TZDB.

## Current boundary

| Boundary | Current evidence / required connection |
| --- | --- |
| Parser/lowerer | Existing `calendar_source_test.mbt` compares series/bucket bodies and common checked schema with the independent JSON Program. Its historical results retain their original source qualification. |
| Artifact admission | Existing `checking_environment_with_calendar_artifact` and its Client bridge attach the selected artifact to the same environment Owner. A second same-CID environment is not interchangeable. |
| Physical lowering | At the inspected source, `lowering_relation/prepare.mbt::classify` still maps `Calendar(_)` to `None`. The existing public preparation control retains `OperationNotImplemented`. |
| Execution | `calendar_transition` provides offset lookup, not civil boundary enumeration. The existing `local_tea` and provider packages have no Calendar kernel. Fixed-duration `time_series` cannot substitute for civil days/months. |
| Installed Host | `embedded-local.mjs` has no selected Calendar artifact installation input and does not advertise unavailable Calendar execution. Enabling a checker Boolean alone would not discharge execution requirements. |

The common runtime boundary must consume the existing checked Calendar operation,
selected profile and resolved range through the ordinary preparation path. Its
existing execution obligations are `AdmitCalendarValues`,
`ValidateCalendarBoundaries` and `EnforceCalendarOutputEnvelope`. It must preserve
the bounded execution/capture/output/cleanup owners; this preparation does not
invent a second evaluator or exempt those obligations.

Once that runtime exists, the installed Host connection must admit explicit
selection/artifact bytes on its original checker environment, retain their
semantic identity and dispatch through the existing Host owner. That API boundary
was sent to A and the integration owner for overlap coordination. No common
runtime file is edited by this fixture change.

## Exact limited evidence

At clean `a25989af3e364c5b85675fca6413abc925f6bb55`, tree
`f0cb3f3935790a00f36d4141c84c1ae0009fc1eb`, the following pinned Node 22.22.0
command ran two preparation checks, both passing:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 60 --kill-grace-seconds 5 -- \
  scripts/calendar-source-input.test.mjs
```

`run-9loX2E` completed with exit 0; focused evidence is `focused-test-SWXWhP`.
Owner 81122, its group and the worktree lock were observed absent. Raw summary,
output and focused evidence are retained in the workspace directory
`reviews/2026-10-13-b-calendar-public-controls-evidence`.
The subsequent evidence note is documentation only.

These tests compare the newly packaged controls to the original independent
oracle and artifact; they do not execute the parser, checker, runtime or public
Client. The fixture is not registered as a passing default public case while
Calendar execution is unavailable. Producer, Local/HTTPS, Named Result, same-Run
replay, fresh-process recovery and Hosted CI executions remain zero here.
Calendar completion remains open, alongside the unchanged Vector/public and
other Phase2 completion requirements. No shared Heavy window is acquired.
