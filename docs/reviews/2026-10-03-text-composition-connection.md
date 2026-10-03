# Text composition: candidate connection inspection

This is read-only inspection of B #242 candidate
`aa24b3f0c36fb643efafcc1a0e3206202db030be`. It is not adoption GO, a
text execution result, or a replacement for the JSON acceptance. D's published
#246 HEAD is `df842fb35a51a0a9fc33740a1cca73d4e6f4848a`; its Native/Workers
CI follow-up is retained locally at `d2979058715d98b90cef72c4a10347156580b734`.

## Existing connection boundaries

| Boundary | Inspected behavior | D follow-up |
| --- | --- | --- |
| `installNodePublicSourcePreparation` → `client_program_prepare_source_with_parameters` | The public Local/HTTP preparation shares the installed, generation-bound Source publication and Check Environment. It invokes the existing Frontend, then effect-free preparation. | Preserve this publication and the lowerer's Program when connecting Effect admission; do not introduce another parser. |
| `source_frontend::bind_query_context` | Any captured installed Source selects `captured_stage = Some("capture")`. | The public context selects the capture branch, rather than placing both physical Source inputs directly in the compute Stage. |
| `query_program::bind_script_input` | Each distinct captured input produces one acquisition Stage, named `capture`, then `capture_1`, and an ordinary Stage Result reference. Repeated DATA/CTE uses reuse `sources.bound`. | For this two-Source prefix, acquisition occurrences are `(stage=0,input=0,task=0)` and `(stage=1,input=0,task=1)`, matching `openAcquiredEffectComputation`. Resolve installed providers from the checked requirements, not authored alias order. |
| `lower_script_join_relation` → `compile_join_steps` | Both inputs use that same binding owner. DATA JOIN uses shared JOIN/expression/order lowering and reserves private step names. | Preserve the checked prefix and its producer identities through INFER/KEEP and Effect compilation. |
| `lower_infer_steps` | ITEM KEY maps to the ordinary infer key; KEEP joins the retained input snapshot one-to-one. It does not generate `assert_rows.unique_by`. | Establish the common checker's complete non-null candidate-key proof. The existing JSON fixture explicitly asserts the joined ID; ITEM KEY alone cannot replace that assertion. |
| `installNodeClientProgramPreparation` / `installNodeClientEffectProgramPreparation` | Text selects Source preparation. Effect fallback serializes the original request; B's query-script output has stages/results/params, without an Effect declaration. | Adopting the lowerer alone does not complete text-to-Effect admission. Reuse the existing Effect Program/Run owner and installed MappingRef through the agreed authored input contract. Do not add an implicit write or split the components into separate Runs. |

The Source-prefix occurrence alignment above is established by source inspection,
not a new physical acquisition. B's acquired DATA/CTE/JOIN fixtures do not
contain the full INFER/Effect/restart composition and are not its acceptance.

## Minimal next text probe

The following is an authored query-side probe for the same two-row deterministic
Source/Model fixture. The publication must bind `left_records` and
`right_records` to the corresponding existing installed Sources. This probe is
not an accepted full Effect Program and has not been executed on the candidate:

```text
DATA joined = SELECT l.id AS id, l.amount AS left_amount,
  r.amount AS right_amount
  FROM left_records AS l JOIN right_records AS r ON l.id = r.id;
FROM joined
  |> INFER `model-task:composition-risk.v1` ITEM KEY (id)
     INPUT (score = right_amount)
     KEEP (id, left_amount, right_amount) AS assessment
  |> WHERE assessment.outcome = 'success' AND assessment.value.risk = 'high'
  |> SELECT id, left_amount, right_amount, assessment.value.risk AS risk,
     'a00000000000002' AS target_id, 'review-required' AS next_name
  |> RESULT selected
```

The independent intended selected row remains
`{"id":2,"left_amount":20,"right_amount":200,"risk":"high","target_id":"a00000000000002","next_name":"review-required"}`.
The first unchecked computation boundary is the JOIN-to-INFER key proof; neither
the distinct fixture rows nor the ITEM KEY syntax prove it. Confirm this through
the original checker after formal adoption, before treating any later error as
an A runtime/capture defect. A successful complete text acceptance must also
preserve the JSON expectations: Source sessions `[2,0,0,0]`, Model inputs
`[100,200]`, Effect writes `[0,0,1,1]`, and the same request/Run after both
durable restart boundaries.

## A and integration order

No additional A API, capture or cleanup defect has been established. The older
source-free fragment/ordered omission recorded in the historical handoff is
already closed in the adopted implementation: the physical/replay bridges and
`client_infer_host::start_owned` forward both bodies in the source-free and
acquired branches. The JSON composition exercises the original installed Model
and durable capture owners. The natural CI run
[37114187107](https://github.com/actql/actql/actions/runs/37114187107) completed
its packed Local/HTTPS composition and fault cases at test-merge SHA
`d4132b00a8a1b0647e7cfbbc1461d6b37d80e54e`, associated with submitted HEAD
`df842fb35a51a0a9fc33740a1cca73d4e6f4848a`. Overall CI failed separately.

Close the JSON #246 unit first, then adopt B's reviewed fixed SHA after formal
GO and connect these boundaries with equivalent public text acceptance. #233's
missing history declaration is owned exclusively by B #254. D reuses its
main integration without adding or rewriting declarations. History repair,
new-HEAD product acceptance and final required CI are separate results.
