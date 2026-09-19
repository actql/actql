///|
struct PreparedGraphSubgraph {
  node : PreparedNode
  checked : @graph.CheckedSubgraph
  node_predicate : Expression?
  edge_predicate : Expression?
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
  let expected_inputs = match @graph.selector_form(selector) {
    @graph.RelationIds(field~, ..) => {
      entries += 1
      name_bytes = @utf8.encode(@schema.reference_name(field)).length()
      2
    }
    @graph.ExplicitIds | @graph.PredicateNodes => 1
  }
  if node.inputs.length() != expected_inputs ||
    entries > max_entries ||
    name_bytes > max_name_bytes {
    return Err(GraphSubgraphPreparationLimit)
  }
  let mut remaining = expressions
  let lower = fn(index : Int) -> Result[Expression, GraphSubgraphIssue] {
    let (expression, usage) = match
      lower_expression_measured(owner, step_index, index, remaining) {
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
    Ok(expression)
  }
  let node_predicate = match @graph.selector_predicate(selector) {
    None => None
    Some(_) =>
      match lower(0) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let edge_predicate = match @graph.subgraph_edges(checked) {
    None => None
    Some(_) =>
      match lower(1) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  Ok(
    (
      { node, checked, node_predicate, edge_predicate, },
      entries,
      name_bytes,
      remaining,
    ),
  )
}

///|
fn emit_graph_selector(
  selector : @graph.CheckedSelector,
  predicate : Expression?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  match @graph.selector_form(selector) {
    @graph.ExplicitIds => {
      @encode.key(out, "ids")
      @encode.begin_array(out)
      for index in 0..<@graph.selector_id_count(selector) {
        emit_wire_value(
          @graph.selector_id_at(selector, index).unwrap().value,
          out,
        )
      }
      @encode.end_array(out)
    }
    @graph.RelationIds(field~, ..) => {
      @encode.key(out, "input_port")
      @encode.number_value(out, 1.0)
      @encode.key(out, "id")
      @encode.string_value(out, @schema.reference_name(field))
    }
    @graph.PredicateNodes => {
      guard predicate is Some(expression) else {
        abort("missing prepared graph selector predicate")
      }
      @encode.key(out, "where")
      emit_expression(expression, out)
    }
  }
  @encode.end_object(out)
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
  emit_graph_selector(
    @graph.subgraph_nodes(prepared.checked),
    prepared.node_predicate,
    out,
  )
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
