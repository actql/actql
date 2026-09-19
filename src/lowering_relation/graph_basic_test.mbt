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
  assert_eq(
    graph_basic_wire(
      "\"components\":{\"kind\":\"strong\",\"max_output_rows\":7}",
    ),
    "[{\"id\":\"components_0\",\"in\":[\"input_0\"],\"op\":\"SGA.components\",\"params\":{\"kind\":\"strong\",\"max_output_rows\":7}}]",
  )
  assert_eq(
    graph_basic_wire(
      "\"graph_bounds\":{\"max_nodes\":9,\"max_edges\":8,\"max_degree\":7}",
    ),
    "[{\"id\":\"graph_bounds_0\",\"in\":[\"input_0\"],\"op\":\"SGA.bounds_check\",\"params\":{\"max_degree\":7,\"max_edges\":8,\"max_nodes\":9}}]",
  )
}

///|
fn graph_basic_parameter_owner(value : Int) -> @lowering_relation.BoundPrepared {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"cap\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"g\",\"graph_bounds\":{\"max_nodes\":{\"$param\":\"cap\"}}}]",
    ),
    [("g", graph_union_carrier())],
    Some(declarations),
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
  let values = match
    @parameter.bind(
      declarations,
      Some(cursor("{\"cap\":" + value.to_string() + "}")),
      { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
    ).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("complete Graph bound")
  }
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    Some(values),
    max_parameters=1,
    max_name_bytes=3,
  ).unwrap()
}

///|
test "Graph bounds resolve checked parameters before canonical emission" {
  let sequence = @lowering_relation.prepare_sequence(
    graph_basic_parameter_owner(11),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"graph_bounds_0\",\"in\":[\"input_0\"],\"op\":\"SGA.bounds_check\",\"params\":{\"max_nodes\":11}}]",
  )
  assert_true(
    @lowering_relation.prepare_sequence(
      graph_basic_parameter_owner(-1),
      sequence_limits(),
    )
    is Err(
      @lowering_relation.GraphBasicFailure(
        0,
        @lowering_relation.InvalidGraphBasicParameter("cap")
      )
    ),
  )
}
