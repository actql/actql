// Historical contract evidence, deliberately not regenerated from current output.

///|
let resident_effect_source_historical_registry : String =
  #|{"ACTQL.expression_fragment/0.1":{"execution_contract":{"cid":"sha256:9f0694ddd7c76d720024297fce02652bb15f5dad8b278d3db9ff58936a976b87","file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/ACTQL.expression_fragment~10.1"},"inputs":["relation"],"output":"relation"},"BRIDGE.events.to_rows":{"inputs":["event_stream"],"output":"relation"},"BRIDGE.graph.to_edge_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.graph.to_node_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.rows.to_events":{"inputs":["relation"],"output":"event_stream"},"BRIDGE.rows.to_graph":{"execution_contract":{"cid":"sha256:b6c5006e94c3c865672ab2478f4b1897aa567314502e55eb50f784a50a94d210","file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/BRIDGE.rows.to_graph"},"finite_inputs":{"minimum_inputs":0,"repeated_input":"relation"},"output":"graph"},"BRIDGE.rows.to_vectors":{"inputs":["relation"],"output":"vector_set"},"BRIDGE.vectors.to_rows":{"inputs":["vector_set"],"output":"relation"},"EFFECT.plan":{"inputs":["relation"],"output":"relation"},"REL.analytic":{"inputs":["relation"],"output":"relation"},"REL.assert_all":{"inputs":["relation"],"output":"relation"},"REL.assert_unique":{"inputs":["relation"],"output":"relation"},"REL.cross_join":{"inputs":["relation","relation"],"output":"relation"},"REL.dedupeRows":{"inputs":["relation"],"output":"relation"},"REL.derive":{"execution_extensions":{"ordered_bindings":{"cid":"sha256:2c5818e25cf54e21aadecd451414a295cb7d8398adf632ebd07c63943ddfdecb","file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.derive.ordered"}},"inputs":["relation"],"output":"relation"},"REL.distinct":{"inputs":["relation"],"output":"relation"},"REL.except_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.groupBy":{"inputs":["relation"],"output":"relation"},"REL.intersect_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.join":{"inputs":["relation","relation"],"output":"relation"},"REL.json.pick":{"inputs":["relation"],"output":"relation"},"REL.limit":{"inputs":["relation"],"output":"relation"},"REL.orderByStable":{"inputs":["relation"],"output":"relation"},"REL.pivot":{"inputs":["relation"],"output":"relation"},"REL.select":{"inputs":["relation"],"output":"relation"},"REL.topk":{"inputs":["relation"],"output":"relation"},"REL.topk_partitioned":{"inputs":["relation"],"output":"relation"},"REL.unionAll":{"inputs":["relation","relation"],"output":"relation"},"REL.unnest":{"inputs":["relation"],"output":"relation"},"REL.unpivot":{"inputs":["relation"],"output":"relation"},"REL.values":{"execution_contract":{"cid":"sha256:9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b","file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.values"},"inputs":[],"output":"relation"},"REL.watermark":{"inputs":["relation"],"output":"relation"},"REL.where":{"inputs":["relation"],"output":"relation"},"REL.window.fixed":{"inputs":["relation"],"output":"relation"},"REL.window.lag":{"inputs":["relation"],"output":"relation"},"REL.window.project":{"inputs":["relation"],"output":"relation"},"REL.window.sliding":{"inputs":["relation"],"output":"relation"},"SGA.apply_delta":{"inputs":["graph","relation"],"output":"graph"},"SGA.bounds_check":{"inputs":["graph"],"output":"relation"},"SGA.components":{"inputs":["graph"],"output":"relation"},"SGA.degree_metrics":{"inputs":["graph"],"output":"relation"},"SGA.diff":{"inputs":["graph","graph"],"output":"relation"},"SGA.diff_structural":{"inputs":["graph","graph"],"output":"graph"},"SGA.equal":{"inputs":["graph","graph"],"output":"relation"},"SGA.graft":{"inputs":["graph","graph"],"output":"graph"},"SGA.match_edges":{"inputs":["graph"],"output":"relation"},"SGA.match_nodes":{"inputs":["graph"],"output":"relation"},"SGA.mean_structural":{"finite_inputs":{"minimum_inputs":1,"repeated_input":"graph"},"output":"graph"},"SGA.normalize":{"inputs":["graph"],"output":"graph"},"SGA.reachable":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.shortest_path":{"input_alternatives":[["graph"],["graph","relation"],["graph","relation","relation"]],"output":"relation"},"SGA.subgraph":{"input_alternatives":[["graph"],["graph","relation"]],"output":"graph"},"SGA.traverse":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.union_structural":{"finite_inputs":{"minimum_inputs":2,"repeated_input":"graph"},"output":"graph"},"TEA.dedupe":{"inputs":["event_stream"],"output":"event_stream"},"TEA.join.asof":{"inputs":["event_stream","relation"],"output":"relation"},"TEA.join.interval":{"inputs":["relation","relation"],"output":"relation"},"TEA.sequence.match":{"inputs":["event_stream"],"output":"relation"},"TEA.time_series":{"inputs":[],"output":"relation"},"TEA.watermark.label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.fixed_label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.session_assign":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.sliding_assign":{"inputs":["event_stream"],"output":"event_stream"},"VEC.knn_join":{"inputs":["vector_set","vector_set"],"output":"relation"},"VEC.merge_rankings":{"output":"relation","policy_inputs":{"max":{"inputs":["relation","relation"]},"rrf":{"minimum_inputs":2,"repeated_input":"relation"},"weighted_sum":{"inputs":["relation","relation"]}}},"VEC.normalize_l2":{"inputs":["vector_set"],"output":"vector_set"},"VEC.pool":{"inputs":["vector_set"],"output":"vector_set"},"VEC.score_sort":{"inputs":["vector_set"],"output":"vector_set"}}

///|
test "stale Source registry is refused by the original admission before acquisition" {
  let body = @canonical.from_json(
    @json.parse(resident_effect_source_historical_registry),
    10000,
    100,
    100000,
  )
  assert_eq(
    @canonical.cid_value(body, 100000, 10000, 100),
    "sha256:b79f24b0c777c4b9d533ef01289587e666caa7a6ba00159f6b45f3e57265f04e",
  )
  let values = @canonical.from_json(
    @json.parse(resident_effect_source_values),
    10000,
    100,
    100000,
  )
  assert_true(
    @execution.admit_relation_registry(body, values, {
      max_body_bytes: 100000,
      max_body_nodes: 10000,
      max_body_depth: 100,
    })
    is Err(UnsupportedRegistry),
  )
  assert_true(
    @local.prepare_installed_sequence_contracts(
      resident_effect_source_historical_registry,
      resident_effect_source_values,
      Some(resident_effect_source_fragment),
      None,
    )
    is Err(@local.Unsupported),
  )
}
