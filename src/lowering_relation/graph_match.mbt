///|
struct PreparedGraphMatch {
  node : PreparedNode
  checked : @graph.CheckedMatch
  predicate : Expression?
}

///|
/// Whether this prepared occurrence matches nodes rather than edges.
pub fn graph_match_nodes(value : PreparedGraphMatch) -> Bool {
  @graph.match_entity(value.checked) == @graph.Nodes
}

///|
/// The checked Relation schema produced by this match occurrence.
pub fn graph_match_output_schema(value : PreparedGraphMatch) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
/// Number of authored output fields, in authored projection order.
pub fn graph_match_field_count(value : PreparedGraphMatch) -> Int {
  @graph.match_field_count(value.checked)
}

///|
/// One authored output field, in authored projection order.
pub fn graph_match_field_at(
  value : PreparedGraphMatch,
  index : Int,
) -> @schema.FieldName? {
  @graph.match_field_at(value.checked, index)
}

///|
/// Number of checked identities in the node identity-list branch.
pub fn graph_match_id_count(value : PreparedGraphMatch) -> Int {
  @graph.match_id_count(value.checked)
}

///|
/// One checked node identity from the authored identity list.
pub fn graph_match_id_at(
  value : PreparedGraphMatch,
  index : Int,
) -> @value.CheckedValue? {
  @graph.match_id_at(value.checked, index)
}

///|
/// Whether this occurrence contains a checked predicate expression.
pub fn graph_match_has_predicate(value : PreparedGraphMatch) -> Bool {
  value.predicate is Some(_)
}

///|
pub(all) enum GraphMatchIssue {
  InvalidGraphMatchLimits
  InvalidGraphMatchWiring
  GraphMatchPreparationLimit
  GraphMatchExpression(ExpressionIssue)
}

///|
fn prepare_graph_match_node(
  owner : BoundPrepared,
  step_index : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  expressions~ : ExpressionLimits,
) -> Result[(PreparedGraphMatch, Int, Int, ExpressionLimits), GraphMatchIssue] {
  if max_entries < 0 ||
    max_name_bytes < 0 ||
    expressions.max_nodes < 0 ||
    expressions.max_work < 0 ||
    expressions.max_depth < 0 ||
    expressions.max_literal_nodes < 0 ||
    expressions.max_literal_text_bytes < 0 {
    return Err(InvalidGraphMatchLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is GraphMatchRows(checked) &&
    node.inputs.length() == 1 else {
    return Err(InvalidGraphMatchWiring)
  }
  let fields = @graph.match_field_count(checked)
  let ids = @graph.match_id_count(checked)
  let types = @graph.match_type_count(checked).unwrap_or(0)
  let entries = fields + ids + types
  if fields > max_entries ||
    ids > max_entries - fields ||
    types > max_entries - fields - ids {
    return Err(GraphMatchPreparationLimit)
  }
  let mut name_bytes = 0
  let charge_name = fn(name : String) -> Bool {
    let bytes = @utf8.encode(name).length()
    if bytes > max_name_bytes - name_bytes {
      false
    } else {
      name_bytes += bytes
      true
    }
  }
  for index in 0..<fields {
    guard @graph.match_field_at(checked, index) is Some(field) else {
      return Err(InvalidGraphMatchWiring)
    }
    if !charge_name(@schema.reference_name(field)) {
      return Err(GraphMatchPreparationLimit)
    }
  }
  for index in 0..<types {
    guard @graph.match_type_at(checked, index) is Some(name) else {
      return Err(InvalidGraphMatchWiring)
    }
    if !charge_name(name) {
      return Err(GraphMatchPreparationLimit)
    }
  }
  let (predicate, remaining) = match @graph.match_predicate(checked) {
    None => (None, expressions)
    Some(_) => {
      let (expression, usage) = match
        lower_expression_measured(owner, step_index, 0, expressions) {
        Ok(value) => value
        Err(issue) => return Err(GraphMatchExpression(issue))
      }
      (
        Some(expression),
        {
          ..expressions,
          max_nodes: expressions.max_nodes - usage.nodes,
          max_work: expressions.max_work - usage.work,
          max_literal_nodes: expressions.max_literal_nodes - usage.literal_nodes,
          max_literal_text_bytes: expressions.max_literal_text_bytes -
          usage.literal_bytes,
        },
      )
    }
  }
  Ok(({ node, checked, predicate, }, entries, name_bytes, remaining))
}

///|
fn emit_graph_match_node(
  prepared : PreparedGraphMatch,
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
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "fields")
  @encode.begin_array(out)
  for index in 0..<@graph.match_field_count(prepared.checked) {
    let field = @graph.match_field_at(prepared.checked, index).unwrap()
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.end_array(out)
  if @graph.match_id_count(prepared.checked) > 0 {
    @encode.key(out, "ids")
    @encode.begin_array(out)
    for index in 0..<@graph.match_id_count(prepared.checked) {
      let value = @graph.match_id_at(prepared.checked, index).unwrap()
      emit_wire_value(value.value, out)
    }
    @encode.end_array(out)
  }
  if @graph.match_type_count(prepared.checked) is Some(count) {
    @encode.key(out, "types")
    @encode.begin_array(out)
    for index in 0..<count {
      @encode.string_value(
        out,
        @graph.match_type_at(prepared.checked, index).unwrap(),
      )
    }
    @encode.end_array(out)
  }
  if prepared.predicate is Some(predicate) {
    @encode.key(out, "where")
    emit_expression(predicate, out)
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
