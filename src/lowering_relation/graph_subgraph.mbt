///|
struct PreparedGraphSubgraph {
  node : PreparedNode
  checked : @graph.CheckedSubgraph
  edge_predicate : Expression?
}

///|
pub fn graph_subgraph_literal_id_count(value : PreparedGraphSubgraph) -> Int? {
  let selector = @graph.subgraph_nodes(value.checked)
  if @graph.selector_form(selector) is @graph.ExplicitIds {
    Some(@graph.selector_id_count(selector))
  } else {
    None
  }
}

///|
pub fn graph_subgraph_literal_id_at(
  value : PreparedGraphSubgraph,
  index : Int,
) -> @value.CheckedValue? {
  let selector = @graph.subgraph_nodes(value.checked)
  guard @graph.selector_form(selector) is @graph.ExplicitIds else {
    return None
  }
  @graph.selector_id_at(selector, index)
}

///|
pub fn graph_subgraph_relation_selector_field(
  value : PreparedGraphSubgraph,
) -> @schema.FieldName? {
  match @graph.selector_form(@graph.subgraph_nodes(value.checked)) {
    @graph.RelationIds(field~, ..) => Some(field)
    _ => None
  }
}

///|
pub fn graph_subgraph_edge_predicate(
  value : PreparedGraphSubgraph,
) -> Expression? {
  value.edge_predicate
}

///|
pub fn graph_subgraph_literal_edge_predicate(
  value : PreparedGraphSubgraph,
) -> Bool? {
  match value.edge_predicate {
    None => Some(true)
    Some(expression) =>
      match expression_body(expression) {
        Literal(checked) =>
          match checked.value {
            @value.Boolean(selected) => Some(selected)
            _ => None
          }
        _ => None
      }
  }
}

///|
pub fn graph_subgraph_edge_fields(
  value : PreparedGraphSubgraph,
) -> @carrier.Knowledge {
  @graph.subgraph_edge_fields(value.checked)
}

///|
pub fn graph_subgraph_edge_property_position(
  value : PreparedGraphSubgraph,
  definition : Int,
  field : Int,
) -> Int? {
  @graph.subgraph_edge_property_position(value.checked, definition, field)
}

///|
pub(all) enum GraphSubgraphIssue {
  InvalidGraphSubgraphLimits
  InvalidGraphSubgraphWiring
  GraphSubgraphPreparationLimit
  GraphSubgraphExpression(ExpressionIssue)
}

///|
fn prepare_graph_subgraph_node(
  owner : BoundPrepared,
  step_index : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  expressions~ : ExpressionLimits,
) -> Result[
  (PreparedGraphSubgraph, Int, Int, ExpressionLimits),
  GraphSubgraphIssue,
] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidGraphSubgraphLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is GraphSubgraphValue(checked) else {
    return Err(InvalidGraphSubgraphWiring)
  }
  let selector = @graph.subgraph_nodes(checked)
  let mut entries = @graph.selector_id_count(selector)
  let mut name_bytes = 0
  let expected_inputs = if @graph.selector_form(selector)
    is @graph.RelationIds(field~, ..) {
    entries += 1
    name_bytes = @utf8.encode(@schema.reference_name(field)).length()
    2
  } else {
    1
  }
  if node.inputs.length() != expected_inputs ||
    entries > max_entries ||
    name_bytes > max_name_bytes {
    return Err(GraphSubgraphPreparationLimit)
  }
  let mut remaining = expressions
  let edge_predicate = if @graph.subgraph_edges(checked) is Some(_) {
    let (expression, usage) = match
      lower_expression_measured(owner, step_index, 0, remaining) {
      Ok(value) => value
      Err(issue) => return Err(GraphSubgraphExpression(issue))
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
  } else {
    None
  }
  Ok(({ node, checked, edge_predicate, }, entries, name_bytes, remaining))
}

///|
fn emit_graph_subgraph_node(
  prepared : PreparedGraphSubgraph,
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
  @encode.string_value(out, "SGA.subgraph")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "nodes")
  emit_graph_selector(@graph.subgraph_nodes(prepared.checked), out)
  @encode.key(out, "edges")
  match prepared.edge_predicate {
    Some(expression) => emit_expression(expression, out)
    None => {
      @encode.begin_object(out)
      @encode.key(out, "body")
      @encode.bool_value(out, true)
      @encode.key(out, "op")
      @encode.string_value(out, "literal")
      @encode.end_object(out)
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
