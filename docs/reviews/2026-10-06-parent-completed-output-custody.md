# Completed-output custody in the serial Relation parent

This change follows the current provider-construction recipe update in #543.
It updates the existing parent observer rather than accepting the historical
single-`previous` representation as a current-source fallback. Product execution,
capacity reservations, and the cleanup owner are unchanged.

## Source-derived obligations

`bounded_relation_chain_execution` creates `Ref[Array[CompletedOutput?]]`
with exactly the checked step count of nullable slots before starting a child.
Each nonfinal completion is stored at its producer position. The final output
is returned to the caller and is not put into those intermediate slots.
`relation_chain_step_inputs` uses the producer step to find that exact slot,
then validates the checked owner, receiving port, and actual completed output.
The completed array is neither copied nor grown by the parent.

The parent retains the array through terminal observation and reverse child
cleanup. A pending/error child cleanup leaves its references intact. Only
successful cleanup of every child resets `completed` and `children` to empty
arrays. A successful cleanup observation does not prove physical GC reclamation.
Completed payloads remain a separate child/shared-ownership obligation; their
bytes are not silently included in this container-only formula.

Under the existing pinned Native ABI premises, the retained-core conditional
envelope becomes `736 + 16 * childrenSlotsCeiling(count) + 8 * count` requested
header/payload bytes. The fixed completed backing contributes one dynamic header
and `count` nullable reference slots. Its reset may overlap two Array owners,
but the new empty backing is process-static. This is not a whole-parent or
physical process memory bound. The retired component witness becomes 624.
The two-child startup lower component, including its newly observed completed
container, becomes 664; this remains distinct from total reservation soundness.

## Independent correspondence boundaries

The C phase reader synchronously borrows the actual parent roots and completed
array/backing. It reports slot output/completion identities, lengths, storage,
and lifecycle observations without saving object pointers or adding strong
references. A separate temporary Native MoonBit helper borrows the actual
`CompletedOutput`, its typed `completion`, and `completion.result_identity`.
The audit requires both observations to agree. A numeric label in an archive
cannot replace that typed observation.

`result_identity` denotes a successful process-local completion occurrence.
It is **not** a ledger holding generation. Actual ledger generation, reservation
release, child payload allocation sites, upstream anchors, and their lifetime
union require their own correspondence evidence. They remain unfinished.

The existing executor closes its own exact fixture before source restoration;
closure checks inode/bytes and does not unlink another owner's fixture.
Historical reports are retained by their content digest before updating the
current report pointer. Original source, model, and execution receipts remain
separate from any new observation.

## Current verification

The selected parent bounds/layout/overlay Node tests passed 10/10 against the
working diff over `b91632768fa163a29540bdbb04289a6758cbd6a3`:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 60 -- \
  proofs/relation-pipeline/capacity/backing/parent-bounds.test.mjs \
  proofs/relation-pipeline/capacity/backing/parent-layout.test.mjs \
  proofs/relation-pipeline/capacity/backing/parent-overlay.test.mjs
```

Local receipts: `_build/local-checks/attempts/run-thByU7` and
`_build/focused-evidence/focused-test-5tQdVx`. These are synthetic validator
and source/overlay checks, not actual Native lifecycle evidence.
An initial sandbox rejection occurred before test execution and is not a test
failure. The same command succeeded with the existing process-ownership guard.

At clean source `455c7bb2587d396bd4e657361c0e4b0a30f52e15`, one Native
`pair:filter/distinct` diagnostic used the existing bounded supervisor:

```sh
env MOON_HOME=<pinned MoonBit home> PATH=<pinned MoonBit home>/bin:$PATH \
  node --input-type=module -e '
import {runLocalCheck} from "./scripts/local-checks-guard.mjs";
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:true,
  timeoutSeconds:180,graceSeconds:5,steps:[{
    name:"one Native parent completed-output custody case",
    command:process.execPath,
    args:["proofs/relation-pipeline/capacity/parent-control/run.mjs"]
  }]});'
```

Receipt `_build/local-checks/attempts/run-uGMgho` records timeout/exit 124,
complete captured streams, and released locks. It did not obtain a passed
Native case or an executed binary receipt. No automatic retry or budget increase
was performed. This is not a detected mutation or a Native acceptance success.

The model subprocess preceding Native compilation checked all five conditional
Lean propositions on that exact clean source. Its immutable log and receipt are
`.artifacts/relation-pipeline/capacity/parent-control-probe/models/`:

- log `c0e06bebe299515c66a4509a48268ce3146148d06f63ce9ada474b24cc53e324.log`;
- receipt `134325913b01e7a5a815882e72af1a751a6484e4f96b41860e93c268da7e5f33.json`;
- original source digest `79f2cc368df03abe4f73c5d9f9bb8de999e277a32ea56872e3fc0fa1ac9e3f26`.

After supervisor termination, the complete overlay was compared byte-for-byte
with the overlay reconstructed from that clean Git revision before restoring
all seven source paths and removing four exact generated observers. The restored
source snapshot equals the model receipt's original source digest. The fixture
was retained, rather than treating this as successful executor closure: its
bytes equal the archived fixture and its inode is preserved in
`run-uGMgho/retained-fixture.mbt`, with `fixture-custody.json` recording identity,
digest, and the timeout boundary. The original archived fixture and input remain
in `.artifacts/relation-pipeline/1791242443059-74007-0000-parent-control-startup-native.*`.

Actual Native lifecycle/custody acceptance remains pending. No new full Core,
packed, cross-target, mutation, or performance campaign has been performed.
