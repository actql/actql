///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="bounded-graph-diff.aql",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn graph_carrier() -> @carrier.Carrier {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let node = @carrier.rows(
    [(@schema.Unqualified("p"), Some(number))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let edge = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  @carrier.graph(
    number,
    node,
    edge,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    label_contract=None,
  ).unwrap()
}

///|
fn storage_limits() -> @storage.Limits {
  {
    max_input_rows: 100,
    max_nodes: 100,
    max_edges: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_value_nodes: 1000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  let contract = @contract.primitive(@contract.NumberType, nullable=false)
  @value.recheck_runtime_value(@value.number_value(value).unwrap(), contract, {
    max_nodes: 10,
    max_depth: 10,
    max_text_bytes: 10,
  }).unwrap()
}

///|
fn graph_storage(
  first_property : Double,
  second_identity : Double,
  second_property : Double,
) -> @storage.Storage {
  let builder = @storage.prepare(
    graph_carrier(),
    @storage.DeclaredNodes,
    storage_limits(),
  ).unwrap()
  @storage.append_node(builder, number(1.0), [number(first_property)]).unwrap()
  @storage.append_node(builder, number(second_identity), [
    number(second_property),
  ]).unwrap()
  @storage.append_edge(builder, number(1.0), number(second_identity), None, []).unwrap()
  @storage.finish(builder).unwrap()
}

///|
fn diff_limits(workspace : Int) -> Limits {
  {
    max_workspace_slots: workspace,
    max_output_nodes: 1000,
    max_output_text_bytes: 10000,
    max_output_depth: 20,
    max_identity_bytes: 100000,
    max_identity_nodes: 10000,
    max_identity_depth: 100,
    value_limits: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }
}

///|
fn wire(value : @value.CheckedValue) -> String raise {
  let out = @encode.writer(100000, 10000, 100)
  @value.emit_wire_value(value.value, out)
  @encode.finish(out)
}

///|
test "graph diff emits canonical bounded actions with quantum one" {
  let left = graph_storage(10.0, 2.0, 20.0)
  let right = graph_storage(11.0, 3.0, 30.0)
  let checked = @graph_type.check_diff(
    cursor("{\"with\":\"target\"}"),
    graph_carrier(),
    graph_carrier(),
    {
      max_work: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
  ).unwrap()
  let graph_cid = @graph_contract.cid(@graph_type.diff_graph_contract(checked))
  let preparation = prepare(
    left,
    right,
    @graph_type.diff_contract(checked),
    graph_cid,
    diff_limits(100),
  ).unwrap()
  let mut polls = 0
  let mut result = None
  while result is None {
    match advance(preparation, 1) {
      Ok(Continue(_)) => {
        polls += 1
        assert_true(polls < 1000)
      }
      Ok(Complete(delta, ..)) => result = Some(delta)
      Ok(Failed(_, ..)) => abort("diff failed")
      Err(_) => abort("diff protocol failed")
    }
  }
  let delta = result.unwrap()
  let expected = "{\"base_graph_cid\":\"" +
    base_cid(delta) +
    "\",\"edges\":{\"add\":[{\"dst\":3,\"props\":{},\"rel\":null,\"src\":1}],\"remove\":[{\"dst\":2,\"props\":{},\"rel\":null,\"src\":1}],\"update\":[]},\"graph_contract_cid\":\"" +
    graph_cid +
    "\",\"nodes\":{\"add\":[{\"id\":3,\"props\":{\"p\":30}}],\"remove\":[{\"id\":2,\"props\":{\"p\":20}}],\"update\":[{\"after\":{\"id\":1,\"props\":{\"p\":11}},\"before\":{\"id\":1,\"props\":{\"p\":10}}}]},\"target_graph_cid\":\"" +
    target_cid(delta) +
    "\",\"version\":\"actql-graph-delta/0.1\"}"
  assert_eq(wire(value(delta)), expected)
  assert_true(base_cid(delta) != target_cid(delta))
}

///|
test "graph diff admits combined workspace before snapshot construction" {
  let left = graph_storage(10.0, 2.0, 20.0)
  let right = graph_storage(11.0, 3.0, 30.0)
  let checked = @graph_type.check_diff(
    cursor("{\"with\":\"target\"}"),
    graph_carrier(),
    graph_carrier(),
    {
      max_work: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
  ).unwrap()
  assert_true(
    prepare(
      left,
      right,
      @graph_type.diff_contract(checked),
      @graph_contract.cid(@graph_type.diff_graph_contract(checked)),
      diff_limits(53),
    )
    is Err(WorkspaceLimit),
  )
}

///|
test "graph diff cleanup cancels partial snapshots" {
  let left = graph_storage(10.0, 2.0, 20.0)
  let right = graph_storage(11.0, 3.0, 30.0)
  let checked = @graph_type.check_diff(
    cursor("{\"with\":\"target\"}"),
    graph_carrier(),
    graph_carrier(),
    {
      max_work: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
  ).unwrap()
  let preparation = prepare(
    left,
    right,
    @graph_type.diff_contract(checked),
    @graph_contract.cid(@graph_type.diff_graph_contract(checked)),
    diff_limits(100),
  ).unwrap()
  assert_true(advance(preparation, 1) is Ok(Continue(_)))
  assert_true(cleanup(preparation))
  assert_true(cleanup(preparation))
}
