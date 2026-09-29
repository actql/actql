# Checked Result transformation handoff

## Fixed source and ownership

Shared baseline: `3c2be81e0eac698defd31ded49f9a29338b72160`.
Branch: `feat/frontend-sga-operators`.

The independent shared commits, in adoption order, are:

1. `1a3282093494e02ad1dfa98cb6c0417d511a1098`: derive Reach capacity
   applications from existing Host ceilings. No kernel or ceiling change.
2. `2eda3030b4f67e5c2a348fbf32b8325a56975ce6`: checked Result transformation selection and bounded export.
   It can also be adopted without the Reach change for Relation-only Programs.

B owns `client_result_transformation.mbt` and the separate regression files.
C owns Plan assembly, bridge and Host connection. This work does not depend
on an unpublished C commit. The existing direct-root rejection is unchanged.

## Interface and ownership

`prepare_client_result_transformation(prepared, resultIndex, bytes, nodes,
 depth)` selects the exact checked root occurrence and issues its existing
logical Result Plan and Result Definition. Names, projection and order come
from that owner, not caller-supplied JSON. `client_result_transformation_plan`
returns the existing `ClientResultPlanIdentity`; its row contract and logical
CID are available through existing accessors. This is not an Executable Plan
node and does not grant permission to publish raw task output under that CID.

`start_client_result_transformation(selection, completedOutput, limits)` uses
`execution_relation.start_completed_result_relation_export`. The existing
Result projection and bounded stable sort remain the only implementation.
A different checked owner or output target is rejected even with equal data.

```moonbit
let selection = @publication_host.prepare_client_result_transformation(
  prepared, result_index, 100000, 10000, 100,
).unwrap()
let transformation = @publication_host.start_client_result_transformation(
  selection, completed_output, export_limits,
).unwrap()
while true {
  let (done, _) = transformation.advance(64).unwrap()
  if done { break }
}
let export = transformation.finish().unwrap()
// Drain export.next(), then export.finish(), before issuing evidence.
// Existing export.issue_result_evidence uses the completed transformed view.
// Close export on success or failure; cancel unfinished transformation work.
```

The caller retains the exact completed producer or managed publication bridge
until the export and any replay have closed. The new handle does not acquire
an additional physical hold or create a cleanup owner. Cancellation delegates
to the existing export preparation; it neither cancels the Run nor releases
another consumer's hold. Once `finish` transfers the stream, `export.cancel`
owns its cleanup. A failed preparation must be cancelled by its caller.

Ordering evidence is issued only after the transformed stream establishes its
logical identity and schema. Its `occurrence` order is the transformed checked
Result sequence, not the producer's original sequence. C supplies the existing
admitted Run/computation/policy bindings; the module does not invent them.

## Connection changes for C

- In `issue_prepared_client_values_plan_graph` and
  `issue_prepared_client_task_plan_graph` (their respective `*_plan_graph.mbt`
  files), preserve
  the existing direct-root fast path. A Result requiring transformation needs
  its checked transformation and output contract represented before accepting
  the Executable Plan. Do not change the direct root to describe raw output as
  transformed output, or remove `RequiresResultTransformation`.
- Retain the selection for the same prepared owner and Result index through
  compilation and Run execution. Bind the Result Plan's logical identity to
  the resulting publication; do not substitute task/Unit identity for it.
- At completed-output publication, pass the exact live producer/bridge to the
  new module, drive bounded preparation, then use the existing export receipt,
  evidence and Store/publication path. Preserve current holds and error cleanup.
- `client_program_bridge.mbt`, `local-values-plan.mjs` and Host routing are not
  edited by B. Add their connection in C's separate commit.

## Local evidence and remaining acceptance

The Reach change passed the affected `pipeline_check_context` package and the
separate runtime ceiling/cleanup regression: 281 tests on JS. It checks Reach
subjects, unchanged Host ceilings, swapped-subject refusal, work-limit refusal,
Traverse path behavior, runtime output-limit failure and cleanup.

The Result module regression passed on JS. An ordinary checked Values Program
executes through the existing Local Host test driver with producer rows
`[3,1,2]`. Its ordered Result exports `[1,2,3]`; its unchanged Result exports
`[3,1,2]`. The test checks different logical identities, transformed evidence,
foreign-owner rejection, mismatched logical-value evidence, bounded work,
cancellation, and that the direct root still refuses the ordered Result while
accepting the unchanged Result.

```sh
moon test --target js --deny-warn src/pipeline_check_context \
  src/query_integration/reach_capacity_boundary_wbtest.mbt
moon test --target js --deny-warn \
  src/query_integration/client_result_transformation_wbtest.mbt
```

This is module/Host-driver evidence, not packed SDK acceptance. The packed
Reach reproduction now passes capacity preparation but still rejects explicit
Result ordering at the direct compilation boundary. Keep that rejection until
C connects the transformation. The desired descending order differs from the
Reach producer's ascending node order:

```sh
ACTQL_LOCAL_STATE_DIR="$PWD/_build/reach-result-state" \
  node scripts/reproduce-packed-reach-capacity.mjs <packed-installation>
```

C must run this through both packed Local and HTTP after connection. Public
source-text SDK/CLI routing and SGA syntax execution remain separate pending
acceptance. No HTTP, remote provider, Linux CI or deployed-service success is
claimed here. Full local gate results are recorded after the fixed-source run.

## Packed capacity diagnostic artifacts

Produced with normal package prepack from the Reach-fixed source (runtime
source corresponds to `1a3282093`), then installed with `--ignore-scripts` into
a clean workspace-local directory. These are diagnostic artifacts, not package
releases or proof that Result publication is connected.

| Package | SHA-256 tarball digest |
| --- | --- |
| @actql/client-wire | `7f244f979465e83283a9c4af57ba20cddd99b4a18cac618f746288e03c37d1cd` |
| @actql/sdk | `e07a6bdfb41c38b3613911180aaaf155f1334300a81ae0e4b830962aace95f58` |
| @actql/local-node | `de421bbc43b3f3a64c471f02cb400bbed2fb4ecd6ccad193c4c241a3f31e8b87` |
| @actql/node | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

## Fixed-source Core verification

The validated source tree is `79a719ce4ce1499f2c1bf406d7761990739ab6a6`,
retained at `83db9f1d4`. JS and Wasm were run before an unpublished commit
message was wrapped to 72 columns; the tree before and after that metadata-only
change is exactly identical. Native ran after the message correction. This
record subsequently changes documentation only.

| Local Core job | Result |
| --- | --- |
| `node scripts/local-checks.mjs run core --target js` | Total tests: 6938, passed: 6938, failed: 0. |
| `node scripts/local-checks.mjs run core --target wasm` | Total tests: 6935, passed: 6935, failed: 0. |
| `node scripts/local-checks.mjs run core --target native` | Total tests: 6997, passed: 6997, failed: 0. |

The new Result module test uses test authority CIDs when exercising the
existing evidence encoder/validator. It does not claim a formally connected
Executable Plan, a durable Run admission, or a Store publication. Those remain
C's connection and packed acceptance obligations above.

On clean commit `689e41ee9f966415beb90b73bb653d33a4f64155`, the local
`lint` job (including public MoonBit interfaces) and `spec` job both passed
through `scripts/local-checks.mjs`. The latter includes the version, schema,
pin and generated-artifact checks. This final evidence update changes only
this document; no product source or generated interface changed after those
checks. Linux CI was not checked.
