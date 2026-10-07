# Resumable Values and binary Relation completion preparation

## Scope and adopted owners

This unit follows #749 at
`34103565a2c1643c20bba25f26336d7bb47741ad`. It normally merges main
`59786a7d88f5f2c86ce336b8907febcce12137b2` without conflicts and retains
the unmerged parent dependency. Current Graph definitions and identity domains
remain authoritative; no saved identity is reinterpreted or aliased.

Values, Append, EXCEPT/INTERSECT ALL and DISTINCT, and Cross Join already use
bounded computation and trusted completion owners. Their start functions still
called the synchronous output-port validator, scanning all output spellings
before the first resume. Four independent one-short name regressions failed
at start before this change (`run-COSVse`, `focused-test-FFppTB`, 0/4).
This is evidence of synchronous preparation, not measured public stop latency.

The four kernels now drive the private `TrustedOutputPreparation` from #749
inside their existing bounded sessions. Exact receiving-port admission stays
at start. Output identity UTF-8 admission, retained identity matching and
canonical schema names advance one scalar or code unit per transition before
input scanning, cell demand or set sorting. The kernel algorithms, logical
control/value charges, row ordering and workspace limits are unchanged.

Partial preparation cannot provide a trusted completion port. Stop is checked
between transitions, and binary input availability remains checked by its
existing read owner. Cleanup clears the pending name array once and retains
borrowed input custody. Successful preparation transfers its array to the
port; completed output survives cleanup. Verifier closures capture only the
live/rows Refs, not the complete execution state.

## Independent quantities and regression scope

The name limits are derived from the fixture spellings, not successful usage:

| Operation | Exact UTF-8 bytes | One-short |
| --- | ---: | ---: |
| Values: `values_0` twice, `id`, `label` | 23 | 22 |
| Append: `append_0` twice, `id` | 18 | 17 |
| EXCEPT: `except_0` twice, `id` | 18 | 17 |
| INTERSECT: `intersect_0` twice, `id` | 24 | 23 |
| Cross Join: `cross_join_0` twice, `id`, `tag` | 29 | 28 |

For Values, a 256-ASCII-plus-emoji field requires 278 bytes including both
target occurrences and `id`; 277 refuses before cell demand. This byte-focused
case has workspace headroom rather than conflating name and frame limits.
The original short Values logical work 15/14 and workspace 4/3 remain tested.
Existing binary work/workspace, input, output and nested comparison boundaries
are retained. Earlier input-scan stop fixtures explicitly finish the newly
resumable port phase before testing their original boundary; their logical
limits and operation-phase poll watchdogs are not enlarged.

Quanta 1/7/256 preserve independent fixed rows, complete column order, cumulative
physical work, logical control usage and workspace peak. Separate stops inside
all four name phases prove no completion, no input scan, retained borrowed
inputs and idempotent cleanup. ALL/DISTINCT Set variants use fixed duplicate
rows and independently expected survivors. Pending-cursor cleanup is included
in each public cleanup API's invariant.

The working-tree selected JS batch passed 58/58 (`run-MMPtP4`,
`focused-test-ObLSNF`), including the four kernels, binary output/resource
boundaries and shared Local chain lifetime/evidence callers. An earlier batch
passed 52/58: five older fixtures hit their pre-existing poll watchdog before
reaching their intended operation boundary; the Unicode name-only case lacked
separate workspace headroom. A preceding compiler diagnostic found an invalid
new Stopped pattern. These are retained diagnostics, not passing receipts.

## Normal Host evidence connection

The existing public retained-name harness adds ordinary Programs for Values,
Append, both Set operators and both duplicate modes, and Cross Join. Each
producer emits a long Unicode-named column, then explicitly renames it for
three public Named Results (`published`, `consumed_a`, `consumed_b`). Fixed
expected rows preserve NULL, duplicates and canonical public order. The
actual Embedded Local Host and retained Store exercise repeated-request reuse,
post-progress cancellation, physical-stop confirmation, nonpublication and
final snapshot reclamation. This public barrier observes preparation progress;
only the private cursor fixtures claim an exact output-name phase.

The production-route inventory connects limit, quantum, stop and public
evidence to each of the five operations. Removing any required role fails the
resource checker. These supplement the existing operation-specific assurance;
they do not replace work/workspace evidence with a name correspondence table.
Submitted-source public execution receipts are reported separately in the PR.

## Remaining obligations

Other bounded kernels still use synchronous trusted-port preparation. These
four kernels also have separate downstream metadata/name-charge and field
resolution work; moving the completion validator does not certify every such
scan as interruptible. Installed availability callbacks and general producer
preparation retain their distinct audit scope.

Each state now holds optional pending/prepared ports and one private cursor.
The existing name array transfers without a second backing; record shape and
allocation timing nevertheless change. This portable source/test evidence is
not Native byte/callback correspondence. G's affected correspondence review
remains separate, as do full Core, Wasm/Native execution, packed Local/HTTPS,
performance and real stop-latency measurement. Runtime bundles must be rebuilt
from the submitted source and remain untracked. This is not Local Compute
completion or CI success.
