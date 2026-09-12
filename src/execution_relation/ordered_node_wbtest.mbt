///|
test "ordered node identity covers complete graph step while source excludes machine metadata" {
  let params = params_for(",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}")
  let artifact = prepare_ordered_node_artifact(params, registry_limits()).unwrap()
  assert_true(physical_equal(artifact.params, params))
  // Independently assembled {id,in,op,params}, hashed with Node SHA-256.
  assert_eq(
    artifact.graph.cid,
    "sha256:184a9ccd00ea30cefc64519b67f9e69c56113a4b15a86ca2ddda349e463b1b55",
  )
  let source = @identity.stringify_value(
    artifact.source.value,
    10000,
    1000,
    100,
  )
  assert_false(source.contains("references"))
  assert_false(source.contains("row_kernel_contract_cid"))
  assert_false(source.contains("row_kernel_evidence"))
  assert_true(source.contains("\"bindings\""))
  assert_true(source.contains("\"in\":[\"input\"]"))
  assert_true(artifact.source.cid != artifact.graph.cid)
  let exact = {
    ..registry_limits(),
    max_body_bytes: artifact.source.bytes + artifact.graph.bytes,
    max_body_nodes: artifact.source.nodes + artifact.graph.nodes,
  }
  assert_true(prepare_ordered_node_artifact(params, exact) is Ok(_))
  assert_true(
    prepare_ordered_node_artifact(params, {
      ..exact,
      max_body_bytes: exact.max_body_bytes - 1,
    })
    is Err(OutputLimit),
  )
  assert_true(
    prepare_ordered_node_artifact(params, {
      ..exact,
      max_body_nodes: exact.max_body_nodes - 1,
    })
    is Err(OutputLimit),
  )
}
