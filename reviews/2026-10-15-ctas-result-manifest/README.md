# Complete captured Result Manifests for ordinary Effects

The ordinary Result-backed CTAS control declares `before_write` and `written`
in one Unit, publishes the former, and consumes the latter in Store. The
installed e193 cohort retained its original four successful CTAS cases and
six failed retained-Result cases. JSON failed before Checkpoint with
`MoonBitHostFailure`; its original Run, database, receipt and artifacts remain
unchanged. SQL/AQL's separate implicit-public-Result defect was fixed in #2286.

Common requires every declared Result in a local Result Manifest. The Host
previously supplemented non-consumed declarations only when an Effect used a
private Table input. Ordinary Effects could therefore submit only `written`
and omit `before_write`. The independent pre-fix Node sequencing case observes
that omission. A reduced in-memory Core case captures two declared Results,
issues both real Artifacts, and proves `IncompleteResults` for the consumed
subset and acceptance for the complete inventory. It does not claim to run
the original two-task installed control.

The fix uses the existing captured local Result inventory and exporter for
ordinary inputs too. Temporary Manifest exports use retained data and the
existing prepared-payload cleanup owner. No Source read, Effect member,
public Result, permission or new runtime owner is invented. Common strict
Manifest admission is unchanged.

Enumeration and membership comparisons spend the original grouping-work
budget. The independent two-member/one-Result sequencing case now accounts
for two import checks, three live-view checks, one Result visit and one member
match. The former four- and five-work requests remain refusals with no Store
writer; the seven-work control expresses that independent sum. No adapter
default, caller budget, capacity, fuel or public expectation is increased.

Run the tracked recipe from its exact clean commit with pinned Node/Moon:

```sh
node reviews/2026-10-15-ctas-result-manifest/prepared-checks.mjs <full-source-sha>
```

The recipe executes the focused Node sequencing/cleanup cases and one actual
Core capture/Artifact/Manifest case, checks changed Moon formatting read-only,
and checks whitespace. It uses non-Heavy 60 seconds / TERM 5, child 30 and j1.
Cold compilation, when needed, is a separate build-only preparation, not a
test pass. Node doubles establish Host sequencing only; the Core case uses
the existing in-memory dispatcher and capture owners. Neither is installed
Local/HTTPS acceptance.

The original JSON/SQL/AQL CTAS controls, `before_write` rows/schema, false
filter, NULL column, empty Table input and ten-case public inventory are
unchanged. A new same-source normal release cohort must execute that original
public inventory. This PR alone adds zero installed E2E successes and does not
reclassify the original JSON Unknown or acknowledge its cleanup.
