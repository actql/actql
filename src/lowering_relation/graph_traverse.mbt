///|
priv struct PreparedGraphTraverseHop {
  checked : @graph.TraversalHop
}

///|
struct PreparedGraphTraverse {
  node : PreparedNode
  checked : @graph.CheckedTraverse
  hops : Array[PreparedGraphTraverseHop]
  output_guard : Int64?
}

///|
pub fn graph_traverse_property_path_mode(
  value : PreparedGraphTraverse,
) -> @graph.PropertyPathMode {
  @graph.traverse_property_path_mode(value.checked)
}

///|
/// The checked Relation schema produced by this traversal occurrence.
pub fn graph_traverse_output_schema(
  value : PreparedGraphTraverse,
) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
/// Whether the authored traversal uses an exact per-hop pattern.
pub fn graph_traverse_patterned(value : PreparedGraphTraverse) -> Bool {
  @graph.traverse_patterned(value.checked)
}

///|
/// The checked homogeneous hop bounds. Patterned traversal returns None.
pub fn graph_traverse_bounds(value : PreparedGraphTraverse) -> (Int64, Int64)? {
  if graph_traverse_patterned(value) {
    return None
  }
  let (minimum, maximum) = @graph.traverse_bounds(value.checked)
  guard @scalar.read_safe_integer(minimum) is Some(minimum) &&
    @scalar.read_safe_integer(maximum) is Some(maximum) else {
    return None
  }
  Some((minimum, maximum))
}

///|
/// Whether this occurrence emits complete paths rather than reached nodes.
pub fn graph_traverse_emits_paths(value : PreparedGraphTraverse) -> Bool {
  @graph.traverse_emission(value.checked) == @graph.TraversedPaths
}

///|
/// The resolved optional output row guard.
pub fn graph_traverse_output_guard(value : PreparedGraphTraverse) -> Int64? {
  value.output_guard
}

///|
/// Number of checked literal identities in the start selector.
pub fn graph_traverse_start_id_count(value : PreparedGraphTraverse) -> Int {
  @graph.selector_id_count(@graph.traverse_start(value.checked))
}

///|
/// One checked literal start identity in authored order.
pub fn graph_traverse_start_id_at(
  value : PreparedGraphTraverse,
  index : Int,
) -> @value.CheckedValue? {
  @graph.selector_id_at(@graph.traverse_start(value.checked), index)
}

///|
/// The selected field for a Relation-backed start selector.
pub fn graph_traverse_start_relation_field(
  value : PreparedGraphTraverse,
) -> @schema.FieldName? {
  match @graph.selector_form(@graph.traverse_start(value.checked)) {
    @graph.RelationIds(field~, ..) => Some(field)
    _ => None
  }
}

///|
/// Number of exact hop specifications available to the kernel.
pub fn graph_traverse_hop_count(value : PreparedGraphTraverse) -> Int {
  value.hops.length()
}

///|
/// Direction of one checked hop specification.
pub fn graph_traverse_hop_direction(
  value : PreparedGraphTraverse,
  index : Int,
) -> @graph.Direction? {
  value.hops.get(index).map(hop => @graph.hop_direction(hop.checked))
}

///|
/// Number of edge labels on one hop, preserving absence versus an empty list.
pub fn graph_traverse_hop_type_count(
  value : PreparedGraphTraverse,
  index : Int,
) -> Int? {
  value.hops.get(index).bind(hop => @graph.hop_type_count(hop.checked))
}

///|
/// One checked edge label in authored order.
pub fn graph_traverse_hop_type_at(
  value : PreparedGraphTraverse,
  hop_index : Int,
  type_index : Int,
) -> String? {
  value.hops
  .get(hop_index)
  .bind(hop => @graph.hop_type_at(hop.checked, type_index))
}

///|
pub(all) enum GraphTraverseIssue {
  InvalidGraphTraverseLimits
  InvalidGraphTraverseWiring
  GraphTraversePreparationLimit
  MissingGraphTraverseParameter(String)
  InvalidGraphTraverseParameter(String)
  GraphTraverseExpression(ExpressionIssue)
}

