# SGA integration and Reach selector follow-up

## Fixed source and executed public acceptance

The original eight SGA cases pass at
`64812d8eff6d16414c4e894d5845e2f44d8b21c7` through clean packed Embedded
Local, HTTPS Remote, and the Node-free native CLI. The cases are `components`,
`reach-subgraph`, `diff-apply`, `mean-graphs`, `graphs-equal`, `normalize-rows`,
`degree-rows`, and `graph-bounds`. Each transport reads the independently
authored Named Results. Source ordering and expected rows are unchanged.
SDK acceptance also checks lookup, exact attach, same-request resubmission,
reread and normal stream termination. SQL/Pipe controls pass on both SDK
transports. Source-free SGA adds no external source reads.

| Adopted input | Full SHA |
| --- | --- |
| B Frontend baseline | `2e21a039245ba681a90a7f18a3fd6e2797265107` |
| A retained Graph comparisons | `682ebfb4f45943dc30480d6263fe9b173620d61c` |
| Checked Graph order correction | `20e09070c98072c9a732fec72668eeebafa16aeb` |
| Merged PR #63 head | `e1f7d333b702613336739798e3c9cdc41cb5a3d6` |
| Adopted main | `d22e53fc5fc9a96018044c424f4ad8c7e9830295` |
| Follow-up integration commit | `fed6ec2e2c4d5e3bbfb7372ebcb23abc97c16ab5` |
| Verified follow-up source | `64812d8eff6d16414c4e894d5845e2f44d8b21c7` |

PR #63 is merged. Its earlier Draft status and the failed A/B order probe
are historical evidence, not current blockers. The later checked Graph
identity order witness permits the authored edge ordering without calling a
nullable Relation field a candidate key. No Frontend sort or Local-only
execution path was introduced.

Reproduction, with the pinned MoonBit toolchain and Node 22:

```sh
ACTQL_TEST_SGA_CASES=components,reach-subgraph,diff-apply,mean-graphs,graphs-equal,normalize-rows,degree-rows,graph-bounds node scripts/test-packed-public-query.mjs
```

Evidence: `worktrees/.codex-scratch/public-query-evidence-0UZBXE`.
All ten recorded commands exited zero. The installed artifacts were removed
after saving command observations, logs, source SHA and digests.

| Packed artifact | SHA-256 |
| --- | --- |
| `client-wire` | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| `sdk` | `8831e97c0f431c0d0e60c52ba1b0eebad755f2fd2403963912daf82862cbfd8b` |
| `run-host-core` | `1938f3fee2d0c820350b3748aad9cb8e211d126ee6200237097d6eb1d8901325` |
| `local-node` | `7c2b19fbfa42d01f731b10927a9b2a3ada163138ac34bb3914634c7e14b65b82` |
| `node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |
| Native CLI binary | `919d05e1d5728e2d40825f4d830a5a3a75f63056b32a0e5cc34c5fd8dbe770d4` |

The public Result API exposes rows, not schema type/nullability/column order.
These packed expectations prove row shape, values and order; common typed
Program tests remain separate schema evidence. No external Graph service or
pushdown was tested. Linux CI for this follow-up source is not yet verified.

## Reach selector changes and failure boundary

The existing Reach contract admits a retained Relation selector. Its selected
IDs are deduplicated, every ID must exist, and an empty selection is valid.
A nullable field may supply non-null IDs; an actual selected NULL is invalid.
The independent fixtures now explicitly declare the full Result projection,
including semantic `id`, rather than asking the Host to infer open fields.

The follow-up commits are:

- `f8cb0299fc8fe486035f8205519b5d8e552ed93b`: classify checked Graph
  schema-domain incompatibility as invalid input. Keep owner and unavailable
  evidence failures unclassified. Focused `program_check` JS passed 343/343.
- `c1ff7d4fd2224dce73547b5cb2bbb5a0279a703a`: independent duplicate,
  empty and nullable seed fixtures, public type refusal, selected NULL and
  missing-member failure assertions. These are tests, not passing public
  selector execution evidence.
- `64812d8eff6d16414c4e894d5845e2f44d8b21c7`: declare the checked Graph
  port at input zero and Relation selector at input one. Compiler tests prove
  exact task edges and Result roots for the shared alias and separate seed
  producers. Source/Program plus common preparation tests passed 35/35;
  `lowering_relation` JS passed 219/219. Format and diff checks passed.

The first selector packed probe at `c1ff7d4fd` failed before Run acceptance:
`RunHostCompilationRejected`, exposed as `SubmissionUnknown`. Its evidence
is `worktrees/.codex-scratch/public-query-evidence-Sgk984`; no positive
selector public execution is claimed. Common task preparation subsequently
identified the missing managed Relation input declaration and now emits four
tasks for the alias case, or five for a separate seed producer.

The remaining provider boundary is
`src/local_sga_provider/graph_pipeline.mbt`, in `provider`'s selected-input
cardinality validation. It currently groups `direct_reach` with unary Graph
diagnostics and requires zero Relations. The already existing Reach view
kernel accepts the checked Relation selector through `value.inputs`.

The required local provider change is to derive the Reach Relation count
from `graph_reach_start_relation_field` on the selected checked operation:
one when present, zero otherwise, with exactly one Graph in either case.
Keep the exact selected owner/generation checks and existing input binding.
Do not change the Reach kernel, resource ceilings, task owner or cleanup
implementation. Unsolicited, missing and wrong-generation inputs must still
fail. The file remains A-owned under the existing editing agreement; the
scoped ownership question has been presented before editing it.

After that connection, B must run the four positive selector sources and
the typed refusal/runtime membership tests through both packed SDK
transports, then close the requested capacity-excess and cancellation
acceptance. Neither the eight-case success nor the compiler port tests
substitute for those remaining checks. The SGA goal is still active.
