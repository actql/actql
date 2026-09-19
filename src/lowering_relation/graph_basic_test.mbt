///|
fn graph_basic_sequence(body : String) -> @lowering_relation.PreparedSequence {
  let checked = @pipeline.check_carriers(
    cursor("[{\"from\":\"g\"," + body + "}]"),
    [("g", graph_union_carrier())],
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
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
}

///|
fn graph_basic_wire(body : String) -> String raise {
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(graph_basic_sequence(body), writer)
  @encode.finish(writer)
}

///|
test "Basic Graph operations lower from checked typed options" {
  assert_eq(
    graph_basic_wire("\"normalize_graph\":true"),
    "[{\"id\":\"normalize_graph_0\",\"in\":[\"input_0\"],\"op\":\"SGA.normalize\",\"params\":{}}]",
  )
  assert_eq(
    graph_basic_wire("\"degree\":{\"direction\":\"both\"}"),
    "[{\"id\":\"degree_0\",\"in\":[\"input_0\"],\"op\":\"SGA.degree_metrics\",\"params\":{\"direction\":\"both\"}}]",
  )
}
