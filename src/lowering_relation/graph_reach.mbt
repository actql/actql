///|
struct PreparedGraphReach {
  node : PreparedNode
  checked : @graph.CheckedReach
}

///|
pub fn graph_reach_output_schema(value : PreparedGraphReach) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
pub fn graph_reach_start(value : PreparedGraphReach) -> @value.CheckedValue {
  @graph.reach_start(value.checked)
}

///|
pub fn graph_reach_direction(value : PreparedGraphReach) -> @graph.Direction {
  @graph.reach_direction(value.checked)
}

///|
pub fn graph_reach_max_depth(value : PreparedGraphReach) -> Int? {
  let depth = @graph.reach_max_depth(value.checked)
  if depth <= 0.0 || depth.is_nan() || depth.is_inf() {
    None
  } else if depth > 2147483647.0 {
    Some(2147483647)
  } else if depth.to_int().to_double() == depth {
    Some(depth.to_int())
  } else {
    None
  }
}

///|
pub(all) enum GraphReachIssue {
  InvalidGraphReachLimits
  InvalidGraphReachWiring
  GraphReachPreparationLimit
} derive(Eq, Debug)

///|
fn prepare_graph_reach_node(
  node : PreparedNode,
  max_entries~ : Int,
  max_work~ : Int,
) -> Result[(PreparedGraphReach, Int, Int), GraphReachIssue] {
  if max_entries < 0 || max_work < 0 {
    return Err(InvalidGraphReachLimits)
  }
  guard node.payload is GraphReachRows(checked) && node.inputs.length() == 1 else {
    return Err(InvalidGraphReachWiring)
  }
  if max_entries < 1 || max_work < 1 {
    return Err(GraphReachPreparationLimit)
  }
  Ok(({ node, checked, }, 1, 1))
}

///|
fn emit_graph_direction(
  direction : @graph.Direction,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.string_value(
    out,
    match direction {
      @graph.Incoming => "in"
      @graph.Outgoing => "out"
      @graph.Both => "both"
    },
  )
}

///|
fn emit_graph_reach_node(
  prepared : PreparedGraphReach,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, prepared.node.inputs[0])
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "SGA.reachable")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "direction")
  emit_graph_direction(@graph.reach_direction(prepared.checked), out)
  @encode.key(out, "max_depth")
  @encode.number_value(out, @graph.reach_max_depth(prepared.checked))
  @encode.key(out, "start")
  emit_wire_value(@graph.reach_start(prepared.checked).value, out)
  @encode.end_object(out)
  @encode.end_object(out)
}
