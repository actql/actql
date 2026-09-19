///|
priv struct PreparedGraphTraverseHop {
  checked : @graph.TraversalHop
  edge_predicate : Expression?
  node_predicate : Expression?
}

///|
struct PreparedGraphTraverse {
  node : PreparedNode
  checked : @graph.CheckedTraverse
  start_predicate : Expression?
  hops : Array[PreparedGraphTraverseHop]
  output_guard : Int64?
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
  let mut remaining = expressions
  let lower = fn(index : Int) -> Result[Expression, GraphTraverseIssue] {
    let (expression, usage) = match
      lower_expression_measured(owner, step_index, index, remaining) {
      Ok(value) => value
      Err(issue) => return Err(GraphTraverseExpression(issue))
    }
    remaining = {
      ..remaining,
      max_nodes: remaining.max_nodes - usage.nodes,
      max_work: remaining.max_work - usage.work,
      max_literal_nodes: remaining.max_literal_nodes - usage.literal_nodes,
      max_literal_text_bytes: remaining.max_literal_text_bytes -
      usage.literal_bytes,
    }
    Ok(expression)
  }
  let start_predicate = match @graph.selector_predicate(start) {
    None => None
    Some(_) =>
      match lower(0) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let hops : Array[PreparedGraphTraverseHop] = []
  for index in 0..<hop_count {
    let hop = @graph.traverse_hop_at(checked, index).unwrap()
    let edge_predicate = match @graph.hop_predicate(hop, @graph.Edges) {
      None => None
      Some(_) =>
        match lower(1 + index * 2) {
          Ok(value) => Some(value)
          Err(issue) => return Err(issue)
        }
    }
    let node_predicate = match @graph.hop_predicate(hop, @graph.Nodes) {
      None => None
      Some(_) =>
        match lower(2 + index * 2) {
          Ok(value) => Some(value)
          Err(issue) => return Err(issue)
        }
    }
    hops.push({ checked: hop, edge_predicate, node_predicate, })
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
  Ok(
    (
      { node, checked, start_predicate, hops, output_guard, },
      entries,
      name_bytes,
      remaining,
    ),
  )
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
  emit_graph_selector(
    @graph.traverse_start(prepared.checked),
    prepared.start_predicate,
    out,
  )
  if @graph.traverse_patterned(prepared.checked) {
    @encode.key(out, "hops")
    @encode.begin_array(out)
    for hop in prepared.hops {
      @encode.begin_object(out)
      @encode.key(out, "direction")
      emit_graph_direction(@graph.hop_direction(hop.checked), out)
      emit_graph_types(hop.checked, out)
      if hop.edge_predicate is Some(predicate) {
        @encode.key(out, "edge_where")
        emit_expression(predicate, out)
      }
      if hop.node_predicate is Some(predicate) {
        @encode.key(out, "node_where")
        emit_expression(predicate, out)
      }
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
  @encode.string_value(
    out,
    match @graph.traverse_emission(prepared.checked) {
      @graph.TraversedNodes => "nodes"
      @graph.TraversedPaths => "paths"
      @graph.ShortestPaths => abort("invalid traverse emission")
    },
  )
  if prepared.output_guard is Some(value) {
    @encode.key(out, "max_output_rows")
    @encode.number_value(out, value.to_double())
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
