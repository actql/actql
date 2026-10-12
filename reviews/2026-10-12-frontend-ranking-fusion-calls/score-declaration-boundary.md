# Retained score declaration boundary

Inspection baseline: `b3a0cfafffeee515fcceb8a5ae59f1b4f63ca617`.
The finite source below reaches the existing MissingScoreContract, not a successful
scored fusion. This is expected for unasserted raw Values. The same missing
metadata axis must not be concealed by inventing a frontend declaration.

```aql
WITH l AS (SELECT 1 AS id, 0.5 AS s), r AS (SELECT 2 AS id, 0.5 AS s)
FROM l |> merge_rankings(with: r, by: [], candidate: id, score: s, k: 3,
  score_policy: {weighted_sum: {left: 0.5, right: 0.5}},
  score_contract: {domain: 'Relevance', range: [0, 1], normalization: 'Identity'});
```

Independent intended operation body:

```json
{"with":"r","by":[],"candidate":"id","score":"s","k":3,"score_policy":{"weighted_sum":{"left":0.5,"right":0.5}},"score_contract":{"domain":"Relevance","range":[0,1],"normalization":"Identity"}}
```

Positive captured inputs require existing environment snapshot score assertions
for `s` on both Relations under this exact domain/range/normalization. Source
ownership, environment membership and bound schema must be retained. Expected
scored rows would be `{id:1,score:0.25,rank:1}` and `{id:2,score:0.25,rank:2}`;
missing-side score is +0, weights are not renormalized, and candidate identity
completes the tie. This positive case has not been executed.

Relevant existing APIs: stage_local_inputs.reconcile_environment and
prepare_environment; environment_input_at yields typed registrations and
attach_reconciled retains the same Owner. Relevant frontend seam:
query_program.Context and query_binding_check.check_query_prefix. No source
adapter, permission bypass or separate Score evaluator is proposed. The main
product's actual public snapshot/Source path must be used and independently
accepted before this remaining requirement closes.
