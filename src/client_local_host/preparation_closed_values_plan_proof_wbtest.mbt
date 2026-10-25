///|
test "closed Values plan schema envelope uses actual Number schema emitter" {
  let prepared=result_envelope_fixture()
  let graph=@publication_host.prepared_client_graph(prepared)
  let occurrence=@strategy.graph_result_occurrence(graph,2).unwrap()
  let schema=@results.port_schema(@execution.managed_result_occurrence_port(occurrence))
  let identity=@execution.identify_relation_schema(schema,{max_fields:1,max_bytes:1000,max_nodes:4,max_depth:2}).unwrap()
  let (bytes,nodes,fields)=@execution.relation_schema_usage(identity)
  assert_eq(fields,1)
  assert_eq(nodes,4)
  assert_eq(bytes,40)
  assert_true(bytes<=2+1*(1+38))
  let small=closed_values_plan_proof_layout(1,1).unwrap()
  let large=closed_values_plan_proof_layout(100,23).unwrap()
  assert_true(preparation_representation_cost(large.temporary).unwrap()>preparation_representation_cost(small.temporary).unwrap())
  assert_true(small.retained==large.retained)
  assert_true(closed_values_plan_proof_layout(2147483647,1) is None)
}
