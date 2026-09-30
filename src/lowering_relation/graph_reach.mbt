///|
struct PreparedGraphReach {
  node : PreparedNode
  checked : @graph.CheckedReach
  start_predicate : Expression?
}

///|
pub fn graph_reach_output_schema(value : PreparedGraphReach) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
pub fn graph_reach_start(value : PreparedGraphReach) -> @graph.ReachStart {
  @graph.reach_start(value.checked)
}

///|
pub fn graph_reach_start_id_count(value : PreparedGraphReach) -> Int {
  match @graph.reach_start(value.checked) {
    @graph.SingleReachStart(_) => 1
    @graph.SelectedReachStarts(selector) => @graph.selector_id_count(selector)
  }
}

///|
pub fn graph_reach_start_id_at(
  value : PreparedGraphReach,
  index : Int,
) -> @value.CheckedValue? {
  match @graph.reach_start(value.checked) {
    @graph.SingleReachStart(id) => if index == 0 { Some(id) } else { None }
    @graph.SelectedReachStarts(selector) =>
      @graph.selector_id_at(selector, index)
  }
}

///|
pub fn graph_reach_start_relation_field(
  value : PreparedGraphReach,
) -> @schema.FieldName? {
  match @graph.reach_start(value.checked) {
    @graph.SelectedReachStarts(selector) =>
      match @graph.selector_form(selector) {
        @graph.RelationIds(field~, ..) => Some(field)
        _ => None
      }
    _ => None
  }
}

///|
pub fn graph_reach_start_predicate(value : PreparedGraphReach) -> Expression? {
  value.start_predicate
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
  owner : BoundPrepared,
  step_index : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  expressions~ : ExpressionLimits,
) -> Result[(PreparedGraphReach, Int, Int, ExpressionLimits), GraphReachIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidGraphReachLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is GraphReachRows(checked) else {
    return Err(InvalidGraphReachWiring)
  }
  let start = @graph.reach_start(checked)
  let expected_inputs = if start is @graph.SelectedReachStarts(selector) &&
    @graph.selector_form(selector) is @graph.RelationIds(..) {
    2
  } else {
    1
  }
  if node.inputs.length() != expected_inputs {
    return Err(InvalidGraphReachWiring)
  }
  let entries = match start {
    @graph.SingleReachStart(_) => 1
    @graph.SelectedReachStarts(selector) =>
      @graph.selector_id_count(selector) +
      (if @graph.selector_form(selector) is @graph.RelationIds(..) {
        1
      } else {
        0
      })
  }
  if entries > max_entries || entries > expressions.max_work {
    return Err(GraphReachPreparationLimit)
  }
  let mut name_bytes = 0
  if start is @graph.SelectedReachStarts(selector) &&
    @graph.selector_form(selector) is @graph.RelationIds(field~, ..) {
    name_bytes = @utf8.encode(@schema.reference_name(field)).length()
  }
  if name_bytes > max_name_bytes {
    return Err(GraphReachPreparationLimit)
  }
  let mut remaining = {
    ..expressions,
    max_work: expressions.max_work - entries,
  }
  let start_predicate = match start {
    @graph.SelectedReachStarts(selector) if @graph.selector_predicate(selector)
      is Some(_) => {
      let (expression, usage) = match
        lower_expression_measured(owner, step_index, 0, remaining) {
        Ok(value) => value
        Err(_) => return Err(GraphReachPreparationLimit)
      }
      remaining = {
        ..remaining,
        max_nodes: remaining.max_nodes - usage.nodes,
        max_work: remaining.max_work - usage.work,
        max_literal_nodes: remaining.max_literal_nodes - usage.literal_nodes,
        max_literal_text_bytes: remaining.max_literal_text_bytes -
        usage.literal_bytes,
      }
      Some(expression)
    }
    _ => None
  }
  Ok(({ node, checked, start_predicate, }, entries, name_bytes, remaining))
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
  for input in prepared.node.inputs {
    @encode.string_value(out, input)
  }
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
  match @graph.reach_start(prepared.checked) {
    @graph.SingleReachStart(value) => emit_wire_value(value.value, out)
    @graph.SelectedReachStarts(selector) =>
      emit_graph_selector(selector, prepared.start_predicate, out)
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
