///|
test "graph computations publish only their explicit typed relation outputs" {
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    @carrier.unknown_rows(),
    @carrier.unknown_rows(),
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"normalize_graph\":true,\"as\":\"normalized\"},{\"components\":{\"kind\":\"weak\"},\"as\":\"members\"}]",
    ),
    [("g", graph)],
    None,
    None,
    {
      max_steps: 100,
      max_work: 10000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let accepted = @relation_results.check(
    p,
    cursor(
      "{\"result\":{\"from\":\"members\",\"fields\":[\"node_id\",\"component_size\"]}}",
    ),
    limits(),
  ).unwrap()
  assert_eq(@relation_results.count(accepted), 1)
  let rejected = @relation_results.check(
    p,
    cursor("{\"result\":{\"from\":\"normalized\",\"fields\":[\"node_id\"]}}"),
    limits(),
  ).unwrap_err()
  assert_eq(rejected.kind, WrongCarrier(GraphKind))
}
