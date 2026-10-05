///|
fn graph_current_selector_relation() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("key"),
          Some(@contract.primitive(JsonType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=3,
    ).unwrap(),
  )
}

///|
fn graph_current_owner(
  source : String,
  with_relation : Bool,
) -> @lowering_relation.BoundPrepared {
  let inputs = if with_relation {
    [
      ("g", graph_match_carrier()),
      ("selected", graph_current_selector_relation()),
    ]
  } else {
    [("g", graph_match_carrier())]
  }
  let checked = @pipeline.check_carriers(cursor(source), inputs, None, None, {
    max_steps: 100,
    max_work: 100000,
    max_text_bytes: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 4000,
  }).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "unconnected lowering consumers cannot issue retired Graph kernels for a current definition" {
  for
    (name, body) in [
      (
        "reach",
        "{\"start\":{\"ids\":[" +
        graph_match_identity(2) +
        "]},\"direction\":\"out\",\"max_depth\":1}",
      ),
      (
        "shortest_path",
        "{\"source\":{\"ids\":[" +
        graph_match_identity(2) +
        "]},\"target\":{\"ids\":[" +
        graph_match_identity(2) +
        "]},\"direction\":\"out\",\"max_hops\":1}",
      ),
      ("subgraph", "{\"nodes\":{\"where\":\"active\"},\"edges\":\"active\"}"),
      ("graft_graph", "{\"with\":\"peer\"}"),
      ("subtract_graphs", "{\"with\":\"peer\"}"),
      ("union_graphs", "{\"with\":[\"peer\",\"g\",\"peer\"]}"),
      (
        "mean_graphs", "{\"with\":[\"peer\",\"g\"],\"weights\":[1,1],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}",
      ),
    ] {
    let checked = @pipeline.check_carriers(
      cursor(
        "[{" +
        (if name == "mean_graphs" {
          "\"as\":\"mean\","
        } else {
          "\"from\":\"g\","
        }) +
        "\"" +
        name +
        "\":" +
        body +
        "}]",
      ),
      [("g", graph_match_carrier()), ("peer", graph_match_carrier())],
      None,
      None,
      {
        max_steps: 100,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 4000,
      },
    )
    guard checked is Err(issue) else {
      fail("unsupported consumer issued a pipeline")
    }
    if !(issue.kind is @pipeline.Graph(@graph.UnsupportedGraphOperation) ||
      issue.kind
      is @pipeline.GraphMatch(
        @graph.Structure(@graph.UnsupportedGraphOperation)
      )) {
      fail(
        "unexpected refusal from " + name + ": " + @debug.to_string(issue.kind),
      )
    }
    assert_true(issue.path.contains(@source.Key(name)))
  }
}

///|
test "current Graph equality lowers as one ordered binary occurrence" {
  let graph = graph_match_carrier()
  let checked = @pipeline.check_carriers(
    cursor("[{\"from\":\"g\",\"graphs_equal\":{\"with\":\"peer\"}}]"),
    [("g", graph), ("peer", graph)],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 4000,
    },
  ).unwrap()
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let plan = @lowering_relation.bound_preparation(owner)
  let node = @lowering_relation.node_at(plan, 0).unwrap()
  assert_eq(@lowering_relation.operation(node), "SGA.equal")
  assert_eq(@lowering_relation.node_input_count(node), 2)
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_true(
    @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphEqualityStep(_)),
  )
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"graphs_equal_0\",\"in\":[\"input_0\",\"input_1\"],\"op\":\"SGA.equal\",\"params\":{}}]",
  )
}

///|
test "current Graph diagnostics lower to their registered typed operations" {
  for
    (name, body, operation) in [
      ("normalize_graph", "true", "SGA.normalize"),
      ("degree", "{\"direction\":\"both\"}", "SGA.degree_metrics"),
      ("graph_bounds", "{\"max_nodes\":1}", "SGA.bounds_check"),
      (
        "components", "{\"kind\":\"strong\",\"max_output_rows\":2}", "SGA.components",
      ),
    ] {
    let prepared = graph_current_owner(
      "[{\"from\":\"g\",\"" + name + "\":" + body + "}]",
      false,
    )
    let plan = @lowering_relation.bound_preparation(prepared)
    assert_eq(@lowering_relation.node_count(plan), 1)
    assert_eq(
      @lowering_relation.operation(@lowering_relation.node_at(plan, 0).unwrap()),
      operation,
    )
  }
}
