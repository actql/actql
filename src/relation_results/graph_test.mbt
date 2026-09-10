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

///|
test "graph bridges feed ordinary relation steps and Result publication" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("customer"),
    Unqualified("source"),
    Unqualified("target"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
  let caps : @pipeline.Limits = {
    max_steps: 100,
    max_work: 10000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }
  for
    (body, field) in [
      (
        "[{\"node_rows\":true},{\"select\":[\"customer\"],\"as\":\"rows\"}]", "customer",
      ),
      (
        "[{\"edge_rows\":true},{\"select\":[\"source\"],\"as\":\"rows\"}]", "source",
      ),
    ] {
    let p = @pipeline.check_carriers(
      cursor(body),
      [("g", graph)],
      None,
      None,
      caps,
    ).unwrap()
    let result = @relation_results.check(
      p,
      cursor("{\"main\":{\"from\":\"rows\",\"fields\":[\"" + field + "\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.count(result), 1)
  }
  let unknown_graph = @pipeline.check_carriers(
    cursor("[{\"node_rows\":true,\"as\":\"rows\"}]"),
    [("g", @carrier.unknown_carrier(GraphKind))],
    None,
    None,
    caps,
  ).unwrap()
  assert_true(
    @relation_results.check(
      unknown_graph,
      cursor("{\"main\":{\"from\":\"rows\",\"fields\":[\"id\"]}}"),
      limits(),
    )
    is Err(_),
  )
}