///|
fn prepare_graph_traverse_node(
  owner : BoundPrepared,
  step_index : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  expressions~ : ExpressionLimits,
) -> Result[
  (PreparedGraphTraverse, Int, Int, ExpressionLimits),
  GraphTraverseIssue,
] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidGraphTraverseLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is GraphTraverseRows(checked) else {
    return Err(InvalidGraphTraverseWiring)
  }
  let start = @graph.traverse_start(checked)
  let expected_inputs = if @graph.selector_form(start) is @graph.RelationIds(..) {
    2
  } else {
    1
  }
  if node.inputs.length() != expected_inputs {
    return Err(InvalidGraphTraverseWiring)
  }
  let mut entries = @graph.selector_id_count(start)
  let mut name_bytes = 0
  if @graph.selector_form(start) is @graph.RelationIds(field~, ..) {
    entries += 1
    name_bytes += @utf8.encode(@schema.reference_name(field)).length()
  }
  let hop_count = @graph.traverse_hop_count(checked)
  if hop_count > max_entries - entries {
    return Err(GraphTraversePreparationLimit)
  }
  entries += hop_count
  for index in 0..<hop_count {
    guard @graph.traverse_hop_at(checked, index) is Some(hop) else {
      return Err(InvalidGraphTraverseWiring)
    }
    let type_count = @graph.hop_type_count(hop).unwrap_or(0)
    if type_count > max_entries - entries {
      return Err(GraphTraversePreparationLimit)
    }
    entries += type_count
    for type_index in 0..<type_count {
      guard @graph.hop_type_at(hop, type_index) is Some(name) else {
        return Err(InvalidGraphTraverseWiring)
      }
      let bytes = @utf8.encode(name).length()
      if bytes > max_name_bytes - name_bytes {
        return Err(GraphTraversePreparationLimit)
      }
      name_bytes += bytes
    }
  }
  let hops : Array[PreparedGraphTraverseHop] = []
  for index in 0..<hop_count {
    hops.push({ checked: @graph.traverse_hop_at(checked, index).unwrap(), })
  }
  let output_guard = match @graph.traverse_output_guard(checked) {
    None => None
    Some(@graph.Literal(value)) => Some(value)
    Some(@graph.Parameter(name)) => {
      let bytes = @utf8.encode(name).length()
      if entries >= max_entries || bytes > max_name_bytes - name_bytes {
        return Err(GraphTraversePreparationLimit)
      }
      entries += 1
      name_bytes += bytes
      guard parameter_value(owner, name) is Some(value) else {
        return Err(MissingGraphTraverseParameter(name))
      }
      guard value.value is @value.Number(number) &&
        @scalar.read_safe_integer(number) is Some(integer) &&
        integer >= 1L else {
        return Err(InvalidGraphTraverseParameter(name))
      }
      Some(integer)
    }
  }
  Ok(({ node, checked, hops, output_guard, }, entries, name_bytes, expressions))
}

///|
fn emit_graph_types(
  hop : @graph.TraversalHop,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if @graph.hop_type_count(hop) is Some(count) {
    @encode.key(out, "edge_types")
    @encode.begin_array(out)
    for index in 0..<count {
      @encode.string_value(out, @graph.hop_type_at(hop, index).unwrap())
    }
    @encode.end_array(out)
  }
}

///|
fn emit_graph_traverse_node(
  prepared : PreparedGraphTraverse,
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
  @encode.string_value(out, "SGA.traverse")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "start")
  emit_graph_selector(@graph.traverse_start(prepared.checked), out)
  @encode.key(out, "path_mode")
  @encode.string_value(
    out,
    match graph_traverse_property_path_mode(prepared) {
      @graph.Walk => "walk"
      @graph.Trail => "trail"
      @graph.Acyclic => "acyclic"
    },
  )
  if @graph.traverse_patterned(prepared.checked) {
    @encode.key(out, "hops")
    @encode.begin_array(out)
    for hop in prepared.hops {
      @encode.begin_object(out)
      @encode.key(out, "direction")
      emit_graph_direction(@graph.hop_direction(hop.checked), out)
      emit_graph_types(hop.checked, out)
      @encode.end_object(out)
    }
    @encode.end_array(out)
  } else {
    let hop = prepared.hops[0].checked
    @encode.key(out, "direction")
    emit_graph_direction(@graph.hop_direction(hop), out)
    emit_graph_types(hop, out)
    let (minimum, maximum) = @graph.traverse_bounds(prepared.checked)
    @encode.key(out, "min_hops")
    @encode.number_value(out, minimum)
    @encode.key(out, "max_hops")
    @encode.number_value(out, maximum)
  }
  @encode.key(out, "emit")
  @encode.string_value(out, "paths")
  if prepared.output_guard is Some(value) {
    @encode.key(out, "max_output_rows")
    @encode.number_value(out, value.to_double())
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
